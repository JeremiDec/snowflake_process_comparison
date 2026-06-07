-- =============================================================
-- 01_create_tables.sql
-- Run by: clean refresh team member
-- Description: Creates Silver (cleaned) and Gold (aggregated)
--              tables for the clean refresh pipeline
-- =============================================================
 
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.clean_refresh;
 
-- -------------------------
-- Silver table (cleaned, typed columns)
-- -------------------------
CREATE OR REPLACE TABLE sports_reviews_silver (
  review_id           VARCHAR(100),     -- MD5 hash of user_id + asin + timestamp
  asin                VARCHAR(25),
  parent_asin         VARCHAR(25),
  user_id             VARCHAR(50),
  rating              FLOAT,
  review_title        VARCHAR(500),
  review_text         TEXT,
  helpful_vote        INTEGER,
  verified_purchase   BOOLEAN,
  review_ts           TIMESTAMP_NTZ,    -- converted from unix milliseconds
  has_images          BOOLEAN,
  loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
 
-- -------------------------
-- Gold table (aggregated per product)
-- -------------------------
CREATE OR REPLACE TABLE sports_reviews_gold (
  parent_asin           VARCHAR(25),
  avg_rating            FLOAT,
  total_reviews         INTEGER,
  verified_count        INTEGER,        -- number of verified purchases
  unverified_count      INTEGER,
  helpful_votes_sum     INTEGER,
  reviews_with_images   INTEGER,
  latest_review_ts      TIMESTAMP_NTZ,
  earliest_review_ts    TIMESTAMP_NTZ,
  loaded_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
 
-- -------------------------
-- Pipeline run metrics table (for comparison with teammates)
-- -------------------------
CREATE OR REPLACE TABLE pipeline_run_metrics (
  run_id              VARCHAR(50),
  run_timestamp       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  method              VARCHAR(50)   DEFAULT 'clean_refresh',
  bronze_row_count    INTEGER,      -- rows in Bronze at time of run
  silver_rows_loaded  INTEGER,      -- rows inserted into Silver
  silver_rows_deleted INTEGER,      -- rows deleted (always full truncate)
  gold_rows_loaded    INTEGER,
  duration_sec        FLOAT,        -- total pipeline duration
  credits_used        FLOAT         -- credits consumed during the run
);
 
-- -------------------------
-- Verification
-- -------------------------
SHOW TABLES IN SCHEMA amazon_reviews_db.clean_refresh;