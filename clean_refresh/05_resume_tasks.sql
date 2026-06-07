-- =============================================================
-- 05_resume_tasks.sql
-- Run by: by admin user
-- Description: Resume all tasks for clean_refresh pipeline
--              
--              
-- =============================================================
 
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.clean_refresh;
 

-- =============================================================
-- Resume tasks
-- =============================================================
ALTER TASK task_5_log_metrics RESUME;
ALTER TASK task_4_load_gold     RESUME;
ALTER TASK task_3_truncate_gold RESUME;
ALTER TASK task_2_load_silver     RESUME;
ALTER TASK task_1_truncate_silver RESUME;


-- =============================================================
-- Activate task manually
-- =============================================================
EXECUTE TASK task_1_truncate_silver;


-- =============================================================
-- To monitor task execution:
-- =============================================================
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_1_TRUNCATE_SILVER'))
ORDER BY SCHEDULED_TIME DESC;

SELECT *
FROM CLEAN_REFRESH.PIPELINE_RUN_METRICS;

-- =============================================================
-- suspend tasks
-- =============================================================
ALTER TASK task_1_truncate_silver SUSPEND;