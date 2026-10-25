-- Advanced banking logic for PostgreSQL 18 (CREATE OR REPLACE throughout).
-- Exactly 3 views, 2 business UDFs, 2 triggers with 2 required trigger functions,
-- 2 core procedures, and 2 cursor batch procedures. No schema changes.
-- Run with psql -X -v ON_ERROR_STOP=1 in AUTOCOMMIT mode, NOT with -1 or an
-- enclosing BEGIN: sp_transfer_funds deliberately commits its own transaction.
-- Definitions are replaceable. Bottom demonstrations make real banking changes;
-- rerunning them repeats the transfer and EMI. Monthly interest and FD maturity
-- themselves prevent duplicate postings. Existing historical rows are untouched.

-- =====================================================================
-- 1. Views
-- =====================================================================

-- Four-table passbook; transfer direction is recorded in Remarks because the
-- existing TransactionType CHECK permits only Deposit, Withdrawal, Transfer.
-- Consumers should ORDER BY date (and their own tie-breaker) when displaying it.
CREATE OR REPLACE VIEW vw_customer_passbook AS
SELECT a.AccountNo, CONCAT(c.FirstName, ' ', c.LastName) AS Name,
       b.BranchName, t.TransactionDate AS Date, t.TransactionType AS Type,
       t.Amount, COALESCE(t.Remarks, 'No remarks provided') AS Remarks
FROM Customer c
JOIN Account a ON a.CustomerID = c.CustomerID
JOIN Branch b ON b.BranchID = a.BranchID
JOIN Transaction_History t ON t.AccountNo = a.AccountNo;

-- Independent aggregates avoid multiplying loans/FDs by account counts.
-- Loan outstanding includes all stored statuses, as requested.
-- FD maturity totals cover Active FDs (unpaid obligations), attributed ONCE to
-- the customer's primary account branch: prefer Active, then Savings, then
-- oldest OpeningDate/lowest AccountNo. FD has no BranchID: this is reporting
-- attribution, NOT an issuing-branch relationship. Owners without any account
-- have no attributable branch and their FDs cannot enter a branch total.
CREATE OR REPLACE VIEW vw_branch_financial_summary AS
WITH active_accounts AS (
    SELECT BranchID, COUNT(*) AS total_active_accounts
    FROM Account WHERE Status = 'Active' GROUP BY BranchID
), loan_totals AS (
    SELECT BranchID, SUM(OutstandingBalance) AS total_loan_outstanding
    FROM Loan GROUP BY BranchID
), primary_branch AS (
    SELECT DISTINCT ON (CustomerID) CustomerID, BranchID
    FROM Account
    ORDER BY CustomerID, (Status = 'Active') DESC NULLS LAST,
             (AccountType = 'Savings') DESC, OpeningDate, AccountNo
), fd_totals AS (
    SELECT p.BranchID, SUM(f.MaturityAmount) AS total_fd_maturity_amounts
    FROM Fixed_Deposit f JOIN primary_branch p ON p.CustomerID = f.CustomerID
    WHERE f.Status = 'Active'
    GROUP BY p.BranchID
)
SELECT b.BranchID, b.BranchName,
       COALESCE(a.total_active_accounts, 0) AS total_active_accounts,
       COALESCE(l.total_loan_outstanding, 0) AS total_loan_outstanding,
       COALESCE(f.total_fd_maturity_amounts, 0) AS total_fd_maturity_amounts
FROM Branch b
LEFT JOIN active_accounts a ON a.BranchID = b.BranchID
LEFT JOIN loan_totals l ON l.BranchID = b.BranchID
LEFT JOIN fd_totals f ON f.BranchID = b.BranchID;

