"""CoreBank workflow API: uv run uvicorn backend.main:app --reload.

The requested demo identity selector is not authentication. This local API is
intended for a university demonstration, not an Internet-facing banking service.
"""
from decimal import Decimal
from typing import Annotated
import psycopg2
from fastapi import FastAPI, HTTPException, Path, Query, Request
from fastapi.encoders import jsonable_encoder
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from backend import database as db, services as s
from backend.models import (
    AccountCreate, AccountStatusUpdate, BankCreate, BeneficiaryRequest, BranchCreate,
    CashRequest, CustomerCreate, EMIRequest, EmployeeCreate, FDRequest, KYCUpdate,
    LoanCreate, LoginRequest, PostalCreate, TransferRequest,
)

app = FastAPI(title='CoreBank Workflow API', version='2.0.0', description=(
    'Comprehensive twelve-table banking demonstration. Simulated identities, no access tokens. '
    'All monetary values are serialized as decimal strings; database column keys are lowercase.'))
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_credentials=False,
                   allow_methods=['*'], allow_headers=['*'])
ID = Annotated[int, Path(ge=1, le=2_147_483_647)]

def response(data, status=200):
    return JSONResponse(status_code=status, content=jsonable_encoder(data, custom_encoder={Decimal: str}))

def success(message, **data):
    return response({'success': True, 'message': message, **data})

@app.exception_handler(psycopg2.Error)
async def database_failure(request: Request, error: psycopg2.Error):
    code = error.pgcode or ''
    status = 409 if code.startswith('40') or code == '55P03' else (
        503 if isinstance(error, (psycopg2.OperationalError, psycopg2.InterfaceError)) else (
            400 if code.startswith(('22', '23')) or code == 'P0001' else 500))
    # Retain the ORIGINAL server text (constraint, DETAIL, CONTEXT) for viva
    # demonstrations. The connection context already rolled back all mutations.
    return response({'success': False, 'detail': f'Transaction Failed: {error}', 'sqlstate': error.pgcode}, status)

@app.get('/api/health', tags=['Discovery'])
def health():
    db.fetch_one('SELECT 1')
    return {'status': 'ok', 'database': 'connected'}

@app.get('/api/directory/customers-preview', tags=['Discovery'])
def customers_preview():
    return response(s.preview_customers())

@app.get('/api/directory/employees-preview', tags=['Discovery'])
def employees_preview():
    return response(s.employees())

@app.get('/api/lookups', tags=['Discovery'])
def lookups():
    return response(s.lookups())

@app.post('/api/login', tags=['Discovery'])
def login(payload: LoginRequest):
    if payload.role == 'Admin':
        if payload.employee_id is not None:
            employee = db.fetch_one('''SELECT e.*,b.BranchName FROM public.Employee e
                JOIN public.Branch b USING(BranchID) WHERE e.EmployeeID=%s''', (payload.employee_id,))
            if not employee:
                s.fail('Bank official not found', 404)
            user = {'id': employee['employeeid'], 'role': 'Admin', 'employee_id': employee['employeeid'],
                    'name': f"{employee['firstname']} {employee['lastname']}",
                    'title': employee['role'], 'branchid': employee['branchid'], 'branchname': employee['branchname']}
        else:
            user = {'id': payload.id, 'role': 'Admin', 'name': 'Bank Administrator', 'title': 'System Admin'}
    else:
        customer_id = payload.id
        if payload.identity_type == 'account':
            account = db.fetch_one('SELECT CustomerID FROM public.Account WHERE AccountNo=%s', (payload.id,))
            if not account:
                s.fail('Account not found', 404)
            customer_id = account['customerid']
        c = s.customer(customer_id)
        user = {'id': c['customerid'], 'role': 'Customer', 'name': f"{c['firstname']} {c['lastname']}",
                'email': c['email'], 'kyc_status': c['kyc_status']}
    return {'success': True, 'user': user}

@app.get('/api/customer/{customer_id}/overview', tags=['Customer'])
def overview(customer_id: ID):
    return response(s.overview(customer_id))

@app.get('/api/customer/{customer_id}/accounts', tags=['Customer'])
def accounts(customer_id: ID):
    s.customer(customer_id)
    return response(s.accounts(customer_id))

@app.get('/api/customer/{customer_id}/transactions', tags=['Customer'])
def transactions(customer_id: ID, account_no: int | None = Query(None, ge=1),
                 txn_type: str | None = None, payment_mode: str | None = None):
    s.customer(customer_id)
    return response(s.transactions(customer_id, account_no, txn_type or None, payment_mode or None))

