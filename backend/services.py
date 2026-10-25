"""Relational reads and atomic workflows; no parallel financial state in Python."""
from decimal import Decimal
from fastapi import HTTPException
from psycopg2 import sql
from backend import database as db

TABLES = ('Customer', 'Account', 'Loan', 'Loan_Repayment', 'Fixed_Deposit',
          'Beneficiary', 'Branch', 'Employee', 'Postal_Directory', 'Bank_Directory',
          'Transaction_History', 'Audit_Log')

def fail(message, status=400):
    raise HTTPException(status_code=status, detail=f'Transaction Failed: {message}')

def customer(customer_id, cursor=None):
    if cursor:
        cursor.execute('SELECT * FROM public.Customer WHERE CustomerID=%s', (customer_id,))
        row = cursor.fetchone()
    else:
        row = db.fetch_one('SELECT * FROM public.Customer WHERE CustomerID=%s', (customer_id,))
    if not row:
        fail('Customer not found', 404)
    return dict(row)

def allocate(cursor, table, column, lock_key):
    # Cooperating API requests allocate serial-free INT keys under a transaction
    # advisory lock. PK constraints remain the final arbiter for external writers.
    cursor.execute('SELECT pg_advisory_xact_lock(302, %s)', (lock_key,))
    cursor.execute(sql.SQL('SELECT COALESCE(MAX({}),0)+1 AS id FROM public.{}').format(
        sql.Identifier(column.lower()), sql.Identifier(table.lower())))
    return cursor.fetchone()['id']

def locked_account(cursor, account_no, customer_id=None):
    cursor.execute('SELECT * FROM public.Account WHERE AccountNo=%s FOR UPDATE', (account_no,))
    account = cursor.fetchone()
    if not account:
        fail('Account not found', 404)
    if customer_id is not None and account['customerid'] != customer_id:
        fail('Account does not belong to the selected customer', 403)
    if account['status'] != 'Active':
        fail('Account must be Active; Dormant, Frozen and Closed accounts cannot transact')
    return account

def history(cursor, account_no, amount, kind, mode, remarks):
    cursor.execute('''INSERT INTO public.Transaction_History
        (AccountNo,Amount,TransactionType,PaymentMode,Remarks) VALUES (%s,%s,%s,%s,%s)
        RETURNING TransactionID''', (account_no, amount, kind, mode, remarks))
    return cursor.fetchone()['transactionid']

def debit(cursor, account_no, amount, customer_id, mode, remarks, kind='Withdrawal'):
    account = locked_account(cursor, account_no, customer_id)
    if account['balance'] < amount:
        fail(f'Insufficient balance in account {account_no}')
    cursor.execute('UPDATE public.Account SET Balance=Balance-%s WHERE AccountNo=%s', (amount, account_no))
    return history(cursor, account_no, amount, kind, mode, remarks)

def cash(payload, withdrawal=False):
    with db.transaction() as cursor:
        if withdrawal:
            txn = debit(cursor, payload.account_no, payload.amount, payload.customer_id,
                        payload.mode, payload.remarks or 'Self withdrawal')
        else:
            locked_account(cursor, payload.account_no, payload.customer_id)
            cursor.execute('UPDATE public.Account SET Balance=Balance+%s WHERE AccountNo=%s',
                           (payload.amount, payload.account_no))
            txn = history(cursor, payload.account_no, payload.amount, 'Deposit', payload.mode,
                          payload.remarks or 'Self deposit')
        cursor.execute('SELECT Balance FROM public.Account WHERE AccountNo=%s', (payload.account_no,))
        return {'transaction_id': txn, 'balance': cursor.fetchone()['balance']}

