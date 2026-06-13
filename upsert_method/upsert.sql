CREATE OR REPLACE PROCEDURE process_upsert()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS

DECLARE
    v_run_id        VARCHAR;
    v_start         TIMESTAMP_NTZ;
    v_bronze        INTEGER;
    v_silver_loaded INTEGER;
    v_gold_loaded   INTEGER;
    v_duration      FLOAT;
BEGIN
    v_run_id := UUID_STRING();
    v_start  := CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- (a) licznik Bronze
    SELECT COUNT(*) INTO :v_bronze
    FROM AMAZON_REVIEWS_DB.RAW_DATA.SPORTS_REVIEWS_RAW;

    -- (b) UPSERT do Silver
    MERGE INTO AMAZON_REVIEWS_DB.UPSERT.SPORTS_REVIEWS_SILVER AS cel
    USING (
        SELECT
            MD5(raw_json:user_id::VARCHAR || '|' || raw_json:asin::VARCHAR || '|' || raw_json:timestamp::VARCHAR) AS review_id,
            raw_json:asin::VARCHAR              AS asin,
            raw_json:parent_asin::VARCHAR       AS parent_asin,
            raw_json:user_id::VARCHAR           AS user_id,
            raw_json:rating::FLOAT              AS rating,
            raw_json:title::VARCHAR             AS review_title,
            raw_json:text::STRING               AS review_text,
            raw_json:helpful_vote::INTEGER      AS helpful_vote,
            raw_json:verified_purchase::BOOLEAN AS verified_purchase,
            TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) AS review_ts,
            IFF(ARRAY_SIZE(raw_json:images) > 0, TRUE, FALSE)   AS has_images
        FROM AMAZON_REVIEWS_DB.RAW_DATA.SPORTS_REVIEWS_RAW
        WHERE raw_json:rating::FLOAT BETWEEN 1.0 AND 5.0
          AND raw_json:text::STRING <> ''
          AND raw_json:user_id::VARCHAR IS NOT NULL
          AND raw_json:asin::VARCHAR    IS NOT NULL
          AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) >= '1996-01-01'::TIMESTAMP_NTZ
          AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) <  '2025-01-01'::TIMESTAMP_NTZ
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY raw_json:user_id::VARCHAR, raw_json:asin::VARCHAR
            ORDER BY raw_json:timestamp::NUMBER DESC
        ) = 1
    ) AS src
    ON cel.user_id = src.user_id AND cel.asin = src.asin
    WHEN MATCHED AND (
            cel.rating            IS DISTINCT FROM src.rating
         OR cel.review_ts         IS DISTINCT FROM src.review_ts
         OR cel.review_title      IS DISTINCT FROM src.review_title
         OR cel.review_text       IS DISTINCT FROM src.review_text
         OR cel.helpful_vote      IS DISTINCT FROM src.helpful_vote
         OR cel.verified_purchase IS DISTINCT FROM src.verified_purchase
         OR cel.parent_asin       IS DISTINCT FROM src.parent_asin
         OR cel.has_images        IS DISTINCT FROM src.has_images
    ) THEN UPDATE SET
        cel.review_id         = src.review_id,
        cel.parent_asin       = src.parent_asin,
        cel.rating            = src.rating,
        cel.review_title      = src.review_title,
        cel.review_text       = src.review_text,
        cel.helpful_vote      = src.helpful_vote,
        cel.verified_purchase = src.verified_purchase,
        cel.review_ts         = src.review_ts,
        cel.has_images        = src.has_images,
        cel.loaded_at         = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (review_id, asin, parent_asin, user_id, rating, review_title, review_text,
         helpful_vote, verified_purchase, review_ts, has_images, loaded_at)
    VALUES
        (src.review_id, src.asin, src.parent_asin, src.user_id, src.rating, src.review_title, src.review_text,
         src.helpful_vote, src.verified_purchase, src.review_ts, src.has_images, CURRENT_TIMESTAMP());

    v_silver_loaded := SQLROWCOUNT;

    -- (c) Gold: idempotentny MERGE
    MERGE INTO AMAZON_REVIEWS_DB.UPSERT.SPORTS_REVIEWS_GOLD AS g
    USING (
        SELECT
            parent_asin,
            AVG(rating)                          AS avg_rating,
            COUNT(*)                             AS total_reviews,
            COUNT_IF(verified_purchase = TRUE)   AS verified_count,
            COUNT_IF(verified_purchase = FALSE)  AS unverified_count,
            SUM(helpful_vote)                    AS helpful_votes_sum,
            COUNT_IF(has_images = TRUE)          AS reviews_with_images,
            MAX(review_ts)                       AS latest_review_ts,
            MIN(review_ts)                       AS earliest_review_ts
        FROM AMAZON_REVIEWS_DB.UPSERT.SPORTS_REVIEWS_SILVER
        WHERE parent_asin IS NOT NULL
        GROUP BY parent_asin
    ) AS s
    ON g.parent_asin = s.parent_asin
    WHEN MATCHED THEN UPDATE SET
        g.avg_rating          = s.avg_rating,
        g.total_reviews       = s.total_reviews,
        g.verified_count      = s.verified_count,
        g.unverified_count    = s.unverified_count,
        g.helpful_votes_sum   = s.helpful_votes_sum,
        g.reviews_with_images = s.reviews_with_images,
        g.latest_review_ts    = s.latest_review_ts,
        g.earliest_review_ts  = s.earliest_review_ts,
        g.loaded_at           = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (parent_asin, avg_rating, total_reviews, verified_count, unverified_count,
         helpful_votes_sum, reviews_with_images, latest_review_ts, earliest_review_ts, loaded_at)
    VALUES
        (s.parent_asin, s.avg_rating, s.total_reviews, s.verified_count, s.unverified_count,
         s.helpful_votes_sum, s.reviews_with_images, s.latest_review_ts, s.earliest_review_ts, CURRENT_TIMESTAMP());

    v_gold_loaded := SQLROWCOUNT;

    -- (d) KPI
    v_duration := DATEDIFF('millisecond', :v_start, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) / 1000.0;

    INSERT INTO AMAZON_REVIEWS_DB.UPSERT.PIPELINE_RUN_METRICS
        (run_id, method, bronze_row_count, silver_rows_loaded, silver_rows_deleted, gold_rows_loaded, duration_sec, credits_used)
    SELECT :v_run_id, 'upsert', :v_bronze, :v_silver_loaded, 0, :v_gold_loaded, :v_duration, NULL;

    RETURN 'upsert OK | run_id=' || :v_run_id
        || ' | bronze=' || :v_bronze
        || ' | silver_loaded=' || :v_silver_loaded
        || ' | gold_loaded=' || :v_gold_loaded
        || ' | duration_sec=' || :v_duration;
END;

-- 1. Uruchomienie procedury (transfer danych Bronze -> Silver -> Gold)
CALL process_upsert();

-- 2. Sprawdzenie metryk wydajności
SELECT *
FROM pipeline_run_metrics
ORDER BY run_timestamp DESC
LIMIT 10;

-- 3. Kontrola liczności tabel
SELECT 'silver' AS warstwa, COUNT(*) AS wierszy FROM sports_reviews_silver
UNION ALL
SELECT 'gold'   AS warstwa, COUNT(*)            FROM sports_reviews_gold;

-- 4. Podgląd danych
SELECT * FROM sports_reviews_silver LIMIT 5;
SELECT * FROM sports_reviews_gold ORDER BY total_reviews DESC LIMIT 5;