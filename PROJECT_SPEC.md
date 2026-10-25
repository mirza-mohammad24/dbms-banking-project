# Core Banking & Transaction Management System

Persistent reference for the BCSE302P Database Systems lab, Reviews 2 and 3.
The schema is implemented in Sprint 1; scripts 03–07 add query catalogues,
programmability, administration, and tests. The current React/FastAPI workflow
application is documented in `frontend/README.md` and `backend/README.md`.
The checklist below records the original academic targets; it is not a claim
that every original minimum has independently been reevaluated in this document.

## Environment and Sprint 1 operation

- Python >=3.12, managed by `uv`; dependencies: Streamlit and psycopg2-binary.
- PostgreSQL Docker container: `banking-postgres`.
- Local development connection: localhost:5432, database `banking_db`, user
  `postgres`, password `admin` (provided local lab credentials).
- `sql/01_ddl.sql` drops all twelve tables with CASCADE and recreates them in a
  transaction. This destroys existing data and dependent objects.
- `sql/02_dml.sql` seeds fictional data and demonstrates INSERT/UPDATE/DELETE
  in a transaction, then reports all twelve table counts. Run once after DDL;
  rerunning DML alone will fail on duplicate primary keys.
- Execute in PowerShell from the project root, in this order:

```powershell
Get-Content -Raw sql/01_ddl.sql | docker exec -i banking-postgres psql -X -v ON_ERROR_STOP=1 -U postgres -d banking_db
Get-Content -Raw sql/02_dml.sql | docker exec -i banking-postgres psql -X -v ON_ERROR_STOP=1 -U postgres -d banking_db
```

## Twelve-table schema

Identifiers are unquoted SQL names, so PostgreSQL stores them in lowercase.
Every declared foreign key is NOT NULL. Monetary amounts use fixed precision
DECIMAL; primary keys are integers except directory keys. SERIAL supplies IDs
for transaction history, repayments, beneficiaries, and audit records.

| Table | Primary key | Attributes and relationships |
| --- | --- | --- |
| Postal_Directory | Pincode | City, State; postal lookup |
| Bank_Directory | IFSC_Code | BankName; external/internal beneficiary bank lookup |
| Branch | BranchID | BranchName, Address, Pincode FK, unique IFSC_Code and ContactPhone |
| Customer | CustomerID | FirstName, LastName, Gender, Age >=18, Address; unique Phone, Email, PAN_Number; KYC_Status |
| Account | AccountNo | CustomerID FK (delete cascade), BranchID FK; AccountType, nonnegative Balance, InterestRate, OpeningDate, Status |
| Transaction_History | TransactionID | AccountNo FK; positive Amount, TransactionType, PaymentMode, nullable Remarks, TransactionDate |
| Loan | LoanID | CustomerID and BranchID FKs; LoanType, positive PrincipalAmount/InterestRate/TenureMonths, generated EMI_Amount, nonnegative OutstandingBalance, IssueDate, Status |
| Loan_Repayment | PaymentID | LoanID FK (delete cascade); positive AmountPaid, PaymentMode, PaymentStatus, PaymentDate |
| Beneficiary | BeneficiaryID | CustomerID FK (delete cascade), BeneficiaryName, external-capable BIGINT LinkedAccountNo, IFSC_Code FK, MaxTransferLimit |
| Fixed_Deposit | FD_ID | CustomerID FK; Amount >=1000, InterestRate, StartDate, EndDate > StartDate, generated MaturityAmount, Status |
| Employee | EmployeeID | BranchID FK; FirstName, LastName, unique Email, Role, positive Salary, HireDate |
| Audit_Log | LogID | TableName, RecordID, ActionType, Description, LogDate |

The DDL is the authoritative detailed column/type/default/CHECK specification.
Account types: Savings, Current, Salary. Loan types: Home, Personal, Auto,
Education, Business. KYC states: Pending, Approved, Rejected. Account states:
Active, Dormant, Frozen, Closed. Loan states: Pending, Approved, Active, Closed,
Defaulted. FD states: Active, Matured, Closed.

EMI uses the monthly reducing-balance formula with r=InterestRate/1200 and
n=TenureMonths: round(P*r*(1+r)^n/((1+r)^n-1), 2).
FD maturity uses simple actual-day interest:
round(Amount + Amount*InterestRate*(EndDate-StartDate)/36500, 2).
Both values are GENERATED ALWAYS STORED and omitted from seed INSERT columns.

### Normalization and integrity qualifications

The required target is strict 3NF with no partial/transitive dependencies.
Single-column primary keys avoid partial-key dependencies; postal and bank
lookups avoid repeating directory facts in referencing tables. However, the
explicitly requested stored generated EMI and maturity columns are derived
from non-key attributes and require qualification in a formal 3NF discussion.
The exact requested schema is preserved instead of silently removing them.
The postal model assumes one canonical city/state per pincode.

