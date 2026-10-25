-- Administration sprint. Run as postgres in banking_db AFTER 01-05.
-- psql -X -v ON_ERROR_STOP=1, autocommit enabled; do not use --single-transaction.
-- Only the three named project roles are reset. No data or tables are dropped.
-- Roles are NOLOGIN group roles, intended for later assignment to real logins.

-- =====================================================================
-- 1. Role reset, grants, and secure procedure exposure
-- =====================================================================
BEGIN;

-- On reruns, recover ownership of ONLY the specific routines assigned below.
-- Refuse to delete a role owning anything else, rather than dropping its objects.
-- DROP OWNED is used only after the ownership guard: it then revokes grants.
-- Grants in unrelated databases are not removed; DROP ROLE will safely fail if
-- such dependencies exist (these are dedicated roles for this lab database).
DO $$
DECLARE
    v_role RECORD;
    v_routine RECORD;
BEGIN
    FOR v_role IN SELECT oid, rolname FROM pg_roles
                  WHERE rolname IN ('bank_admin', 'branch_manager', 'bank_teller') LOOP
        FOR v_routine IN
            SELECT p.oid::regprocedure AS identity, p.prokind
            FROM pg_proc p
            WHERE p.proowner = v_role.oid AND p.oid = ANY (ARRAY[
                TO_REGPROCEDURE('public._bank_transfer_atomic(integer,integer,numeric,character varying,character varying)')::oid,
                TO_REGPROCEDURE('public.tg_audit_account_changes()')::oid,
                TO_REGPROCEDURE('public.sp_pay_loan_emi(integer,integer,integer)')::oid,
                TO_REGPROCEDURE('public.sp_batch_credit_savings_interest()')::oid,
                TO_REGPROCEDURE('public.sp_batch_mature_fixed_deposits()')::oid
            ])
        LOOP
            EXECUTE FORMAT('ALTER %s %s OWNER TO %I',
                CASE WHEN v_routine.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                v_routine.identity, CURRENT_USER);
        END LOOP;
        IF EXISTS (SELECT 1 FROM pg_shdepend
                   WHERE refclassid = 'pg_authid'::regclass
                     AND refobjid = v_role.oid AND deptype = 'o') THEN
            RAISE EXCEPTION 'Refusing to drop role %: it owns objects outside this script', v_role.rolname;
        END IF;
        EXECUTE FORMAT('DROP OWNED BY %I RESTRICT', v_role.rolname);
    END LOOP;
END;
$$;

DROP ROLE IF EXISTS bank_teller;
DROP ROLE IF EXISTS branch_manager;
DROP ROLE IF EXISTS bank_admin;
CREATE ROLE bank_admin NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE branch_manager NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE bank_teller NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- PUBLIC receives function EXECUTE by default; explicit role grants alone would
-- not restrict access. Remove those inherited permissions for this lab schema.
-- Prevent untrusted objects in public from shadowing names in definer routines.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE banking_db TO bank_admin, branch_manager, bank_teller;
GRANT USAGE ON SCHEMA public TO bank_admin, branch_manager, bank_teller;

