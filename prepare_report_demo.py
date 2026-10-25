"""Prepare isolated report examples. Never modify banking_db."""
from pathlib import Path
import subprocess
import json

ROOT = Path(__file__).resolve().parent
WORK = ROOT / '.report_work' / 'review3-final-evidence'
SQL = ROOT / 'report_screenshots' / 'review3' / 'supplemental'
SQL.mkdir(parents=True, exist_ok=True)
DB = 'banking_report_demo'


def execute(sql, database=DB, tuples=False):
    args = ['docker', 'exec', '-i', 'banking-postgres', 'psql', '-X',
            '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', database]
    if tuples:
        args += ['-At']
    result = subprocess.run(args, input=sql.encode(), capture_output=True, check=True)
    return result.stdout.decode()


def live_fingerprint():
    tables = ['postal_directory', 'bank_directory', 'branch', 'customer', 'account',
              'transaction_history', 'loan', 'loan_repayment', 'beneficiary',
              'fixed_deposit', 'employee', 'audit_log']
    return {t: execute(f"SELECT COUNT(*), MD5(COALESCE(STRING_AGG(row_json, '' ORDER BY row_json), '')) "
                       f"FROM (SELECT row_to_json(t)::text AS row_json FROM public.{t} t) s;",
                       'banking_db', True).strip() for t in tables}


