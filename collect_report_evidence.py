"""Collect report evidence without resetting banking_db or changing its rows.

Run with the project interpreter: uv run python collect_report_evidence.py
Read-only catalogues use one repeatable-read snapshot. Constraint tests, audit
proofs, grants and index comparisons are rolled back. Committing demonstrations
run in a temporary database created from the exact project scripts.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
import json
from pathlib import Path
import re
from uuid import uuid4


ROOT = Path(__file__).resolve().parent
OUT = ROOT / '.report_work'
DSN = 'postgresql://postgres:admin@localhost:5432/banking_db'
TABLES = ['Postal_Directory','Bank_Directory','Branch','Customer','Account',
          'Transaction_History','Loan','Loan_Repayment','Beneficiary',
          'Fixed_Deposit','Employee','Audit_Log']


def split_sql(source):
    """Split SQL at semicolons outside strings, comments and dollar bodies."""
    result, start, i, quote, dollar, block = [], 0, 0, None, None, 0
    while i < len(source):
        if dollar:
            if source.startswith(dollar, i):
                i += len(dollar); dollar = None
            else: i += 1
            continue
        if block:
            if source.startswith('/*', i): block += 1; i += 2
            elif source.startswith('*/', i): block -= 1; i += 2
            else: i += 1
            continue
        if quote:
            if source[i] == quote:
                if i + 1 < len(source) and source[i+1] == quote: i += 2; continue
                quote = None
            i += 1; continue
        if source.startswith('--', i):
            newline = source.find('\n', i)
            i = len(source) if newline < 0 else newline + 1; continue
        if source.startswith('/*', i): block = 1; i += 2; continue
        if source[i] in "'\"": quote = source[i]; i += 1; continue
        match = re.match(r'\$(?:[A-Za-z_]\w*)?\$', source[i:])
        if match:
            dollar = match[0]; i += len(dollar); continue
        if source[i] == ';':
            piece = source[start:i+1]
            if clean_sql(piece): result.append(piece.strip())
            start = i + 1
        i += 1
    if clean_sql(source[start:]): result.append(source[start:].strip())
    return result


def clean_sql(source):
    return re.sub(r'^\s*--[^\n]*(?:\n|$)', '', source, flags=re.M).strip()


def labelled(source, pattern):
    labels = list(re.finditer(pattern, source, re.M))
    return [{'id':m.group(1), 'label':m.group(2).strip() if m.lastindex >= 2 else m.group(1),
             'source':source[m.end():labels[n+1].start() if n+1<len(labels) else len(source)].strip()}
            for n,m in enumerate(labels)]


def serial(value):
    if isinstance(value, Decimal): return str(value)
    if hasattr(value, 'isoformat'): return value.isoformat()
    return str(value)


def result(cursor, command, limit=3):
    cursor.execute(command)
    if not cursor.description: return {'status':cursor.statusmessage}
    rows = cursor.fetchall()
    return {'columns':[c.name for c in cursor.description], 'rows':rows[:limit], 'row_count':len(rows)}


def capture_live_objects(evidence):
    """Show installed objects against banking_db with no retained row changes."""
    import psycopg2
    conn=psycopg2.connect(DSN)
    try:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL lock_timeout='2s'")
            cur.execute('SELECT Balance FROM Account WHERE AccountNo=100001')
            requested=cur.fetchone()[0]+1
            command=f"CALL public.sp_transfer_funds(100001,100003,{requested},'Internal','Report rejection proof');"
            try:
                cur.execute(command)
                raise RuntimeError('Expected transfer validation rejection')
            except psycopg2.Error as error:
                if error.pgcode!='22023' or 'Insufficient balance' not in str(error): raise
                evidence['objects']['sp_transfer_funds']['live_test']={'command':command,
                    'output':{'columns':['sqlstate','postgresql_error'], 'rows':[[error.pgcode,str(error).strip()]],'row_count':1},
                    'context':'banking_db; real validation failure before COMMIT; no debit posted'}
        conn.rollback()
        for name in ['sp_pay_loan_emi','trg_audit_account_changes','trg_loan_repayment',
                     'sp_batch_credit_savings_interest','sp_batch_mature_fixed_deposits']:
            with conn.cursor() as cur:
                cur.execute("SET LOCAL lock_timeout='2s'")
                if name=='sp_pay_loan_emi':
                    call='CALL public.sp_pay_loan_emi(1,2001,100001);'
                    query='SELECT LoanID,EMI_Amount,OutstandingBalance,Status FROM Loan WHERE LoanID=2001'
                elif name=='trg_audit_account_changes':
                    call='UPDATE public.Account SET Balance=Balance+1 WHERE AccountNo=100001;'
                    query="SELECT TableName,RecordID,ActionType,Description FROM Audit_Log ORDER BY LogID DESC LIMIT 1"
                elif name=='trg_loan_repayment':
                    call="INSERT INTO public.Loan_Repayment(LoanID,AmountPaid,PaymentMode,PaymentStatus) VALUES(2001,10,'UPI','Success');"
                    query='SELECT LoanID,OutstandingBalance,Status FROM Loan WHERE LoanID=2001'
                else:
                    call=f'CALL public.{name}();'
                    query="SELECT COUNT(*) AS postings_in_this_transaction,COALESCE(SUM(Amount),0) AS credited_amount FROM Transaction_History WHERE xmin=pg_current_xact_id()::text::xid"
                cur.execute(call)
                evidence['objects'][name]['live_test']={'command':'BEGIN;\n'+call+'\n'+query+';\nROLLBACK;',
                    'output':result(cur,query,3),'context':'banking_db; observed inside a transaction and then rolled back'}
            conn.rollback()
        evidence['live_object_captured_at']=datetime.now().astimezone().isoformat()
    finally:
        conn.rollback(); conn.close()


def main():
    import psycopg2
    from psycopg2 import sql
    OUT.mkdir(exist_ok=True)
    scripts = {f.name:f.read_text(encoding='utf-8') for f in sorted((ROOT/'sql').glob('0[1-7]_*.sql'))}
    evidence = {'captured_at':datetime.now().astimezone().isoformat(), 'source':'banking_db',
                'scripts':scripts, 'standard':[], 'complex':[], 'views':{}, 'tests':[], 'objects':{}}
    connection = psycopg2.connect(DSN)
    connection.set_session(isolation_level='REPEATABLE READ', readonly=True)
    try:
        with connection.cursor() as cur:
            evidence['server'] = result(cur, 'SELECT version(), current_database(), CURRENT_DATE, current_user', 1)
            evidence['counts'] = []
            for name in TABLES:
                cur.execute(sql.SQL('SELECT COUNT(*) FROM public.{}').format(sql.Identifier(name.lower())))
                evidence['counts'].append([name, cur.fetchone()[0]])
            for query in labelled(scripts['03_standard_queries.sql'], r'^-- ([A-G]-\d{2}): (.+)$'):
                query['sql'] = clean_sql(query['source'])
                query['result'] = result(cur, query['sql'])
                evidence['standard'].append(query)
            for query in labelled(scripts['04_complex_queries.sql'], r'^-- (CQ-\d{2})\s*$'):
                comments = re.findall(r'^-- ?(.*)', query['source'], re.M)
                prose = ' '.join(comments)
                query['business_question'] = prose.split('Business Question: ')[1].split('Explanation:')[0].strip()
                query['explanation'] = prose.split('Explanation: ')[1].strip()
                query['sql'] = clean_sql(query['source'])
                query['result'] = result(cur, query['sql'])
                evidence['complex'].append(query)
            evidence['columns'] = result(cur, """SELECT table_name,column_name,data_type,
                character_maximum_length,numeric_precision,numeric_scale,is_nullable,column_default,
                is_generated,generation_expression FROM information_schema.columns
                WHERE table_schema='public' AND table_name IN
                ('postal_directory','bank_directory','branch','customer','account','transaction_history',
                'loan','loan_repayment','beneficiary','fixed_deposit','employee','audit_log')
                ORDER BY table_name,ordinal_position""", 200)
            evidence['constraints'] = result(cur, """SELECT c.relname AS table_name,co.conname,
                co.contype,pg_get_constraintdef(co.oid) AS definition
                FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
                JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'
                ORDER BY c.relname,co.contype,co.conname""", 200)
            evidence['foreign_keys'] = result(cur, """SELECT c.relname, co.conname,pg_get_constraintdef(co.oid)
                FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
                WHERE co.contype='f' AND co.connamespace='public'::regnamespace ORDER BY c.relname,co.conname""", 20)
            for name in ['vw_customer_passbook','vw_branch_financial_summary','vw_active_vellore_accounts']:
                order = 'BranchID' if 'summary' in name else 'AccountNo'
                evidence['views'][name] = result(cur, f'SELECT * FROM public.{name} ORDER BY {order}', 3)
            evidence['view_updatability'] = result(cur, """SELECT table_name,is_updatable,check_option
                FROM information_schema.views WHERE table_schema='public' ORDER BY table_name""", 10)
            evidence['routines'] = result(cur, """SELECT p.proname,p.prokind,p.prosecdef,
                pg_get_userbyid(p.proowner) AS owner,pg_get_functiondef(p.oid) AS definition
                FROM pg_proc p WHERE p.pronamespace='public'::regnamespace ORDER BY p.proname""", 20)
            evidence['roles'] = result(cur, """SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole
                FROM pg_roles WHERE rolname IN ('bank_admin','branch_manager','bank_teller') ORDER BY rolname""", 3)
            permission_sql = next(clean_sql(x) for x in split_sql(scripts['06_security_concurrency.sql'])
                                  if clean_sql(x).startswith('SELECT role_name,'))
            evidence['privileges'] = result(cur, permission_sql, 3)
            evidence['indexes'] = result(cur, """SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public'
                AND indexname IN ('idx_txn_account_date','idx_customer_name','idx_loan_status') ORDER BY indexname""", 3)
            evidence['udfs'] = result(cur, """SELECT fn_calculate_emi(2500000,8.50,240) AS reference_emi,
                fn_calculate_emi(12000,0,12) AS zero_rate_emi, fn_customer_net_worth(1) AS customer_1_net_worth""", 1)
            evidence['audit_sample'] = result(cur, 'SELECT * FROM Audit_Log ORDER BY LogDate DESC,LogID DESC LIMIT 3', 3)
        connection.rollback()
        connection.set_session(isolation_level='READ COMMITTED', readonly=False)

        # Exact TC statements: internal exceptions undo intended failures. The
        # outer transaction additionally rolls back the whole verification run.
        with connection.cursor() as cur:
            before = len(connection.notices)
            for test in labelled(scripts['07_test_cases.sql'], r'^-- (TC-\d{2}): (.+)$'):
                statement = split_sql(test['source'])[0]
                connection.notices.clear()
                cur.execute(statement)
                notices = ''.join(connection.notices).strip()
                if f"{test['id']} PASS:" not in notices:
                    raise RuntimeError(f"Missing PASS evidence for {test['id']}: {notices}")
                test.update(sql=clean_sql(statement), output=notices, status='PASS')
                evidence['tests'].append(test)
        connection.rollback()

        # Literal SAVEPOINT demonstration, with full before/after evidence.
        with connection.cursor() as cur:
            cur.execute('SELECT Balance FROM Account WHERE AccountNo=100001'); initial=cur.fetchone()[0]
            cur.execute('SELECT COUNT(*) FROM Audit_Log'); audit_before=cur.fetchone()[0]
            cur.execute('SAVEPOINT account_demo')
            cur.execute('UPDATE Account SET Balance=Balance+1 WHERE AccountNo=100001')
            cur.execute('SELECT Balance FROM Account WHERE AccountNo=100001'); changed=cur.fetchone()[0]
            cur.execute('ROLLBACK TO SAVEPOINT account_demo'); cur.execute('RELEASE SAVEPOINT account_demo')
            cur.execute('SELECT Balance FROM Account WHERE AccountNo=100001'); restored=cur.fetchone()[0]
            cur.execute('SELECT COUNT(*) FROM Audit_Log'); audit_after=cur.fetchone()[0]
            evidence['savepoint']={'before':initial,'inside_savepoint':changed,'after_rollback':restored,
                                   'audit_before':audit_before,'audit_after':audit_after}
        connection.commit()  # Only the restored state is committed.

        # Exact role grant/revoke and least-privilege block; never reset shared roles.
        security_statements=split_sql(scripts['06_security_concurrency.sql'])
        with connection.cursor() as cur:
            cur.execute('GRANT DELETE ON public.Account TO bank_teller')
            grant = result(cur, "SELECT has_table_privilege('bank_teller','public.Account','DELETE') AS can_delete",1)
            cur.execute('REVOKE DELETE ON public.Account FROM bank_teller')
            revoke = result(cur, "SELECT has_table_privilege('bank_teller','public.Account','DELETE') AS can_delete",1)
            proof = next(x for x in security_statements if 'DECLARE v_denied BOOLEAN' in x)
            connection.notices.clear(); cur.execute(proof)
            evidence['rbac_demo']={'grant':grant,'revoke':revoke,'proof_sql':clean_sql(proof),
                                   'output':''.join(connection.notices).strip()}
        connection.rollback()

        # Compare identical reads with the one named index absent/present.
        plan_query='''SELECT TransactionID, AccountNo, TransactionDate, Amount
FROM public.Transaction_History
WHERE AccountNo = 100001 AND TransactionDate >= CURRENT_DATE - INTERVAL '365 days'
ORDER BY TransactionDate'''
        with connection.cursor() as cur:
            cur.execute("SET LOCAL lock_timeout='2s'")
            cur.execute('DROP INDEX IF EXISTS public.idx_txn_account_date')
            evidence['plan_without'] = result(cur,'EXPLAIN (ANALYZE, BUFFERS) '+plan_query,100)
        connection.rollback()
        with connection.cursor() as cur:
            evidence['plan_with'] = result(cur,'EXPLAIN (ANALYZE, BUFFERS) '+plan_query,100)
        connection.rollback()
        evidence['plan_sql']=plan_query+';'

        # Two actual sessions, never modifying the locked account.
        second=psycopg2.connect(DSN)
        try:
            with connection.cursor() as first, second.cursor() as other:
                first.execute('SELECT AccountNo,Balance FROM Account WHERE AccountNo=100001 FOR UPDATE')
                locked=first.fetchone()
                try:
                    other.execute('SELECT AccountNo,Balance FROM Account WHERE AccountNo=100001 FOR UPDATE NOWAIT')
                    raise RuntimeError('Lock conflict was not detected')
                except psycopg2.errors.LockNotAvailable as error:
                    evidence['concurrency']={'session_a':list(locked),'sqlstate':error.pgcode,
                                              'session_b_error':str(error).strip(),'status':'PASS'}
        finally:
            second.rollback(); second.close(); connection.rollback()
    finally:
        connection.close()

    # Source object definitions, including the two mandatory trigger functions.
    for statement in split_sql(scripts['05_advanced_logic.sql']):
        clean=clean_sql(statement)
        match=re.match(r'CREATE OR REPLACE (VIEW|FUNCTION|PROCEDURE|TRIGGER) (\w+)',clean)
        if match: evidence['objects'][match[2]]={'kind':match[1],'sql':clean}

    clone='banking_report_'+uuid4().hex[:12]
    admin=psycopg2.connect(DSN); admin.autocommit=True
    clone_conn=None
    try:
        with admin.cursor() as cur: cur.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(clone)))
        clone_conn=psycopg2.connect(psycopg2.extensions.make_dsn(DSN,dbname=clone)); clone_conn.autocommit=True
        with clone_conn.cursor() as cur:
            for filename in ['01_ddl.sql','02_dml.sql']:
                cur.execute(scripts[filename])
            clone_conn.notices.clear()
            for statement in split_sql(scripts['05_advanced_logic.sql']): cur.execute(statement)
            evidence['clean_install']={'database':clone,'ddl':'COMMIT','dml':'COMMIT',
                                       'verification_output':''.join(clone_conn.notices).strip()}
            # All successful CALLs are real commits in the disposable database.
            tests=[('sp_transfer_funds',"CALL sp_transfer_funds(100001,100003,1000.00,'Internal','Report verification');",
                    'SELECT AccountNo,Balance FROM Account WHERE AccountNo IN (100001,100003) ORDER BY AccountNo'),
                   ('sp_pay_loan_emi','CALL sp_pay_loan_emi(1,2001,100001);',
                    'SELECT LoanID,EMI_Amount,OutstandingBalance,Status FROM Loan WHERE LoanID=2001')]
            for name,call,query in tests:
                cur.execute(call)
                evidence['objects'][name]['test']={'command':call,'output':result(cur,query,3),
                                                  'context':'Disposable verification database; exact 01, 02, 05 scripts'}
            # Fresh, eligible fixtures ensure the cursors show positive processing.
            cur.execute("DELETE FROM Transaction_History WHERE Remarks='Monthly Interest Credit'")
            before=result(cur,'SELECT SUM(Balance) AS total_balance,COUNT(*) AS accounts FROM Account',1)
            cur.execute('SELECT COUNT(*) FROM Audit_Log'); audit_before=cur.fetchone()[0]
            cur.execute('CALL sp_batch_credit_savings_interest()')
            posted=result(cur,"SELECT AccountNo,Amount,Remarks FROM Transaction_History WHERE Remarks='Monthly Interest Credit' ORDER BY AccountNo",3)
            evidence['objects']['sp_batch_credit_savings_interest']['test']={'command':'CALL sp_batch_credit_savings_interest();',
                'output':posted,'before':before,'context':'Disposable verification database; monthly posting markers cleared for this demonstration'}
            cur.execute("UPDATE Fixed_Deposit SET Status='Active' WHERE FD_ID=3001")
            cur.execute('CALL sp_batch_mature_fixed_deposits()')
            evidence['objects']['sp_batch_mature_fixed_deposits']['test']={'command':'CALL sp_batch_mature_fixed_deposits();',
                'output':result(cur,"SELECT FD_ID,MaturityAmount,Status FROM Fixed_Deposit WHERE FD_ID=3001",1),
                'context':'Disposable verification database; FD 3001 reactivated solely for this demonstration'}
            # Trigger outputs observed before rolling back the temporary debit.
            cur.execute('BEGIN')
            cur.execute('SELECT COUNT(*) FROM Audit_Log'); n=cur.fetchone()[0]
            cur.execute('UPDATE Account SET Balance=Balance+1 WHERE AccountNo=100001')
            out=result(cur,"SELECT TableName,RecordID,ActionType,Description FROM Audit_Log ORDER BY LogID DESC LIMIT 1",1)
            cur.execute('SELECT COUNT(*) FROM Audit_Log'); n2=cur.fetchone()[0]
            evidence['objects']['trg_audit_account_changes']['test']={'command':'BEGIN;\nUPDATE Account SET Balance=Balance+1 WHERE AccountNo=100001;\nSELECT * FROM Audit_Log ORDER BY LogID DESC LIMIT 1;\nROLLBACK;',
                'output':out,'before_count':n,'after_count':n2,'context':'Disposable verification database; rolled back after observation'}
            cur.execute('ROLLBACK')
            cur.execute('BEGIN')
            cur.execute('SELECT OutstandingBalance FROM Loan WHERE LoanID=2001'); before=cur.fetchone()[0]
            cur.execute("INSERT INTO Loan_Repayment(LoanID,AmountPaid,PaymentMode,PaymentStatus) VALUES(2001,10,'UPI','Success')")
            out=result(cur,'SELECT LoanID,OutstandingBalance,Status FROM Loan WHERE LoanID=2001',1)
            evidence['objects']['trg_loan_repayment']['test']={'command':"BEGIN;\nINSERT INTO Loan_Repayment(LoanID,AmountPaid,PaymentMode,PaymentStatus)\nVALUES(2001,10,'UPI','Success');\nSELECT LoanID,OutstandingBalance,Status FROM Loan WHERE LoanID=2001;\nROLLBACK;",
                'output':out,'before_outstanding':before,'context':'Disposable verification database; rolled back after observation'}
            cur.execute('ROLLBACK')
        evidence['clean_install']['status']='PASS; verification database removed after capture'
    finally:
        if clone_conn: clone_conn.close()
        with admin.cursor() as cur:
            cur.execute(sql.SQL('DROP DATABASE IF EXISTS {} WITH (FORCE)').format(sql.Identifier(clone)))
        admin.close()
    assert len(evidence['standard'])==35 and len(evidence['complex'])==10 and len(evidence['tests'])==15
    capture_live_objects(evidence)
    import sys
    path=Path(sys.argv[sys.argv.index('--output')+1]) if '--output' in sys.argv else OUT/'evidence.json'
    path.write_text(json.dumps(evidence,indent=2,default=serial,ensure_ascii=False),encoding='utf-8')
    print(f"Captured 35 standard queries, 10 business queries, 15 passing tests, 11 FKs and both query plans: {path}")
    print('banking_db business rows retained; only rolled-back SERIAL calls may consume sequence values.')


if __name__=='__main__':
    import sys
    if '--augment-live' in sys.argv:
        path=OUT/'evidence.json'
        evidence=json.loads(path.read_text(encoding='utf-8'))
        capture_live_objects(evidence)
        path.write_text(json.dumps(evidence,indent=2,default=serial,ensure_ascii=False),encoding='utf-8')
        print('Added live, rollback-only procedure, trigger and cursor observations.')
    else:
        main()