@app.get('/api/customer/{customer_id}/passbook', tags=['Customer'])
def passbook(customer_id: ID):
    s.customer(customer_id)
    return response(db.fetch_all('''SELECT p.* FROM public.vw_customer_passbook p
        JOIN public.Account a USING(AccountNo) WHERE a.CustomerID=%s
        ORDER BY p.Date DESC NULLS LAST,p.AccountNo''', (customer_id,)))

@app.get('/api/customer/{customer_id}/net-worth', tags=['Customer'])
def net_worth(customer_id: ID):
    s.customer(customer_id)
    return response({'customer_id': customer_id, **db.fetch_one(
        'SELECT public.fn_customer_net_worth(%s) AS net_worth', (customer_id,))})

@app.post('/api/transaction/deposit', tags=['Transactions'])
def deposit(payload: CashRequest):
    return success('Deposit committed; balance audit trigger fired.', **s.cash(payload))

@app.post('/api/transaction/withdraw', tags=['Transactions'])
def withdraw(payload: CashRequest):
    return success('Withdrawal committed; balance audit trigger fired.', **s.cash(payload, True))

@app.post('/api/transaction/transfer', tags=['Transactions'])
def transfer(payload: TransferRequest):
    # SQL exceptions propagate to database_failure with their exact text.
    return success('Transfer committed successfully.', **s.transfer(payload))

@app.get('/api/customer/{customer_id}/beneficiaries', tags=['Beneficiaries'])
def beneficiaries(customer_id: ID):
    s.customer(customer_id)
    return response(s.beneficiaries(customer_id))

@app.post('/api/customer/{customer_id}/beneficiaries', tags=['Beneficiaries'])
def add_beneficiary(customer_id: ID, payload: BeneficiaryRequest):
    with db.transaction() as cursor:
        s.customer(customer_id, cursor)
        s.ensure_bank(cursor, payload.ifsc_code, payload.bank_name)
        cursor.execute('''INSERT INTO public.Beneficiary
            (CustomerID,BeneficiaryName,LinkedAccountNo,IFSC_Code,MaxTransferLimit)
            VALUES (%s,%s,%s,%s,%s) RETURNING *''',
            (customer_id, payload.beneficiary_name, payload.linked_account_no, payload.ifsc_code, payload.max_transfer_limit))
        result = dict(cursor.fetchone())
    return success('Beneficiary saved; IFSC directory integrity preserved.', beneficiary=result)

@app.delete('/api/beneficiaries/{beneficiary_id}', tags=['Beneficiaries'])
def delete_beneficiary(beneficiary_id: ID, customer_id: int = Query(..., ge=1)):
    with db.transaction() as cursor:
        cursor.execute('DELETE FROM public.Beneficiary WHERE BeneficiaryID=%s AND CustomerID=%s RETURNING BeneficiaryID',
                       (beneficiary_id, customer_id))
        if not cursor.fetchone():
            s.fail('Beneficiary not found for this customer', 404)
    return success('Beneficiary deleted.')

@app.get('/api/customer/{customer_id}/loans', tags=['Loans'])
def customer_loans(customer_id: ID):
    s.customer(customer_id)
    return response(s.loans(customer_id))

@app.get('/api/loans/{loan_id}/repayments', tags=['Loans'])
def repayments(loan_id: ID, customer_id: int | None = Query(None, ge=1)):
    loan = db.fetch_one('SELECT CustomerID FROM public.Loan WHERE LoanID=%s', (loan_id,))
    if not loan:
        s.fail('Loan not found', 404)
    if customer_id is not None and loan['customerid'] != customer_id:
        s.fail('Loan does not belong to selected customer', 403)
    return response(db.fetch_all('SELECT * FROM public.Loan_Repayment WHERE LoanID=%s ORDER BY PaymentDate DESC NULLS LAST,PaymentID DESC', (loan_id,)))

@app.post('/api/loans/pay-emi', tags=['Loans'])
@app.post('/api/transaction/emi', tags=['Loans'])
def pay_emi(payload: EMIRequest):
    db.execute('CALL public.sp_pay_loan_emi(%s,%s,%s)', (payload.customer_id, payload.loan_id, payload.account_no))
    return success('EMI committed; repayment trigger reduced the loan outstanding balance.')

@app.get('/api/customer/{customer_id}/fixed-deposits', tags=['Fixed deposits'])
def customer_fds(customer_id: ID):
    s.customer(customer_id)
    return response(s.fixed_deposits(customer_id))

