# Data Pipeline na Snowflake

Projekt zaliczeniowy z przedmiotu **Big Data**.  
Porównanie trzech strategii aktualizacji danych analitycznych na platformie Snowflake:  
**Clean Refresh**, **Batch** i **Upsert**.

---

## Opis projektu

Celem projektu jest odpowiedź na praktyczne pytanie inżynierii danych:

> **Jak odświeżać warstwę analityczną na Snowflake, gdy pojawiają się nowe i zmienione dane — i ile to kosztuje?**

Zaimplementowaliśmy trzy podejścia na tym samym zbiorze danych i porównaliśmy je pod trzema osiami:

- **Poprawność** — czy wszystkie metody produkują ten sam wynik?
- **Wydajność** — czas trwania, liczba wierszy, skanowane partycje, bytes spilled.
- **Koszt** — zużyte credits Snowflake (compute + cloud services).

---

## Zbiór danych

| Właściwość | Wartość |
|---|---|
| Nazwa | Amazon Reviews 2023 |
| Źródło | McAuley Lab, UC San Diego ([Hugging Face](https://huggingface.co/datasets/McAuley-Lab/Amazon-Reviews-2023)) |
| Kategoria | Sports & Outdoors |
| Format | JSONL (jeden obiekt JSON na linię) |
| Zakres czasowy | maj 1996 – wrzesień 2023 |
| Rozmiar całego zbioru | 570 mln+ recenzji, 48 mln produktów, 33 kategorie |
| Wiersze Bronze (Sports) | ~19 595 170 |
| Cytowanie | Hou et al., *Bridging Language and Items for Retrieval and Recommendation*, arXiv 2024 |

**Pola rekordu:** `rating`, `title`, `text`, `asin`, `parent_asin`, `user_id`, `timestamp`, `helpful_vote`, `verified_purchase`, `images`

---

## Architektura

Projekt opiera się na wzorcu **Medallion** (Bronze → Silver → Gold):

```
@sports_stage (JSONL)
      │
      ▼
┌─────────────┐
│   BRONZE    │  sports_reviews_raw (VARIANT)
│  raw_data   │  wspólny dla całego zespołu — ładowany raz
└─────────────┘
      │
      ▼  (każda metoda ma własny schemat)
┌─────────────┐
│   SILVER    │  oczyszczone, typowane kolumny
│             │  wspólne filtry jakości + review_id = MD5(user_id||asin||timestamp)
└─────────────┘
      │
      ▼
┌─────────────┐
│    GOLD     │  agregaty per parent_asin
│             │  avg_rating, total_reviews, verified_count, ...
└─────────────┘
      │
      ▼
pipeline_run_metrics  ← KPI każdego przebiegu (czas, wiersze, credits)
```

### Infrastruktura

| Zasób | Wartość |
|---|---|
| Baza danych | `amazon_reviews_db` |
| Schematy | `raw_data`, `clean_refresh`, `batch`, `upsert` |
| Warehouse | `project_wh` (X-SMALL, auto-suspend 60 s) |
| Stage | `@sports_stage` (format JSON, STRIP_OUTER_ARRAY = FALSE) |
| Rola | `ACCOUNTADMIN` |

### Wspólne filtry jakości Silver (identyczne dla każdej metody)

```sql
WHERE raw_json:rating::FLOAT BETWEEN 1.0 AND 5.0
  AND LENGTH(raw_json:text::STRING) > 0
  AND raw_json:asin      IS NOT NULL
  AND raw_json:user_id   IS NOT NULL
  AND raw_json:rating    IS NOT NULL
  AND raw_json:timestamp IS NOT NULL
  AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) >= '1996-01-01'
  AND TO_TIMESTAMP_NTZ(raw_json:timestamp::NUMBER / 1000) <= '2024-01-01'
```

---

## Struktura repozytorium

```
├── shared/
│   ├── 01_setup_database.sql        # baza, schematy, warehouse, stage
│   └── 02_bronze_load.sql           # jednorazowe ładowanie Bronze (cały zespół)
│
├── clean_refresh/
│   ├── 01_create_tables.sql         # Silver, Gold, pipeline_run_metrics
│   ├── 02_task_bronze_to_silver.sql # Task 1 (TRUNCATE Silver) + Task 2 (INSERT Silver)
│   ├── 03_task_silver_to_gold.sql   # Task 3 (TRUNCATE Gold)  + Task 4 (INSERT Gold)
│   ├── 04_task_metrics.sql          # Task 5 (logowanie KPI)
│   └── 05_resume_tasks.sql          # RESUME DAG + EXECUTE TASK + monitoring
│
├── batch/
│   ├── create_tables.sql            # Silver, Gold, metrics, batch_state (watermark)
│   ├── load_batch.sql               # procedura process_next_batch()
│   ├── task_batch.sql               # Task opakowujący procedurę (CRON)
│   ├── run_and_KPI.sql              # pętla FOR + wszystkie zapytania KPI
│   └── print_KPI.sql                # szybki podgląd metryk per batch
│
├── upsert/
│   ├── KPI.sql                      # wyliczenie KPI
│   ├── create_tables.sql            # tworzenie tabel dla upserta
│   └── upsert.sql          # pełny pipeline: Silver + Gold
│
└── README.md
```
---

## Kolejność uruchamiania

### Krok 0 — jednorazowa konfiguracja (jeden członek zespołu, ACCOUNTADMIN)

```sql
-- 1. Utwórz bazę, schematy, warehouse, stage
-- shared/01_setup_database.sql

-- 2. Wgraj plik Sports_and_Outdoors.jsonl na stage, a następnie załaduj Bronze
-- shared/02_bronze_load.sql

-- Weryfikacja:
SELECT COUNT(*) FROM amazon_reviews_db.raw_data.sports_reviews_raw;
-- Oczekiwane: ~19 595 170
```

### Krok 1 — Clean Refresh

```sql
-- Uruchamiaj pliki w kolejności 01 → 02 → 03 → 04 → 05
-- schemat: amazon_reviews_db.clean_refresh

-- plik 05 zawiera EXECUTE TASK task_1_truncate_silver (uruchamia cały DAG)
-- monitorowanie:
SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_1_TRUNCATE_SILVER'))
ORDER BY SCHEDULED_TIME DESC;
```

DAG Tasków:
```
task_1_truncate_silver  (root, CRON 0 2 * * * UTC)
        │
task_2_load_silver
        │
task_3_truncate_gold
        │
task_4_load_gold
        │
task_5_log_metrics
```

### Krok 2 — Batch

```sql
-- schemat: amazon_reviews_db.batch

-- 1. create_tables.sql        → tabele + batch_state (next_year = 1996)
-- 2. load_batch.sql           → CREATE PROCEDURE process_next_batch()
-- 3. task_batch.sql           → (opcjonalnie) Task z CRON
-- 4. run_and_KPI.sql          → pętla FOR 1..30, przetwarza roczniki 1996–2023

-- Reset przed czystym benchmarkiem (odkomentuj w run_and_KPI.sql):
TRUNCATE TABLE sports_reviews_silver;
TRUNCATE TABLE sports_reviews_gold;
TRUNCATE TABLE pipeline_run_metrics;
UPDATE batch_state SET next_year = 2000;   -- dataset ma dane od ~2000
```

Jeden przebieg procedury = jeden rocznik → watermark += 1.  
Gold przeliczany tylko dla `parent_asin` dotkniętych w danym roczniku (DELETE + INSERT).

### Krok 3 — Upsert

```sql
-- schemat: amazon_reviews_db.upsert

-- Wersja finalna (pełny medalion + KPI):
-- upsert/upsert_pipeline.sql → CALL process_upsert();

-- Test idempotencji (opcjonalnie):
-- upsert/testing_phase.sql
```

---

## Porównanie metod

| Aspekt | Clean Refresh | Batch | Upsert |
|---|---|---|---|
| Zakres przetwarzania | cały wolumen | jeden rocznik | zmienione + nowe |
| Silver — mechanizm | TRUNCATE + INSERT | append (INSERT) | MERGE |
| Gold — mechanizm | TRUNCATE + INSERT | DELETE + INSERT (dotknięte) | MERGE |
| Obsługa duplikatów | brak (świeże dane) | brak (rozłączne okna) | QUALIFY ROW_NUMBER() |
| Logowanie KPI | Task 5 | wewnątrz procedury | wewnątrz procedury |
| Złożoność kodu | niska | średnia | średnia |
| Idempotencja | tak | tak (per rocznik) | tak |

---

## Wyniki benchmarku

> Uzupełnij tabelę po finalnym uruchomieniu wszystkich metod.  
> Autoryzowane credits: `SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY` (opóźnienie ~3 h).

---

### Szybkie zapytanie porównawcze (cross-schema)

```sql
SELECT * FROM amazon_reviews_db.clean_refresh.pipeline_run_metrics
UNION ALL
SELECT run_id, run_timestamp, method, bronze_row_count, silver_rows_loaded,
       silver_rows_deleted, gold_rows_loaded, duration_sec, credits_used
FROM amazon_reviews_db.batch.pipeline_run_metrics
UNION ALL
SELECT run_id, run_timestamp, method, bronze_row_count, silver_rows_loaded,
       silver_rows_deleted, gold_rows_loaded, duration_sec, credits_used
FROM amazon_reviews_db.upsert.pipeline_run_metrics
ORDER BY run_timestamp DESC;
```

---

## Wymagania

- Konto Snowflake z rolą `ACCOUNTADMIN`
- Warehouse `project_wh` (X-SMALL; wystarczy do projektu, choć upsert generuje bytes spilled ~6,8 GB przy tym rozmiarze)
- Plik `Sports_and_Outdoors.jsonl` wgrany na stage `@sports_stage`
- Dostęp do `SNOWFLAKE.ACCOUNT_USAGE` (potrzebny do autoryzowanych kredytów i `QUERY_HISTORY`)

### Kolejność plików SQL (od zera)

```
1.  shared/01_setup_database.sql
2.  shared/02_bronze_load.sql
3a. clean_refresh/01_create_tables.sql
3b. clean_refresh/02_task_bronze_to_silver.sql
3c. clean_refresh/03_task_silver_to_gold.sql
3d. clean_refresh/04_task_metrics.sql
3e. clean_refresh/05_resume_tasks.sql      ← uruchamia DAG
4a. batch/create_tables.sql
4b. batch/load_batch.sql                   ← tworzy procedurę
4c. batch/run_and_KPI.sql                  ← uruchamia wszystkie batche
5.  upsert/upsert_pipeline.sql             ← CALL process_upsert()
```

---