-- Account-to-Branch/Postal semi-join via EXISTS preserves automatic updateability
-- (a flat three-table FROM join would be read-only in PostgreSQL). CHECK OPTION
-- prevents view writes from moving rows outside Active Vellore membership.
-- security_barrier protects predicate evaluation; actual restricted access also
-- requires later RBAC grants on this view and no direct base-table access.
CREATE OR REPLACE VIEW vw_active_vellore_accounts
WITH (security_barrier = true) AS
SELECT a.AccountNo, a.CustomerID, a.BranchID, a.AccountType, a.Balance,
       a.InterestRate, a.OpeningDate, a.Status
FROM Account a
WHERE a.Status = 'Active'
  AND EXISTS (
      SELECT 1 FROM Branch b
      JOIN Postal_Directory p ON p.Pincode = b.Pincode
      WHERE b.BranchID = a.BranchID AND p.City = 'Vellore'
  )
WITH CASCADED CHECK OPTION;

-- =====================================================================
-- 2. Business UDFs (trigger-support functions are separate below)
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_calculate_emi(
    p_principal DECIMAL, p_rate DECIMAL, p_months INT
) RETURNS DECIMAL
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_rate NUMERIC;
    v_factor NUMERIC;
BEGIN
    IF p_principal IS NULL OR p_principal <= 0
       OR p_principal::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_rate IS NULL OR p_rate < 0
       OR p_rate::text IN ('NaN', 'Infinity', '-Infinity')
       OR p_months IS NULL OR p_months <= 0 THEN
        RAISE EXCEPTION 'EMI requires finite positive principal/months and nonnegative rate'
            USING ERRCODE = '22023';
    END IF;
    -- Zero-rate extension avoids division by zero (stored Loan requires >0).
    IF p_rate = 0 THEN
        RETURN ROUND(p_principal / p_months, 2);
    END IF;
    v_rate := p_rate / 1200.0;
    v_factor := POWER(1 + v_rate, p_months);
    RETURN ROUND(p_principal * v_rate * v_factor / (v_factor - 1), 2);
END;
$$;

CREATE OR REPLACE FUNCTION fn_customer_net_worth(p_customer_id INT)
RETURNS DECIMAL LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_customer_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM Customer WHERE CustomerID = p_customer_id
    ) THEN
        RAISE EXCEPTION 'Customer % does not exist', p_customer_id
            USING ERRCODE = '22023';
    END IF;
    -- Aggregate each product independently. Outstanding loans include all
    -- statuses exactly as stored; Active FDs contribute principal, not maturity.
    RETURN COALESCE((SELECT SUM(Balance) FROM Account
                    WHERE CustomerID = p_customer_id), 0)
         + COALESCE((SELECT SUM(Amount) FROM Fixed_Deposit
                    WHERE CustomerID = p_customer_id AND Status = 'Active'), 0)
         - COALESCE((SELECT SUM(OutstandingBalance) FROM Loan
                    WHERE CustomerID = p_customer_id), 0);
END;
$$;

-- =====================================================================
-- 3. Two triggers and their mandatory RETURNS TRIGGER support functions
-- =====================================================================

CREATE OR REPLACE FUNCTION tg_audit_account_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Audit_Log (TableName, RecordID, ActionType, Description)
    VALUES ('Account', NEW.AccountNo, 'BALANCE_UPDATE',
            FORMAT('AccountNo=%s; old balance=%s; new balance=%s',
                   NEW.AccountNo, OLD.Balance, NEW.Balance));
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_audit_account_changes
AFTER UPDATE OF Balance ON Account
FOR EACH ROW WHEN (OLD.Balance IS DISTINCT FROM NEW.Balance)
EXECUTE FUNCTION tg_audit_account_changes();

CREATE OR REPLACE FUNCTION tg_loan_repayment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_loan Loan%ROWTYPE;
    v_remaining NUMERIC(15, 2);
