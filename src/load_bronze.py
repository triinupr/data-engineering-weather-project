from pathlib import Path
import os
import psycopg2

RAW_DATA_DIR = Path(os.getenv("RAW_DATA_DIR", "/app/data/raw"))
DB_CONN_STR = os.getenv(
    "POSTGRES_CONN_STR",
    "postgresql://airflow:airflow@postgres:5432/airflow"
)


def load_files_to_bronze():
    conn = psycopg2.connect(DB_CONN_STR)
    cursor = conn.cursor()

    try:
        # 0. Ensure Medallion schemas and Bronze tables exist
        cursor.execute("""
            CREATE SCHEMA IF NOT EXISTS bronze;
            CREATE SCHEMA IF NOT EXISTS silver;
            CREATE SCHEMA IF NOT EXISTS gold;

            CREATE TABLE IF NOT EXISTS bronze.raw_forecasts (
                id BIGSERIAL PRIMARY KEY,
                file_name VARCHAR(255) UNIQUE NOT NULL,
                retrieved_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                raw_payload XML NOT NULL
            );

            CREATE TABLE IF NOT EXISTS bronze.raw_observations (
                id BIGSERIAL PRIMARY KEY,
                file_name VARCHAR(255) UNIQUE NOT NULL,
                retrieved_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                raw_payload XML NOT NULL
            );

            CREATE TABLE IF NOT EXISTS bronze.raw_historical_observations (
                id BIGSERIAL PRIMARY KEY,
                file_name VARCHAR(255) UNIQUE NOT NULL,
                retrieved_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                raw_payload JSONB NOT NULL
            );
        """)

        # 1. Load forecast XML files
        forecasts_dir = RAW_DATA_DIR / "forecasts"
        if forecasts_dir.exists():
            for xml_file in sorted(forecasts_dir.glob("*.xml")):
                content = xml_file.read_text(encoding="utf-8")
                cursor.execute(
                    """
                    INSERT INTO bronze.raw_forecasts (file_name, raw_payload)
                    VALUES (%s, %s)
                    ON CONFLICT (file_name) DO NOTHING;
                    """,
                    (xml_file.name, content),
                )

        # 2. Load observation XML files
        observations_dir = RAW_DATA_DIR / "observations"
        if observations_dir.exists():
            for xml_file in sorted(observations_dir.glob("*.xml")):
                content = xml_file.read_text(encoding="utf-8")
                cursor.execute(
                    """
                    INSERT INTO bronze.raw_observations (file_name, raw_payload)
                    VALUES (%s, %s)
                    ON CONFLICT (file_name) DO NOTHING;
                    """,
                    (xml_file.name, content),
                )

        # 3. Load historical JSON files (across all month subfolders)
        historical_dir = RAW_DATA_DIR / "historical_observations"
        if historical_dir.exists():
            for json_file in sorted(historical_dir.rglob("*.json")):
                content = json_file.read_text(encoding="utf-8")
                unique_name = f"{json_file.parent.name}/{json_file.name}"
                cursor.execute(
                    """
                    INSERT INTO bronze.raw_historical_observations (file_name, raw_payload)
                    VALUES (%s, %s)
                    ON CONFLICT (file_name) DO NOTHING;
                    """,
                    (unique_name, content),
                )

        conn.commit()
        print("All raw backup files have been successfully loaded into PostgreSQL Bronze tables!")
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    load_files_to_bronze()