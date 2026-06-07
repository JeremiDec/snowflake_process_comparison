-- =============================================================
-- 01_setup_database.sql
-- Run by: the person uploading the file (ACCOUNTADMIN)
-- Description: Creates the database, schemas for all team members
--              and the shared stage for raw data
-- =============================================================

USE ROLE ACCOUNTADMIN;

-- -------------------------
-- Database
-- -------------------------
CREATE DATABASE IF NOT EXISTS amazon_reviews_db;

-- -------------------------
-- Schemas
-- -------------------------
-- Shared schema for raw data (Bronze layer)
CREATE SCHEMA IF NOT EXISTS amazon_reviews_db.raw_data;

-- Schema for clean refresh method
CREATE SCHEMA IF NOT EXISTS amazon_reviews_db.clean_refresh;

-- Schema for upsert method
CREATE SCHEMA IF NOT EXISTS amazon_reviews_db.upsert;

-- Schema for batch processing method
CREATE SCHEMA IF NOT EXISTS amazon_reviews_db.batch;

-- -------------------------
-- Warehouse (shared for the whole team)
-- -------------------------
CREATE WAREHOUSE IF NOT EXISTS project_wh
  WAREHOUSE_SIZE      = 'X-SMALL'
  AUTO_SUSPEND        = 60          -- suspends after 60 seconds of inactivity
  AUTO_RESUME         = TRUE        -- resumes automatically when needed
  INITIALLY_SUSPENDED = TRUE        -- starts in suspended state
  COMMENT = 'Shared project warehouse - X-Small to save credits';

USE WAREHOUSE project_wh;

-- -------------------------
-- Stage (shared for the whole team)
-- -------------------------
USE SCHEMA amazon_reviews_db.raw_data;

CREATE STAGE IF NOT EXISTS sports_stage
  FILE_FORMAT = (
    TYPE              = 'JSON'
    STRIP_OUTER_ARRAY = FALSE   -- JSONL: each line is a separate JSON object
    COMPRESSION       = 'AUTO'
  )
  COMMENT = 'Shared stage for Sports_and_Outdoors.jsonl file';

-- -------------------------
-- Verification
-- -------------------------
-- Check if the file is on the stage:
LIST @sports_stage;