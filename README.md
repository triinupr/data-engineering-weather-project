# Weather Forecast Accuracy – Data Engineering Project

This University of Tartu group project compares Estonian weather forecasts with observations. Team: Gailin Savi, Eliise Ševtšenko, Karoliine Inselberg and Triinu Prants.

The implementation uses Python, Airflow 2.10.5, PostgreSQL 16 and dbt Core 1.10.15 with dbt-postgres 1.9.1. dbt runs in an isolated Python environment inside Airflow, following the CLI orchestration approach in course practical `04_dbt`.

## Sources and layers

| Source | Acquisition | Purpose |
|---|---|---|
| Estonian Weather Service forecast XML | Daily at 13:00, Europe/Tallinn | Forecast snapshots |
| Estonian Weather Service observations XML | Hourly at minute 5, Europe/Tallinn | Live station observations and station metadata |
| Environment Portal `f_kliima_tund` JSON | Manually triggered, one calendar month | Validated hourly air temperatures, metric `TA` |

Raw XML files and complete JSON response pages are archived under `data/raw/` and excluded from Git. `data/sample/` contains the two original XML examples.

| Layer | PostgreSQL location | Contents |
|---|---|---|
| Bronze | `bronze` | `raw_forecasts`, `raw_observations`, `raw_historical_observations` |
| Silver | `public_silver` | XML staging views, JSON extraction and source reconciliation |
| Intermediate | `public` | Existing forecast selection, station mapping and period aggregation views |
| Gold | `public_gold` | `fact_forecast_accuracy` and five dimensions |
| Station history | `snapshots` | `station_snapshot`, using the check strategy on WMO code |

The loader also creates empty `silver` and `gold` schemas. dbt uses its default schema naming convention, so its actual configured Silver/Gold models are in `public_silver` and `public_gold`.

PostgreSQL suits this small batch workload: it provides native XML/XPath and JSONB extraction, joins, window functions, transactions and dbt support in the existing Compose environment. File names uniquely identify Bronze payloads; repeated loading uses `ON CONFLICT DO NOTHING`. Gold tables are rebuilt on refresh, while the station snapshot retains versions. This supports repeated updates at the project’s scale; the Gold fact is not an incremental dbt model.

## Setup

Install Git and Docker Desktop, and start Docker Desktop. No host Python installation is required for the Docker pipeline.

```bash
git clone https://github.com/triinupr/data-engineering-weather-project.git
cd data-engineering-weather-project
mkdir -p data/raw/forecasts data/raw/observations data/raw/historical_observations
docker compose --profile tools build
docker compose up -d postgres
docker compose run --rm airflow-init
docker compose up -d airflow-webserver airflow-scheduler pgadmin
docker compose ps
```

For an existing checkout, start at `mkdir` instead of cloning again. If Linux bind-mount ownership causes a permission error, set the `data/` and `dbt/` directories writable by the container Airflow user (UID 50000); avoid making the whole repository world writable.

| Service | Address | Local course credentials |
|---|---|---|
| Airflow | http://localhost:8080/ | `admin` / `admin` |
| pgAdmin | http://localhost:5051/ | `admin@example.com` / `admin` |
| PostgreSQL, from containers | `postgres:5432`, database `airflow` | `airflow` / `airflow` |

These credentials are for the local course setup. In pgAdmin, register PostgreSQL with host `postgres`, port `5432` and the credentials above. PostgreSQL is not published to a host port.

New recurring DAGs start paused, so saved data can be loaded and tested before enabling collection. The two manual DAGs start unpaused and have no automatic schedule, so explicit triggers can run immediately. Existing DAG pause state is stored in Airflow and is retained during upgrades.

## Restore the supplied raw backup

The supplied `../data/raw/` directory contains the XML backup through 12 November 2026. Copy it into this repository before replaying:

```bash
rsync -av ../data/raw/ data/raw/
```

Keep the original backup. The supplied folder has 44 forecast XML files and 961 observation XML files; it does not contain historical JSON. Historical data must be downloaded separately for extra-credit evidence.

Trigger `weather_rebuild_from_raw` from the Airflow UI, or test it directly:

```bash
docker compose exec airflow-scheduler airflow dags test weather_rebuild_from_raw
```

This loads Bronze, executes `dbt build` (snapshots, models and tests in dependency order), then generates dbt documentation. All three stages must succeed for the task to succeed.

## Airflow orchestration

| DAG | Schedule | Task order |
|---|---|---|
| `weather_observations_hourly` | `5 * * * *`, Europe/Tallinn | `collect_observations` → `refresh_warehouse` |
| `weather_forecast_daily` | `0 13 * * *`, Europe/Tallinn | `collect_forecast` → `refresh_warehouse` |
| `weather_historical_month` | Manual; parameters `year`, `month` | `collect_historical_json` → `refresh_warehouse` |
| `weather_rebuild_from_raw` | Manual; no API calls | `refresh_warehouse` |

