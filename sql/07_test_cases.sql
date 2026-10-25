-- Review 3: exactly fifteen executable test cases, run as postgres after 01-06.
-- psql -X -v ON_ERROR_STOP=1 -U postgres -d banking_db -f this_file.sql
-- Expected failures use nested EXCEPTION WHEN others handlers which verify the
-- exact SQLSTATE/constraint. An unexpected error or missing rejection FAILS the
-- suite instead of being mistaken for success. Test changes are rolled back;
-- SERIAL sequences may consume values even when their inserted rows roll back.

-- TC-01: Customer primary-key uniqueness (23505, customer_pkey).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    BEGIN
        INSERT INTO public.Customer SELECT * FROM public.Customer WHERE CustomerID = 1;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23505' OR v_constraint <> 'customer_pkey' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-01 PASS: Expected failure caught (duplicate customer PK)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-01 FAIL: duplicate PK accepted or fixture missing'; END IF;
END;
$$;

-- TC-02: Account cannot reference a nonexistent customer (23503).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM public.Customer WHERE CustomerID = -2147483648) THEN
        RAISE EXCEPTION 'TC-02 fixture ID must be unused';
    END IF;
    BEGIN
        UPDATE public.Account SET CustomerID = -2147483648 WHERE AccountNo = 100001;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23503' OR v_constraint <> 'account_customerid_fkey' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-02 PASS: Expected failure caught (missing customer FK)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-02 FAIL: invalid customer FK accepted'; END IF;
END;
$$;

-- TC-03: Loan cannot reference a nonexistent issuing branch (23503).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM public.Branch WHERE BranchID = -2147483648) THEN
        RAISE EXCEPTION 'TC-03 fixture ID must be unused';
    END IF;
    BEGIN
        UPDATE public.Loan SET BranchID = -2147483648 WHERE LoanID = 2001;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23503' OR v_constraint <> 'loan_branchid_fkey' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-03 PASS: Expected failure caught (missing branch FK)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-03 FAIL: invalid branch FK accepted'; END IF;
END;
$$;

-- TC-04: Customer must be at least 18 (23514, customer_age_check).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    BEGIN
        UPDATE public.Customer SET Age = 17 WHERE CustomerID = 1;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23514' OR v_constraint <> 'customer_age_check' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-04 PASS: Expected failure caught (Age below 18)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-04 FAIL: underage customer accepted'; END IF;
END;
$$;

-- TC-05: Account balance cannot be negative (23514).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    BEGIN
        UPDATE public.Account SET Balance = -1 WHERE AccountNo = 100001;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23514' OR v_constraint <> 'account_balance_check' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-05 PASS: Expected failure caught (negative balance)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-05 FAIL: negative balance accepted'; END IF;
END;
$$;

-- TC-06: Gender must match the allowed enumeration (23514).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    BEGIN
        UPDATE public.Customer SET Gender = 'Invalid' WHERE CustomerID = 1;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23514' OR v_constraint <> 'customer_gender_check' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-06 PASS: Expected failure caught (invalid Gender)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-06 FAIL: invalid gender accepted'; END IF;
END;
$$;

-- TC-07: Two customers cannot share the same PAN (23505).
DO $$
DECLARE v_caught BOOLEAN := false; v_constraint TEXT;
BEGIN
    BEGIN
        UPDATE public.Customer SET PAN_Number = (SELECT PAN_Number FROM public.Customer WHERE CustomerID = 1)
        WHERE CustomerID = 2;
    EXCEPTION WHEN others THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF SQLSTATE <> '23505' OR v_constraint <> 'customer_pan_number_key' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-07 PASS: Expected failure caught (duplicate PAN)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-07 FAIL: duplicate PAN accepted'; END IF;
END;
$$;

-- TC-08: A balance credit creates exactly one audit with the right old/new values.
-- Deliberately roll back the successful update and its audit after checking.
DO $$
DECLARE v_before BIGINT; v_balance NUMERIC;
BEGIN
    SELECT COUNT(*) INTO v_before FROM public.Audit_Log;
    SELECT Balance INTO STRICT v_balance FROM public.Account WHERE AccountNo = 100001;
    BEGIN
        UPDATE public.Account SET Balance = Balance + 1 WHERE AccountNo = 100001;
        IF (SELECT COUNT(*) FROM public.Audit_Log) <> v_before + 1 OR NOT EXISTS (
            SELECT 1 FROM public.Audit_Log WHERE TableName = 'Account' AND RecordID = 100001
              AND ActionType = 'BALANCE_UPDATE'
              AND Description = FORMAT('AccountNo=%s; old balance=%s; new balance=%s',
                                       100001, v_balance::numeric(15,2), (v_balance+1)::numeric(15,2))
        ) THEN RAISE EXCEPTION 'TC-08 FAIL: balance credit audit missing or incorrect'; END IF;
        RAISE EXCEPTION 'Undo successful audit test' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
    END;
    IF (SELECT COUNT(*) FROM public.Audit_Log) <> v_before
       OR (SELECT Balance FROM public.Account WHERE AccountNo = 100001) <> v_balance THEN
        RAISE EXCEPTION 'TC-08 FAIL: test rollback leaked changes';
    END IF;
    RAISE NOTICE 'TC-08 PASS: credit audit records correct balances; test changes rolled back';