BEGIN
    -- Pending, Failed, or NULL statuses must never reduce principal.
    IF NEW.PaymentStatus IS DISTINCT FROM 'Success' THEN
        RETURN NEW;
    END IF;
    -- NO KEY UPDATE also serializes balance changes without conflicting with
    -- another repayment INSERT's foreign-key KEY SHARE lock on the same loan.
    SELECT * INTO v_loan FROM Loan WHERE LoanID = NEW.LoanID FOR NO KEY UPDATE;
    IF NOT FOUND OR v_loan.Status IS NULL
       OR v_loan.Status NOT IN ('Approved', 'Active', 'Defaulted')
       OR v_loan.OutstandingBalance <= 0 THEN
        RAISE EXCEPTION 'Loan % is not repayable', NEW.LoanID USING ERRCODE = '22023';
    END IF;
    -- Reject direct overpayments; the EMI procedure caps the final installment.
    -- This avoids silently losing money by accepting more than the debt.
    IF NEW.AmountPaid > v_loan.OutstandingBalance THEN
        RAISE EXCEPTION 'Repayment exceeds outstanding balance for loan %', NEW.LoanID
            USING ERRCODE = '22023';
    END IF;
    v_remaining := v_loan.OutstandingBalance - NEW.AmountPaid;
    UPDATE Loan
    SET OutstandingBalance = GREATEST(v_remaining, 0),
        Status = CASE WHEN v_remaining <= 0 THEN 'Closed' ELSE Status END
    WHERE LoanID = NEW.LoanID;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_loan_repayment
AFTER INSERT ON Loan_Repayment
FOR EACH ROW EXECUTE FUNCTION tg_loan_repayment();

-- =====================================================================
-- 4. Core transaction procedures
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_transfer_funds(
    p_sender INT, p_receiver INT, p_amount DECIMAL,
    p_mode VARCHAR, p_remarks VARCHAR
) LANGUAGE plpgsql AS $$
DECLARE
    v_sender Account%ROWTYPE;
    v_receiver Account%ROWTYPE;
BEGIN
    IF p_sender IS NULL OR p_receiver IS NULL OR p_sender = p_receiver THEN
        RAISE EXCEPTION 'Transfer requires two different account numbers'
            USING ERRCODE = '22023';
    END IF;
    -- Require exact paise to prevent debit/credit rounding discrepancies.
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> ROUND(p_amount, 2)
       OR p_amount::text IN ('NaN', 'Infinity', '-Infinity') THEN
        RAISE EXCEPTION 'Transfer amount must be finite, positive, and at most two decimal places'
            USING ERRCODE = '22023';
    END IF;
    IF p_mode IS NULL OR p_mode NOT IN ('UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash', 'Internal') THEN
        RAISE EXCEPTION 'Invalid payment mode: %', p_mode USING ERRCODE = '22023';
    END IF;
    -- Both opposite-direction transfers acquire row locks in the same order.
    -- This is INVOKER security; a SET clause/SECURITY DEFINER would disallow
    -- transaction control. Run with a trusted role and trusted search_path.
    PERFORM AccountNo FROM Account WHERE AccountNo IN (p_sender, p_receiver)
    ORDER BY AccountNo FOR UPDATE;
    SELECT * INTO v_sender FROM Account WHERE AccountNo = p_sender;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sender account % does not exist', p_sender USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_receiver FROM Account WHERE AccountNo = p_receiver;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receiver account % does not exist', p_receiver USING ERRCODE = '22023';
    END IF;
    IF v_sender.Status IS DISTINCT FROM 'Active'
       OR v_receiver.Status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'Both transfer accounts must be Active' USING ERRCODE = '22023';
    END IF;
    IF v_sender.Balance < p_amount THEN
        -- Manual rollback condition: an UNCAUGHT exception aborts this CALL's
        -- transaction, rolling back balances, histories, and audit triggers.
        -- Do not swallow it or ROLLBACK inside an EXCEPTION subtransaction.
        RAISE EXCEPTION 'Insufficient balance in sender account %', p_sender
            USING ERRCODE = '22023';
    END IF;
    UPDATE Account SET Balance = Balance - p_amount WHERE AccountNo = p_sender;
    UPDATE Account SET Balance = Balance + p_amount WHERE AccountNo = p_receiver;
    INSERT INTO Transaction_History (AccountNo, Amount, TransactionType, PaymentMode, Remarks)
    VALUES
        (p_sender, p_amount, 'Transfer', p_mode,
         LEFT(FORMAT('Debit to %s: %s', p_receiver, COALESCE(p_remarks, 'Fund transfer')), 255)),
        (p_receiver, p_amount, 'Transfer', p_mode,
         LEFT(FORMAT('Credit from %s: %s', p_sender, COALESCE(p_remarks, 'Fund transfer')), 255));
    -- This must remain outside any EXCEPTION block. A failure above never
    -- reaches COMMIT. Caller must issue CALL at top level in autocommit mode.
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_pay_loan_emi(
    p_customer_id INT, p_loan_id INT, p_account_no INT
) LANGUAGE plpgsql AS $$
DECLARE
    v_account Account%ROWTYPE;
    v_loan Loan%ROWTYPE;
    v_payment NUMERIC(15, 2);
