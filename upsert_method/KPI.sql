SELECT 
    bronze_row_count AS "Wiersze Bronze",
    silver_rows_loaded AS "Zapisy do Silver (Insert/Update)",
    gold_rows_loaded AS "Zapisy do Gold (Insert/Update)",
    duration_sec AS "Czas trwania (s)"
FROM amazon_reviews_db.upsert.pipeline_run_metrics
ORDER BY run_timestamp DESC
LIMIT 1;


// bytes oraz partitions 
USE ROLE ACCOUNTADMIN;

SELECT 
    query_id,
    execution_time / 1000 AS execution_time_sec,
    partitions_scanned,
    partitions_total,
    bytes_spilled_to_local_storage,
    bytes_spilled_to_remote_storage
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%MERGE INTO AMAZON_REVIEWS_DB.UPSERT.SPORTS_REVIEWS_SILVER%'
ORDER BY start_time DESC
LIMIT 1;

// czas pracy 
SELECT 
    duration_sec AS "Czas pracy warehouse (s)"
FROM amazon_reviews_db.upsert.pipeline_run_metrics
WHERE method = 'upsert'
ORDER BY run_timestamp DESC
LIMIT 1;

// koszty 

USE ROLE ACCOUNTADMIN;

SELECT 
    start_time AS "Okres",
    warehouse_name AS "Warehouse",
    credits_used_compute AS "Credits — compute",
    credits_used_cloud_services AS "Credits — cloud services",
    credits_used AS "Credits — łącznie",
    (credits_used * 2.0) AS "Szac. koszt (USD)*" -- mnożymy kredyty przez stawkę 2 USD
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'PROJECT_WH' -- Upewnij się, że podajesz nazwę swojego warehouse (pisana WIELKIMI LITERAMI)
ORDER BY start_time DESC
LIMIT 5;