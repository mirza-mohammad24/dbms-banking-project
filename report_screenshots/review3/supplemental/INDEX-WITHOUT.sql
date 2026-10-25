-- banking_report_demo: named index absent for the baseline.
EXPLAIN (ANALYZE, BUFFERS)
SELECT TransactionID,AccountNo,TransactionDate,Amount
FROM public.Transaction_History
WHERE AccountNo=100001
  AND TransactionDate>=CURRENT_DATE-INTERVAL '365 days'
ORDER BY TransactionDate;
