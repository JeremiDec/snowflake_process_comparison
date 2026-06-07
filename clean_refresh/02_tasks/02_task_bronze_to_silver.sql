-- =============================================================
-- 02_task_bronze_to_silver.sql
-- Run by: clean refresh team member
-- Description: Creates tasks for Bronze → Silver layer
--              Task 1: truncate Silver
--              Task 2: load and transform data into Silver
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.clean_refresh;

-- =============================================================
-- TASK 1: Truncate Silver
-- Root task - triggers the whole DAG
-- No schedule - run manually only via EXECUTE TASK
-- =============================================================
CREATE OR REPLACE TASK task_1_truncate_silver
  WAREHOUSE = project_wh
  SCHEDULE  = 'USING CRON 0 2 * * * UTC'
AS
  TRUNCATE TABLE sports_reviews_silver;



-- =============================================================
-- TASK 2: Load Silver from Bronze
-- Transforms raw VARIANT JSON into typed columns
-- =============================================================
CREATE OR REPLACE TASK task_2_load_silver
  WAREHOUSE = project_wh
  AFTER task_1_truncate_silver
AS
  INSERT INTO sports_reviews_silver (
    review_id,
    asin,
    parent_asin,
    user_id,
    rating,
    review_title,
    review_text,
    helpful_vote,
    verified_purchase,
    review_ts,
    has_images
  )
  SELECT
    -- Unique ID: hash of user_id + asin + timestamp
    MD5(
      raw_json:user_id::STRING ||
      raw_json:asin::STRING    ||
      raw_json:timestamp::STRING
    )                                                     AS review_id,
    raw_json:asin::VARCHAR(25)                            AS asin,
    raw_json:parent_asin::VARCHAR(25)                     AS parent_asin,
    raw_json:user_id::VARCHAR(50)                         AS user_id,
    raw_json:rating::FLOAT                                AS rating,
    raw_json:title::VARCHAR(500)                          AS review_title,
    raw_json:text::TEXT                                   AS review_text,
    COALESCE(raw_json:helpful_vote::INTEGER, 0)           AS helpful_vote,
    raw_json:verified_purchase::BOOLEAN                   AS verified_purchase,
    -- Convert unix milliseconds to timestamp
    TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000)   AS review_ts,
    ARRAY_SIZE(raw_json:images) > 0                       AS has_images
  FROM amazon_reviews_db.raw_data.sports_reviews_raw
  WHERE raw_json:asin IS NOT NULL
    AND raw_json:user_id IS NOT NULL
    AND raw_json:rating IS NOT NULL
    AND raw_json:timestamp IS NOT NULL
    -- Rating must be within valid range
    AND raw_json:rating::FLOAT BETWEEN 1.0 AND 5.0
    -- Timestamp must be within dataset range (May 1996 - Sep 2023)
    AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) >= '1996-01-01'
    AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) <= '2024-01-01'
    -- Skip empty review text
    AND LENGTH(raw_json:text::STRING) > 0;