END;
$$;

-- TC-09: A debit audits once; setting Balance to itself produces no extra audit.
DO $$
DECLARE v_before BIGINT; v_balance NUMERIC;
BEGIN
    SELECT COUNT(*) INTO v_before FROM public.Audit_Log;
    SELECT Balance INTO STRICT v_balance FROM public.Account WHERE AccountNo = 100003;
    IF v_balance < 0.01 THEN RAISE EXCEPTION 'TC-09 requires at least one paise'; END IF;
    BEGIN
        UPDATE public.Account SET Balance = Balance - 0.01 WHERE AccountNo = 100003;
        IF (SELECT COUNT(*) FROM public.Audit_Log) <> v_before + 1 OR NOT EXISTS (
            SELECT 1 FROM public.Audit_Log WHERE TableName = 'Account' AND RecordID = 100003
              AND ActionType = 'BALANCE_UPDATE'
              AND Description = FORMAT('AccountNo=%s; old balance=%s; new balance=%s',
                                       100003, v_balance::numeric(15,2), (v_balance-0.01)::numeric(15,2))
        ) THEN RAISE EXCEPTION 'TC-09 FAIL: debit audit missing or incorrect'; END IF;
        UPDATE public.Account SET Balance = Balance WHERE AccountNo = 100003;
        IF (SELECT COUNT(*) FROM public.Audit_Log) <> v_before + 1 THEN
            RAISE EXCEPTION 'TC-09 FAIL: no-op update produced an audit';
        END IF;
        RAISE EXCEPTION 'Undo successful debit test' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
    END;
    IF (SELECT COUNT(*) FROM public.Audit_Log) <> v_before
       OR (SELECT Balance FROM public.Account WHERE AccountNo = 100003) <> v_balance THEN
        RAISE EXCEPTION 'TC-09 FAIL: test rollback leaked changes';
    END IF;
    RAISE NOTICE 'TC-09 PASS: debit audited once, no-op ignored, changes rolled back';
END;
$$;

-- TC-10: Insufficient-funds procedure rejection must happen before COMMIT.
-- Catch only the exact validation error, not privilege/transaction-control errors.
DO $$
DECLARE
    v_caught BOOLEAN := false; v_sender NUMERIC; v_receiver NUMERIC;
    v_history BIGINT; v_audits BIGINT;
BEGIN
    SELECT Balance INTO STRICT v_sender FROM public.Account WHERE AccountNo = 100001;
    SELECT Balance INTO STRICT v_receiver FROM public.Account WHERE AccountNo = 100003;
    SELECT COUNT(*) INTO v_history FROM public.Transaction_History;
    SELECT COUNT(*) INTO v_audits FROM public.Audit_Log;
    BEGIN
        CALL public.sp_transfer_funds(100001, 100003, v_sender + 1, 'Internal', 'TC-10 must fail');
    EXCEPTION WHEN others THEN
        IF SQLSTATE <> '22023' OR SQLERRM NOT LIKE 'Insufficient balance%' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-10 PASS: Expected failure caught (insufficient balance)';
    END;
    IF NOT v_caught OR (SELECT Balance FROM public.Account WHERE AccountNo = 100001) <> v_sender
       OR (SELECT Balance FROM public.Account WHERE AccountNo = 100003) <> v_receiver
       OR (SELECT COUNT(*) FROM public.Transaction_History) <> v_history
       OR (SELECT COUNT(*) FROM public.Audit_Log) <> v_audits THEN
        RAISE EXCEPTION 'TC-10 FAIL: rejected transfer changed balances/history/audit';
    END IF;
END;
$$;

-- TC-11: Passbook returns exactly the four-table join's rows and readable remarks.
DO $$
DECLARE v_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM public.vw_customer_passbook;
    IF v_count = 0 OR v_count <> (
        SELECT COUNT(*) FROM public.Customer c
        JOIN public.Account a ON a.CustomerID = c.CustomerID
        JOIN public.Branch b ON b.BranchID = a.BranchID
        JOIN public.Transaction_History t ON t.AccountNo = a.AccountNo
    ) OR EXISTS (SELECT 1 FROM public.vw_customer_passbook WHERE Remarks IS NULL) THEN
        RAISE EXCEPTION 'TC-11 FAIL: passbook empty, incorrect count, or unreadable NULL remarks';
    END IF;
    RAISE NOTICE 'TC-11 PASS: passbook retrieves % joined transaction rows', v_count;
