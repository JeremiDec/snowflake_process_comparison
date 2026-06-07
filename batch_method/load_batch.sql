-- =============================================================
-- 02_load_batch_procedure.sql  (BATCH method)
-- Run by: batch processing team member
-- Description: Stored procedure that processes ONE yearly batch:
--              - appends that year's reviews to Silver (no truncate, no merge)
--              - recomputes Gold ONLY for products touched by the batch
--              - logs one metrics row
--              - advances the watermark
--
-- HOW TO RUN: execute the WHOLE "CREATE OR REPLACE PROCEDURE ... $$;"
--             block as a single statement first, confirm it says
--             "successfully created", THEN run the CALL at the bottom.
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE project_wh;
USE SCHEMA amazon_reviews_db.batch;

CREATE OR REPLACE PROCEDURE process_next_batch()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  v_year  INTEGER;
  v_rows  INTEGER;
  v_start TIMESTAMP_NTZ;
BEGIN
  -- capture start time (SQL statement -> use :var for the INTO target)
  SELECT CURRENT_TIMESTAMP() INTO :v_start;

  -- read watermark
  SELECT next_year INTO :v_year FROM batch_state;

  -- scripting expression -> reference variable WITHOUT colon
  IF (v_year > 2023) THEN
    RETURN 'all batches done';
  END IF;

  -- 1) SILVER: append-only load of one yearly batch (no truncate, no merge).
  --    Transforms + filters IDENTICAL to clean_refresh so Silver matches.
  INSERT INTO sports_reviews_silver (
    review_id, asin, parent_asin, user_id, rating, review_title, review_text,
    helpful_vote, verified_purchase, review_ts, has_images
  )
  SELECT
    MD5(raw_json:user_id::STRING || raw_json:asin::STRING || raw_json:timestamp::STRING),
    raw_json:asin::VARCHAR(25),
    raw_json:parent_asin::VARCHAR(25),
    raw_json:user_id::VARCHAR(50),
    raw_json:rating::FLOAT,
    raw_json:title::VARCHAR(500),
    raw_json:text::TEXT,
    COALESCE(raw_json:helpful_vote::INTEGER, 0),
    raw_json:verified_purchase::BOOLEAN,
    TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000),
    ARRAY_SIZE(raw_json:images) > 0
  FROM amazon_reviews_db.raw_data.sports_reviews_raw
  WHERE raw_json:asin       IS NOT NULL
    AND raw_json:user_id    IS NOT NULL
    AND raw_json:rating     IS NOT NULL
    AND raw_json:timestamp  IS NOT NULL
    AND raw_json:rating::FLOAT BETWEEN 1.0 AND 5.0
    AND LENGTH(raw_json:text::STRING) > 0
    AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) >= DATE_FROM_PARTS(:v_year, 1, 1)
    AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) <  DATE_FROM_PARTS(:v_year + 1, 1, 1);

  v_rows := SQLROWCOUNT;

  -- 2) GOLD: recompute aggregates ONLY for products touched in this batch.
  DELETE FROM sports_reviews_gold
  WHERE parent_asin IN (
    SELECT DISTINCT parent_asin FROM sports_reviews_silver
    WHERE review_ts >= DATE_FROM_PARTS(:v_year, 1, 1)
      AND review_ts <  DATE_FROM_PARTS(:v_year + 1, 1, 1)
  );

  INSERT INTO sports_reviews_gold (
    parent_asin, avg_rating, total_reviews, verified_count, unverified_count,
    helpful_votes_sum, reviews_with_images, latest_review_ts, earliest_review_ts
  )
  SELECT
    parent_asin,
    ROUND(AVG(rating), 2),
    COUNT(*),
    COUNT_IF(verified_purchase = TRUE),
    COUNT_IF(verified_purchase = FALSE),
    SUM(helpful_vote),
    COUNT_IF(has_images = TRUE),
    MAX(review_ts),
    MIN(review_ts)
  FROM sports_reviews_silver
  WHERE parent_asin IN (
    SELECT DISTINCT parent_asin FROM sports_reviews_silver
    WHERE review_ts >= DATE_FROM_PARTS(:v_year, 1, 1)
      AND review_ts <  DATE_FROM_PARTS(:v_year + 1, 1, 1)
  )
  GROUP BY parent_asin;

  -- 3) METRICS: one row per batch. Duration computed inside the SQL
  --    statement, where :v_start is a valid bind.
  INSERT INTO pipeline_run_metrics (
    run_id, method, batch_id, bronze_row_count, silver_rows_loaded,
    silver_rows_deleted, gold_rows_loaded, duration_sec, credits_used
  )
  SELECT
    UUID_STRING(),
    'batch',
    :v_year,
    (SELECT COUNT(*) FROM amazon_reviews_db.raw_data.sports_reviews_raw),
    :v_rows,
    0,
    (SELECT COUNT(*) FROM sports_reviews_gold),
    DATEDIFF('millisecond', :v_start, CURRENT_TIMESTAMP()) / 1000.0,
    ROUND(DATEDIFF('millisecond', :v_start, CURRENT_TIMESTAMP()) / 1000.0 / 3600.0 * 1, 6);

  -- 4) advance watermark
  UPDATE batch_state SET next_year = :v_year + 1;

  -- scripting expression -> variables WITHOUT colon
  RETURN 'processed batch year=' || v_year || ' rows=' || v_rows;
END;
$$;

-- -------------------------
-- After the procedure is created, verify and run one batch:
-- -------------------------
SHOW PROCEDURES LIKE 'PROCESS_NEXT_BATCH' IN SCHEMA amazon_reviews_db.batch;

CALL amazon_reviews_db.batch.process_next_batch();

-- 1) czy Bronze nie jest pusty?
SELECT COUNT(*) FROM amazon_reviews_db.raw_data.sports_reviews_raw;

-- 2) rozkład recenzji po latach
SELECT YEAR(TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000)) AS yr,
       COUNT(*) AS n
FROM amazon_reviews_db.raw_data.sports_reviews_raw
GROUP BY 1
ORDER BY 1;


TRUNCATE TABLE amazon_reviews_db.batch.sports_reviews_silver;
TRUNCATE TABLE amazon_reviews_db.batch.sports_reviews_gold;
TRUNCATE TABLE amazon_reviews_db.batch.pipeline_run_metrics;
UPDATE  amazon_reviews_db.batch.batch_state SET next_year = 2000;