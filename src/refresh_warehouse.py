"""Refresh Bronze and dbt under one database lock, shared by all weather DAGs."""

from contextlib import closing
import os
from pathlib import Path
import subprocess
import sys

import psycopg2


def main():
    connection_string = os.environ.get(
        "POSTGRES_CONN_STR", "postgresql://airflow:airflow@postgres:5432/airflow"
    )
    project = os.environ.get("DBT_PROJECT_DIR", "/app/dbt/weather_transformations")
    profiles = os.environ.get("DBT_PROFILES_DIR", "/app/dbt")
    dbt = os.environ.get("DBT_BIN", "/opt/airflow/dbt-venv/bin/dbt")
    with closing(psycopg2.connect(connection_string)) as connection:
        connection.autocommit = True
        with connection.cursor() as cursor:
            # A session-level advisory lock covers the entire refresh. Task pools
            # would only protect individual tasks, allowing different DAG runs to
            # interleave Bronze loads, snapshots and table rebuilds.
            cursor.execute("SET statement_timeout = '30min'")
            print("Waiting for the shared warehouse refresh lock", flush=True)
            cursor.execute("SELECT pg_advisory_lock(20261121, 12)")
            try:
                subprocess.run(
                    [sys.executable, str(Path(__file__).with_name("load_bronze.py"))],
                    check=True,
                )
                flags = ["--project-dir", project, "--profiles-dir", profiles,
                         "--no-use-colors"]
                # build orders snapshots before dependent dimensions, builds all
                # models and runs tests. Nonzero exit codes fail the Airflow task.
                subprocess.run([dbt, "build", *flags], check=True)
                subprocess.run([dbt, "docs", "generate", *flags], check=True)
                subprocess.run(
                    [sys.executable, str(Path(__file__).with_name("export_warehouse_schema.py")),
                     "--output", str(Path(project) / "target" / "warehouse_schema.sql")],
                    check=True,
                )
                print("Bronze, dbt models/tests, documentation and schema export succeeded", flush=True)
            finally:
                cursor.execute("SELECT pg_advisory_unlock(20261121, 12)")


if __name__ == "__main__":
    main()