Branch.IFSC_Code is UNIQUE NOT NULL but has no FK in the supplied specification;
seed codes are nevertheless present in Bank_Directory. LinkedAccountNo supports
external accounts and is not an Account FK. Audit_Log.RecordID is a polymorphic
record identifier, not a foreign key. Nullable defaulted status/timestamp
columns retain the requested nullability; a DEFAULT alone does not forbid NULL.
Cascade actions do not bypass other references: deleting a customer with
transactions or loans can still be blocked by dependent rows.

## Dual-portal use case (future sprints)

**Staff/admin:** manage branches and postal/bank directories; onboard customers
and approve/reject KYC; open savings/current/salary accounts; issue loans with
database-calculated EMI; open FDs with database-calculated maturity; execute
monthly savings interest and FD maturity cursor batches; inspect automatic
trigger audit trails, branch financial summaries, and query plans.

**Customer:** view balances and view-backed passbooks; register internal/external
beneficiaries validated against IFSC directory entries and daily transfer
limits; transfer/deposit/withdraw through ACID stored procedures with row locks,
rollback on insufficient funds, and dormant/frozen status checks; pay EMIs via
a procedure and trigger that reduce outstanding principal and close fully paid
loans; inspect dynamically computed net worth via a UDF.

Future design must define principal versus interest allocation for EMI payments,
transfer direction/pairing, current-customer identity for row restriction,
daily-limit aggregation, and payout destinations/idempotency for batch jobs.
The current fixtures are opening snapshots plus illustrative historical events,
not a reconstructed double-entry ledger. Repayments do not adjust seeded loan
balances; audit SEED records are explicitly inserted, not trigger output.

## Review 2 and Review 3 checklist (future SQL implementation)

| Category | Minimum | Required coverage |
| --- | --- | --- |
| A: Basic | 6 | SELECT, WHERE, ORDER BY, DISTINCT, BETWEEN, IN, LIKE, IS NULL |
| B: Aggregate | 5 | COUNT, SUM, AVG, MIN, MAX, GROUP BY, HAVING; explicitly contrast WHERE vs HAVING in one query |
| C: Joins | 6 | INNER, LEFT, RIGHT, FULL OUTER, meaningful SELF and CROSS joins |
| D: Subqueries | 6 | Scalar, single-row, multi-row IN/ANY/ALL, correlated, EXISTS, NOT EXISTS, NOT IN; demonstrate/explain NULL pitfall and fix |
| E: Set operations | 4 | UNION, UNION ALL, INTERSECT, EXCEPT |
| F: Advanced functions | 6 | CASE, COALESCE, NULLIF, date/time, string, numeric functions |
| G: Window/analytic | 2-4 | RANK, ROW_NUMBER, running SUM OVER, LAG/LEAD |

- Ten complex business queries CQ-01 through CQ-10, each joining at least three
  tables or using nested/analytic constructs.
- Three views: a >=3-table join, an aggregate, and a security/row-restricting
  updatable view.
- At least two stored procedures, two UDFs, two triggers, two cursors.
- RBAC: >=3 roles, GRANT matrix, REVOKE demonstration, least-privilege SET ROLE
  error test, and secure exposure through views/procedures.
- Transactions: BEGIN, SAVEPOINT, ROLLBACK, COMMIT.
- Indexing: EXPLAIN ANALYZE before/after comparison.
- Concurrency: SELECT ... FOR UPDATE and demonstrable locking behavior.
- At least fifteen test cases.
- DML checklist item #2: INSERT, UPDATE, DELETE (implemented in Sprint 1).

## Seed coverage for later queries

| Fixture | Purpose |
| --- | --- |
| Eight postal entries including Vellore, Chennai, Bengaluru, Mumbai, Delhi | Directory joins and geographic grouping |
| Ten IFSC entries, eight branches | Internal/external beneficiaries and directory joins |
| Customers 1 and 2 each hold Savings and Current | Meaningful SELF JOIN and INTERSECT |
| Customers 1-8 have accounts, transaction history, loans, and FDs | Multi-table business queries and net worth |
| Customers 9 and 10 have accounts/history but no loans or FDs | LEFT/RIGHT joins, NOT EXISTS, EXCEPT |
| Branch 8 has an account and employees but no loans | Meaningful outer joins |
| Four transactions have explicitly NULL Remarks | IS NULL, COALESCE, nullable NOT IN subquery |
| FD 3001 is Active with EndDate=CURRENT_DATE at seed time | Immediate maturity cursor target |
| Active, Dormant, Frozen, Closed account states | Later status checks and transaction failure cases |

For the future NOT IN demonstration, use the nullable Remarks expression (or
another deliberately nullable projection): all foreign keys are non-null.
Explain UNKNOWN propagation and fix it with NULL filtering or NOT EXISTS.