-- The Sprint 3 transfer procedure explicitly COMMITs, so it CANNOT itself be
-- SECURITY DEFINER (PostgreSQL forbids that combination). Instead, this narrowly
-- scoped function performs validated, atomic writes with a fixed search_path;
-- the invoker procedure below calls it and then COMMITs. No direct table grants
-- to the teller are needed. The helper is callable for the same transfer operation
-- only; it exposes no general-purpose SQL, arbitrary tables, or audit rewriting.
CREATE OR REPLACE FUNCTION public._bank_transfer_atomic(
    p_sender INT, p_receiver INT, p_amount DECIMAL, p_mode VARCHAR, p_remarks VARCHAR
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
    v_sender public.Account%ROWTYPE;
    v_receiver public.Account%ROWTYPE;
BEGIN
    IF p_sender IS NULL OR p_receiver IS NULL OR p_sender = p_receiver THEN
        RAISE EXCEPTION 'Transfer requires two different account numbers' USING ERRCODE = '22023';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> ROUND(p_amount, 2)
       OR p_amount::text IN ('NaN', 'Infinity', '-Infinity') THEN
        RAISE EXCEPTION 'Transfer amount must be finite, positive, and at most two decimal places'
            USING ERRCODE = '22023';
    END IF;
    IF p_mode IS NULL OR p_mode NOT IN ('UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash', 'Internal') THEN
        RAISE EXCEPTION 'Invalid payment mode: %', p_mode USING ERRCODE = '22023';
    END IF;
    PERFORM AccountNo FROM public.Account WHERE AccountNo IN (p_sender, p_receiver)
    ORDER BY AccountNo FOR UPDATE;
    SELECT * INTO v_sender FROM public.Account WHERE AccountNo = p_sender;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sender account % does not exist', p_sender USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_receiver FROM public.Account WHERE AccountNo = p_receiver;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receiver account % does not exist', p_receiver USING ERRCODE = '22023';
    END IF;
    IF v_sender.Status IS DISTINCT FROM 'Active' OR v_receiver.Status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'Both transfer accounts must be Active' USING ERRCODE = '22023';
    END IF;
    IF v_sender.Balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance in sender account %', p_sender USING ERRCODE = '22023';
    END IF;
    UPDATE public.Account SET Balance = Balance - p_amount WHERE AccountNo = p_sender;
    UPDATE public.Account SET Balance = Balance + p_amount WHERE AccountNo = p_receiver;
    INSERT INTO public.Transaction_History (AccountNo, Amount, TransactionType, PaymentMode, Remarks)
    VALUES
        (p_sender, p_amount, 'Transfer', p_mode,
         LEFT(FORMAT('Debit to %s: %s', p_receiver, COALESCE(p_remarks, 'Fund transfer')), 255)),
        (p_receiver, p_amount, 'Transfer', p_mode,
         LEFT(FORMAT('Credit from %s: %s', p_sender, COALESCE(p_remarks, 'Fund transfer')), 255));
END;
$$;

CREATE OR REPLACE PROCEDURE public.sp_transfer_funds(
    p_sender INT, p_receiver INT, p_amount DECIMAL, p_mode VARCHAR, p_remarks VARCHAR
) LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    PERFORM public._bank_transfer_atomic(p_sender, p_receiver, p_amount, p_mode, p_remarks);
    COMMIT;
END;
$$;

-- These procedures do not contain transaction control; definer execution is
-- appropriate. The manager can run them without general audit/history writes.
ALTER PROCEDURE public.sp_pay_loan_emi(INT, INT, INT) SECURITY DEFINER;
ALTER PROCEDURE public.sp_pay_loan_emi(INT, INT, INT) SET search_path = pg_catalog, public, pg_temp;
ALTER PROCEDURE public.sp_batch_credit_savings_interest() SECURITY DEFINER;
ALTER PROCEDURE public.sp_batch_credit_savings_interest() SET search_path = pg_catalog, public, pg_temp;
ALTER PROCEDURE public.sp_batch_mature_fixed_deposits() SECURITY DEFINER;
ALTER PROCEDURE public.sp_batch_mature_fixed_deposits() SET search_path = pg_catalog, public, pg_temp;
-- Direct manager Account updates must still write protected audit records.
ALTER FUNCTION public.tg_audit_account_changes() SECURITY DEFINER;
ALTER FUNCTION public.tg_audit_account_changes() SET search_path = pg_catalog, public, pg_temp;

-- Definer code runs as a non-superuser project role, not as postgres.
GRANT ALL PRIVILEGES ON DATABASE banking_db TO bank_admin;
GRANT ALL PRIVILEGES ON SCHEMA public TO bank_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO bank_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bank_admin;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO bank_admin;
ALTER FUNCTION public._bank_transfer_atomic(INT, INT, NUMERIC, VARCHAR, VARCHAR) OWNER TO bank_admin;
ALTER FUNCTION public.tg_audit_account_changes() OWNER TO bank_admin;
ALTER PROCEDURE public.sp_pay_loan_emi(INT, INT, INT) OWNER TO bank_admin;
ALTER PROCEDURE public.sp_batch_credit_savings_interest() OWNER TO bank_admin;
ALTER PROCEDURE public.sp_batch_mature_fixed_deposits() OWNER TO bank_admin;

-- GRANT matrix (existing objects):
-- Role            Tables/views                         Routines
-- bank_admin      ALL tables/views + sequence ALL       ALL
-- branch_manager  SELECT/INSERT/UPDATE Customer,        all 4 procedures;
--                 Account, Loan                        transfer helper EXECUTE
-- bank_teller     SELECT vw_customer_passbook only      transfer + its helper
-- No memberships in bank_admin are granted to the other roles.
GRANT SELECT, INSERT, UPDATE ON public.Customer, public.Account, public.Loan TO branch_manager;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO branch_manager;
GRANT SELECT ON public.vw_customer_passbook TO bank_teller;
GRANT EXECUTE ON PROCEDURE public.sp_transfer_funds(INT, INT, NUMERIC, VARCHAR, VARCHAR) TO bank_teller;
REVOKE ALL ON FUNCTION public._bank_transfer_atomic(INT, INT, NUMERIC, VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._bank_transfer_atomic(INT, INT, NUMERIC, VARCHAR, VARCHAR)
TO branch_manager, bank_teller;

-- REVOKE demonstration: no DELETE permission remains after these statements.
GRANT DELETE ON public.Account TO bank_teller;
REVOKE DELETE ON public.Account FROM bank_teller;

-- An unexpected error or an unexpectedly successful DELETE is a real failure.
-- WHERE false avoids data loss even if permissions were accidentally too broad.
DO $$
DECLARE v_denied BOOLEAN := false;
BEGIN
    SET LOCAL ROLE bank_teller;
    BEGIN
        DELETE FROM public.Account WHERE false;
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := true;
        RAISE NOTICE 'PASS: bank_teller DELETE denied (SQLSTATE %)', SQLSTATE;
    END;
    RESET ROLE;
    IF NOT v_denied THEN RAISE EXCEPTION 'Least privilege failed: teller can DELETE Account'; END IF;
    IF HAS_TABLE_PRIVILEGE('bank_teller', 'public.Account', 'UPDATE')
       OR HAS_TABLE_PRIVILEGE('bank_teller', 'public.Account', 'SELECT')
       OR HAS_FUNCTION_PRIVILEGE('bank_teller', 'public.fn_customer_net_worth(integer)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Teller inherited unintended base-table or routine access';
    END IF;
    SET LOCAL ROLE bank_teller;
    PERFORM * FROM public.vw_customer_passbook LIMIT 1;
    RESET ROLE;
    RAISE NOTICE 'PASS: teller can read passbook while base Account access remains denied';
END;
$$;
COMMIT;

-- Prove the teller can actually perform a VALID transfer. One paise is moved
-- and then returned. Balances are unchanged; four history/audit rows remain as
-- evidence. Both CALLs must be top-level because the procedure explicitly COMMITs.
SET ROLE bank_teller;
CALL public.sp_transfer_funds(100001, 100003, 0.01, 'Internal', 'RBAC transfer proof');
CALL public.sp_transfer_funds(100003, 100001, 0.01, 'Internal', 'RBAC transfer reversal');
RESET ROLE;

-- Actual effective permission matrix for the report.
SELECT role_name,
       HAS_TABLE_PRIVILEGE(role_name, 'public.Account', 'SELECT') AS account_select,
       HAS_TABLE_PRIVILEGE(role_name, 'public.Account', 'INSERT') AS account_insert,
       HAS_TABLE_PRIVILEGE(role_name, 'public.Account', 'UPDATE') AS account_update,
       HAS_TABLE_PRIVILEGE(role_name, 'public.Account', 'DELETE') AS account_delete,
       HAS_TABLE_PRIVILEGE(role_name, 'public.vw_customer_passbook', 'SELECT') AS passbook_select,
       HAS_FUNCTION_PRIVILEGE(role_name,
           'public.sp_transfer_funds(integer,integer,numeric,character varying,character varying)',
           'EXECUTE') AS transfer_execute
FROM (VALUES ('bank_admin'), ('branch_manager'), ('bank_teller')) roles(role_name)
ORDER BY role_name;

-- =====================================================================
-- 2. Three indexes and EXPLAIN ANALYZE before/after evidence
-- =====================================================================
-- The baseline temporarily removes only the named project index, restoring it
-- on ROLLBACK if it previously existed. Other indexes/planner choices remain.
-- With a small seed table, PostgreSQL may correctly choose a sequential scan
-- even after indexing. Do not claim a speedup from these tiny timings.
BEGIN;
DROP INDEX IF EXISTS public.idx_txn_account_date;
EXPLAIN (ANALYZE, BUFFERS)
SELECT TransactionID, AccountNo, TransactionDate, Amount
FROM public.Transaction_History
WHERE AccountNo = 100001 AND TransactionDate >= CURRENT_DATE - INTERVAL '365 days'
ORDER BY TransactionDate;
ROLLBACK;

CREATE INDEX IF NOT EXISTS idx_txn_account_date ON public.Transaction_History(AccountNo, TransactionDate);
CREATE INDEX IF NOT EXISTS idx_customer_name ON public.Customer(LastName, FirstName);
CREATE INDEX IF NOT EXISTS idx_loan_status ON public.Loan(CustomerID, Status);
ANALYZE public.Transaction_History;
ANALYZE public.Customer;
ANALYZE public.Loan;
EXPLAIN (ANALYZE, BUFFERS)
SELECT TransactionID, AccountNo, TransactionDate, Amount
FROM public.Transaction_History
WHERE AccountNo = 100001 AND TransactionDate >= CURRENT_DATE - INTERVAL '365 days'
ORDER BY TransactionDate;

-- Commented comparison recipe, using the identical predicate in each plan:
-- BEGIN;
-- DROP INDEX public.idx_txn_account_date;
-- EXPLAIN ANALYZE SELECT * FROM public.Transaction_History
-- WHERE AccountNo = 100001 ORDER BY TransactionDate; -- without named index
-- ROLLBACK;
-- EXPLAIN ANALYZE SELECT * FROM public.Transaction_History
-- WHERE AccountNo = 100001 ORDER BY TransactionDate; -- with named index available

-- =====================================================================
-- 3. Transactions: literal SQL SAVEPOINT and a PL/pgSQL subtransaction
-- =====================================================================
-- PostgreSQL does NOT support SAVEPOINT/ROLLBACK TO SAVEPOINT inside DO or
-- PL/pgSQL. Show the literal commands at SQL level, then the supported DO
-- equivalent (BEGIN/EXCEPTION creates an implicit subtransaction) separately.
BEGIN;
SAVEPOINT account_demo;
UPDATE public.Account SET Balance = Balance + 1 WHERE AccountNo = 100001;
ROLLBACK TO SAVEPOINT account_demo; -- also undoes the balance audit trigger
RELEASE SAVEPOINT account_demo;
COMMIT;

DO $$
DECLARE v_before NUMERIC;
BEGIN
    SELECT Balance INTO STRICT v_before FROM public.Account WHERE AccountNo = 100001;
    BEGIN -- implicit SAVEPOINT
        UPDATE public.Account SET Balance = Balance + 1 WHERE AccountNo = 100001;
        RAISE EXCEPTION 'Intentional subtransaction rollback' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'Z0001' THEN
        -- Equivalent to ROLLBACK TO SAVEPOINT for this inner block.
        RAISE NOTICE 'PASS: inner update and trigger audit rolled back; outer DO continues';
    END;
    IF (SELECT Balance FROM public.Account WHERE AccountNo = 100001) IS DISTINCT FROM v_before THEN
        RAISE EXCEPTION 'Subtransaction failed to restore balance';
    END IF;
    -- Outside the inner exception block, top-level DO may COMMIT.
    COMMIT;
END;
$$;

-- =====================================================================
-- 4. Row-level locking: read/modify/write with SELECT FOR UPDATE
-- =====================================================================
-- Single-session simulation: lock before reading the balance, then update
-- using that locked value. Another transaction attempting the same row must
-- wait until this subtransaction releases its lock. Undo the simulation so
-- neither balances nor audit rows remain changed.
DO $$
DECLARE v_locked_balance NUMERIC;
BEGIN
    BEGIN
        SELECT Balance INTO STRICT v_locked_balance FROM public.Account
        WHERE AccountNo = 100001 FOR UPDATE;
        UPDATE public.Account SET Balance = v_locked_balance + 1 WHERE AccountNo = 100001;
        IF (SELECT Balance FROM public.Account WHERE AccountNo = 100001) <> v_locked_balance + 1 THEN
            RAISE EXCEPTION 'Locked update failed';
        END IF;
        RAISE EXCEPTION 'Undo concurrency demo' USING ERRCODE = 'Z0001';
    EXCEPTION WHEN SQLSTATE 'Z0001' THEN
        RAISE NOTICE 'PASS: row locked before balance calculation; simulation rolled back';
    END;
END;
$$;

-- For an observable TWO-SESSION lock proof, execute these in separate psql
-- sessions. No sleep is built into the normal script.
-- Session A:
-- BEGIN;
-- SELECT AccountNo, Balance FROM public.Account WHERE AccountNo = 100001 FOR UPDATE;
-- [leave transaction open while Session B runs]
-- ROLLBACK;
-- Session B (run while A holds its lock):
-- DO $$ BEGIN
--     PERFORM AccountNo FROM public.Account WHERE AccountNo = 100001 FOR UPDATE NOWAIT;
--     RAISE EXCEPTION 'Expected a conflicting row lock';
-- EXCEPTION WHEN lock_not_available THEN
--     RAISE NOTICE 'PASS: second writer blocked by first writer (55P03)';
-- END $$;
-- Without NOWAIT, B waits, then reads the committed value when A finishes.

SELECT 'Security, indexing, savepoint and row-lock demonstrations completed' AS result;
