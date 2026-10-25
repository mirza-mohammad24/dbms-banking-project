-- banking_report_demo: idx_txn_account_date restored.
EXPLAIN (ANALYZE, BUFFERS)
SELECT TransactionID,AccountNo,TransactionDate,Amount
FROM public.Transaction_History
WHERE AccountNo=100001
  AND TransactionDate>=CURRENT_DATE-INTERVAL '365 days'
ORDER BY TransactionDate;
