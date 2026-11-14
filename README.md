# Weather Forecast Accuracy – Data Engineering Project

This project collects weather forecast and observation data from the Estonian Environment Agency for analysing weather forecast accuracy. It is a group project for the University of Tartu Data Engineering course.

## Team members

- Gailin Savi
- Eliise Ševtšenko
- Karoliine Inselberg
- Triinu Prants

## Data sources

- Estonian Weather Service live forecast XML
- Estonian Weather Service live observations XML
- Environment Portal validated historical hourly climate data

Raw source data is preserved before later parsing and transformation.

## Sample data

The repository contains example responses from the Estonian Environment

Agency Weather Service under `data/sample/`.
- `forecast_sample.xml` – example daily forecast XML response.
- `observations_sample.xml` – example weather station observation XML response.

These files demonstrate the structure of the source datasets and can be
used for development and testing without retrieving new data.
Continuously collected raw data is stored under `data/raw/` and is not
committed to GitHub.

## Requirements

1. Install and run Docker Desktop.
2. Install Git if it is not already installed.
3. No local Python installation is required.

## Initial setup

Clone the repository and enter it:

    git clone <REPOSITORY-URL>
    cd data-engineering-weather-project

Build the Docker images:

    docker compose build

## Manual live-ingestion test

These commands are useful for checking that data retrieval works without Airflow.

### Forecast

    docker compose run --rm ingestion python src/ingest.py forecast

The XML appears in:

    data/raw/forecasts/

### Observations

    docker compose run --rm ingestion python src/ingest.py observations

The XML appears in:

    data/raw/observations/

Verify the files:

    ls data/raw/forecasts
    ls data/raw/observations

## Historical observations - one-time batch load

Historical observations are a bootstrap dataset and are intentionally **not** an Airflow recurring task. The command uses the Environment Portal's official `f_kliima_tund` hourly climate-data service by default.

The service has a response-size limit, so the script automatically downloads the selected month in pages and preserves each page as a separate raw JSON response.

Download one month, for example September 2026:

    docker compose run --rm ingestion python src/ingest.py historical --year 2026 --month 9

The raw files appear under:

    data/raw/historical_observations/2026_09/

Repeat the command for each additional month that the project needs. Existing historical raw files are never overwritten.

If the official service URL changes, it can be overridden explicitly:

    docker compose run --rm -e HISTORICAL_OBSERVATIONS_URL=<URL> ingestion python src/ingest.py historical --year 2026 --month 9

## Automatic data collection with Airflow

Airflow runs two independent schedules:

- observations: every hour at minute 5;
- forecast: every day at 13:00 Estonia time (`Europe/Tallinn`).

Historical observations are not scheduled.

### 1. Make sure Docker Desktop is running

Open Docker Desktop and wait until it reports that Docker is running.

### 2. Build the images

From the repository root:

    docker compose build

### 3. Initialize Airflow

Run this once when setting up the project for the first time:

    docker compose up airflow-init

Wait until it finishes successfully and returns to the terminal prompt.

### 4. Start automatic collection (postgreSQL, Airflow and pgAdmin in the backround)

    docker compose up -d postgres airflow-webserver airflow-scheduler pgadmin


Check that the services are running:

    docker compose ps
    
Ensure container write permissions on the mounted `data/` volume (especially on Windows):

    docker compose exec -u root airflow-webserver bash -c "mkdir -p /app/data/raw/forecasts /app/data/raw/observations /app/data/raw/historical_observations && chmod 