@app.post('/api/customer/{customer_id}/fixed-deposits', tags=['Fixed deposits'])
def open_fd(customer_id: ID, payload: FDRequest):
    with db.transaction() as cursor:
        s.customer(customer_id, cursor)
        fd_id = s.allocate(cursor, 'Fixed_Deposit', 'FD_ID', 4)
        if payload.account_no:
            s.debit(cursor, payload.account_no, payload.amount, customer_id, 'Internal', f'FD Funding: {fd_id}')
        cursor.execute('''INSERT INTO public.Fixed_Deposit (FD_ID,CustomerID,Amount,InterestRate,StartDate,EndDate)
            VALUES (%s,%s,%s,%s,COALESCE(%s,CURRENT_DATE),%s) RETURNING *''',
            (fd_id, customer_id, payload.amount, payload.interest_rate, payload.start_date, payload.end_date))
        result = dict(cursor.fetchone())
    return success('Fixed deposit opened; PostgreSQL generated the maturity amount.', fixed_deposit=result)

@app.get('/api/admin/dashboard', tags=['Admin analytics'])
def dashboard():
    return response(s.dashboard())

@app.get('/api/admin/summary', tags=['Admin analytics'])
def branch_summary():
    return response(db.fetch_all('SELECT * FROM public.vw_branch_financial_summary ORDER BY BranchID'))

@app.get('/api/admin/customers-master', tags=['Customer administration'])
def customers_master(search: str = '', kyc_status: str | None = None):
    return response(s.preview_customers(search, kyc_status or None))

@app.get('/api/admin/customer/{customer_id}/full-360', tags=['Customer administration'])
def full360(customer_id: ID):
    return response(s.full360(customer_id))

@app.post('/api/admin/customers', tags=['Customer administration'])
def create_customer(payload: CustomerCreate):
    with db.transaction() as cursor:
        customer_id = s.allocate(cursor, 'Customer', 'CustomerID', 1)
        cursor.execute('''INSERT INTO public.Customer
            (CustomerID,FirstName,LastName,Gender,Age,Address,Phone,Email,PAN_Number,KYC_Status)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *''',
            (customer_id, payload.first_name, payload.last_name, payload.gender, payload.age, payload.address,
             payload.phone, payload.email, payload.pan_number, payload.kyc_status))
        result = dict(cursor.fetchone())
    return success('Customer onboarded.', customer=result)

@app.patch('/api/admin/customers/{customer_id}/kyc', tags=['Customer administration'])
def update_kyc(customer_id: ID, payload: KYCUpdate):
    with db.transaction() as cursor:
        cursor.execute('UPDATE public.Customer SET KYC_Status=%s WHERE CustomerID=%s RETURNING *', (payload.kyc_status, customer_id))
        row = cursor.fetchone()
        if not row:
            s.fail('Customer not found', 404)
        result = dict(row)
    return success('KYC status updated.', customer=result)

@app.get('/api/admin/accounts', tags=['Account administration'])
def all_accounts():
    return response(s.accounts())

@app.post('/api/admin/accounts', tags=['Account administration'])
def open_account(payload: AccountCreate):
    with db.transaction() as cursor:
        s.customer(payload.customer_id, cursor)
        account_no = s.allocate(cursor, 'Account', 'AccountNo', 2)
        cursor.execute('''INSERT INTO public.Account
            (AccountNo,CustomerID,BranchID,AccountType,Balance,InterestRate)
            VALUES (%s,%s,%s,%s,%s,%s) RETURNING *''',
            (account_no, payload.customer_id, payload.branch_id, payload.account_type, payload.balance, payload.interest_rate))
        result = dict(cursor.fetchone())
        if payload.balance > 0:
            s.history(cursor, account_no, payload.balance, 'Deposit', 'Cash', 'Initial account deposit')
    return success('Account opened; initial deposit recorded.', account=result)

@app.patch('/api/admin/accounts/{account_no}/status', tags=['Account administration'])
def account_status(account_no: ID, payload: AccountStatusUpdate):
    with db.transaction() as cursor:
        cursor.execute('UPDATE public.Account SET Status=%s WHERE AccountNo=%s RETURNING *', (payload.status, account_no))
        row = cursor.fetchone()
        if not row:
            s.fail('Account not found', 404)
        result = dict(row)
    return success('Account status updated.', account=result)

@app.get('/api/admin/loans', tags=['Loan administration'])
def all_loans():
    return response(s.loans())

@app.get('/api/admin/emi-preview', tags=['Loan administration'])
def emi_preview(principal: Decimal = Query(..., gt=0), rate: Decimal = Query(..., ge=0), months: int = Query(..., ge=1, le=600)):
    return response(db.fetch_one('SELECT public.fn_calculate_emi(%s,%s,%s) AS emi_amount', (principal, rate, months)))

