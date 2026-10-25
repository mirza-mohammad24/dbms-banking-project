-- Executed: CALL sp_batch_mature_fixed_deposits();
-- Dedicated matured FD fixture in banking_report_demo.
SELECT f.FD_ID,b.Status AS status_before,f.Status AS status_after,
       f.MaturityAmount AS payout,b.Balance AS balance_before,
       a.Balance AS balance_after,l.ActionType AS audit_event
FROM Fixed_Deposit f JOIN report_evidence.fd_before b ON b.FD_ID=f.FD_ID
JOIN Account a ON a.AccountNo=b.AccountNo
JOIN Transaction_History t ON t.AccountNo=a.AccountNo
  AND t.Remarks='FD Maturity Credit: 900001'
JOIN Audit_Log l ON l.RecordID=f.FD_ID AND l.TableName='Fixed_Deposit'
  AND l.ActionType='FD_MATURED'
WHERE f.FD_ID=900001;
