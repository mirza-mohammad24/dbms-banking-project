-- Exactly ten read-only business queries against the Sprint 1 schema.
-- Independent one-to-many products are aggregated BEFORE joining to avoid
-- inflated balances, volumes, and counts caused by join fan-out.
-- Amounts are INR. History is illustrative and does not reconstruct balances.

-- CQ-01
-- Business Question: Which borrowers have defaulted loans, and how much
-- outstanding principal and failed-payment activity need branch follow-up?
-- Explanation: Join Loan to Customer and issuing Branch; LEFT JOIN repayments
-- and group per loan. OutstandingBalance is selected once, never summed across
-- repayments. 'Defaulted' is the schema's NPA proxy: delinquency days cannot
-- be inferred because the schema has no repayment due-date schedule.
SELECT l.LoanID, c.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS borrower,
       b.BranchName, l.OutstandingBalance AS defaulted_outstanding,
       COUNT(r.PaymentID) FILTER (WHERE r.PaymentStatus = 'Failed') AS failed_attempts,
       MAX(r.PaymentDate) FILTER (WHERE r.PaymentStatus = 'Success') AS last_successful_payment
FROM Loan l
JOIN Customer c ON c.CustomerID = l.CustomerID
JOIN Branch b ON b.BranchID = l.BranchID
LEFT JOIN Loan_Repayment r ON r.LoanID = l.LoanID
WHERE l.Status = 'Defaulted'
GROUP BY l.LoanID, c.CustomerID, c.FirstName, c.LastName, b.BranchID, b.BranchName
ORDER BY l.OutstandingBalance DESC, l.LoanID;

-- CQ-02
-- Business Question: Which branches have the highest observed transaction
-- activity during the last 365 days, and where are those branches located?
-- Explanation: Branch -> Postal_Directory supplies location; LEFT JOIN Account
-- -> Transaction_History preserves zero-activity branches. The time restriction
-- stays in ON so it cannot remove those branches. Rank aggregated event counts
-- and show the top three ranks (including ties). Volume counts each event once.
WITH activity AS (
    SELECT b.BranchID, b.BranchName, p.City,
           COUNT(t.TransactionID) AS transaction_count,
           COALESCE(SUM(t.Amount), 0) AS gross_volume
    FROM Branch b
    JOIN Postal_Directory p ON p.Pincode = b.Pincode
    LEFT JOIN Account a ON a.BranchID = b.BranchID
    LEFT JOIN Transaction_History t ON t.AccountNo = a.AccountNo
        AND t.TransactionDate >= CURRENT_TIMESTAMP - INTERVAL '365 days'
        AND t.TransactionDate <= CURRENT_TIMESTAMP
    GROUP BY b.BranchID, b.BranchName, p.City
), ranked AS (
    SELECT activity.*, DENSE_RANK() OVER (ORDER BY transaction_count DESC) AS activity_rank
    FROM activity
)
SELECT * FROM ranked WHERE activity_rank <= 3
ORDER BY activity_rank, gross_volume DESC, BranchID;

-- CQ-03
-- Business Question: Which approved customers with Active fixed deposits and
-- Active accounts have never borrowed, making them potential loan prospects?
-- Explanation: Join Customer to separately aggregated Fixed_Deposit and Account
-- holdings, then use correlated NOT EXISTS on Loan. This counts each FD once
-- even if the customer owns multiple accounts. Sprint 1 has no such customers,
-- so an empty result is expected until a qualifying customer is onboarded.
WITH deposits AS (
    SELECT CustomerID, COUNT(*) AS active_fd_count, SUM(Amount) AS fd_principal
    FROM Fixed_Deposit WHERE Status = 'Active' GROUP BY CustomerID
), accounts AS (
    SELECT CustomerID, SUM(Balance) AS active_account_balance
    FROM Account WHERE Status = 'Active' GROUP BY CustomerID
)
SELECT c.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
       c.Phone, d.active_fd_count, d.fd_principal, a.active_account_balance
FROM Customer c
JOIN deposits d ON d.CustomerID = c.CustomerID
JOIN accounts a ON a.CustomerID = c.CustomerID
WHERE c.KYC_Status = 'Approved'
  AND NOT EXISTS (SELECT 1 FROM Loan l WHERE l.CustomerID = c.CustomerID)
ORDER BY d.fd_principal DESC, c.CustomerID;

-- CQ-04
-- Business Question: Which calendar days have the highest bank-wide gross
-- transaction volume, and how many branches contributed on each day?
-- Explanation: Join Transaction_History -> Account -> Branch, aggregate all
-- events per stored timestamp date, then DENSE_RANK daily SUM(Amount). Return
-- the top three volume ranks, preserving ties. Dates follow the stored local
-- timestamp convention; NULL timestamps cannot be assigned to a calendar day.
WITH daily AS (
    SELECT t.TransactionDate::date AS transaction_day,
           COUNT(*) AS event_count, COUNT(DISTINCT b.BranchID) AS contributing_branches,
           SUM(t.Amount) AS gross_volume
    FROM Transaction_History t
    JOIN Account a ON a.AccountNo = t.AccountNo
    JOIN Branch b ON b.BranchID = a.BranchID
    WHERE t.TransactionDate IS NOT NULL
    GROUP BY t.TransactionDate::date
), ranked AS (
    SELECT daily.*, DENSE_RANK() OVER (ORDER BY gross_volume DESC) AS volume_rank
    FROM daily
)
SELECT * FROM ranked WHERE volume_rank <= 3
ORDER BY volume_rank, transaction_day;