* **Airflow Web UI:** [http://localhost:8080/](http://localhost:8080/) (`admin` / `admin`)
* **pgAdmin Web UI:** [http://localhost:5051/](http://localhost:5051/) (`admin@example.com` / `admin`)

### 5. Open Airflow

Open this address in a browser:

    http://localhost:8080

Login for this local course environment:

- username: `admin`
- password: `admin`

You should see:

- `weather_observations_hourly`
- `weather_forecast_daily`

The DAGs are configured to be active when created. If either appears paused in the UI, switch it on.

### 6. Check that collection works

You can trigger either DAG manually from the Airflow UI instead of waiting for its next scheduled time.

Then check:

    ls data/raw/forecasts
    ls data/raw/observations

### 7. View status and logs

Show container status:

    docker compose ps

Follow scheduler logs:

    docker compose logs -f airflow-scheduler

Follow webserver logs:

    docker compose logs -f airflow-webserver

Press `Ctrl+C` to stop following logs. This does not stop the containers.

### 8. Stop automatic collection

    docker compose down

This stops the containers but does **not** delete the collected raw weather data or the named Airflow/PostgreSQL volumes.

Do not use `docker compose down -v` unless you intentionally want to delete the Airflow/PostgreSQL state.

## Important limitation of local scheduling

Automatic collection only runs while the computer is on and Docker Desktop and the Airflow containers are running. If the laptop is asleep or switched off, the scheduled retrieval will not happen. `catchup` is disabled because a live XML endpoint cannot recreate a forecast or observation snapshot that was missed in the past.

For reliable long-running collection, the same setup should eventually run on an always-on machine/server.

## Raw-data directories

    data/raw/forecasts/
    data/raw/observations/
    data/raw/historical_observations/

Files under `data/raw/` are intentionally excluded from Git and should not be committed to GitHub.

## Data Storage (PostgreSQL & Medallion Architecture)

### Database Choice Rationale
We selected **PostgreSQL (v16)** as the analytical data warehouse for this project for the following reasons:
* **Native Semi-Structured Data Support:** The source APIs return raw payloads in both **XML** (forecasts and hourly observations) and **JSON** (historical observations). PostgreSQL natively supports `XML` and `JSONB` column types, allowing raw payloads to be stored unaltered in the Bronze layer and parsed directly in SQL/dbt using `xpath()` and JSONB functions.
* **Medallion Architecture Separation:** PostgreSQL schemas cleanly separate data processing stages into `bronze` (raw payloads), `silver` (cleaned and parsed staging models), and `gold` (analytical star schema).
* **Reliability & Ecosystem Integration:** PostgreSQL provides ACID-compliant transactions for idempotent batch loading (`ON CONFLICT DO NOTHING`) and integrates seamlessly with both **Apache Airflow** and **dbt** within a single Docker Compose stack.

### Schema & Bronze Layer Structure
The database (`airflow`) is organized into three schemas:
* **`bronze`**: Stores raw, unmodified API responses along with ingestion metadata (`file_name`, `retrieved_at`).
  * `bronze.raw_forecasts` (`raw_payload XML`) — weather forecast XML snapshots.
  * `bronze.raw_observations` (`raw_payload XML`) — hourly station observation XML snapshots.
  * `bronze.raw_historical_observations` (`raw_payload JSONB`) — paginated monthly historical climate JSON responses.
* **`silver`**: Intermediate cleaned and structured models built via `dbt`.
* **`gold`**: Final dimensional star schema (`Fact_ForecastAccuracy` and dimension tables) built via `dbt`.

### Loading Raw Data into PostgreSQL
Run the idempotent Bronze loader script to initialize the schemas/tables (if not yet created) and load all local files from `/app/data/raw/` into PostgreSQL:

```bash
docker compose exec airflow-webserver python /app/src/load_bronze.py
```

Already loaded files are safely skipped based on their unique `file_name`.

---

## Inspecting the Database (pgAdmin)

1. Open [http://localhost:5051/](http://localhost:5051/) and log in (`admin@example.com` / `admin`).
2. Select **Object → Register → Server** and configure the connection:
   * **General → Name:** `weather-db`
   * **Connection → Host name/address:** `postgres`
   * **Connection → Port:** `5432`
   * **Connection → Maintenance database:** `airflow`
   * **Connection → Username / Password:** `airflow` / `airflow`
3. Open **Query Tool** on the `airflow` database to verify loaded row counts:
   ```sql
   SELECT 'raw_forecasts' AS table_name, COUNT(*) AS rows FROM bronze.raw_forecasts
   UNION ALL
   SELECT 'raw_observations', COUNT(*) FROM bronze.raw_observations
   UNION ALL
   SELECT 'raw_historical_observations', COUNT(*) FROM bronze.raw_historical_observations;
   ```

## Transformation (dbt)

### Overview

The Transformation layer is implemented using **dbt (data build tool)** and PostgreSQL. Its purpose is to transform raw weather forecast and observation data from the Bronze layer into structured tables suitable for analysing forecast accuracy.

The transformation pipeline follows the Medallion Architecture:

- **Bronze:** Raw XML weather forecasts and observations stored in PostgreSQL.
- **Silver:** Parsed and cleaned weather data.
- **Intermediate:** Prepared and aggregated data used by the final analytical models.
- **Gold:** A dimensional star schema containing one fact table and five dimension tables.

All transformations are defined as SQL models in the `dbt/weather_transformations/` directory. Dependencies between models are managed using dbt's `ref()` function.

### Silver Layer

The Silver layer contains two staging models:

| Model | Description |
|---|---|
| `stg_forecasts` | Extracts and structures forecast information from the raw forecast XML data. |
| `stg_observations` | Extracts and structures weather station measurements from the raw observation XML data. |

### Intermediate Layer

The intermediate layer contains three models:

| Model | Description |
|---|---|
| `int_observations` | Prepares weather station observations for further processing. |
| `int_daily_observations` | Aggregates observations into daily Day/Night periods for comparison with forecasts. |
| `int_latest_forecasts` | Prepares forecast records for the analytical models. |

For this project, daytime is defined as 06:00–18:00 and nighttime as 18:00–06:00 in Estonian local time. These are project-specific assumptions, as explained in the Assumptions section of this README.

### Gold Layer – Star Schema

The Gold layer contains the final analytical tables used for forecast accuracy analysis.

**Fact table: `fact_forecast_accuracy`**

This table combines weather forecasts with the corresponding weather station observations when available.

Each row represents a weather forecast snapshot for a specific forecast date, Day/Night period and forecast location, linked to a mapped weather station and its aggregated observations when available.

The fact table supports comparisons between forecasted and observed weather conditions.

**Dimension tables:**

| Dimension | Description |
|---|---|
| `dim_date` | Forecast dates and related date attributes. |
| `dim_period` | Day and Night forecast periods. |
| `dim_forecast_location` | Forecast locations. |
| `dim_station` | Weather stations mapped to forecast locations. |
| `dim_weather_phenomenon` | Weather phenomena included in the forecasts. |

Together, the fact table and five dimensions form the analytical star schema.

### Snapshot – Slowly Changing Dimension Type 2

A dbt snapshot named `station_snapshot` is implemented to track changes in weather station information.

The snapshot uses the dbt `check` strategy to detect changes in the `wmo_code` field.

Snapshot history is used by `dim_station` to represent station records and their validity periods.

### Data Quality Tests and Documentation

Data quality tests are defined in the dbt project using YAML configuration files.

The tests include checks for missing values, uniqueness and relationships between tables.

During development, **31 dbt tests passed successfully**.

Model and column documentation is provided in `models/marts/schema.yml`.

### Running the Transformation Pipeline

**The transformation models are not automatically executed by starting Docker Compose.**

Before running dbt, PostgreSQL must be running and the Bronze tables must contain weather data.

All commands below should be executed from the repository root directory.

**Step 1 – Start the required services**

If this is the first setup, follow the Docker build and Airflow initialization instructions earlier in this README.

Start PostgreSQL and Airflow:

```bash
docker compose up -d postgres airflow-webserver airflow-scheduler pgadmin
```

**Step 2 – Collect weather data**

If the local `data/raw/` directories are empty, retrieve forecast and observation data:

```bash
docker compose run --rm ingestion python src/ingest.py forecast
docker compose run --rm ingestion python src/ingest.py observations
```

For meaningful forecast accuracy analysis, multiple forecast and observation snapshots are needed. A single collection run will not reproduce the historical dataset used during development.

**Step 3 – Load raw data into PostgreSQL (Bronze)**

```bash
docker compose exec airflow-webserver python /app/src/load_bronze.py
```

This creates the necessary Bronze tables if they do not already exist and loads the locally available raw data. Previously loaded files are skipped.

**Step 4 – Run the dbt snapshot**

```bash
docker compose run --rm dbt dbt snapshot --project-dir /app/dbt/weather_transformations
```

This creates or updates the station snapshot used for tracking changes in station information.

**Step 5 – Run the dbt models**

```bash
docker compose run --rm dbt dbt run --project-dir /app/dbt/weather_transformations
```

This executes the dbt models in dependency order and creates or updates the Silver, Intermediate and Gold tables.

**Step 6 – Run data quality tests**

```bash
docker compose run --rm dbt dbt test --project-dir /app/dbt/weather_transformations
```

The command checks whether the implemented data quality tests pass.

### Verifying the Results

The resulting tables can be inspected using pgAdmin at [http://localhost:5051/](http://localhost:5051/).

The final fact table and dimensions are available in the `public_gold` schema.

For example, the following SQL query returns the number of rows in the fact table:

```sql
SELECT COUNT(*)
FROM public_gold.fact_forecast_accuracy;
```

### Assumptions for forecast accuracy calculations
For this project, daytime is defined as 06:00–18:00 and nighttime as 18:00–06:00 (Estonian local time). The observed maximum temperature during the daytime period and minimum temperature during the nighttime period are compared with the corresponding forecast temperatures.

These time intervals are project-specific assumptions and have not been verified against the official definitions used by the Estonian Weather Service. Therefore, the calculated forecast errors should be interpreted within the scope of these assumptions rather than as official forecast accuracy measurements.
