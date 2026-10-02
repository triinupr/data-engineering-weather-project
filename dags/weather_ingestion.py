from datetime import datetime
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
    tags=["data-engineering", "weather"],
) as observations_dag:
    BashOperator(
        task_id="collect_observations",
        bash_command="python /app/src/ingest.py observations",
    )

with DAG(
    dag_id="weather_forecast_daily",
    description="Collect Estonian Weather Service forecast daily at 13:00 Estonia time",
    start_date=START_DATE,
    schedule="0 13 * * *",
    catchup=False,
    tags=["data-engineering", "weather"],
) as forecast_dag:
    BashOperator(
        task_id="collect_forecast",
        bash_command="python /app/src/ingest.py forecast",
    )