END;
$$;

-- TC-12: Summary has one row per branch and no account/loan/FD fan-out.
-- FD bank-wide total covers Active FDs of owners having at least one account,
-- matching the documented primary-account attribution in the view.
DO $$
DECLARE v_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM public.vw_branch_financial_summary;
    IF v_count = 0 OR v_count <> (SELECT COUNT(*) FROM public.Branch)
       OR EXISTS (
           SELECT 1 FROM public.vw_branch_financial_summary s
           WHERE s.total_active_accounts <> (SELECT COUNT(*) FROM public.Account a
                                             WHERE a.BranchID=s.BranchID AND a.Status='Active')
              OR s.total_loan_outstanding <> COALESCE((SELECT SUM(l.OutstandingBalance)
                                             FROM public.Loan l WHERE l.BranchID=s.BranchID), 0)
       ) OR (SELECT SUM(total_fd_maturity_amounts) FROM public.vw_branch_financial_summary)
            IS DISTINCT FROM (SELECT COALESCE(SUM(f.MaturityAmount), 0) FROM public.Fixed_Deposit f
                WHERE f.Status='Active' AND EXISTS (SELECT 1 FROM public.Account a WHERE a.CustomerID=f.CustomerID)) THEN
        RAISE EXCEPTION 'TC-12 FAIL: branch summary counts or financial totals do not reconcile';
    END IF;
    RAISE NOTICE 'TC-12 PASS: all % branches reconcile with independent product totals', v_count;
END;
$$;

-- TC-13: EMI reference example, zero-interest case, and every stored loan EMI.
DO $$
DECLARE v_emi NUMERIC;
BEGIN
    SELECT public.fn_calculate_emi(2500000, 8.50, 240) INTO v_emi;
    IF v_emi IS DISTINCT FROM 21695.58
       OR public.fn_calculate_emi(12000, 0, 12) IS DISTINCT FROM 1000.00
       OR EXISTS (SELECT 1 FROM public.Loan
                  WHERE EMI_Amount IS DISTINCT FROM public.fn_calculate_emi(PrincipalAmount,InterestRate,TenureMonths)) THEN
        RAISE EXCEPTION 'TC-13 FAIL: EMI function disagrees with reference/generated values';
    END IF;
    RAISE NOTICE 'TC-13 PASS: reference EMI=%, zero-rate and all stored EMIs agree', v_emi;
END;
$$;

-- TC-14: Validate net worth for EVERY customer, including missing products.
-- Independent signed UNION ALL ledger avoids duplicating the UDF's scalar
-- subquery implementation and catches one-to-many join multiplication.
DO $$
DECLARE v_customer RECORD; v_expected NUMERIC; v_actual NUMERIC; v_count INT := 0;
BEGIN
    FOR v_customer IN SELECT CustomerID FROM public.Customer ORDER BY CustomerID LOOP
        SELECT COALESCE(SUM(component), 0) INTO v_expected FROM (
            SELECT Balance AS component FROM public.Account WHERE CustomerID=v_customer.CustomerID
            UNION ALL
            SELECT Amount FROM public.Fixed_Deposit WHERE CustomerID=v_customer.CustomerID AND Status='Active'
            UNION ALL
            SELECT -OutstandingBalance FROM public.Loan WHERE CustomerID=v_customer.CustomerID
        ) products;
        SELECT public.fn_customer_net_worth(v_customer.CustomerID) INTO v_actual;
        IF v_actual IS DISTINCT FROM v_expected THEN
            RAISE EXCEPTION 'TC-14 FAIL: customer % expected %, got %', v_customer.CustomerID, v_expected, v_actual;
        END IF;
        v_count := v_count + 1;
    END LOOP;
    IF v_count = 0 THEN RAISE EXCEPTION 'TC-14 FAIL: customer fixtures missing'; END IF;
    RAISE NOTICE 'TC-14 PASS: net worth reconciles for % customers, including absent-product NULL handling', v_count;
END;
$$;

-- TC-15: A nonnumeric string cannot populate integer Age (22P02).
-- Dynamic SQL defers literal-to-integer conversion until inside the handler.
DO $$
DECLARE v_caught BOOLEAN := false;
BEGIN
    BEGIN
        EXECUTE 'UPDATE public.Customer SET Age = ''not-an-integer'' WHERE CustomerID = 1';
    EXCEPTION WHEN others THEN
        IF SQLSTATE <> '22P02' THEN RAISE; END IF;
        v_caught := true;
        RAISE NOTICE 'TC-15 PASS: Expected failure caught (invalid integer input)';
    END;
    IF NOT v_caught THEN RAISE EXCEPTION 'TC-15 FAIL: integer column accepted a string'; END IF;
END;
$$;

SELECT 'All 15 test cases passed; expected failures caught; row data preserved' AS result;