BEGIN
    -- Global order for this workflow: Account before Loan. All checks and the
    -- subsequent trigger operate under these row locks until transaction end.
    SELECT * INTO v_account FROM Account WHERE AccountNo = p_account_no FOR UPDATE;
    IF NOT FOUND OR v_account.CustomerID IS DISTINCT FROM p_customer_id
       OR v_account.Status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'Active account % must belong to customer %', p_account_no, p_customer_id
            USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_loan FROM Loan WHERE LoanID = p_loan_id FOR UPDATE;
    IF NOT FOUND OR v_loan.CustomerID IS DISTINCT FROM p_customer_id
       OR v_loan.Status IS NULL OR v_loan.Status NOT IN ('Approved', 'Active', 'Defaulted')
       OR v_loan.OutstandingBalance <= 0 THEN
        RAISE EXCEPTION 'Loan % is not repayable by customer %', p_loan_id, p_customer_id
            USING ERRCODE = '22023';
    END IF;
    v_payment := LEAST(v_loan.EMI_Amount, v_loan.OutstandingBalance);
    IF v_payment IS NULL OR v_payment <= 0 OR v_account.Balance < v_payment THEN
        RAISE EXCEPTION 'Insufficient balance or invalid EMI for account %', p_account_no
            USING ERRCODE = '22023';
    END IF;
    -- Lab convention explicitly requested: full EMI reduces OutstandingBalance.
    -- There is no interest/principal allocation schedule in the twelve tables.
    UPDATE Account SET Balance = Balance - v_payment WHERE AccountNo = p_account_no;
    INSERT INTO Transaction_History (AccountNo, Amount, TransactionType, PaymentMode, Remarks)
    VALUES (p_account_no, v_payment, 'Withdrawal', 'Internal', FORMAT('Loan EMI: %s', p_loan_id));
    INSERT INTO Loan_Repayment (LoanID, AmountPaid, PaymentMode, PaymentStatus)
    VALUES (p_loan_id, v_payment, 'Auto-Debit', 'Success');
    -- No COMMIT: one atomic CALL in autocommit mode, or caller-managed transaction.
END;
$$;

-- =====================================================================
-- 5. Exactly two explicit bound cursors, one in each batch procedure
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_batch_credit_savings_interest()
LANGUAGE plpgsql AS $$
DECLARE
    savings_cursor CURSOR FOR
        SELECT AccountNo, Balance, InterestRate FROM Account
        WHERE Status = 'Active' AND AccountType = 'Savings'
        ORDER BY AccountNo FOR UPDATE;
    v_account RECORD;
    v_interest NUMERIC(15, 2);
    v_month TIMESTAMP := DATE_TRUNC('month', CURRENT_TIMESTAMP)::timestamp;
