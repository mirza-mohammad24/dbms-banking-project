-- Sprint 1 fictional Indian banking fixtures. Run after 01_ddl.sql.
-- Balances are opening snapshots; history is illustrative, not a full ledger.
-- No future-sprint procedures or triggers are assumed by these inserts.
BEGIN;

INSERT INTO Postal_Directory (Pincode, City, State) VALUES
('632001', 'Vellore', 'Tamil Nadu'),
('600001', 'Chennai', 'Tamil Nadu'),
('560001', 'Bengaluru', 'Karnataka'),
('400001', 'Mumbai', 'Maharashtra'),
('110001', 'Delhi', 'Delhi'),
('500001', 'Hyderabad', 'Telangana'),
('700001', 'Kolkata', 'West Bengal'),
('411001', 'Pune', 'Maharashtra');

-- Plausible fictional IFSC codes; these are not a verified banking directory.
INSERT INTO Bank_Directory (IFSC_Code, BankName) VALUES
('CBNK0000001', 'Campus Bank'), ('CBNK0000002', 'Campus Bank'),
('CBNK0000003', 'Campus Bank'), ('CBNK0000004', 'Campus Bank'),
('CBNK0000005', 'Campus Bank'), ('CBNK0000006', 'Campus Bank'),
('CBNK0000007', 'Campus Bank'), ('CBNK0000008', 'Campus Bank'),
('NMBK0000001', 'Namma Bank'), ('DBNK0000001', 'Deccan Bank');

INSERT INTO Branch (BranchID, BranchName, Address, Pincode, IFSC_Code, ContactPhone) VALUES
(1, 'Vellore Main', '12 Anna Salai', '632001', 'CBNK0000001', '04162220001'),
(2, 'Chennai Central', '24 Armenian Street', '600001', 'CBNK0000002', '04422220002'),
(3, 'Bengaluru Central', '36 MG Road', '560001', 'CBNK0000003', '08022220003'),
(4, 'Mumbai Fort', '48 Fort Road', '400001', 'CBNK0000004', '02222220004'),
(5, 'Delhi Connaught Place', '60 Janpath', '110001', 'CBNK0000005', '01122220005'),
(6, 'Hyderabad Abids', '72 Abids Road', '500001', 'CBNK0000006', '04022220006'),
(7, 'Kolkata Central', '84 BBD Bagh', '700001', 'CBNK0000007', '03322220007'),
(8, 'Pune Camp', '96 East Street', '411001', 'CBNK0000008', '02022220008');

INSERT INTO Customer (CustomerID, FirstName, LastName, Gender, Age, Address, Phone, Email, PAN_Number, KYC_Status) VALUES
(1, 'Aarav', 'Sharma', 'Male', 32, '10 Gandhi Road, Vellore', '9000000001', 'aarav.sharma@example.com', 'ABCDE1001F', 'Approved'),
(2, 'Ananya', 'Iyer', 'Female', 29, '21 T Nagar, Chennai', '9000000002', 'ananya.iyer@example.com', 'ABCDE1002F', 'Approved'),
(3, 'Rohan', 'Rao', 'Male', 41, '32 Indiranagar, Bengaluru', '9000000003', 'rohan.rao@example.com', 'ABCDE1003F', 'Approved'),
(4, 'Meera', 'Patel', 'Female', 36, '43 Dadar, Mumbai', '9000000004', 'meera.patel@example.com', 'ABCDE1004F', 'Approved'),
(5, 'Kabir', 'Singh', 'Male', 27, '54 Karol Bagh, Delhi', '9000000005', 'kabir.singh@example.com', 'ABCDE1005F', 'Approved'),
(6, 'Sana', 'Khan', 'Female', 24, '65 Banjara Hills, Hyderabad', '9000000006', 'sana.khan@example.com', 'ABCDE1006F', 'Approved'),
(7, 'Arjun', 'Sen', 'Male', 48, '76 Salt Lake, Kolkata', '9000000007', 'arjun.sen@example.com', 'ABCDE1007F', 'Approved'),
(8, 'Priya', 'Deshmukh', 'Female', 34, '87 Shivaji Nagar, Pune', '9000000008', 'priya.deshmukh@example.com', 'ABCDE1008F', 'Approved'),
(9, 'Dev', 'Menon', 'Other', 22, '98 Katpadi, Vellore', '9000000009', 'dev.menon@example.com', 'ABCDE1009F', 'Pending'),
(10, 'Nisha', 'Gupta', 'Female', 30, '109 Adyar, Chennai', '9000000010', 'nisha.gupta@example.com', 'ABCDE1010F', 'Rejected');

