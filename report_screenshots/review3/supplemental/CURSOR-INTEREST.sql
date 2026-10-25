-- Executed: CALL sp_batch_credit_savings_interest();
-- New eligible Savings account in banking_report_demo; rate is 6 percent annually.
SELECT a.AccountNo,b.Balance AS balance_before,a.Balance AS balance_after,
       ROUND(b.Balance*a.InterestRate/1200,2) AS calculated_interest,
       t.Amount AS posted_interest,t.Remarks,
       (a.Balance-b.Balance=t.Amount) AS balance_verified
FROM Account a JOIN report_evidence.account_before b
  ON b.AccountNo=a.AccountNo AND b.phase='interest'
JOIN Transaction_History t ON t.AccountNo=a.AccountNo
WHERE a.AccountNo=900001 AND t.Remarks='Monthly Interest Credit';
