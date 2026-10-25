-- Standard SQL catalogue: exactly 35 top-level, read-only queries.
-- A=6, B=5, C=6, D=6, E=4, F=4, G=4.
-- Run after Sprint 1, preferably with psql -X -v ON_ERROR_STOP=1.
-- Composite demonstrations (including D-06) are single SQL statements.

-- =====================================================================
-- Category A: Basic (6 queries)
-- =====================================================================

-- A-01: SELECT the customer directory in a deterministic order.
SELECT CustomerID, FirstName, LastName, KYC_Status
FROM Customer
ORDER BY CustomerID;

-- A-02: WHERE filters individual accounts; ORDER BY prioritizes balances.
SELECT AccountNo, CustomerID, AccountType, Balance
FROM Account
WHERE Status = 'Active'
ORDER BY Balance DESC, AccountNo;

-- A-03: DISTINCT removes repeated account types.
SELECT DISTINCT AccountType
FROM Account
ORDER BY AccountType;

-- A-04: BETWEEN includes both endpoints of this balance range.
SELECT AccountNo, Balance
FROM Account
WHERE Balance BETWEEN 50000 AND 250000
ORDER BY Balance, AccountNo;

-- A-05: IN selects allowed KYC states; LIKE matches a name prefix.
SELECT CustomerID, FirstName, LastName, KYC_Status
FROM Customer
WHERE KYC_Status IN ('Approved', 'Pending') AND FirstName LIKE 'A%'
ORDER BY FirstName, CustomerID;

-- A-06: NULL must be tested with IS NULL, not equality.
SELECT TransactionID, AccountNo, Amount, Remarks
FROM Transaction_History
WHERE Remarks IS NULL
ORDER BY TransactionID;

-- =====================================================================
-- Category B: Aggregate (5 queries)
-- =====================================================================

-- B-01: COUNT(*) counts customers, including nullable KYC states if present.
SELECT KYC_Status, COUNT(*) AS customer_count
FROM Customer
GROUP BY KYC_Status
ORDER BY KYC_Status NULLS LAST;

-- B-02: SUM reports balances by product, including all account statuses.
SELECT AccountType, SUM(Balance) AS total_balance
FROM Account
GROUP BY AccountType
ORDER BY AccountType;

-- B-03: AVG, MIN, and MAX describe the range of staff salaries per role.
SELECT Role, ROUND(AVG(Salary), 2) AS average_salary,
       MIN(Salary) AS minimum_salary, MAX(Salary) AS maximum_salary
FROM Employee
GROUP BY Role
ORDER BY Role;

-- B-04: WHERE vs HAVING, explicitly contrasted:
-- WHERE removes non-Active accounts BEFORE grouping, so their balances never
-- enter SUM. HAVING removes branch GROUPS AFTER aggregation if the remaining
-- active balances total less than 100000. These filters are not interchangeable.
SELECT BranchID, COUNT(*) AS active_account_count,
       SUM(Balance) AS active_balance
FROM Account
WHERE Status = 'Active'
GROUP BY BranchID
HAVING SUM(Balance) >= 100000
ORDER BY active_balance DESC, BranchID;

-- B-05: Count and sum observed transaction events per payment channel.
-- Gross event volume is not net account cash flow.
SELECT PaymentMode, COUNT(*) AS transaction_count,
       SUM(Amount) AS gross_amount, ROUND(AVG(Amount), 2) AS average_amount
FROM Transaction_History
GROUP BY PaymentMode
ORDER BY gross_amount DESC, PaymentMode;

-- =====================================================================
-- Category C: Joins (6 queries)
-- =====================================================================

-- C-01: INNER JOIN returns accounts with their owners and servicing branches.
SELECT a.AccountNo, c.FirstName, c.LastName, b.BranchName, a.Balance
FROM Account a
INNER JOIN Customer c ON c.CustomerID = a.CustomerID
INNER JOIN Branch b ON b.BranchID = a.BranchID
ORDER BY a.AccountNo;

