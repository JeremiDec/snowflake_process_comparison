USE DATABASE AMAZON_REVIEWS_DB; 
USE SCHEMA UPSERT;

-- ==========================================
-- KROK 1: PRZYGOTOWANIE TABELI DOCELOWEJ
-- ==========================================
CREATE TABLE IF NOT EXISTS sports_and_outdoors_reviews (
    user_id VARCHAR,
    asin VARCHAR,
    parent_asin VARCHAR,
    rating FLOAT,
    title VARCHAR,
    text STRING,
    helpful_vote NUMBER,
    verified_purchase BOOLEAN,
    images VARIANT,             
    timestamp TIMESTAMP_NTZ,    
    data_aktualizacji TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP() 
);

-- ==========================================
-- KROK 2: BEZPIECZNY UPSERT (MERGE) Z USUWANIEM DUPLIKATÓW
-- ==========================================
MERGE INTO sports_and_outdoors_reviews AS cel
USING (
    SELECT 
        raw_json:user_id::VARCHAR AS user_id,
        raw_json:asin::VARCHAR AS asin,
        raw_json:parent_asin::VARCHAR AS parent_asin,
        raw_json:rating::FLOAT AS rating,
        raw_json:title::VARCHAR AS title,
        raw_json:text::STRING AS text,
        raw_json:helpful_vote::NUMBER AS helpful_vote,
        raw_json:verified_purchase::BOOLEAN AS verified_purchase,
        raw_json:images::VARIANT AS images,
        -- Konwersja czasu z milisekund na czytelną datę
        TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) AS timestamp
    FROM KOPIA_SPORTS_REVIEWS_RAW

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY raw_json:user_id::VARCHAR, raw_json:asin::VARCHAR 
        ORDER BY raw_json:timestamp::NUMBER DESC
    ) = 1
    
) AS zrodlo
ON cel.user_id = zrodlo.user_id AND cel.asin = zrodlo.asin

WHEN MATCHED THEN
    UPDATE SET 
        cel.parent_asin = zrodlo.parent_asin,
        cel.rating = zrodlo.rating,
        cel.title = zrodlo.title,
        cel.text = zrodlo.text,
        cel.helpful_vote = zrodlo.helpful_vote,
        cel.verified_purchase = zrodlo.verified_purchase,
        cel.images = zrodlo.images,
        cel.timestamp = zrodlo.timestamp,
        cel.data_aktualizacji = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN
    INSERT (
        user_id, asin, parent_asin, rating, title, 
        text, helpful_vote, verified_purchase, images, timestamp
    )
    VALUES (
        zrodlo.user_id, zrodlo.asin, zrodlo.parent_asin, zrodlo.rating, zrodlo.title, 
        zrodlo.text, zrodlo.helpful_vote, zrodlo.verified_purchase, zrodlo.images, zrodlo.timestamp
    );