-- Customers 1 and 2 each own Savings and Current accounts.
-- Customers 9 and 10 own accounts but no loans or fixed deposits.
INSERT INTO Account (AccountNo, CustomerID, BranchID, AccountType, Balance, InterestRate, OpeningDate, Status) VALUES
(100001, 1, 1, 'Savings', 150000, 3.50, CURRENT_DATE - 730, 'Active'),
(100002, 1, 1, 'Current', 250000, 0, CURRENT_DATE - 600, 'Active'),
(100003, 2, 2, 'Savings', 85000, 3.50, CURRENT_DATE - 500, 'Active'),
(100004, 2, 2, 'Current', 425000, 0, CURRENT_DATE - 450, 'Active'),
(100005, 3, 3, 'Salary', 95000, 3.50, CURRENT_DATE - 400, 'Active'),
(100006, 4, 4, 'Savings', 310000, 3.75, CURRENT_DATE - 380, 'Active'),
(100007, 5, 5, 'Salary', 62000, 3.50, CURRENT_DATE - 300, 'Active'),
(100008, 6, 6, 'Savings', 18000, 3.50, CURRENT_DATE - 270, 'Dormant'),
(100009, 7, 7, 'Current', 740000, 0, CURRENT_DATE - 250, 'Active'),
(100010, 8, 8, 'Savings', 56000, 3.50, CURRENT_DATE - 200, 'Active'),
(100011, 9, 1, 'Savings', 4500, 3.50, CURRENT_DATE - 60, 'Frozen'),
(100012, 10, 2, 'Savings', 0, 3.50, CURRENT_DATE - 90, 'Closed');