BEGIN
    -- Bound cursor FOR loop opens/fetches/closes the cursor automatically.
    FOR v_account IN savings_cursor LOOP
        -- Account locks serialize concurrent batches; recheck history in a fresh
        -- statement after acquiring the row lock. One credit per calendar month.
        IF EXISTS (
            SELECT 1 FROM Transaction_History
            WHERE AccountNo = v_account.AccountNo AND TransactionType = 'Deposit'
              AND Remarks = 'Monthly Interest Credit'
              AND TransactionDate >= v_month
              AND TransactionDate < v_month + INTERVAL '1 month'
        ) THEN
            CONTINUE;
        END IF;
        IF v_account.InterestRate < 0 THEN
            RAISE EXCEPTION 'Negative savings rate on account %', v_account.AccountNo
                USING ERRCODE = '22023';
        END IF;
        v_interest := ROUND((v_account.Balance * v_account.InterestRate / 100) / 12, 2);
        IF v_interest <= 0 THEN
            CONTINUE; -- Transaction_History requires strictly positive Amount.
        END IF;
        UPDATE Account SET Balance = Balance + v_interest
        WHERE AccountNo = v_account.AccountNo;
        INSERT INTO Transaction_History (AccountNo, Amount, TransactionType, PaymentMode, Remarks)
        VALUES (v_account.AccountNo, v_interest, 'Deposit', 'Internal', 'Monthly Interest Credit');
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_batch_mature_fixed_deposits()
LANGUAGE plpgsql AS $$
DECLARE
    maturity_cursor CURSOR FOR
        SELECT FD_ID, CustomerID, MaturityAmount FROM Fixed_Deposit
        WHERE Status = 'Active' AND EndDate <= CURRENT_DATE
        ORDER BY FD_ID FOR UPDATE;
    v_fd RECORD;
    v_account_no INT;
BEGIN
    FOR v_fd IN maturity_cursor LOOP
        -- Primary savings account means oldest ACTIVE Savings account, then
        -- lowest AccountNo. Never pay a Dormant/Frozen/Closed account.
        SELECT AccountNo INTO v_account_no FROM Account
        WHERE CustomerID = v_fd.CustomerID AND AccountType = 'Savings' AND Status = 'Active'
        ORDER BY OpeningDate, AccountNo LIMIT 1 FOR UPDATE;
        IF NOT FOUND THEN
            -- Abort the entire batch: the FD must not be marked paid without
            -- a real account credit. All earlier loop changes also roll back.
            RAISE EXCEPTION 'No Active savings account for FD % customer %', v_fd.FD_ID, v_fd.CustomerID
                USING ERRCODE = '22023';
        END IF;
        IF v_fd.MaturityAmount IS NULL OR v_fd.MaturityAmount <= 0 THEN
            RAISE EXCEPTION 'Invalid maturity amount on FD %', v_fd.FD_ID USING ERRCODE = '22023';
        END IF;
        UPDATE Fixed_Deposit SET Status = 'Matured' WHERE FD_ID = v_fd.FD_ID;
        UPDATE Account SET Balance = Balance + v_fd.MaturityAmount WHERE AccountNo = v_account_no;
        INSERT INTO Transaction_History (AccountNo, Amount, TransactionType, PaymentMode, Remarks)
        VALUES (v_account_no, v_fd.MaturityAmount, 'Deposit', 'Internal',
                FORMAT('FD Maturity Credit: %s', v_fd.FD_ID));
        INSERT INTO Audit_Log (TableName, RecordID, ActionType, Description)
        VALUES ('Fixed_Deposit', v_fd.FD_ID, 'FD_MATURED',
                FORMAT('Maturity amount %s credited to AccountNo=%s', v_fd.MaturityAmount, v_account_no));
        -- The account balance audit is generated by trg_audit_account_changes.
        -- No per-row COMMIT: cursor locks and the entire batch remain atomic.
    END LOOP;
END;
$$;

-- =====================================================================
-- 6. Executable verification against existing Sprint 1 customers/accounts
-- =====================================================================
-- Read-only displays verify all views and both business functions.
SELECT * FROM vw_customer_passbook ORDER BY AccountNo, Date LIMIT 10;
SELECT * FROM vw_branch_financial_summary ORDER BY BranchID;
SELECT * FROM vw_active_vellore_accounts ORDER BY AccountNo;
SELECT fn_calculate_emi(2500000, 8.50, 240) AS calculated_emi,
       fn_customer_net_worth(1) AS customer_1_net_worth;

