-- =============================================================
-- 01_create_tables.sql  (BATCH method)
-- Run by: batch processing team member
-- Description: Silver, Gold, metrics and a watermark control table
--              for the incremental BATCH pipeline.
--              Table definitions MATCH clean_refresh so the final
--              state is directly comparable.
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.batch;

-- -------------------------
-- Silver table (identical to clean_refresh.sports_reviews_silver)
-- -------------------------
CREATE OR REPLACE TABLE sports_reviews_silver (
  review_id         VARCHAR(100),     -- MD5(user_id || asin || timestamp) -- SAME formula as clean_refresh
  asin              VARCHAR(25),
  parent_asin       VARCHAR(25),
  user_id           VARCHAR(50),
  rating            FLOAT,
  review_title      VARCHAR(500),
  review_text       TEXT,
  helpful_vote      INTEGER,
  verified_purchase BOOLEAN,
  review_ts         TIMESTAMP_NTZ,
  has_images        BOOLEAN,
  loaded_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------
-- Gold table (identical to clean_refresh.sports_reviews_gold)
-- -------------------------
CREATE OR REPLACE TABLE sports_reviews_gold (
  parent_asin         VARCHAR(25),
  avg_rating          FLOAT,
  total_reviews       INTEGER,
  verified_count      INTEGER,
  unverified_count    INTEGER,
  helpful_votes_sum   INTEGER,
  reviews_with_images INTEGER,
  latest_review_ts    TIMESTAMP_NTZ,
  earliest_review_ts  TIMESTAMP_NTZ,
  loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------
-- Pipeline run metrics (same columns as clean_refresh + batch_id)
-- One row PER BATCH; sum across batches = comparable to clean_refresh's run.
-- -------------------------
CREATE OR REPLACE TABLE pipeline_run_metrics (
  run_id              VARCHAR(50),
  run_timestamp       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  method              VARCHAR(50)   DEFAULT 'batch',
  batch_id            INTEGER,      -- which yearly batch (1996..2023)
  bronze_row_count    INTEGER,
  silver_rows_loaded  INTEGER,      -- rows appended in THIS batch
  silver_rows_deleted INTEGER,      -- always 0 (batch never truncates Silver)
  gold_rows_loaded    INTEGER,
  duration_sec        FLOAT,
  credits_used        FLOAT
);

-- -------------------------
-- Watermark / control table: which batch (year) to process next
-- -------------------------
CREATE OR REPLACE TABLE batch_state (
  next_year INTEGER
);
INSERT INTO batch_state (next_year) VALUES (1996);   -- dataset starts May 1996

-- -------------------------
-- Verification
-- -------------------------
SHOW TABLES IN SCHEMA amazon_reviews_db.batch;