def main():
    (WORK / 'banking_db_before.json').write_text(json.dumps(live_fingerprint(), indent=2))
    prep = """
DO $$ BEGIN
 IF current_database() <> 'banking_report_demo' THEN
   RAISE EXCEPTION 'Demo setup must run only in the isolated database';
 END IF;
END $$;
CREATE SCHEMA report_evidence;
CREATE TABLE report_evidence.account_before AS
SELECT 'transfer'::text AS phase, AccountNo, Balance FROM Account
WHERE AccountNo IN (100001, 100003);
CREATE TABLE report_evidence.ids_before AS
SELECT MAX(TransactionID) AS transaction_id, (SELECT MAX(LogID) FROM Audit_Log) AS audit_id
FROM Transaction_History;
-- Dedicated fixtures exist only in the demo copy.
INSERT INTO Account(AccountNo,CustomerID,BranchID,AccountType,Balance,InterestRate,OpeningDate,Status)
VALUES(900001,1,1,'Savings',100000,6,CURRENT_DATE-365,'Active');
INSERT INTO report_evidence.account_before
SELECT 'interest',AccountNo,Balance FROM Account WHERE AccountNo=900001;
INSERT INTO Fixed_Deposit(FD_ID,CustomerID,Amount,InterestRate,StartDate,EndDate,Status)
VALUES(900001,1,50000,7,CURRENT_DATE-366,CURRENT_DATE-1,'Active');
CREATE TABLE report_evidence.fd_before AS
SELECT f.FD_ID,f.Status,f.MaturityAmount,a.AccountNo,a.Balance
FROM Fixed_Deposit f JOIN LATERAL (
 SELECT AccountNo,Balance FROM Account
 WHERE CustomerID=f.CustomerID AND AccountType='Savings' AND Status='Active'
 ORDER BY OpeningDate,AccountNo LIMIT 1
) a ON TRUE WHERE f.FD_ID=900001;
"""
    print(execute(prep))
    print(execute("CALL public.sp_transfer_funds(100001,100003,1000,'UPI','Report transfer demonstration');"))
    print(execute("CREATE TABLE report_evidence.transfer_after AS SELECT a.AccountNo,a.Balance,(SELECT Description FROM Audit_Log l WHERE LOWER(l.TableName)='account' AND l.RecordID=a.AccountNo ORDER BY LogID DESC LIMIT 1) AS balance_audit FROM Account a WHERE a.AccountNo IN (100001,100003);"))
    # Save maturity starting balance after the transfer, so the later delta is exact.
    print(execute("UPDATE report_evidence.fd_before b SET Balance=a.Balance FROM Account a WHERE a.AccountNo=b.AccountNo;"))
    print(execute('CALL public.sp_batch_credit_savings_interest();'))
    # The old savings accounts already have monthly markers; the dedicated account
    # is the newly eligible record. Refresh payout baseline after the interest batch.
    print(execute("UPDATE report_evidence.fd_before b SET Balance=a.Balance FROM Account a WHERE a.AccountNo=b.AccountNo;"))
    print(execute('CALL public.sp_batch_mature_fixed_deposits();'))
    queries = {
        'TRANSFER-SUCCESS': """-- Executed: CALL sp_transfer_funds(100001,100003,1000,'UPI','Report transfer demonstration');
-- Actual committed balances saved immediately after the procedure CALL.
SELECT b.AccountNo,b.Balance AS balance_before,s.Balance AS balance_after,
       s.Balance-b.Balance AS balance_change,t.Amount,t.Remarks
FROM report_evidence.account_before b
JOIN report_evidence.transfer_after s ON s.AccountNo=b.AccountNo
JOIN Transaction_History t ON t.AccountNo=b.AccountNo
WHERE b.phase='transfer' AND t.Remarks LIKE '%Report transfer demonstration'
ORDER BY b.AccountNo;""",
        'TRANSFER-HISTORY': """-- The committed transfer creates one debit and one credit history event.
SELECT t.TransactionID,t.AccountNo,t.Amount,t.Remarks,s.balance_audit
FROM Transaction_History t
JOIN report_evidence.transfer_after s ON s.AccountNo=t.AccountNo
WHERE t.Remarks LIKE '%Report transfer demonstration'
ORDER BY TransactionID;""",
        'CURSOR-INTEREST': """-- Executed: CALL sp_batch_credit_savings_interest();
-- New eligible Savings account in banking_report_demo; rate is 6 percent annually.
SELECT a.AccountNo,b.Balance AS balance_before,a.Balance AS balance_after,
       ROUND(b.Balance*a.InterestRate/1200,2) AS calculated_interest,
       t.Amount AS posted_interest,t.Remarks,
       (a.Balance-b.Balance=t.Amount) AS balance_verified
FROM Account a JOIN report_evidence.account_before b
  ON b.AccountNo=a.AccountNo AND b.phase='interest'
JOIN Transaction_History t ON t.AccountNo=a.AccountNo
WHERE a.AccountNo=900001 AND t.Remarks='Monthly Interest Credit';""",
        'CURSOR-MATURITY': """-- Executed: CALL sp_batch_mature_fixed_deposits();
-- Dedicated matured FD fixture in banking_report_demo.
SELECT f.FD_ID,b.Status AS status_before,f.Status AS status_after,
       f.MaturityAmount AS payout,b.Balance AS balance_before,
       a.Balance AS balance_after,l.ActionType AS audit_event
FROM Fixed_Deposit f JOIN report_evidence.fd_before b ON b.FD_ID=f.FD_ID
JOIN Account a ON a.AccountNo=b.AccountNo
JOIN Transaction_History t ON t.AccountNo=a.AccountNo
  AND t.Remarks='FD Maturity Credit: 900001'
JOIN Audit_Log l ON l.RecordID=f.FD_ID AND l.TableName='Fixed_Deposit'
  AND l.ActionType='FD_MATURED'
WHERE f.FD_ID=900001;""",
        'INDEX-WITHOUT': """-- banking_report_demo: named index absent for the baseline.
EXPLAIN (ANALYZE, BUFFERS)
SELECT TransactionID,AccountNo,TransactionDate,Amount
FROM public.Transaction_History
WHERE AccountNo=100001
  AND TransactionDate>=CURRENT_DATE-INTERVAL '365 days'
ORDER BY TransactionDate;""",
        'INDEX-WITH': """-- banking_report_demo: idx_txn_account_date restored.
EXPLAIN (ANALYZE, BUFFERS)
SELECT TransactionID,AccountNo,TransactionDate,Amount
FROM public.Transaction_History
WHERE AccountNo=100001
  AND TransactionDate>=CURRENT_DATE-INTERVAL '365 days'
ORDER BY TransactionDate;""",
    }
    for name, sql in queries.items():
        (SQL / f'{name}.sql').write_text(sql + '\n', encoding='utf-8')
    print('Prepared fixtures and verification query files in', SQL)


if __name__ == '__main__':
    main()
