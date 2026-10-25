"""Run: uv run python -m unittest backend.tests.test_workflows -v.

Creates a disposable PostgreSQL database with the exact DDL, seed, and deployed
logic scripts. Drops it even on failure. Requires the supplied local postgres
role's CREATEDB privileges. No banking_db rows or role grants are changed.
"""
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path
import unittest
from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor
import psycopg2
from psycopg2 import sql
from fastapi.testclient import TestClient
from backend import database as db
from backend.main import app

class BankingWorkflows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original_url = db.DATABASE_URL
        cls.database_name = 'banking_verify_' + uuid4().hex[:12]
        cls.admin = psycopg2.connect(cls.original_url)
        cls.admin.autocommit = True
        cls.addClassCleanup(cls.cleanup_database)
        with cls.admin.cursor() as cursor:
            cursor.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(cls.database_name)))
        db.DATABASE_URL = psycopg2.extensions.make_dsn(cls.original_url, dbname=cls.database_name)
        root = Path(__file__).resolve().parents[2]
        with db.get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute('SET search_path = public')
                for filename in ['01_ddl.sql', '02_dml.sql']:
                    cursor.execute((root / 'sql' / filename).read_text(encoding='utf-8'))
                advanced = (root / 'sql/05_advanced_logic.sql').read_text(encoding='utf-8')
                cursor.execute(advanced.split('-- 6. Executable verification')[0])
                security = (root / 'sql/06_security_concurrency.sql').read_text(encoding='utf-8')
                start = security.index('CREATE OR REPLACE FUNCTION public._bank_transfer_atomic(')
                end = security.index('CREATE OR REPLACE PROCEDURE public.sp_transfer_funds(', start)
                cursor.execute(security[start:end])
        cls.client = TestClient(app)
        cls.addClassCleanup(cls.client.close)

    @classmethod
    def cleanup_database(cls):
        db.DATABASE_URL = cls.original_url
        with cls.admin.cursor() as cursor:
            cursor.execute(sql.SQL('DROP DATABASE IF EXISTS {} WITH (FORCE)').format(sql.Identifier(cls.database_name)))
        cls.admin.close()

    def get(self, path):
        response = self.client.get(path)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def write(self, path, data=None, method='post', expected=200):
        response = getattr(self.client, method)(path, json=data) if data is not None else getattr(self.client, method)(path)
        self.assertEqual(response.status_code, expected, response.text)
        return response.json()

    def test_complete_banking_workflows(self):
        self.assertEqual(self.get('/api/health')['status'], 'ok')
        customers = self.get('/api/directory/customers-preview')
        self.assertEqual(len(customers), 10)
        self.assertEqual(customers[0]['accountcount'], 2)
        employees = self.get('/api/directory/employees-preview')
        self.assertTrue(employees)
        self.assertEqual(self.write('/api/login', {'id':100001,'role':'Customer','identity_type':'account'})['user']['id'], 1)
        self.assertEqual(self.write('/api/login', {'id':4001,'role':'Admin','employee_id':4001})['user']['name'], 'Vikram Nair')
        self.assertEqual(self.write('/api/login', {'id':1,'role':'Admin'})['user']['role'], 'Admin')
        self.write('/api/login', {'id':2147483647,'role':'Customer'}, expected=404)
        lookups = self.get('/api/lookups')
        today = date.fromisoformat(lookups['today'])
        self.get('/api/customer/1/overview')
        self.assertEqual(len(self.get('/api/customer/1/accounts')), 2)
        self.get('/api/customer/1/net-worth')
        self.get('/api/customer/1/passbook')
        filtered = self.get('/api/customer/1/transactions?account_no=100001&txn_type=Deposit&payment_mode=NEFT')
        self.assertTrue(filtered)
        self.assertTrue(all(row['accountno']==100001 and row['transactiontype']=='Deposit' for row in filtered))

        person = {'first_name':'Review','last_name':'Customer','gender':'Other','age':30,'address':'12 Review Street',
                  'phone':'9001234567','email':'review@example.invalid','pan_number':'ZZZPZ1234Q'}
        new = self.write('/api/admin/customers', person)['customer']
        customer_id = new['customerid']
        duplicate = self.write('/api/admin/customers', {**person,'phone':'9001234568','email':'second@example.invalid'}, expected=400)
        self.assertEqual(duplicate['sqlstate'], '23505')
        self.write(f'/api/admin/customers/{customer_id}/kyc', {'kyc_status':'Approved'}, 'patch')
        account = self.write('/api/admin/accounts', {'customer_id':customer_id,'branch_id':1,'account_type':'Savings','balance':'50000'})['account']['accountno']
        second = self.write('/api/admin/accounts', {'customer_id':customer_id,'branch_id':2,'account_type':'Current','balance':'2000'})['account']['accountno']
        def balance():
            return Decimal(next(row['balance'] for row in self.get(f'/api/customer/{customer_id}/accounts') if row['accountno']==account))
        cash = {'customer_id':customer_id,'account_no':account,'amount':'10','mode':'Cash'}
        self.write('/api/transaction/deposit', cash)
        self.write('/api/transaction/withdraw', {**cash,'amount':'5'})
        self.assertEqual(balance(), Decimal('50005'))
        self.write('/api/transaction/withdraw', {**cash,'amount':'900000'}, expected=400)
        self.assertEqual(balance(), Decimal('50005'))
        self.write('/api/transaction/deposit', {**cash,'customer_id':1}, expected=403)
        self.write(f'/api/admin/accounts/{account}/status', {'status':'Frozen'}, 'patch')
        self.write('/api/transaction/transfer', {'customer_id':customer_id,'sender':account,'receiver':second,'amount':'1','mode':'UPI'}, expected=400)
        self.write(f'/api/admin/accounts/{account}/status', {'status':'Active'}, 'patch')
        self.write('/api/transaction/transfer', {'customer_id':customer_id,'sender':account,'receiver':second,'amount':'1','mode':'UPI'})
        self.assertEqual(balance(), Decimal('50004'))

        external = self.write(f'/api/customer/{customer_id}/beneficiaries', {
            'beneficiary_name':'External test','linked_account_no':987654321000,'ifsc_code':'TEST0009999',
            'bank_name':'Review Bank','max_transfer_limit':'100'})['beneficiary']['beneficiaryid']
        transfer = {'customer_id':customer_id,'sender':account,'beneficiary_id':external,'amount':'60','mode':'NEFT'}
        self.write('/api/transaction/transfer', transfer)
        self.write('/api/transaction/transfer', {**transfer,'sender':second}, expected=400)
        self.assertEqual(balance(), Decimal('49944'))
        internal = self.write(f'/api/customer/{customer_id}/beneficiaries', {
            'beneficiary_name':'Internal test','linked_account_no':second,'ifsc_code':'CBNK0000002','max_transfer_limit':'10'})['beneficiary']['beneficiaryid']
        self.write('/api/transaction/transfer', {**transfer,'beneficiary_id':internal,'amount':'8'})
        self.write('/api/transaction/transfer', {**transfer,'beneficiary_id':internal,'amount':'3'}, expected=400)
        self.assertEqual(len(self.get(f'/api/customer/{customer_id}/beneficiaries')), 2)
        self.write(f'/api/beneficiaries/{external}?customer_id={customer_id}', method='delete')

        preview = self.get('/api/admin/emi-preview?principal=12000&rate=12&months=12')
        loan = self.write('/api/admin/loans', {'customer_id':customer_id,'branch_id':1,'loan_type':'Personal',
            'principal_amount':'12000','interest_rate':'12','tenure_months':12,'account_no':account})['loan']
        self.assertEqual(loan['emi_amount'], preview['emi_amount'])
        before_emi = balance()
        self.write('/api/loans/pay-emi', {'customer_id':customer_id,'loan_id':loan['loanid'],'account_no':account})
        repayments = self.get(f"/api/loans/{loan['loanid']}/repayments?customer_id={customer_id}")
        self.assertEqual(len(repayments), 1)
        self.assertEqual(balance(), before_emi - Decimal(loan['emi_amount']))
        current_loan = self.get(f'/api/customer/{customer_id}/loans')[0]
        self.assertEqual(Decimal(current_loan['outstandingbalance']), Decimal('12000')-Decimal(loan['emi_amount']))
        self.write('/api/transaction/emi', {'customer_id':1,'loan_id':loan['loanid'],'account_no':account}, expected=400)
        before_fd = balance()
        fd = self.write(f'/api/customer/{customer_id}/fixed-deposits', {'account_no':account,'amount':'1000',
            'interest_rate':'7','start_date':today.isoformat(),'end_date':(today+timedelta(days=365)).isoformat()})['fixed_deposit']
        self.assertEqual(Decimal(fd['maturityamount']), Decimal('1070'))
        self.assertEqual(balance(), before_fd-1000)
        # The FD CHECK fails AFTER the funding debit: prove both debit and audit
        # roll back with the insert, rather than leaving partially moved money.
        before_bad_fd = balance()
        failure = self.write(f'/api/customer/{customer_id}/fixed-deposits', {'account_no':account,'amount':'1000',
            'interest_rate':'7','start_date':today.isoformat(),'end_date':today.isoformat()}, expected=400)
        self.assertEqual(failure['sqlstate'], '23514')
        self.assertEqual(balance(), before_bad_fd)
        self.assertEqual(len(self.get(f'/api/customer/{customer_id}/fixed-deposits')), 1)
        self.get(f'/api/admin/customer/{customer_id}/full-360')
        master = self.get('/api/admin/customers-master?search=Review&kyc_status=Approved')
        self.assertEqual(master[0]['customerid'], customer_id)
        self.assertEqual(len(master[0]['accounts']), 2)

        self.write('/api/admin/postal-directory', {'pincode':'999001','city':'Review City','state':'Tamil Nadu'})
        self.write('/api/admin/bank-directory', {'ifsc_code':'RVWB0000001','bank_name':'Review Bank'})
        branch = self.write('/api/admin/branches', {'branch_name':'Review Branch','address':'1 Review Road',
            'pincode':'999001','city':'Review City','state':'Tamil Nadu','ifsc_code':'RVWB0000001',
            'bank_name':'Review Bank','contact_phone':'04499990001'})['branch']
        self.write('/api/admin/employees', {'branch_id':branch['branchid'],'first_name':'Review','last_name':'Officer',
            'email':'officer@example.invalid','role':'Branch Manager','salary':'50000'})
        self.get('/api/admin/infrastructure')
        self.get('/api/admin/accounts')
        self.get('/api/admin/loans')
        self.get('/api/admin/fixed-deposits?status=Active')
        dashboard = self.get('/api/admin/dashboard')
        self.assertEqual(len(dashboard['table_counts']), 12)
        self.assertEqual(len(dashboard['branches']), 9)
        self.get('/api/admin/summary')
        self.assertGreaterEqual(self.write('/api/admin/batch/interest')['processed'], 1)
        self.assertEqual(self.write('/api/admin/batch/interest')['processed'], 0)
        self.assertEqual(self.write('/api/admin/batch/mature-fds')['processed'], 1)
        self.assertEqual(self.write('/api/admin/batch/mature-fds')['processed'], 0)
        audits = self.get('/api/admin/audit-log?table_name=Account&action_type=BALANCE_UPDATE')
        self.assertTrue(audits)
        self.assertTrue(all(row['tablename']=='Account' and row['actiontype']=='BALANCE_UPDATE' for row in audits))
        catalog = self.get('/api/admin/programmability')
        self.assertEqual(len(catalog['triggers']), 2)
        self.assertEqual(len(catalog['views']), 3)
        self.assertEqual(self.client.post('/api/transaction/deposit', json={**cash,'amount':'-1'}).status_code, 422)

    def test_concurrent_ids_and_shared_beneficiary_limit(self):
        def create(index):
            with TestClient(app) as client:
                result = client.post('/api/admin/customers', json={
                    'first_name':'Concurrent','last_name':str(index),'gender':'Other','age':25,
                    'address':'Concurrency verification','phone':f'90123456{index:02d}',
                    'email':f'parallel{index}@example.invalid','pan_number':f'AAAPA{7000+index}Q','kyc_status':'Approved'})
                return result.status_code, result.json()
        with ThreadPoolExecutor(max_workers=4) as executor:
            created = list(executor.map(create, range(4)))
        self.assertTrue(all(status == 200 for status, _ in created), created)
        ids = [result['customer']['customerid'] for _, result in created]
        self.assertEqual(len(set(ids)), 4)
        customer_id = ids[0]
        accounts = [self.write('/api/admin/accounts', {'customer_id':customer_id,'branch_id':1,
                    'account_type':'Savings','balance':'1000'})['account']['accountno'] for _ in range(2)]
        beneficiary = self.write(f'/api/customer/{customer_id}/beneficiaries', {
            'beneficiary_name':'Concurrent beneficiary','linked_account_no':123456789012,
            'ifsc_code':'THREAD00001','bank_name':'Thread Bank','max_transfer_limit':'100'})['beneficiary']['beneficiaryid']
        def pay(account):
            with TestClient(app) as client:
                result = client.post('/api/transaction/transfer', json={
                    'customer_id':customer_id,'sender':account,'beneficiary_id':beneficiary,'amount':'60','mode':'IMPS'})
                return result.status_code
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = sorted(executor.map(pay, accounts))
        self.assertEqual(results, [200, 400])
        self.assertEqual(sum(Decimal(a['balance']) for a in self.get(f'/api/customer/{customer_id}/accounts')), Decimal('1940'))

if __name__ == '__main__':
    unittest.main()