-- CQ-05
-- Business Question: What is each customer's indicative net position across
-- account balances, Active FDs, and outstanding issued loans?
-- Explanation: Aggregate Account, Fixed_Deposit, and Loan per Customer first,
-- then LEFT JOIN all three totals to Customer. This avoids product fan-out and
-- retains customers without a product. Use FD principal, not future maturity
-- interest; exclude Closed accounts and Pending/Closed loans. This is a simple
-- product exposure measure, not a valuation including accrued loan interest.
WITH balances AS (
    SELECT CustomerID, SUM(Balance) AS account_balance
    FROM Account WHERE Status IN ('Active', 'Dormant', 'Frozen') GROUP BY CustomerID
), deposits AS (
    SELECT CustomerID, SUM(Amount) AS fd_principal
    FROM Fixed_Deposit WHERE Status = 'Active' GROUP BY CustomerID
), debt AS (
    SELECT CustomerID, SUM(OutstandingBalance) AS loan_outstanding
    FROM Loan WHERE Status IN ('Approved', 'Active', 'Defaulted') GROUP BY CustomerID
)
SELECT c.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
       COALESCE(a.account_balance, 0) AS account_balance,
       COALESCE(f.fd_principal, 0) AS active_fd_principal,
       COALESCE(l.loan_outstanding, 0) AS loan_outstanding,
       COALESCE(a.account_balance, 0) + COALESCE(f.fd_principal, 0)
           - COALESCE(l.loan_outstanding, 0) AS indicative_net_position
FROM Customer c
LEFT JOIN balances a ON a.CustomerID = c.CustomerID
LEFT JOIN deposits f ON f.CustomerID = c.CustomerID
LEFT JOIN debt l ON l.CustomerID = c.CustomerID
ORDER BY indicative_net_position DESC, c.CustomerID;

-- CQ-06
-- Business Question: Which Active FDs are due for maturity, and which account
-- branch could contact the owner about reinvestment?
-- Explanation: Join Fixed_Deposit and Customer to Account/Branch through a
-- ranked account CTE. Select the owner's oldest Active account as a contact
-- branch, preventing duplicate FDs for multi-account customers. LEFT JOIN keeps
-- due FDs whose owners have no Active account. An FD has no BranchID, so this
-- branch is explicitly a contact suggestion, not an inferred FD issuing branch.
WITH contact_accounts AS (
    SELECT a.CustomerID, a.AccountNo, b.BranchName,
           ROW_NUMBER() OVER (PARTITION BY a.CustomerID
               ORDER BY a.OpeningDate, a.AccountNo) AS preference
    FROM Account a
    JOIN Branch b ON b.BranchID = a.BranchID
    WHERE a.Status = 'Active'
)
SELECT f.FD_ID, c.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
       c.Phone, f.EndDate, CURRENT_DATE - f.EndDate AS days_since_maturity,
       f.MaturityAmount, a.AccountNo AS suggested_contact_account,
       a.BranchName AS suggested_contact_branch
FROM Fixed_Deposit f
JOIN Customer c ON c.CustomerID = f.CustomerID
LEFT JOIN contact_accounts a ON a.CustomerID = c.CustomerID AND a.preference = 1
WHERE f.Status = 'Active' AND f.EndDate <= CURRENT_DATE
ORDER BY f.EndDate, f.FD_ID;

-- CQ-07
-- Business Question: How do branch staffing costs compare with their deposit
-- balances, and how many customers does each staff member support?
-- Explanation: Aggregate Employee and Account separately, then join those totals
-- to Branch and Postal_Directory. Count distinct customers within each branch;
-- do not multiply salaries by account rows. NULLIF protects zero-staff and
-- zero-payroll branches. This is a workload proxy, not a profit calculation.
WITH staffing AS (
    SELECT BranchID, COUNT(*) AS staff_count, SUM(Salary) AS monthly_payroll
    FROM Employee GROUP BY BranchID
), holdings AS (
    SELECT BranchID, COUNT(DISTINCT CustomerID) AS customer_count,
           SUM(Balance) AS deposit_balance
    FROM Account WHERE Status IN ('Active', 'Dormant', 'Frozen') GROUP BY BranchID
)
SELECT b.BranchID, b.BranchName, p.City,
       COALESCE(s.staff_count, 0) AS staff_count,
       COALESCE(s.monthly_payroll, 0) AS monthly_payroll,
       COALESCE(h.deposit_balance, 0) AS deposit_balance,
       ROUND(COALESCE(h.customer_count, 0)::numeric / NULLIF(s.staff_count, 0), 2)
           AS customers_per_employee,
       ROUND(COALESCE(h.deposit_balance, 0) / NULLIF(s.monthly_payroll, 0), 2)
           AS balance_to_monthly_payroll_ratio
