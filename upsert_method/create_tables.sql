USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.upsert;

CREATE TABLE IF NOT EXISTS sports_reviews_silver (
  review_id           VARCHAR(100),
  asin                VARCHAR(25),
  parent_asin         VARCHAR(25),
  user_id             VARCHAR(50),
  rating              FLOAT,
  review_title        VARCHAR(500),
  review_text         TEXT,
  helpful_vote        INTEGER,
  verified_purchase   BOOLEAN,
  review_ts           TIMESTAMP_NTZ,
  has_images          BOOLEAN,
  loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS sports_reviews_gold (
  parent_asin           VARCHAR(25),
  avg_rating            FLOAT,
  total_reviews         INTEGER,
  verified_count        INTEGER,
  unverified_count      INTEGER,
  helpful_votes_sum     INTEGER,
  reviews_with_images   INTEGER,
  latest_review_ts      TIMESTAMP_NTZ,
  earliest_review_ts    TIMESTAMP_NTZ,
  loaded_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS pipeline_run_metrics (
  run_id              VARCHAR(50),
  run_timestamp       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  method              VARCHAR(50)   DEFAULT 'upsert',
  bronze_row_count    INTEGER,
  silver_rows_loaded  INTEGER,
  silver_rows_deleted INTEGER,
  gold_rows_loaded    INTEGER,
  duration_sec        FLOAT,
  credits_used        FLOAT
);