-- Session-local JSON snapshot avoids introducing any permanent test tables or
-- helper functions and survives sp_transfer_funds's explicit COMMIT.
SELECT SET_CONFIG('banking.demo_before', JSONB_BUILD_OBJECT(
    'sender', (SELECT Balance FROM Account WHERE AccountNo = 100001),
    'receiver', (SELECT Balance FROM Account WHERE AccountNo = 100003),
    'loan', (SELECT OutstandingBalance FROM Loan WHERE LoanID = 2001),
    'emi', (SELECT LEAST(EMI_Amount, OutstandingBalance) FROM Loan WHERE LoanID = 2001),
    'history', (SELECT COUNT(*) FROM Transaction_History),
    'audits', (SELECT COUNT(*) FROM Audit_Log),
    'repayments', (SELECT COUNT(*) FROM Loan_Repayment)
)::text, false) AS demo_snapshot;

-- Must be a top-level CALL: commits the transfer and two account audit rows.
CALL sp_transfer_funds(100001, 100003, 1000.00, 'Internal', 'Advanced logic verification');

DO $$
DECLARE v_before JSONB := CURRENT_SETTING('banking.demo_before')::jsonb;
BEGIN
    IF (SELECT Balance FROM Account WHERE AccountNo = 100001) <> (v_before->>'sender')::numeric - 1000
       OR (SELECT Balance FROM Account WHERE AccountNo = 100003) <> (v_before->>'receiver')::numeric + 1000
       OR (SELECT COUNT(*) FROM Transaction_History) <> (v_before->>'history')::bigint + 2
       OR (SELECT COUNT(*) FROM Audit_Log) <> (v_before->>'audits')::bigint + 2 THEN
        RAISE EXCEPTION 'Transfer verification failed';
    END IF;
    RAISE NOTICE 'PASS: transfer conserves funds, writes two history rows and two audits';
END;
$$;

CALL sp_pay_loan_emi(1, 2001, 100001);

DO $$
DECLARE v_before JSONB := CURRENT_SETTING('banking.demo_before')::jsonb;
BEGIN
    IF (SELECT Balance FROM Account WHERE AccountNo = 100001)
           <> (v_before->>'sender')::numeric - 1000 - (v_before->>'emi')::numeric
       OR (SELECT OutstandingBalance FROM Loan WHERE LoanID = 2001)
           <> (v_before->>'loan')::numeric - (v_before->>'emi')::numeric
       OR (SELECT COUNT(*) FROM Loan_Repayment) <> (v_before->>'repayments')::bigint + 1 THEN
        RAISE EXCEPTION 'EMI verification failed';
    END IF;
    IF EXISTS (SELECT 1 FROM Loan WHERE EMI_Amount <> fn_calculate_emi(PrincipalAmount, InterestRate, TenureMonths))
       OR fn_calculate_emi(12000, 0, 12) <> 1000
       OR fn_customer_net_worth(10) <> 0 THEN
        RAISE EXCEPTION 'UDF verification failed';
    END IF;
    RAISE NOTICE 'PASS: EMI debit, repayment trigger, stored EMI agreement, zero rate and NULL-safe totals';
END;
$$;

