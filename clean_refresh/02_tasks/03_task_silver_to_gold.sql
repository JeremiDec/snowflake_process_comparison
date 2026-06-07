-- =============================================================
-- 03_task_silver_to_gold.sql
-- Run by: clean refresh team member
-- Description: Creates tasks for Silver → Gold layer
--              Task 3: truncate Gold
--              Task 4: aggregate Silver into Gold
-- =============================================================
 
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.clean_refresh;
 
-- =============================================================
-- TASK 3: Truncate Gold
-- Triggered after task_2_load_silver completes
-- =============================================================
CREATE OR REPLACE TASK task_3_truncate_gold
  WAREHOUSE = project_wh
  AFTER task_2_load_silver
AS
  TRUNCATE TABLE sports_reviews_gold;
 
 
-- =============================================================
-- TASK 4: Load Gold - aggregations per product
-- =============================================================
CREATE OR REPLACE TASK task_4_load_gold
  WAREHOUSE = project_wh
  AFTER task_3_truncate_gold
AS
  INSERT INTO sports_reviews_gold (
    parent_asin,
    avg_rating,
    total_reviews,
    verified_count,
    unverified_count,
    helpful_votes_sum,
    reviews_with_images,
    latest_review_ts,
    earliest_review_ts
  )
  SELECT
    parent_asin,
    ROUND(AVG(rating), 2)               AS avg_rating,
    COUNT(*)                            AS total_reviews,
    COUNT_IF(verified_purchase = TRUE)  AS verified_count,
    COUNT_IF(verified_purchase = FALSE) AS unverified_count,
    SUM(helpful_vote)                   AS helpful_votes_sum,
    COUNT_IF(has_images = TRUE)         AS reviews_with_images,
    MAX(review_ts)                      AS latest_review_ts,
    MIN(review_ts)                      AS earliest_review_ts
  FROM sports_reviews_silver
  GROUP BY parent_asin;
 