-- Executed: CALL sp_transfer_funds(100001,100003,1000,'UPI','Report transfer demonstration');
-- Actual committed balances saved immediately after the procedure CALL.
SELECT b.AccountNo,b.Balance AS balance_before,s.Balance AS balance_after,
       s.Balance-b.Balance AS balance_change,t.Amount,t.Remarks
FROM report_evidence.account_before b
JOIN report_evidence.transfer_after s ON s.AccountNo=b.AccountNo
JOIN Transaction_History t ON t.AccountNo=b.AccountNo
WHERE b.phase='transfer' AND t.Remarks LIKE '%Report transfer demonstration'
ORDER BY b.AccountNo;
