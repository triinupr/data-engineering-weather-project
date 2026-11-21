#!/usr/bin/env bash
# Run from the repository root after building and initialising the services.
set -euo pipefail

docker compose config --quiet
docker compose exec airflow-scheduler airflow dags list-import-errors
docker compose exec airflow-scheduler airflow dags test weather_rebuild_from_raw 2026-11-21

before=$(docker compose exec -T postgres psql -U airflow -d airflow -Atc \
  "SELECT (SELECT count(*) FROM bronze.raw_forecasts), (SELECT count(*) FROM bronze.raw_observations), (SELECT count(*) FROM bronze.raw_historical_observations), (SELECT count(*) FROM public_gold.fact_forecast_accuracy), (SELECT count(*) FROM snapshots.station_snapshot)")

# A second replay should preserve raw counts, fact grain and station versions.
docker compose exec airflow-scheduler airflow dags test weather_rebuild_from_raw 2026-11-21
after=$(docker compose exec -T postgres psql -U airflow -d airflow -Atc \
  "SELECT (SELECT count(*) FROM bronze.raw_forecasts), (SELECT count(*) FROM bronze.raw_observations), (SELECT count(*) FROM bronze.raw_historical_observations), (SELECT count(*) FROM public_gold.fact_forecast_accuracy), (SELECT count(*) FROM snapshots.station_snapshot)")
if [[ "$before" != "$after" ]]; then
  printf 'Replay changed counts. Before: %s After: %s\n' "$before" "$after" >&2
  exit 1
fi
printf 'Replay preserved Bronze, fact and snapshot counts: %s\n' "$after"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U airflow -d airflow < sql/extra_credit_b.sql
