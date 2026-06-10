// poniżej załączam jak testowałem czy upsert działa 


// czyścimy tabele sports_and_outdoors_reviews

USE DATABASE AMAZON_REVIEWS_DB;
USE SCHEMA UPSERT;
TRUNCATE TABLE sports_and_outdoors_reviews;


// najpierw sprwadzamy czy numbers of row inserted się zmienia
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

// potem ta sama komenda sprawdzi czym różni się i wstawi brakujące wiersze - 19380045 - numbers of rows updated

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

//sprawdzenie wartości przed zmianą w surowych danych 

SELECT user_id, asin, rating, text, data_aktualizacji 
FROM sports_and_outdoors_reviews 
LIMIT 1;

//edycja wartości w surowych danych 

UPDATE KOPIA_SPORTS_REVIEWS_RAW
SET raw_json = OBJECT_INSERT(raw_json, 'rating', 1.0, TRUE) -- Nadpisujemy klucz rating wartością 1.0
WHERE raw_json:user_id::VARCHAR = 'AG2ID6DCMZHTCTYDFWUMIABSNHSA' AND raw_json:asin::VARCHAR = 'B00GZO7GWK'; -- Podmieniamy na swoje wartości

//sprawdzamy czy rekord został zaktualizowany 

SELECT user_id, asin, rating, text, data_aktualizacji 
FROM sports_and_outdoors_reviews 
WHERE user_id = 'AG2ID6DCMZHTCTYDFWUMIABSNHSA' AND asin = 'B00GZO7GWK'; -- Podmieniamy na swoje wartości