SELECT SET_CONFIG('banking.batch_before', JSONB_BUILD_OBJECT(
    'balance', (SELECT SUM(Balance) FROM Account),
    'interest', (SELECT COALESCE(SUM(ROUND(a.Balance * a.InterestRate / 1200, 2)), 0)
                 FROM Account a WHERE a.Status = 'Active' AND a.AccountType = 'Savings'
                 AND NOT EXISTS (
                     SELECT 1 FROM Transaction_History t WHERE t.AccountNo = a.AccountNo
                     AND t.TransactionType = 'Deposit' AND t.Remarks = 'Monthly Interest Credit'
                     AND t.TransactionDate >= DATE_TRUNC('month', CURRENT_TIMESTAMP)
                     AND t.TransactionDate < DATE_TRUNC('month', CURRENT_TIMESTAMP) + INTERVAL '1 month')),
    'maturity', (SELECT COALESCE(SUM(MaturityAmount), 0) FROM Fixed_Deposit
                 WHERE Status = 'Active' AND EndDate <= CURRENT_DATE)
)::text, false) AS expected_batch_postings;
CALL sp_batch_credit_savings_interest();
CALL sp_batch_mature_fixed_deposits();

DO $$
DECLARE v_before JSONB := CURRENT_SETTING('banking.batch_before')::jsonb;
BEGIN
    IF (SELECT SUM(Balance) FROM Account) <> (v_before->>'balance')::numeric
           + (v_before->>'interest')::numeric + (v_before->>'maturity')::numeric THEN
        RAISE EXCEPTION 'Batch credits do not match expected interest and maturity amounts';
    END IF;
    RAISE NOTICE 'PASS: batch balance increase matches calculated interest plus due FD maturity';
END;
$$;

-- Snapshot after both batches, then prove immediate reruns do not pay twice.
SELECT SET_CONFIG('banking.batch_after', JSONB_BUILD_OBJECT(
    'balance', (SELECT SUM(Balance) FROM Account),
    'history', (SELECT COUNT(*) FROM Transaction_History),
    'audits', (SELECT COUNT(*) FROM Audit_Log)
)::text, false) AS batch_snapshot;
CALL sp_batch_credit_savings_interest();
CALL sp_batch_mature_fixed_deposits();

DO $$
DECLARE v_after JSONB := CURRENT_SETTING('banking.batch_after')::jsonb;
BEGIN
    IF (SELECT SUM(Balance) FROM Account) <> (v_after->>'balance')::numeric
       OR (SELECT COUNT(*) FROM Transaction_History) <> (v_after->>'history')::bigint
       OR (SELECT COUNT(*) FROM Audit_Log) <> (v_after->>'audits')::bigint THEN
        RAISE EXCEPTION 'Batch duplicate-posting verification failed';
    END IF;
    IF EXISTS (SELECT 1 FROM Fixed_Deposit WHERE Status = 'Active' AND EndDate <= CURRENT_DATE)
       OR NOT EXISTS (SELECT 1 FROM Transaction_History WHERE Remarks = 'Monthly Interest Credit')
       OR NOT EXISTS (SELECT 1 FROM Audit_Log WHERE TableName = 'Fixed_Deposit' AND ActionType = 'FD_MATURED') THEN
        RAISE EXCEPTION 'Batch processing verification failed';
    END IF;
    IF (SELECT is_updatable FROM information_schema.views
        WHERE table_schema = 'public' AND table_name = 'vw_active_vellore_accounts') <> 'YES' THEN
        RAISE EXCEPTION 'Vellore view must be updatable';
    END IF;
    RAISE NOTICE 'PASS: interest, FD maturity, audit, duplicate protection and updatable restricted view';
END;
$$;

-- Expected validation failures are caught only in these TEST blocks. Each
-- inner block is a subtransaction; its changes roll back automatically.
-- Transfer failure paths never reach COMMIT, so testing them here is valid.
DO $$
DECLARE
    v_balance NUMERIC;
    v_history BIGINT;
    v_audits BIGINT;
    v_debt NUMERIC;