def transfer(payload):
    if payload.beneficiary_id is None:
        # Maintain the top-level autocommit CALL required by the existing proc.
        if payload.customer_id is not None:
            owner = db.fetch_one('SELECT CustomerID FROM public.Account WHERE AccountNo=%s', (payload.sender,))
            if not owner or owner['customerid'] != payload.customer_id:
                fail('Sender account does not belong to the selected customer', 403)
        db.execute('CALL public.sp_transfer_funds(%s,%s,%s,%s,%s)',
                   (payload.sender, payload.receiver, payload.amount, payload.mode, payload.remarks))
        return {'destination': 'internal'}
    with db.transaction() as cursor:
        cursor.execute('SELECT * FROM public.Beneficiary WHERE BeneficiaryID=%s FOR UPDATE', (payload.beneficiary_id,))
        beneficiary = cursor.fetchone()
        if not beneficiary or beneficiary['customerid'] != payload.customer_id:
            fail('Saved beneficiary does not belong to the selected customer', 403)
        # A locked beneficiary row serializes the daily limit across ALL of the
        # customer's source accounts. A stable tag is necessary because this
        # twelve-table schema has no BeneficiaryID column in Transaction_History.
        marker = f'BENEFICIARY:{payload.beneficiary_id}; '
        cursor.execute('''SELECT COALESCE(SUM(t.Amount),0) AS spent
            FROM public.Transaction_History t JOIN public.Account a USING(AccountNo)
            WHERE a.CustomerID=%s AND t.TransactionType='Transfer' AND t.Remarks LIKE %s
              AND t.TransactionDate>=CURRENT_DATE AND t.TransactionDate<CURRENT_DATE+1''',
                       (payload.customer_id, marker + '%'))
        if cursor.fetchone()['spent'] + payload.amount > beneficiary['maxtransferlimit']:
            fail('Beneficiary daily MaxTransferLimit exceeded')
        cursor.execute('SELECT BranchID FROM public.Branch WHERE IFSC_Code=%s', (beneficiary['ifsc_code'],))
        local_branch = cursor.fetchone()
        # Preserve recipient account/IFSC even after the saved payee is deleted.
        remarks = (marker + f"Debit to {beneficiary['linkedaccountno']} / {beneficiary['ifsc_code']}: "
                   + (payload.remarks or beneficiary['beneficiaryname']))
        if local_branch:
            cursor.execute('SELECT BranchID FROM public.Account WHERE AccountNo=%s', (beneficiary['linkedaccountno'],))
            target = cursor.fetchone()
            if not target or target['branchid'] != local_branch['branchid']:
                fail('Internal beneficiary account and IFSC do not match')
            # Existing security sprint helper contains the SAME locked transfer
            # logic as sp_transfer_funds, without its COMMIT. This keeps limit
            # checking + debit + credit + history in one indivisible transaction.
            cursor.execute('SELECT CustomerID FROM public.Account WHERE AccountNo=%s', (payload.sender,))
            owner = cursor.fetchone()
            if not owner or owner['customerid'] != payload.customer_id:
                fail('Sender account does not belong to the selected customer', 403)
            cursor.execute('SELECT public._bank_transfer_atomic(%s,%s,%s,%s,%s)',
                           (payload.sender, beneficiary['linkedaccountno'], payload.amount, payload.mode, remarks))
            # The helper adds Debit/Credit prefixes. Normalize only the debit's
            # remarks to the stable prefix used for cumulative daily-limit checks.
            cursor.execute('''UPDATE public.Transaction_History SET Remarks=%s
                WHERE TransactionID=(SELECT MAX(TransactionID) FROM public.Transaction_History
                WHERE AccountNo=%s AND Remarks=%s)''',
                (remarks, payload.sender, f"Debit to {beneficiary['linkedaccountno']}: {remarks}"[:255]))
            return {'destination': 'internal beneficiary'}
        txn = debit(cursor, payload.sender, payload.amount, payload.customer_id,
                    payload.mode, remarks, 'Transfer')
        # External settlement is a recorded outward payment, not a simulated
        # credit to another bank's inaccessible account or a real payment rail.
        return {'destination': 'external beneficiary', 'transaction_id': txn}

def ensure_bank(cursor, ifsc, name=None):
    cursor.execute('SELECT BankName FROM public.Bank_Directory WHERE IFSC_Code=%s', (ifsc,))
    existing = cursor.fetchone()
    if existing:
        if name and name.casefold() != existing['bankname'].casefold():
            fail('Existing IFSC belongs to a different bank; shared directory not overwritten', 409)
        return
    if not name:
        fail('BankName is required for a new IFSC code')
    cursor.execute('INSERT INTO public.Bank_Directory VALUES (%s,%s) ON CONFLICT DO NOTHING', (ifsc, name))
    cursor.execute('SELECT BankName FROM public.Bank_Directory WHERE IFSC_Code=%s', (ifsc,))
    if cursor.fetchone()['bankname'].casefold() != name.casefold():
        fail('Concurrent IFSC registration used a different bank name', 409)

def ensure_postal(cursor, pincode, city, state):
    cursor.execute('INSERT INTO public.Postal_Directory VALUES (%s,%s,%s) ON CONFLICT DO NOTHING', (pincode, city, state))
    cursor.execute('SELECT City,State FROM public.Postal_Directory WHERE Pincode=%s', (pincode,))
    existing = cursor.fetchone()
    if (existing['city'].casefold(), existing['state'].casefold()) != (city.casefold(), state.casefold()):
        fail('Existing pincode has different city/state; shared directory not overwritten', 409)

