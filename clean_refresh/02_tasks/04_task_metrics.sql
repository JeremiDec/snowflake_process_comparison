-- =============================================================
-- 04_task_metrics.sql
-- Run by: clean refresh team member
-- Description: Creates task for logging pipeline run metrics.
--              Logs duration, row counts and credits used
--              after every successful pipeline run.
-- =============================================================
 
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.clean_refresh;
 
-- =============================================================
-- TASK 5: Log pipeline run metrics
-- Final task in the DAG - triggered after task_4_load_gold
-- =============================================================
CREATE OR REPLACE TASK task_5_log_metrics
  WAREHOUSE = project_wh
  AFTER task_4_load_gold
AS
  INSERT INTO pipeline_run_metrics (
    run_id,
    bronze_row_count,
    silver_rows_loaded,
    silver_rows_deleted,
    gold_rows_loaded,
    duration_sec,
    credits_used
  )
  SELECT
    UUID_STRING()                                                     AS run_id,
    (SELECT COUNT(*) FROM amazon_reviews_db.raw_data.sports_reviews_raw) AS bronze_row_count,
    (SELECT COUNT(*) FROM sports_reviews_silver)                      AS silver_rows_loaded,
    (SELECT COUNT(*) FROM sports_reviews_silver)                      AS silver_rows_deleted,
    (SELECT COUNT(*) FROM sports_reviews_gold)                        AS gold_rows_loaded,
    DATEDIFF('second',
      (SELECT MIN(SCHEDULED_TIME)
       FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_1_TRUNCATE_SILVER'))
       WHERE STATE = 'SUCCEEDED'
         AND SCHEDULED_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())),
      CURRENT_TIMESTAMP()
    )                                                                 AS duration_sec,
    (SELECT ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 4)
     FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE(
       WAREHOUSE_NAME       => 'PROJECT_WH',
       END_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())))
    )                                                                 AS credits_used;

SELECT * FROM PIPELINE_RUN_METRICS;