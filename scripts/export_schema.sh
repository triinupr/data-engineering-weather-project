#!/usr/bin/env bash
# Run from the repository root after a successful warehouse build.
set -euo pipefail
mkdir -p sql
schema_tmp=$(mktemp sql/warehouse_schema.XXXXXX)
trap 'rm -f "$schema_tmp"' EXIT
docker compose exec -T airflow-scheduler python /app/src/export_warehouse_schema.py > "$schema_tmp"
mv "$schema_tmp" sql/warehouse_schema.sql
printf 'Updated sql/warehouse_schema.sql\n'