def accounts(customer_id=None):
    return db.fetch_all('''SELECT a.*, CONCAT(c.FirstName,' ',c.LastName) AS customername,
        b.BranchName,b.IFSC_Code,p.City,p.State FROM public.Account a
        JOIN public.Customer c USING(CustomerID) JOIN public.Branch b USING(BranchID)
        JOIN public.Postal_Directory p USING(Pincode)'''
        + (' WHERE a.CustomerID=%s' if customer_id is not None else '') + ' ORDER BY a.AccountNo',
        (customer_id,) if customer_id is not None else ())

def transactions(customer_id, account_no=None, txn_type=None, payment_mode=None):
    query = '''SELECT t.*, CONCAT(c.FirstName,' ',c.LastName) AS name,b.BranchName,
        t.TransactionDate AS date,t.TransactionType AS type
        FROM public.Transaction_History t JOIN public.Account a USING(AccountNo)
        JOIN public.Customer c USING(CustomerID) JOIN public.Branch b USING(BranchID)
        WHERE a.CustomerID=%s'''
    params = [customer_id]
    for column, value in [('t.AccountNo', account_no), ('t.TransactionType', txn_type), ('t.PaymentMode', payment_mode)]:
        if value is not None:
            query += f' AND {column}=%s'
            params.append(value)
    return db.fetch_all(query + ' ORDER BY t.TransactionDate DESC NULLS LAST,t.TransactionID DESC', tuple(params))

def loans(customer_id=None):
    return db.fetch_all('''SELECT l.*, CONCAT(c.FirstName,' ',c.LastName) AS customername,b.BranchName
        FROM public.Loan l JOIN public.Customer c USING(CustomerID) JOIN public.Branch b USING(BranchID)'''
        + (' WHERE l.CustomerID=%s' if customer_id is not None else '') + ' ORDER BY l.LoanID DESC',
        (customer_id,) if customer_id is not None else ())

def fixed_deposits(customer_id=None):
    return db.fetch_all('''SELECT f.*,CONCAT(c.FirstName,' ',c.LastName) AS customername
        FROM public.Fixed_Deposit f JOIN public.Customer c USING(CustomerID)'''
        + (' WHERE f.CustomerID=%s' if customer_id is not None else '') + ' ORDER BY f.FD_ID DESC',
        (customer_id,) if customer_id is not None else ())

def beneficiaries(customer_id):
    return db.fetch_all('''SELECT b.*,d.BankName FROM public.Beneficiary b
        JOIN public.Bank_Directory d USING(IFSC_Code) WHERE b.CustomerID=%s ORDER BY b.BeneficiaryID''', (customer_id,))

def overview(customer_id):
    profile = customer(customer_id)
    totals = db.fetch_one('''SELECT public.fn_customer_net_worth(%s) AS net_worth,
        (SELECT COALESCE(SUM(Balance),0) FROM public.Account WHERE CustomerID=%s) AS liquid_balance,
        (SELECT COALESCE(SUM(Balance),0) FROM public.Account WHERE CustomerID=%s AND AccountType='Savings') AS savings_balance,
        (SELECT COALESCE(SUM(Balance),0) FROM public.Account WHERE CustomerID=%s AND AccountType='Current') AS current_balance,
        (SELECT COALESCE(SUM(Balance),0) FROM public.Account WHERE CustomerID=%s AND AccountType='Salary') AS salary_balance,
        (SELECT COALESCE(SUM(Amount),0) FROM public.Fixed_Deposit WHERE CustomerID=%s AND Status='Active') AS fd_principal,
        (SELECT COALESCE(SUM(MaturityAmount),0) FROM public.Fixed_Deposit WHERE CustomerID=%s AND Status='Active') AS fd_maturity,
        (SELECT COALESCE(SUM(OutstandingBalance),0) FROM public.Loan WHERE CustomerID=%s) AS loan_outstanding,
        (SELECT COUNT(*) FROM public.Beneficiary WHERE CustomerID=%s) AS beneficiary_count''', (customer_id,) * 9)
    return {'profile': profile, **totals}

def full360(customer_id):
    return {**overview(customer_id), 'accounts': accounts(customer_id),
            'transactions': transactions(customer_id), 'loans': loans(customer_id),
            'fixed_deposits': fixed_deposits(customer_id), 'beneficiaries': beneficiaries(customer_id)}