-- C-02: LEFT JOIN preserves customers who have never borrowed.
SELECT c.CustomerID, c.FirstName, l.LoanID, l.LoanType, l.Status
FROM Customer c
LEFT JOIN Loan l ON l.CustomerID = c.CustomerID
ORDER BY c.CustomerID, l.LoanID;

-- C-03: RIGHT JOIN preserves every branch, including branches without loans.
SELECT b.BranchID, b.BranchName, l.LoanID, l.OutstandingBalance
FROM Loan l
RIGHT JOIN Branch b ON b.BranchID = l.BranchID
ORDER BY b.BranchID, l.LoanID;

-- C-04: FULL OUTER JOIN reconciles directory entries and local branches.
-- External bank directory entries remain visible without a local branch.
-- Branch.IFSC_Code has no FK, so an unlisted branch code could also appear.
SELECT d.IFSC_Code AS directory_ifsc, d.BankName,
       b.IFSC_Code AS branch_ifsc, b.BranchName
FROM Bank_Directory d
FULL OUTER JOIN Branch b ON b.IFSC_Code = d.IFSC_Code
ORDER BY COALESCE(d.IFSC_Code, b.IFSC_Code);

-- C-05: SELF JOIN finds distinct account pairs belonging to one customer.
-- The strict inequality excludes self-pairs and reversed duplicate pairs.
SELECT a.CustomerID, a.AccountNo AS first_account, a.AccountType AS first_type,
       other.AccountNo AS second_account, other.AccountType AS second_type
FROM Account a
JOIN Account other ON other.CustomerID = a.CustomerID
                 AND a.AccountNo < other.AccountNo
ORDER BY a.CustomerID, a.AccountNo, other.AccountNo;

-- C-06: CROSS JOIN builds a branch/product coverage grid, including zeroes.
-- The product catalogue is the distinct types actually present in Account.
SELECT b.BranchID, b.BranchName, product.AccountType,
       COUNT(a.AccountNo) AS account_count
FROM Branch b
CROSS JOIN (SELECT DISTINCT AccountType FROM Account) product
LEFT JOIN Account a ON a.BranchID = b.BranchID
                   AND a.AccountType = product.AccountType
GROUP BY b.BranchID, b.BranchName, product.AccountType
ORDER BY b.BranchID, product.AccountType;

-- =====================================================================
-- Category D: Subqueries (6 queries)
-- =====================================================================

-- D-01: An uncorrelated scalar aggregate subquery supplies one benchmark.
SELECT AccountNo, Balance,
       (SELECT ROUND(AVG(Balance), 2) FROM Account) AS bank_average_balance
FROM Account
ORDER BY Balance DESC, AccountNo;

-- D-02: Single-row subquery identifies the highest-balance Savings account.
-- AccountNo breaks ties, so LIMIT 1 always selects a deterministic row.
SELECT CustomerID, FirstName, LastName
FROM Customer
WHERE CustomerID = (
    SELECT CustomerID FROM Account
    WHERE AccountType = 'Savings'
    ORDER BY Balance DESC, AccountNo
    LIMIT 1
)
ORDER BY CustomerID;

-- D-03: Multi-row IN, ANY, and ALL in one loan screening query.
-- Borrower must have an Active account, principal must exceed at least one
-- Personal loan, and be at least as large as every Auto loan principal.
-- With empty subqueries ANY is false and ALL is true (vacuous truth).
SELECT LoanID, CustomerID, LoanType, PrincipalAmount
FROM Loan
WHERE CustomerID IN (SELECT CustomerID FROM Account WHERE Status = 'Active')
  AND PrincipalAmount > ANY (SELECT PrincipalAmount FROM Loan WHERE LoanType = 'Personal')
  AND PrincipalAmount >= ALL (SELECT PrincipalAmount FROM Loan WHERE LoanType = 'Auto')