@app.post('/api/admin/loans', tags=['Loan administration'])
def issue_loan(payload: LoanCreate):
    with db.transaction() as cursor:
        s.customer(payload.customer_id, cursor)
        loan_id = s.allocate(cursor, 'Loan', 'LoanID', 3)
        cursor.execute('''INSERT INTO public.Loan (LoanID,CustomerID,BranchID,LoanType,PrincipalAmount,
            InterestRate,TenureMonths,OutstandingBalance,Status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *''',
            (loan_id, payload.customer_id, payload.branch_id, payload.loan_type, payload.principal_amount,
             payload.interest_rate, payload.tenure_months, payload.principal_amount, 'Active' if payload.account_no else 'Approved'))
        result = dict(cursor.fetchone())
        if payload.account_no:
            s.locked_account(cursor, payload.account_no, payload.customer_id)
            cursor.execute('UPDATE public.Account SET Balance=Balance+%s WHERE AccountNo=%s', (payload.principal_amount, payload.account_no))
            s.history(cursor, payload.account_no, payload.principal_amount, 'Deposit', 'Internal', f'Loan Disbursement: {loan_id}')
    return success('Loan sanctioned; PostgreSQL generated EMI.', loan=result)

@app.get('/api/admin/fixed-deposits', tags=['Fixed deposits'])
def all_fds(status: str | None = None):
    rows = s.fixed_deposits()
    return response([row for row in rows if not status or row['status'] == status])

@app.get('/api/admin/infrastructure', tags=['Infrastructure'])
def infrastructure():
    return response({**s.lookups(), 'employees': s.employees()})

@app.post('/api/admin/postal-directory', tags=['Infrastructure'])
def add_postal(payload: PostalCreate):
    with db.transaction() as cursor:
        s.ensure_postal(cursor, payload.pincode, payload.city, payload.state)
    return success('Postal directory entry saved.')

@app.post('/api/admin/bank-directory', tags=['Infrastructure'])
def add_bank(payload: BankCreate):
    with db.transaction() as cursor:
        s.ensure_bank(cursor, payload.ifsc_code, payload.bank_name)
    return success('Bank directory entry saved.')

@app.post('/api/admin/branches', tags=['Infrastructure'])
def add_branch(payload: BranchCreate):
    with db.transaction() as cursor:
        s.ensure_postal(cursor, payload.pincode, payload.city, payload.state)
        s.ensure_bank(cursor, payload.ifsc_code, payload.bank_name)
        branch_id = s.allocate(cursor, 'Branch', 'BranchID', 5)
        cursor.execute('''INSERT INTO public.Branch (BranchID,BranchName,Address,Pincode,IFSC_Code,ContactPhone)
            VALUES (%s,%s,%s,%s,%s,%s) RETURNING *''',
            (branch_id, payload.branch_name, payload.address, payload.pincode, payload.ifsc_code, payload.contact_phone))
        row = dict(cursor.fetchone())
    return success('Branch created with normalized postal and bank lookups.', branch=row)

@app.post('/api/admin/employees', tags=['Infrastructure'])
def add_employee(payload: EmployeeCreate):
    with db.transaction() as cursor:
        employee_id = s.allocate(cursor, 'Employee', 'EmployeeID', 6)
        cursor.execute('''INSERT INTO public.Employee
            (EmployeeID,BranchID,FirstName,LastName,Email,Role,Salary,HireDate)
            VALUES (%s,%s,%s,%s,%s,%s,%s,COALESCE(%s,CURRENT_DATE)) RETURNING *''',
            (employee_id, payload.branch_id, payload.first_name, payload.last_name, payload.email,
             payload.role, payload.salary, payload.hire_date))
        row = dict(cursor.fetchone())
    return success('Bank official added.', employee=row)

@app.post('/api/admin/batch/interest', tags=['Batch cursors'])
def interest_batch():
    count = s.batch()
    return success(f'Savings interest batch committed: {count} accounts credited.', processed=count)

@app.post('/api/admin/batch/mature-fds', tags=['Batch cursors'])
def maturity_batch():
    count = s.batch(True)
    return success(f'FD maturity batch committed: {count} deposits settled.', processed=count)

@app.get('/api/admin/audit-log', tags=['Audit'])
def audit_log(table_name: str | None = None, action_type: str | None = None):
    return response(db.fetch_all('''SELECT * FROM public.Audit_Log
        WHERE (%s IS NULL OR TableName=%s) AND (%s IS NULL OR ActionType=%s)
        ORDER BY LogDate DESC NULLS LAST,LogID DESC LIMIT 100''',
        (table_name or None, table_name or None, action_type or None, action_type or None)))

@app.get('/api/admin/programmability', tags=['Admin analytics'])
def programmability():
    return response({
        'views': db.fetch_all("SELECT viewname FROM pg_views WHERE schemaname='public' ORDER BY viewname"),
        'routines': db.fetch_all("SELECT p.proname,p.prokind,pg_get_function_identity_arguments(p.oid) AS arguments FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY p.proname"),
        'triggers': db.fetch_all("SELECT t.tgname,c.relname AS table_name,pg_get_triggerdef(t.oid) AS definition FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname='public'")})