def preview_customers(search='', kyc_status=None):
    # Aggregate each product separately through scalar/LATERAL subqueries to
    # avoid multiplying balances when the owner has multiple loans and FDs.
    return db.fetch_all('''SELECT c.*, a.AccountCount,a.PrimaryAccountNo,a.TotalBalance,a.Accounts,
        (SELECT COUNT(*) FROM public.Loan l WHERE l.CustomerID=c.CustomerID
          AND l.Status IN ('Approved','Active','Defaulted')) AS activeloans,
        (SELECT COUNT(*) FROM public.Fixed_Deposit f WHERE f.CustomerID=c.CustomerID AND f.Status='Active') AS activefds
        FROM public.Customer c LEFT JOIN LATERAL (
            SELECT COUNT(*) AS AccountCount, MIN(AccountNo) AS PrimaryAccountNo,
                COALESCE(SUM(Balance),0) AS TotalBalance,
                COALESCE(JSONB_AGG(JSONB_BUILD_OBJECT('accountno',AccountNo,'type',AccountType,
                    'balance',Balance::text,'status',Status) ORDER BY AccountNo),'[]'::jsonb) AS Accounts
            FROM public.Account WHERE CustomerID=c.CustomerID) a ON true
        WHERE (%s IS NULL OR c.KYC_Status=%s) AND (%s='' OR
          CONCAT(c.CustomerID,' ',c.FirstName,' ',c.LastName,' ',c.PAN_Number) ILIKE %s
          OR EXISTS (SELECT 1 FROM public.Account z WHERE z.CustomerID=c.CustomerID AND z.AccountNo::text ILIKE %s))
        ORDER BY c.CustomerID''', (kyc_status, kyc_status, search, f'%{search}%', f'%{search}%'))

def lookups():
    return {
        'branches': db.fetch_all('''SELECT b.*,p.City,p.State,d.BankName FROM public.Branch b
            JOIN public.Postal_Directory p USING(Pincode) LEFT JOIN public.Bank_Directory d USING(IFSC_Code) ORDER BY b.BranchID'''),
        'postal_directory': db.fetch_all('SELECT * FROM public.Postal_Directory ORDER BY Pincode'),
        'bank_directory': db.fetch_all('SELECT * FROM public.Bank_Directory ORDER BY IFSC_Code'),
        'today': db.fetch_one('SELECT CURRENT_DATE AS today')['today'],
    }

def employees():
    return db.fetch_all('''SELECT e.*,b.BranchName FROM public.Employee e
        JOIN public.Branch b USING(BranchID) ORDER BY e.EmployeeID''')

def dashboard():
    counts = {table: db.fetch_one(sql.SQL('SELECT COUNT(*) AS count FROM public.{}').format(
        sql.Identifier(table.lower())))['count'] for table in TABLES}
    totals = db.fetch_one('''SELECT
        (SELECT COALESCE(SUM(Balance),0) FROM public.Account WHERE Status<>'Closed') AS total_deposits,
        (SELECT COALESCE(SUM(OutstandingBalance),0) FROM public.Loan WHERE Status IN ('Approved','Active','Defaulted')) AS active_loan_book,
        (SELECT COALESCE(SUM(Amount),0) FROM public.Fixed_Deposit WHERE Status='Active') AS active_fd_book''')
    branch_summary = db.fetch_all('''SELECT v.*,COALESCE(a.deposits,0) AS total_deposits
        FROM public.vw_branch_financial_summary v LEFT JOIN (
            SELECT BranchID,SUM(Balance) AS deposits FROM public.Account WHERE Status<>'Closed' GROUP BY BranchID
        ) a USING(BranchID) ORDER BY BranchID''')
    return {'table_counts': counts, **totals, 'branches': branch_summary,
        'vellore_accounts': db.fetch_all('SELECT * FROM public.vw_active_vellore_accounts ORDER BY AccountNo'),
        'accounts_by_type': db.fetch_all('SELECT AccountType AS name,COUNT(*) AS value FROM public.Account GROUP BY AccountType ORDER BY AccountType'),
        'loans_by_type_status': db.fetch_all('SELECT LoanType,Status,COUNT(*) AS count,SUM(OutstandingBalance) AS outstanding FROM public.Loan GROUP BY LoanType,Status ORDER BY LoanType,Status'),
        'volume_by_mode': db.fetch_all('SELECT PaymentMode AS name,COUNT(*) AS count,SUM(Amount) AS volume FROM public.Transaction_History GROUP BY PaymentMode ORDER BY PaymentMode')}

def batch(maturity=False):
    with db.transaction() as cursor:
        # Serialize API runs and count this transaction's own postings, rather
        # than a before/after global audit total that another session can change.
        cursor.execute('SELECT pg_advisory_xact_lock(302,99)')
        cursor.execute('CALL public.sp_batch_mature_fixed_deposits()' if maturity else 'CALL public.sp_batch_credit_savings_interest()')
        if maturity:
            cursor.execute("SELECT COUNT(*) AS processed FROM public.Audit_Log WHERE ActionType='FD_MATURED' AND xmin::text=pg_current_xact_id()::text")
        else:
            cursor.execute("SELECT COUNT(*) AS processed FROM public.Transaction_History WHERE Remarks='Monthly Interest Credit' AND xmin::text=pg_current_xact_id()::text")
        return cursor.fetchone()['processed']