```mermaid
flowchart TD
    subgraph observations[weather_observations_hourly]
        O[collect_observations] --> OR[refresh_warehouse]
    end
    subgraph forecasts[weather_forecast_daily]
        F[collect_forecast] --> FR[refresh_warehouse]
    end
    subgraph historical[weather_historical_month]
        H[collect_historical_json] --> HR[refresh_warehouse]
    end
    subgraph replay[weather_rebuild_from_raw]
        RR[refresh_warehouse]
    end
```

Each `refresh_warehouse` task calls `src/refresh_warehouse.py`. A PostgreSQL advisory lock serializes its entire Bronze load, dbt build and documentation generation across all four DAGs. This prevents concurrent snapshot updates and conflicting Gold table rebuilds. Each DAG allows one active run and retries failed tasks twice. DAGs use `catchup=False` because live endpoints provide current data and cannot recreate old forecasts.

Enable the two live schedules after replay succeeds:

```bash
docker compose exec airflow-scheduler airflow dags unpause weather_observations_hourly
docker compose exec airflow-scheduler airflow dags unpause weather_forecast_daily
```

Live collection takes a date/time run identifier from Airflow. The actual UTC retrieval timestamp remains first in the filename, so Gailin’s forecast timestamp extraction still works. A retry reuses the saved file for that run identifier without fetching a different live response. Files are published atomically and not overwritten. A manual trigger of a live DAG collects current weather; it does not backfill the trigger’s historical date.

## Historical JSON: extra-credit B

In Airflow, trigger `weather_historical_month` with `year=2026`, `month=10`. October overlaps the saved forecast dataset, so historical measurements can contribute to forecast accuracy. September-only observations cannot by themselves demonstrate a forecast comparison with the October–November backup.

Command-line alternative:

```bash
docker compose exec airflow-scheduler airflow dags trigger weather_historical_month \
  --conf '{"year":2026,"month":10}'
```

The ingestion script filters `TA` (hourly temperature), paginates the API, validates each record and saves the original JSON arrays. It publishes the month directory only after every page succeeds. Empty API responses fail with an explanatory error. Repeating an archived month reuses its files. Existing manually copied month directories are treated as complete archives, so copy complete months only. To ingest a revised version, preserve the original archive outside `data/raw/` before explicitly replacing it; the current loader does not update a payload already loaded under the same file name.

The existing Bronze loader stores JSON pages as JSONB. New dbt models expand response arrays, type selected fields, convert UTC timestamps to local time and select the latest source revision. At an overlapping station/hour, a non-null historical temperature takes priority; a live phenomenon is kept when available. The existing six-station mapping, period aggregation, dimensions and fact then consume the combined observations.

Run the supporting evidence queries and save the actual output after the historical DAG succeeds:

```bash
mkdir -p results
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U airflow -d airflow \
  < sql/extra_credit_b.sql > results/extra_credit_b.txt
```

The fourth query must show a positive matched-forecast count to demonstrate JSON contributing to Gold. A successful build with zero historical files is useful for XML replay but does not substantiate the JSON extra-credit claim.

## dbt models and dependencies

```mermaid
flowchart TD
    BXML[Bronze XML] --> SF[stg_forecasts]
    BXML --> SO[stg_observations]
    BXML --> SS[station_snapshot]
    BJSON[Bronze JSONB] --> SH[stg_historical_observations]
    SO --> U[int_unified_observations]
    SH --> U
    U --> IO[int_observations]
    IO --> ID[int_daily_observations]
    SF --> IF[int_latest_forecasts]
    SF --> D[Date, period and location dimensions]
    SS --> DS[dim_station]
    BXML --> DP[dim_weather_phenomenon]
    IF --> FACT[fact_forecast_accuracy]
    ID --> FACT
    D --> FACT
    DS --> FACT
    DP --> FACT
```

The fact grain remains one forecast snapshot × forecast date × Day/Night period × forecast location, linked to a mapped station and observations when available. Dimensions are `dim_date`, `dim_period`, `dim_forecast_location`, `dim_station` and `dim_weather_phenomenon`. `int_latest_forecasts` retains its existing name and preserves snapshots rather than filtering to a single latest forecast.

The fact includes temperature errors, precipitation occurrence indicators and `phenomenon_match`, plus separate observation counts and eligibility flags for all three KPIs. Forecast phenomena come from the individual forecast location. `retrieved_at` is PostgreSQL `TIMESTAMPTZ`, parsed explicitly as UTC; `dim_date.season` is `TEXT` with meteorological seasons. The fact grain is unchanged.