ORDER BY PrincipalAmount DESC, LoanID;

-- D-04: Correlated EXISTS tests each customer without multiplying rows for
-- multiple accounts. The nested correlated AVG uses that account's branch.
SELECT c.CustomerID, c.FirstName, c.LastName
FROM Customer c
WHERE EXISTS (
    SELECT 1 FROM Account a
    WHERE a.CustomerID = c.CustomerID
      AND a.Balance > (SELECT AVG(peer.Balance) FROM Account peer
                       WHERE peer.BranchID = a.BranchID)
)
ORDER BY c.CustomerID;

-- D-05: Correlated NOT EXISTS finds customers without either product.
SELECT c.CustomerID, c.FirstName, c.LastName
FROM Customer c
WHERE NOT EXISTS (SELECT 1 FROM Loan l WHERE l.CustomerID = c.CustomerID)
  AND NOT EXISTS (SELECT 1 FROM Fixed_Deposit f WHERE f.CustomerID = c.CustomerID)
ORDER BY c.CustomerID;

-- D-06: NOT IN NULL pitfall AND fix, executable as ONE statement.
-- Question: which known narratives have never appeared on a Withdrawal?
-- One NULL in the inner set makes unmatched NOT IN comparisons UNKNOWN;
-- WHERE discards UNKNOWN, so the unsafe version returns zero matches here.
-- The fix removes NULL from the inner set. Candidates are also non-null,
-- making the intended treatment of missing narratives explicit.
-- Two result rows expose the unsafe and corrected counts side by side.
WITH narratives AS (
    SELECT DISTINCT Remarks FROM Transaction_History WHERE Remarks IS NOT NULL
)
SELECT '1. Unsafe NOT IN (NULL poisoned)' AS demonstration,
       COUNT(*) AS matching_narratives
FROM narratives
WHERE Remarks NOT IN (
    SELECT Remarks FROM Transaction_History WHERE TransactionType = 'Withdrawal'
)
UNION ALL
SELECT '2. Corrected NOT IN (NULL filtered)', COUNT(*)
FROM narratives
WHERE Remarks NOT IN (
    SELECT Remarks FROM Transaction_History
    WHERE TransactionType = 'Withdrawal' AND Remarks IS NOT NULL
)
ORDER BY demonstration;

-- =====================================================================
-- Category E: Set Operations (4 queries)
-- =====================================================================

-- E-01: UNION removes duplicate customer IDs across the two product sets.
SELECT CustomerID FROM Account WHERE AccountType = 'Savings'
UNION
SELECT CustomerID FROM Loan
ORDER BY CustomerID;

-- E-02: UNION ALL retains each individual product holding, even for an owner
-- with many holdings. Product labels distinguish overlapping integer IDs.
SELECT CustomerID, 'Account' AS product, AccountNo AS product_id FROM Account
UNION ALL
SELECT CustomerID, 'Fixed Deposit', FD_ID FROM Fixed_Deposit
ORDER BY CustomerID, product, product_id;

-- E-03: INTERSECT finds customers holding both Savings and Current accounts.
SELECT CustomerID FROM Account WHERE AccountType = 'Savings'
INTERSECT
SELECT CustomerID FROM Account WHERE AccountType = 'Current'
ORDER BY CustomerID;

-- E-04: EXCEPT finds account holders who have no loan of any status.
SELECT CustomerID FROM Account
EXCEPT
SELECT CustomerID FROM Loan
ORDER BY CustomerID;

-- =====================================================================
-- Category F: Advanced Functions (4 queries)
-- Four queries keep the overall catalogue at exactly 35 statements.
-- =====================================================================

-- F-01: CASE assigns balance bands; ROUND computes a monthly interest estimate.
-- The estimate is illustrative and does not post interest to the database.
SELECT AccountNo, Balance,
       CASE WHEN Balance >= 250000 THEN 'High'
            WHEN Balance >= 50000 THEN 'Medium' ELSE 'Low' END AS balance_band,
       ROUND(Balance * InterestRate / 1200.0, 2) AS estimated_monthly_interest