BEGIN
    SELECT SUM(Balance) INTO v_balance FROM Account;
    SELECT COUNT(*) INTO v_history FROM Transaction_History;
    SELECT COUNT(*) INTO v_audits FROM Audit_Log;
    BEGIN
        CALL sp_transfer_funds(100001, 100003, 999999999999.00, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected insufficient-funds rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100001, 100011, 1.00, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected Frozen receiver rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100008, 100003, 1.00, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected Dormant sender rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100001, 100001, 1.00, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected same-account rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100001, 100003, -1.00, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected negative-amount rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100001, 100003, 0.001, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected fractional-paise rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100001, 100003, 1.00, 'Invalid', 'Must fail');
        RAISE EXCEPTION 'Expected payment-mode rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        CALL sp_transfer_funds(100001, -1, 1.00, 'Internal', 'Must fail');
        RAISE EXCEPTION 'Expected missing-account rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    -- Force the RECEIVER update to overflow after sender debit/audit succeeded.
    -- Catching the real database error rolls the entire inner test block back,
    -- including the test setup, sender debit, and generated audit record.
    BEGIN
        UPDATE Account SET Balance = 9999999999999.99 WHERE AccountNo = 100003;
        CALL sp_transfer_funds(100001, 100003, 1.00, 'Internal', 'Rollback after debit');
        RAISE EXCEPTION 'Expected receiver balance overflow';
    EXCEPTION WHEN numeric_value_out_of_range THEN NULL;
    END;
    BEGIN
        CALL sp_pay_loan_emi(2, 2001, 100003);
        RAISE EXCEPTION 'Expected loan-ownership rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        PERFORM fn_calculate_emi(1000, 5, 0);
        RAISE EXCEPTION 'Expected invalid-tenure rejection';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
    BEGIN
        UPDATE vw_active_vellore_accounts SET Status = 'Frozen' WHERE AccountNo = 100001;
        RAISE EXCEPTION 'Expected view CHECK OPTION rejection';
    EXCEPTION WHEN SQLSTATE '44000' THEN NULL; -- with_check_option_violation
    END;
    -- A failed or pending payment is recorded but cannot reduce the debt.
    -- Roll these test inserts back deliberately with SQLSTATE Z0001.
    SELECT OutstandingBalance INTO v_debt FROM Loan WHERE LoanID = 2001;
    BEGIN
        INSERT INTO Loan_Repayment (LoanID, AmountPaid, PaymentMode, PaymentStatus)
        VALUES (2001, 1, 'UPI', 'Failed'), (2001, 1, 'UPI', 'Pending');
        IF (SELECT OutstandingBalance FROM Loan WHERE LoanID = 2001) <> v_debt THEN
            RAISE EXCEPTION 'Unsuccessful repayments reduced debt';
        END IF;
        RAISE EXCEPTION 'Rollback unsuccessful-payment test fixtures' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
    END;
    -- Simulate the final installment using existing rows, then undo all effects.
    BEGIN
        UPDATE Loan SET OutstandingBalance = 10 WHERE LoanID = 2001;
        CALL sp_pay_loan_emi(1, 2001, 100001);
        IF NOT EXISTS (SELECT 1 FROM Loan WHERE LoanID = 2001
                       AND OutstandingBalance = 0 AND Status = 'Closed') THEN
            RAISE EXCEPTION 'Final installment failed to close loan';
        END IF;
        RAISE EXCEPTION 'Rollback final-installment test' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
    END;
    IF (SELECT SUM(Balance) FROM Account) <> v_balance
       OR (SELECT COUNT(*) FROM Transaction_History) <> v_history
       OR (SELECT COUNT(*) FROM Audit_Log) <> v_audits
       OR (SELECT OutstandingBalance FROM Loan WHERE LoanID = 2001) <> v_debt THEN
        RAISE EXCEPTION 'Validation/rollback tests leaked changes';
    END IF;
    RAISE NOTICE 'PASS: validation failures roll back, unsuccessful repayments ignored, final EMI closes loan';
END;
$$;

SELECT AccountNo, Balance FROM Account WHERE AccountNo IN (100001, 100003) ORDER BY AccountNo;
SELECT LoanID, EMI_Amount, OutstandingBalance, Status FROM Loan WHERE LoanID = 2001;
SELECT FD_ID, MaturityAmount, Status FROM Fixed_Deposit WHERE FD_ID = 3001;
SELECT 'Advanced logic installed and all verification blocks passed' AS result;