| KPI | Definition | Eligible rows |
|---|---|---|
| Temperature MAE | Sum of `absolute_error` / number of eligible rows | `is_temperature_eligible = true` |
| Precipitation occurrence accuracy | 100 × eligible rows with `precipitation_match = true` / all eligible rows | `is_precipitation_eligible = true` |
| Phenomenon accuracy | 100 × eligible rows with `phenomenon_match = true` / all eligible rows | `is_phenomenon_eligible = true` |

If there are no eligible rows, the KPI is undefined (null). Every eligible comparison requires a forecast collected before the period starts, a completed period, a mapped station and complete coverage for that metric. Expected coverage is the number of UTC hours between local period boundaries: normally 12, but 11 or 13 for daylight-saving transition nights. Unknown amounts/descriptions remain null and are excluded from that metric's denominator; a known incorrect prediction remains eligible and counts as a mismatch. Ineligible error and match fields are null.

Precipitation is summed over its measurement intervals: the value reported at 18:00 covers the preceding hour and closes the Day period. Temperature and phenomenon use the hourly point samples. The observed phenomenon category is the most frequent recognised category over the period, independently of the temperature extreme. Category ties use alphabetical order; the representative description within the winning category uses frequency, then alphabetical order. Matching uses broad standardised categories, not exact wording. Unclassified `Other` values do not establish weather/precipitation eligibility. Missing precipitation and phenomena at Kuressaare linn therefore do not become dry weather or successful matches.

The combined observations are materialised in Silver once per refresh. Their UTC hour key preserves both occurrences of the repeated autumn clock hour. The historical JSON source supplies temperature only; precipitation and phenomena remain sourced from XML. Analytical query files and results are maintained separately by the team.

Day is assumed to be 06:00–18:00 and Night the preceding 18:00–06:00, in Estonian local time. These are project assumptions, not verified official forecast-period definitions. The historical source supplies hourly temperature samples, matching the live sample approach; it does not add within-hour maximum/minimum metrics. Only periods with all expected hourly samples are eligible for each metric. Hourly temperature samples still do not capture extrema occurring between samples; this limitation should accompany the reported results.

### Manual dbt commands

Airflow normally runs the complete build. For diagnosis, use the separate tools service:

```bash
docker compose run --rm dbt dbt debug --project-dir /app/dbt/weather_transformations
docker compose run --rm dbt dbt build --project-dir /app/dbt/weather_transformations
docker compose run --rm dbt dbt docs generate --project-dir /app/dbt/weather_transformations
docker compose run --rm --service-ports -p 8081:8081 dbt \
  dbt docs serve --project-dir /app/dbt/weather_transformations --host 0.0.0.0 --port 8081
```

Open http://localhost:8081/ for the dbt catalog and lineage graph. Avoid running manual dbt commands while scheduled DAGs are refreshing the warehouse: the advisory lock is applied by `refresh_warehouse.py`. Generated artifacts are in `dbt/weather_transformations/target/` and excluded by the existing dbt `.gitignore`.

### Warehouse schema DDL

`sql/warehouse_schema.sql` is a generated schema-only snapshot of the actual warehouse. It excludes Airflow metadata tables. dbt models remain the source for transformations; do not maintain a second handwritten Gold schema.

A successful Airflow refresh writes the current export to `dbt/weather_transformations/target/warehouse_schema.sql`. To update the committed snapshot from a running warehouse:

```bash
bash scripts/export_schema.sh
```

The correctly named profile is `dbt/profiles.yml`. The original `dbt/profiles` is retained unchanged for reference and is not read by dbt.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RAW_DATA_DIR` | `/app/data/raw` | Ingestion and Bronze input directory |
| `POSTGRES_CONN_STR` | `postgresql://airflow:airflow@postgres:5432/airflow` | Bronze loader and warehouse lock |
| `DBT_PROJECT_DIR` | `/app/dbt/weather_transformations` | Project invoked by Airflow |
| `DBT_PROFILES_DIR` | `/app/dbt` | Directory containing `profiles.yml` |
| `DBT_BIN` | `/opt/airflow/dbt-venv/bin/dbt` | Isolated dbt executable in Airflow |
| `DBT_HOST`, `DBT_PORT` | `postgres`, `5432` | dbt connection |
| `DBT_USER`, `DBT_PASSWORD`, `DBT_DATABASE` | `airflow` | dbt connection credentials/database |
| `HISTORICAL_OBSERVATIONS_URL` | `https://keskkonnaandmed.envir.ee/f_kliima_tund` | Historical JSON endpoint |

Compose currently sets the local database values explicitly. For a different deployment, update the Compose environment consistently for PostgreSQL, Airflow metadata, the loader and dbt; setting only a host shell variable does not override a literal Compose value.

## Verification

Offline ingestion regression tests require Python 3.12 and `requests`:

```bash
python3 -m unittest discover -s tests -v
```

With Docker running and the raw archive restored, test replay and idempotency. Pause the recurring collection DAGs during verification so incoming data does not change the row counts between replays:

```bash
bash scripts/verify_pipeline.sh
```
