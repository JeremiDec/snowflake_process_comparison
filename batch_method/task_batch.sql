-- =============================================================
-- 03_task_batch_pipeline.sql  (BATCH method)
-- Run by: batch processing team member
-- Description: Wraps the batch procedure in a scheduled Task -
--              one yearly batch per execution. Mirrors the Task
--              approach used by clean_refresh.
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.batch;

-- Single-step "DAG": each run processes the next unprocessed batch.
CREATE OR REPLACE TASK task_batch_pipeline
  WAREHOUSE = project_wh
  SCHEDULE  = 'USING CRON 0 3 * * * UTC'   -- one batch/day; remove or change for the demo
AS
  CALL process_next_batch();

-- -------------------------
-- Resume + run one batch manually + monitor
-- -------------------------
ALTER TASK task_batch_pipeline RESUME;
EXECUTE TASK task_batch_pipeline;

SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_BATCH_PIPELINE'))
ORDER BY SCHEDULED_TIME DESC;

-- IMPORTANT: suspend it so it does not auto-run daily and burn credits
ALTER TASK task_batch_pipeline SUSPEND;