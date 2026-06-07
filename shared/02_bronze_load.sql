-- =============================================================
-- 02_bronze_load.sql
-- Run by: the person uploading the file (once, for the whole team)
-- Description: Loads raw JSONL data from stage into the Bronze table.
--              This table is shared - each team member uses it
--              as their starting point.
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.raw_data;

-- -------------------------
-- Bronze table (raw JSON)
-- -------------------------
CREATE OR REPLACE TABLE sports_reviews_raw (
  raw_json        VARIANT,
  load_timestamp  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------
-- Load data from stage
-- -------------------------

COPY INTO sports_reviews_raw (raw_json)
FROM @sports_stage
FILE_FORMAT = (
  TYPE              = 'JSON'
  STRIP_OUTER_ARRAY = FALSE
)
ON_ERROR = 'CONTINUE';  -- skip corrupted lines, do not abort

-- -------------------------
-- Verification
-- -------------------------
-- Check how many records were loaded:
SELECT COUNT(*) AS total_rows FROM sports_reviews_raw;

-- Preview sample records:
SELECT raw_json FROM sports_reviews_raw LIMIT 5;

-- Check available fields:
SELECT
  raw_json:rating::FLOAT              AS rating,
  raw_json:title::VARCHAR             AS review_title,
  raw_json:text::VARCHAR              AS review_text,
  raw_json:asin::VARCHAR              AS asin,
  raw_json:parent_asin::VARCHAR       AS parent_asin,
  raw_json:user_id::VARCHAR           AS user_id,
  raw_json:timestamp::NUMBER          AS ts_unix,
  raw_json:verified_purchase::BOOLEAN AS verified_purchase,
  raw_json:helpful_vote::INTEGER      AS helpful_vote,
  ARRAY_SIZE(raw_json:images)         AS image_count
FROM sports_reviews_raw
LIMIT 10;