FROM Account
ORDER BY AccountNo;

-- F-02: COALESCE substitutes a display value without changing stored NULLs.
SELECT TransactionID, AccountNo, COALESCE(Remarks, 'No remarks provided') AS narrative
FROM Transaction_History
ORDER BY TransactionID;

-- F-03: NULLIF turns a zero denominator into NULL, preventing division by zero.
-- A zero-balance account has no defined withdrawal/balance percentage.
SELECT a.AccountNo, a.Balance,
       COALESCE(SUM(t.Amount) FILTER (WHERE t.TransactionType = 'Withdrawal'), 0)
           AS recorded_withdrawals,
       ROUND(100.0 * COALESCE(SUM(t.Amount)
           FILTER (WHERE t.TransactionType = 'Withdrawal'), 0)
           / NULLIF(a.Balance, 0), 2) AS withdrawals_to_current_balance_pct
FROM Account a
LEFT JOIN Transaction_History t ON t.AccountNo = a.AccountNo
GROUP BY a.AccountNo, a.Balance
ORDER BY a.AccountNo;

-- F-04: String formatting plus AGE/EXTRACT for customer account tenure.
-- CURRENT_DATE is cast to timestamp so AGE uses midnight on both dates.
SELECT a.AccountNo, UPPER(CONCAT(c.FirstName, ' ', c.LastName)) AS display_name,
       a.OpeningDate,
       AGE(CURRENT_DATE::timestamp, a.OpeningDate::timestamp) AS account_tenure,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE::timestamp, a.OpeningDate::timestamp))
           AS completed_years
FROM Account a
JOIN Customer c ON c.CustomerID = a.CustomerID
ORDER BY a.AccountNo;

-- =====================================================================
-- Category G: Window / Analytic (4 queries)
-- =====================================================================

-- G-01: RANK leaves gaps after ties; DENSE_RANK does not.
-- Rank by balance only, preserving ties; AccountNo orders the displayed rows.
SELECT AccountNo, BranchID, Balance,
       RANK() OVER (PARTITION BY BranchID ORDER BY Balance DESC) AS balance_rank,
       DENSE_RANK() OVER (PARTITION BY BranchID ORDER BY Balance DESC) AS dense_balance_rank
FROM Account
ORDER BY BranchID, balance_rank, AccountNo;

-- G-02: ROW_NUMBER assigns an unambiguous recency sequence per account.
SELECT TransactionID, AccountNo, TransactionDate, Amount,
       ROW_NUMBER() OVER (PARTITION BY AccountNo
           ORDER BY TransactionDate DESC NULLS LAST, TransactionID DESC) AS recency_number
FROM Transaction_History
ORDER BY AccountNo, recency_number;

-- G-03: Explicit ROWS frame and ID tiebreaker make event-by-event totals stable.
-- All amounts are positive: this is cumulative GROSS volume, not a balance.
SELECT TransactionID, AccountNo, TransactionDate, Amount,
       SUM(Amount) OVER (PARTITION BY AccountNo
           ORDER BY TransactionDate NULLS LAST, TransactionID
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_gross_volume
FROM Transaction_History
ORDER BY AccountNo, TransactionDate NULLS LAST, TransactionID;

-- G-04: LAG and LEAD inspect adjacent account events; boundary rows yield NULL.
SELECT TransactionID, AccountNo, TransactionDate, Amount,
       LAG(Amount) OVER account_events AS previous_amount,
       LEAD(TransactionDate) OVER account_events AS next_transaction_date
FROM Transaction_History
WINDOW account_events AS (PARTITION BY AccountNo
                         ORDER BY TransactionDate NULLS LAST, TransactionID)
ORDER BY AccountNo, TransactionDate NULLS LAST, TransactionID;
