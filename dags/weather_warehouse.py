"""Manual historical ingestion and archived-file replay, including Gold refresh."""

from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.models.param import Param
from airflow.operators.bash import BashOperator

DEFAULTS = {"owner": "triinu", "retries": 2, "retry_delay": timedelta(minutes=2)}

with DAG(
    dag_id="weather_historical_month",
    description="Retrieve a month of historical JSON and refresh the dimensional model",
    start_date=pendulum.datetime(2026, 10, 1, tz="Europe/Tallinn"),
    schedule=None,
    is_paused_upon_creation=False,
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=2),
    default_args=DEFAULTS,
    params={
        "year": Param(2026, type="integer", minimum=1900, maximum=2100),
        "month": Param(10, type="integer", minimum=1, maximum=12),
    },
    tags=["weather", "historical", "json", "dbt"],
) as historical_dag:
    collect = BashOperator(
        task_id="collect_historical_json",
        bash_command='python /app/src/ingest.py historical --year "$HISTORY_YEAR" --month "$HISTORY_MONTH"',
        env={"HISTORY_YEAR": "{{ params.year }}", "HISTORY_MONTH": "{{ params.month }}"},
        append_env=True,
        execution_timeout=timedelta(hours=1),
    )
    refresh = BashOperator(
        task_id="refresh_warehouse",
        bash_command="python /app/src/refresh_warehouse.py",
        execution_timeout=timedelta(hours=1),
    )
    collect >> refresh

with DAG(
    dag_id="weather_rebuild_from_raw",
    description="Replay existing raw XML/JSON files through Bronze, dbt and tests",
    start_date=pendulum.datetime(2026, 10, 1, tz="Europe/Tallinn"),
    schedule=None,
    is_paused_upon_creation=False,
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=1),
    default_args=DEFAULTS,
    tags=["weather", "replay", "dbt"],
) as replay_dag:
    BashOperator(
        task_id="refresh_warehouse",
        bash_command="python /app/src/refresh_warehouse.py",
        execution_timeout=timedelta(minutes=50),
    )
