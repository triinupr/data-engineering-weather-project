#!/usr/bin/env bash
# Run from the repository root after building and initialising the services.
set -euo pipefail

docker compose config --quiet
printf 'Checking Airflow DAG imports...\n'
docker compose exec -T airflow-scheduler python - <<'PY'
from airflow.models import DagBag

bag = DagBag(include_examples=False)
if bag.import_errors:
    for path, error in bag.import_errors.items():
        print(f"{path}:\n{error}")
    raise SystemExit(1)
if "weather_rebuild_from_raw" not in bag.dags:
    raise SystemExit("weather_rebuild_from_raw was not found")
print("Airflow DAG imports passed")
PY

# Airflow 2.10 uses a test's logical date as its run start time. A fixed old
# date can therefore trigger dagrun_timeout while the task itself succeeds.
# Omit the date so each replay starts now and has a separate run identifier.
printf 'Running the first warehouse replay...\n'
docker compose exec -T airflow-scheduler airflow dags test weather_rebuild_from_raw

before=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U airflow -d airflow -Atc \
  "SELECT (SELECT count(*) FROM bronze.raw_forecasts), (SELECT count(*) FROM bronze.raw_observations), (SELECT count(*) FROM bronze.raw_historical_observations), (SELECT count(*) FROM public_gold.fact_forecast_accuracy), (SELECT count(*) FROM snapshots.station_snapshot)")

# A second replay should preserve raw counts, fact grain and station versions.
printf 'Running the second warehouse replay...\n'
docker compose exec -T airflow-scheduler airflow dags test weather_rebuild_from_raw
after=$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U airflow -d airflow -Atc \
  "SELECT (SELECT count(*) FROM bronze.raw_forecasts), (SELECT count(*) FROM bronze.raw_observations), (SELECT count(*) FROM bronze.raw_historical_observations), (SELECT count(*) FROM public_gold.fact_forecast_accuracy), (SELECT count(*) FROM snapshots.station_snapshot)")
if [[ "$before" != "$after" ]]; then
  printf 'Replay changed counts. Before: %s After: %s\n' "$before" "$after" >&2
  exit 1
fi
printf 'Replay preserved Bronze, fact and snapshot counts: %s\n' "$after"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U airflow -d airflow < sql/extra_credit_b.sql
