-- The committed transfer creates one debit and one credit history event.
SELECT t.TransactionID,t.AccountNo,t.Amount,t.Remarks,s.balance_audit
FROM Transaction_History t
JOIN report_evidence.transfer_after s ON s.AccountNo=t.AccountNo
WHERE t.Remarks LIKE '%Report transfer demonstration'
ORDER BY TransactionID;