FROM Branch b
JOIN Postal_Directory p ON p.Pincode = b.Pincode
LEFT JOIN staffing s ON s.BranchID = b.BranchID
LEFT JOIN holdings h ON h.BranchID = b.BranchID
ORDER BY customers_per_employee DESC NULLS LAST, b.BranchID;

-- CQ-08
-- Business Question: Which customers registered the largest potential daily
-- beneficiary limits, and how are those limits distributed by destination bank?
-- Explanation: Join Customer -> Beneficiary -> Bank_Directory, aggregate limits
-- per customer/bank, and rank within each bank. These are sums of configured
-- per-beneficiary caps; the schema has no executed-beneficiary transfer linkage,
-- so these are neither observed transfers nor enforced customer-wide limits.
WITH exposure AS (
    SELECT c.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
           d.BankName, COUNT(*) AS beneficiary_count,
           SUM(b.MaxTransferLimit) AS configured_limit_sum
    FROM Customer c
    JOIN Beneficiary b ON b.CustomerID = c.CustomerID
    JOIN Bank_Directory d ON d.IFSC_Code = b.IFSC_Code
    GROUP BY c.CustomerID, c.FirstName, c.LastName, d.BankName
)
SELECT exposure.*,
       DENSE_RANK() OVER (PARTITION BY BankName ORDER BY configured_limit_sum DESC)
           AS limit_rank_within_bank
FROM exposure
ORDER BY BankName, limit_rank_within_bank, CustomerID;

-- CQ-09
-- Business Question: How much has each loan collected successfully, and which
-- borrowers have failed or pending repayment attempts requiring follow-up?
-- Explanation: Join Loan -> Customer -> Branch and LEFT JOIN Loan_Repayment.
-- FILTER separates successful collections from pending/failed attempts. Loan
-- principal and outstanding are not summed across repayments. Seed repayments
-- are illustrative: collected amounts are not a principal reconciliation.
SELECT l.LoanID, CONCAT(c.FirstName, ' ', c.LastName) AS borrower,
       b.BranchName, l.Status AS loan_status, l.OutstandingBalance,
       COALESCE(SUM(r.AmountPaid) FILTER (WHERE r.PaymentStatus = 'Success'), 0)
           AS successful_collections,
       COUNT(r.PaymentID) FILTER (WHERE r.PaymentStatus = 'Pending') AS pending_attempts,
       COUNT(r.PaymentID) FILTER (WHERE r.PaymentStatus = 'Failed') AS failed_attempts,
       MAX(r.PaymentDate) FILTER (WHERE r.PaymentStatus = 'Success') AS latest_collection
FROM Loan l
JOIN Customer c ON c.CustomerID = l.CustomerID
JOIN Branch b ON b.BranchID = l.BranchID
LEFT JOIN Loan_Repayment r ON r.LoanID = l.LoanID
GROUP BY l.LoanID, c.CustomerID, c.FirstName, c.LastName, b.BranchID, b.BranchName
ORDER BY failed_attempts DESC, pending_attempts DESC, l.LoanID;

-- CQ-10
-- Business Question: Which accounts need a KYC or account-status review, what
-- activity has been recorded, and what is their most recent account audit entry?
-- Explanation: Join Customer -> Account -> Branch, then LEFT JOIN history
-- aggregated per account. A LEFT JOIN LATERAL selects at most one Audit_Log
-- entry with BOTH the Account table discriminator and matching RecordID, since
-- audit IDs are polymorphic. IS DISTINCT FROM also flags a NULL KYC status.
-- Activity is historical context, not proof of a post-freeze violation: the
-- schema has no status-change timestamp. Sprint 1 audits are explicit SEED rows.
WITH activity AS (
    SELECT AccountNo, COUNT(*) AS historical_events, MAX(TransactionDate) AS last_event
    FROM Transaction_History GROUP BY AccountNo
)
SELECT c.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
       c.KYC_Status, a.AccountNo, a.Status AS account_status, a.Balance,
       b.BranchName, COALESCE(t.historical_events, 0) AS historical_events,
       t.last_event, audit.ActionType AS latest_audit_action,
       audit.Description AS latest_audit_description, audit.LogDate AS latest_audit_date
FROM Customer c
JOIN Account a ON a.CustomerID = c.CustomerID
JOIN Branch b ON b.BranchID = a.BranchID
LEFT JOIN activity t ON t.AccountNo = a.AccountNo
LEFT JOIN LATERAL (
    SELECT al.ActionType, al.Description, al.LogDate
    FROM Audit_Log al
    WHERE LOWER(al.TableName) = 'account' AND al.RecordID = a.AccountNo
    ORDER BY al.LogDate DESC NULLS LAST, al.LogID DESC
    LIMIT 1
) audit ON TRUE
WHERE c.KYC_Status IS DISTINCT FROM 'Approved'
   OR a.Status IN ('Dormant', 'Frozen')
ORDER BY b.BranchID, c.CustomerID, a.AccountNo;
