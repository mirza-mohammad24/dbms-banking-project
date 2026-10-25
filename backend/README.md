# CoreBank workflow API

Run from the repository root:

```powershell
uv sync
uv run uvicorn backend.main:app --reload
```

API: `http://localhost:8000`; complete schemas: `http://localhost:8000/docs`.
The existing `banking_db` must have SQL scripts 01–06 installed. No schema reset
or migration is performed by the API. `DATABASE_URL` can override the supplied
local PostgreSQL connection. Monetary responses are exact decimal strings.

## Workflow coverage

- Discovery: customer ownership previews, real employee profiles, normalized
  branch/postal/bank lookups, and customer-ID or account-number demo sign-in.
- Customer: complete overview, accounts, filterable transactions, deposit and
  withdrawal, internal and beneficiary transfer, payee CRUD, loans/repayments,
  EMI payment, fixed deposit funding, and full KYC profile.
- Official: bank-wide KPIs and twelve table counts; branch and Vellore views;
  searchable customer master and full-360 inspection; customer/KYC onboarding;
  account opening/status changes; loan sanction/disbursement and UDF EMI preview;
  FD book; branch/staff/postal/bank directory creation; two cursor batches;
  latest 100 filtered audit records and the live programmability catalog.
- Compatibility: original passbook, net-worth, summary, and transaction EMI
  routes remain available for the earlier Streamlit/React demonstrations.

## Transaction boundaries and schema decisions

`database.get_connection()` uses isolated autocommit connections for the existing
`sp_transfer_funds` procedure, which explicitly COMMITs. Multi-statement workflows
use `database.transaction()`: commit happens once after the complete workflow;
all Python, HTTP validation, and PostgreSQL failures roll it back.

Account ownership, Active status, sufficient balance, and row locks are checked
before deposits/withdrawals, FD funding, or loan disbursement. Balance updates
fire the installed audit trigger. EMI calls the installed procedure; its
Loan_Repayment insert fires the repayment trigger. Loan EMI and FD maturity
generated columns are never written by Python. The existing lab convention
deducts the whole EMI from outstanding principal; there is no amortization
allocation/due-date table, so the UI shows actual payment history.

Direct internal payments call `sp_transfer_funds`. Saved internal beneficiaries
use the security sprint's `_bank_transfer_atomic` helper in a larger transaction
to keep the daily-limit check and money movement atomic. Beneficiaries match
internal destinations by both account number and branch IFSC. Unmatched local
IFSC/account pairs fail; external payments record an outward debit and history,
without contacting real interbank payment rails.

The unchanged schema has no beneficiary key in transaction history. Outgoing
beneficiary remarks therefore start with `BENEFICIARY:<id>; `; cumulative daily
limits are summed across the owner's source accounts while the beneficiary row
is locked. Deleting and recreating a payee creates a new beneficiary identity;
these are per-beneficiary caps, not recipient-wide fraud controls. API ID
allocation uses transaction advisory locks and PK constraints; external writers
that bypass the API remain responsible for coordinating their manual INT keys.

Directory insertion preserves shared facts: an existing IFSC/pincode with a
conflicting name/location is rejected rather than changing every referencing
record. FD branch reporting follows the existing view's primary-account rule,
because Fixed_Deposit has no BranchID. No extra financial tables were added.

Batch endpoints execute the installed cursor procedures inside one transaction
and count that transaction's own postings. Repeated interest credits in the same
calendar month and already settled FD payouts are skipped by database logic.
The PostgreSQL date returned by `/api/lookups` anchors FD dates consistently.

## Verification

```powershell
uv run python -m unittest backend.tests.test_workflows -v
```

The suite creates a disposable PostgreSQL database from the exact project SQL,
exercises every new endpoint, checks trigger effects and rollback after an FD
funding debit, then drops the database. It also checks concurrent customer ID
allocation and simultaneous beneficiary payments from separate source accounts.
The suite never changes `banking_db` rows or shared role grants.

This is a local university demonstration with explicitly simulated identity
selection and wildcard development CORS, not authenticated banking access.
Customer/employee selectors do not issue credentials or enforce server-side
role authorization. Original PostgreSQL errors are deliberately exposed for the
Review 3 constraint/rollback demonstration.
