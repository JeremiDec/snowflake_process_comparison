SELECT COUNT(*) FROM raw_data.sports_reviews_raw

SELECT batch_id, silver_rows_loaded, gold_rows_loaded,
       ROUND(duration_sec, 2) AS duration_sec, credits_used
FROM pipeline_run_metrics
WHERE method = 'batch'
ORDER BY batch_id;

