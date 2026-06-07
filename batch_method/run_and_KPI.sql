-- =============================================================
-- 04_run_and_kpi.sql  (BATCH method)
-- Run by: batch processing team member
-- Description: Runs ALL yearly batches in one go (for benchmarking),
--              then extracts KPIs and verifies the final state
--              matches clean_refresh.
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.batch;

ALTER SESSION SET QUERY_TAG = 'method=batch';

-- -------------------------
-- Reset before a clean benchmark run (uncomment all 4 lines):
-- TRUNCATE TABLE sports_reviews_silver;
-- TRUNCATE TABLE sports_reviews_gold;
-- TRUNCATE TABLE pipeline_run_metrics;
-- UPDATE batch_state SET next_year = 2000;
-- -------------------------

-- Process every yearly batch (2000..2023 if watermark starts at 2000).
-- Extra calls after the last batch return 'all batches done' and do nothing.
EXECUTE IMMEDIATE $$
BEGIN
  FOR i IN 1 TO 30 DO
    CALL amazon_reviews_db.batch.process_next_batch();
  END FOR;
  RETURN 'all batches processed';
END;
$$;

-- -------------------------
-- KPI 1: per-batch metrics (shows throughput and cost per yearly batch)
-- -------------------------
SELECT batch_id, silver_rows_loaded, gold_rows_loaded,
       ROUND(duration_sec, 2) AS duration_sec,
       credits_used
FROM pipeline_run_metrics
WHERE method = 'batch'
ORDER BY batch_id;

-- -------------------------
-- KPI 2: totals for the batch method (compare with clean_refresh)
-- -------------------------
SELECT method,
       COUNT(*)                   AS num_batches,
       SUM(silver_rows_loaded)    AS total_silver_rows,
       ROUND(SUM(duration_sec),2) AS total_duration_sec,
       ROUND(SUM(credits_used),6) AS est_credits
FROM pipeline_run_metrics
WHERE method = 'batch'
GROUP BY method;

-- -------------------------
-- KPI 3: correctness - final Silver and Gold MUST match clean_refresh
-- -------------------------
SELECT 'batch'         AS method, COUNT(*) AS silver_rows FROM sports_reviews_silver
UNION ALL
SELECT 'clean_refresh',           COUNT(*) FROM amazon_reviews_db.clean_refresh.sports_reviews_silver;

SELECT 'batch'         AS method, COUNT(*) AS gold_rows FROM sports_reviews_gold
UNION ALL
SELECT 'clean_refresh',           COUNT(*) FROM amazon_reviews_db.clean_refresh.sports_reviews_gold;

-- -------------------------
-- KPI 4: per-query performance (immediate, no latency)
-- INFORMATION_SCHEMA.QUERY_HISTORY() has a limited column set -
-- use KPI 5 (ACCOUNT_USAGE) for partitions_scanned / bytes_spilled.
-- -------------------------
SELECT query_id,
       LEFT(query_text, 60)                  AS query,
       ROUND(total_elapsed_time / 1000, 2)   AS total_sec,
       ROUND(compilation_time   / 1000, 2)   AS compile_sec,
       ROUND(execution_time     / 1000, 2)   AS execute_sec,
       rows_produced,
       rows_inserted,
       ROUND(bytes_scanned / 1024 / 1024, 1) AS mb_scanned,
       credits_used_cloud_services
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_tag = 'method=batch'
ORDER BY start_time DESC;

-- -------------------------
-- KPI 5: authoritative credits + partitions (ACCOUNT_USAGE, up to ~3h delay)
-- Use this for the final cost comparison in the report.
-- -------------------------
SELECT start_time, end_time,
       credits_used_compute,
       credits_used_cloud_services,
       credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'PROJECT_WH'
ORDER BY start_time DESC
LIMIT 24;

ALTER SESSION UNSET QUERY_TAG;