INSERT INTO Transaction_History (AccountNo, Amount, TransactionType, PaymentMode, Remarks, TransactionDate) VALUES
(100001, 50000, 'Deposit', 'NEFT', 'Salary credit', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(100001, 2500, 'Withdrawal', 'UPI', NULL, CURRENT_TIMESTAMP - INTERVAL '28 days'),
(100002, 75000, 'Deposit', 'RTGS', 'Invoice settlement', CURRENT_TIMESTAMP - INTERVAL '27 days'),
(100002, 10000, 'Transfer', 'IMPS', 'Supplier payment', CURRENT_TIMESTAMP - INTERVAL '26 days'),
(100003, 40000, 'Deposit', 'NEFT', 'Salary credit', CURRENT_TIMESTAMP - INTERVAL '25 days'),
(100003, 1500, 'Withdrawal', 'Cash', NULL, CURRENT_TIMESTAMP - INTERVAL '24 days'),
(100004, 120000, 'Deposit', 'RTGS', 'Consulting income', CURRENT_TIMESTAMP - INTERVAL '23 days'),
(100004, 12000, 'Transfer', 'NEFT', 'Office rent', CURRENT_TIMESTAMP - INTERVAL '22 days'),
(100005, 95000, 'Deposit', 'NEFT', 'Salary credit', CURRENT_TIMESTAMP - INTERVAL '21 days'),
(100005, 3000, 'Withdrawal', 'UPI', 'Groceries', CURRENT_TIMESTAMP - INTERVAL '20 days'),
(100006, 80000, 'Deposit', 'Cash', NULL, CURRENT_TIMESTAMP - INTERVAL '19 days'),
(100006, 5000, 'Transfer', 'Internal', 'Family support', CURRENT_TIMESTAMP - INTERVAL '18 days'),
(100007, 62000, 'Deposit', 'NEFT', 'Salary credit', CURRENT_TIMESTAMP - INTERVAL '17 days'),
(100007, 2000, 'Withdrawal', 'Cash', NULL, CURRENT_TIMESTAMP - INTERVAL '16 days'),
(100008, 18000, 'Deposit', 'Cash', 'Opening deposit', CURRENT_TIMESTAMP - INTERVAL '200 days'),
(100009, 250000, 'Deposit', 'RTGS', 'Business receipts', CURRENT_TIMESTAMP - INTERVAL '14 days'),
(100009, 35000, 'Transfer', 'NEFT', 'Inventory purchase', CURRENT_TIMESTAMP - INTERVAL '13 days'),
(100010, 56000, 'Deposit', 'IMPS', 'Savings contribution', CURRENT_TIMESTAMP - INTERVAL '12 days'),
(100011, 4500, 'Deposit', 'Cash', 'Before KYC freeze', CURRENT_TIMESTAMP - INTERVAL '50 days'),
(100012, 8000, 'Withdrawal', 'Cash', 'Account closure payout', CURRENT_TIMESTAMP - INTERVAL '40 days');

-- Branch 8 deliberately has no loans. Generated EMI_Amount is omitted.
INSERT INTO Loan (LoanID, CustomerID, BranchID, LoanType, PrincipalAmount, InterestRate, TenureMonths, OutstandingBalance, IssueDate, Status) VALUES
(2001, 1, 1, 'Home', 2500000, 8.50, 240, 2300000, CURRENT_DATE - 700, 'Active'),
(2002, 2, 2, 'Business', 800000, 11.00, 60, 710000, CURRENT_DATE - 400, 'Active'),
(2003, 3, 3, 'Auto', 600000, 9.25, 60, 480000, CURRENT_DATE - 350, 'Active'),
(2004, 4, 4, 'Personal', 200000, 12.50, 36, 175000, CURRENT_DATE - 180, 'Active'),
(2005, 5, 5, 'Education', 400000, 9.00, 84, 400000, CURRENT_DATE - 90, 'Approved'),
(2006, 6, 6, 'Personal', 100000, 13.00, 24, 85000, CURRENT_DATE - 240, 'Defaulted'),
(2007, 7, 7, 'Business', 1200000, 10.50, 60, 0, CURRENT_DATE - 2000, 'Closed'),
(2008, 8, 1, 'Home', 1800000, 8.75, 180, 1800000, CURRENT_DATE - 10, 'Pending');

-- Historical fixtures: no balance-deduction trigger exists in Sprint 1.
INSERT INTO Loan_Repayment (LoanID, AmountPaid, PaymentMode, PaymentStatus, PaymentDate) VALUES
(2001, 21696, 'Auto-Debit', 'Success', CURRENT_TIMESTAMP - INTERVAL '60 days'),
(2001, 21696, 'Auto-Debit', 'Success', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(2002, 17394, 'NEFT', 'Success', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(2002, 17394, 'NEFT', 'Pending', CURRENT_TIMESTAMP - INTERVAL '1 day'),
(2003, 12528, 'UPI', 'Success', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(2004, 6691, 'Cash', 'Success', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(2005, 6436, 'Auto-Debit', 'Pending', CURRENT_TIMESTAMP - INTERVAL '1 day'),
(2006, 4754, 'Auto-Debit', 'Failed', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(2006, 4754, 'UPI', 'Success', CURRENT_TIMESTAMP - INTERVAL '60 days'),
(2007, 25793, 'NEFT', 'Success', CURRENT_TIMESTAMP - INTERVAL '100 days');

INSERT INTO Beneficiary (CustomerID, BeneficiaryName, LinkedAccountNo, IFSC_Code, MaxTransferLimit) VALUES
(1, 'Ananya Iyer', 100003, 'CBNK0000002', 100000),
(2, 'Aarav Sharma', 100001, 'CBNK0000001', 75000),
(3, 'Namma Motors', 900000000001, 'NMBK0000001', 150000),
(4, 'Deccan Housing', 900000000002, 'DBNK0000001', 200000),
(5, 'Meera Patel', 100006, 'CBNK0000004', 25000),
(6, 'Kabir Singh', 100007, 'CBNK0000005', 20000),
(7, 'Rohan Rao', 100005, 'CBNK0000003', 100000),
(8, 'Sana Khan', 100008, 'CBNK0000006', 50000),
(9, 'Arjun Sen', 100009, 'CBNK0000007', 10000),
(10, 'Priya Deshmukh', 100010, 'CBNK0000008', 30000);

-- FD 3001 is Active and due today on every fresh run; cursor target for Sprint 3.
-- Generated MaturityAmount is omitted from INSERT.
INSERT INTO Fixed_Deposit (FD_ID, CustomerID, Amount, InterestRate, StartDate, EndDate, Status) VALUES
(3001, 1, 100000, 7.00, CURRENT_DATE - 365, CURRENT_DATE, 'Active'),
(3002, 2, 150000, 7.25, CURRENT_DATE - 100, CURRENT_DATE + 265, 'Active'),
(3003, 3, 75000, 6.75, CURRENT_DATE - 60, CURRENT_DATE + 305, 'Active'),
(3004, 4, 250000, 7.50, CURRENT_DATE - 180, CURRENT_DATE + 550, 'Active'),
(3005, 5, 50000, 6.50, CURRENT_DATE - 30, CURRENT_DATE + 150, 'Active'),
(3006, 6, 10000, 6.25, CURRENT_DATE - 400, CURRENT_DATE - 35, 'Matured'),
(3007, 7, 300000, 7.50, CURRENT_DATE - 800, CURRENT_DATE - 70, 'Closed'),
(3008, 8, 60000, 7.00, CURRENT_DATE - 90, CURRENT_DATE + 275, 'Active');

INSERT INTO Employee (EmployeeID, BranchID, FirstName, LastName, Email, Role, Salary, HireDate) VALUES
(4001, 1, 'Vikram', 'Nair', 'vikram.nair@example.com', 'Branch Manager', 85000, CURRENT_DATE - 1800),
(4002, 2, 'Lakshmi', 'Raman', 'lakshmi.raman@example.com', 'Branch Manager', 90000, CURRENT_DATE - 1600),
(4003, 3, 'Aditya', 'Reddy', 'aditya.reddy@example.com', 'Loan Officer', 62000, CURRENT_DATE - 1200),
(4004, 4, 'Pooja', 'Shah', 'pooja.shah@example.com', 'Loan Officer', 65000, CURRENT_DATE - 1100),
(4005, 5, 'Ishaan', 'Verma', 'ishaan.verma@example.com', 'KYC Officer', 48000, CURRENT_DATE - 900),
(4006, 6, 'Fatima', 'Ali', 'fatima.ali@example.com', 'Cashier', 42000, CURRENT_DATE - 800),
(4007, 7, 'Soham', 'Das', 'soham.das@example.com', 'Branch Manager', 82000, CURRENT_DATE - 1400),
(4008, 8, 'Aditi', 'Joshi', 'aditi.joshi@example.com', 'Branch Manager', 78000, CURRENT_DATE - 600),
(4009, 1, 'Karthik', 'Bala', 'karthik.bala@example.com', 'Cashier', 40000, CURRENT_DATE - 500),
(4010, 2, 'Divya', 'Krishnan', 'divya.krishnan@example.com', 'KYC Officer', 46000, CURRENT_DATE - 400);

-- Explicit seed/bootstrap audit entries, NOT evidence of trigger execution.
INSERT INTO Audit_Log (TableName, RecordID, ActionType, Description) VALUES
('Branch', 1, 'SEED', 'Sprint 1 fixture: Vellore branch inserted'),
('Branch', 8, 'SEED', 'Sprint 1 fixture: Pune branch inserted without loans'),
('Customer', 1, 'SEED', 'Sprint 1 fixture: approved customer inserted'),
('Customer', 9, 'SEED', 'Sprint 1 fixture: pending KYC customer inserted'),
('Account', 100001, 'SEED', 'Sprint 1 fixture: savings snapshot inserted'),
('Account', 100011, 'SEED', 'Sprint 1 fixture: frozen account inserted'),
('Loan', 2001, 'SEED', 'Sprint 1 fixture: home loan inserted'),
('Fixed_Deposit', 3001, 'SEED', 'Sprint 1 fixture: active deposit due today inserted');

-- DML demonstration (Checklist Item #2): INSERT -> UPDATE -> DELETE.
-- Temporary negative ID cannot collide with the positive fixture IDs.
INSERT INTO Beneficiary (BeneficiaryID, CustomerID, BeneficiaryName, LinkedAccountNo, IFSC_Code)
VALUES (-1, 1, 'Temporary DML demonstration', 999999999999, 'NMBK0000001');
UPDATE Beneficiary SET MaxTransferLimit = 25000.00 WHERE BeneficiaryID = -1;
DELETE FROM Beneficiary WHERE BeneficiaryID = -1;

COMMIT;

-- Final single UNION ALL summary, including all twelve tables.
SELECT 'Postal_Directory' AS table_name, COUNT(*) AS row_count FROM Postal_Directory
UNION ALL SELECT 'Bank_Directory', COUNT(*) FROM Bank_Directory
UNION ALL SELECT 'Branch', COUNT(*) FROM Branch
UNION ALL SELECT 'Customer', COUNT(*) FROM Customer
UNION ALL SELECT 'Account', COUNT(*) FROM Account
UNION ALL SELECT 'Transaction_History', COUNT(*) FROM Transaction_History
UNION ALL SELECT 'Loan', COUNT(*) FROM Loan
UNION ALL SELECT 'Loan_Repayment', COUNT(*) FROM Loan_Repayment
UNION ALL SELECT 'Beneficiary', COUNT(*) FROM Beneficiary
UNION ALL SELECT 'Fixed_Deposit', COUNT(*) FROM Fixed_Deposit
UNION ALL SELECT 'Employee', COUNT(*) FROM Employee
UNION ALL SELECT 'Audit_Log', COUNT(*) FROM Audit_Log;
