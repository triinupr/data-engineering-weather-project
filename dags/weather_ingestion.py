from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
import pendulum

TALLINN = pendulum.timezone("Europe/Tallinn")
START_DATE = datetime(2026, 10, 1, tzinfo=TALLINN)

with DAG(
    dag_id="weather_observations_hourly",
    description="Collect Estonian Weather Service observations every hour",
    start_date=START_DATE,
    schedule="5 * * * *",
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=1),
    default_args={"retries": 2, "retry_delay": timedelta(minutes=2)},
    tags=["data-engineering", "weather"],
) as observations_dag:
    collect = BashOperator(
        task_id="collect_observations",
        # Use an Airflow interval identifier for retry-safe collection.
        bash_command='python /app/src/ingest.py observations --date {{ data_interval_end.in_timezone("UTC").strftime("%Y%m%dT%H%M%SZ") }}',
    )
    refresh = BashOperator(
        task_id="refresh_warehouse",
        bash_command="python /app/src/refresh_warehouse.py",
        execution_timeout=timedelta(minutes=50),
    )
    collect >> refresh

with DAG(
    dag_id="weather_forecast_daily",
    description="Collect Estonian Weather Service forecast daily at 13:00 Estonia time",
    start_date=START_DATE,
    schedule="0 13 * * *",
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=1),
    default_args={"retries": 2, "retry_delay": timedelta(minutes=2)},
    tags=["data-engineering", "weather"],
) as forecast_dag:
    collect = BashOperator(
        task_id="collect_forecast",
        # Use an Airflow interval identifier for retry-safe collection.
        bash_command='python /app/src/ingest.py forecast --date {{ data_interval_end.in_timezone("UTC").strftime("%Y%m%dT%H%M%SZ") }}',
    )

    refresh = BashOperator(
        task_id="refresh_warehouse",
        bash_command="python /app/src/refresh_warehouse.py",
        execution_timeout=timedelta(minutes=50),
    )
    collect >> refresh
