from pathlib import Path
from datetime import datetime, timezone
import argparse
import json
import os
import requests

FORECAST_URL = "https://ilmateenistus.ee/ilma_andmed/xml/forecast.php?lang=eng"
OBSERVATIONS_URL = "https://ilmateenistus.ee/ilma_andmed/xml/observations.php"
HISTORICAL_HOURLY_URL = os.getenv(
    "HISTORICAL_OBSERVATIONS_URL",
    "https://keskkonnaandmed.envir.ee/f_kliima_tund",
)

RAW_DATA_DIR = Path(os.getenv("RAW_DATA_DIR", "/app/data/raw"))


def validate_xml_data_quality(data: bytes, dataset_type: str):
    """
    Data quality validation:
    - Parses XML payload
    - Checks for null/missing values on critical nodes
    - Validates station uniqueness (no duplicates)
    - Validates numeric metric ranges (air temperature between -50°C and +50°C)
    """
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise ValueError(f"Data Quality Failed: Invalid XML payload structure") from exc

    if dataset_type == "observations":
        stations = root.findall(".//station")
        if not stations:
            raise ValueError("Data Quality Failed: Zero station elements found in observations XML")

        seen_stations = set()
        null_temp_count = 0

        for station in stations:
            name = station.findtext("name")
            temp_str = station.findtext("airtemperature")

            # Null check
            if not name or not name.strip():
                raise ValueError("Data Quality Failed: Found observation record with missing/NULL station name")

            # Duplicate check within payload
            clean_name = name.strip()
            if clean_name in seen_stations:
                raise ValueError(f"Data Quality Failed: Duplicate observation station entry '{clean_name}'")
            seen_stations.add(clean_name)

            # Temperature range check
            if temp_str is not None and temp_str.strip() != "":
                try:
                    temp = float(temp_str)
                    if not (-50.0 <= temp <= 50.0):
                        raise ValueError(f"Data Quality Failed: Temperature {temp}°C out of valid range [-50, 50] for {clean_name}")
                except ValueError:
                    raise ValueError(f"Data Quality Failed: Invalid non-numeric temperature '{temp_str}' for {clean_name}")
            else:
                null_temp_count += 1

        print(f"Data Quality Passed: {len(stations)} observation stations validated ({null_temp_count} null temps)")

    elif dataset_type == "forecast":
        forecasts = root.findall(".//forecast")
        if not forecasts:
            raise ValueError("Data Quality Failed: Zero forecast nodes found in XML")
        print(f"Data Quality Passed: {len(forecasts)} forecast days validated")
        

def fetch_xml(url: str) -> bytes:
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    data = response.content
    if not data.strip().startswith(b"<?xml"):
        raise ValueError("Response does not appear to be XML")
    return data


def save_bytes(data: bytes, dataset: str, extension: str, run_date: str = None) -> Path:
    """
    Idempotent file saver:
    - If run_date is provided (e.g. from Airflow parameter), uses deterministic filename.
    - Overwrites existing files for the same run_date instead of creating duplicates.
    """
    if run_date:
        filename = f"{dataset}_{run_date}.{extension}"
    else:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        filename = f"{dataset}_{timestamp}.{extension}"

    output_dir = RAW_DATA_DIR / dataset
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / filename
    
    # Overwrites cleanly for idempotency
    output_file.write_bytes(data)
    return output_file


def ingest_forecast(run_date: str = None):
    data = fetch_xml(FORECAST_URL)
    validate_xml_data_quality(data, "forecast")
    output_file = save_bytes(data, "forecasts", "xml", run_date=run_date)
    print(f"Forecast saved cleanly to {output_file}")


def ingest_observations(run_date: str = None):
    data = fetch_xml(OBSERVATIONS_URL)
    validate_xml_data_quality(data, "observations")
    output_file = save_bytes(data, "observations", "xml", run_date=run_date)
    print(f"Observations saved cleanly to {output_file}")
    
    

    
def ingest_historical(year: int, month: int, overwrite: bool = True):
     """Download one calendar month of validated hourly climate observations.

    The official service limits response size, so this function retrieves the
    month in pages and preserves each page as a separate raw JSON response.
    """
    params = {
        "aasta": f"eq.{year}",
        "kuu": f"eq.{month}",
        "order": "jaam_kood.asc,element_kood.asc,paev.asc,tund.asc",
    }
    output_dir = RAW_DATA_DIR / "historical_observations" / f"{year}_{month:02d}"

    # Handle idempotency cleanly on re-runs instead of crashing with FileExistsError
    if output_dir.exists() and any(output_dir.glob("*.json")) and not overwrite:
        print(f"{output_dir} already contains data. Skipping re-ingestion.")
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    page_size = 10000
    offset = 0
    page_number = 1
    total_rows = 0

    while True:
        headers = {"Range": f"{offset}-{offset + page_size - 1}"}
        response = requests.get(
            HISTORICAL_HOURLY_URL, params=params, headers=headers, timeout=120
        )
        response.raise_for_status()
        try:
            payload = response.json()
        except requests.JSONDecodeError as exc:
            raise ValueError("Historical response does not appear to be JSON") from exc

        if not isinstance(payload, list):
            raise ValueError("Historical response is not the expected JSON array")
        if not payload:
            break

        output_file = output_dir / f"page_{page_number:04d}.json"
        output_file.write_bytes(response.content)
        total_rows += len(payload)
        print(f"Saved {output_file} ({len(payload)} rows)")

        if len(payload) < page_size:
            break
        offset += page_size
        page_number += 1

    print(f"Historical observations for {year}-{month:02d}: {total_rows} rows saved")


def main():
    parser = argparse.ArgumentParser(description="Weather data raw ingestion")
    subparsers = parser.add_subparsers(dest="dataset", required=True)

    # Parameterised forecast subparser
    forecast_parser = subparsers.add_parser("forecast", help="Retrieve current forecast XML")
    forecast_parser.add_argument("--date", type=str, help="Execution date or timestamp parameter (e.g. YYYY-MM-DD)")

    # Parameterised observations subparser
    obs_parser = subparsers.add_parser("observations", help="Retrieve current observation XML")
    obs_parser.add_argument("--date", type=str, help="Execution date or timestamp parameter (e.g. YYYY-MM-DD)")

    # Historical subparser
    historical = subparsers.add_parser("historical", help="Retrieve one month of historical hourly observations")
    historical.add_argument("--year", type=int, required=True)
    historical.add_argument("--month", type=int, choices=range(1, 13), required=True)

    args = parser.parse_args()

    if args.dataset == "forecast":
        ingest_forecast(run_date=args.date)
    elif args.dataset == "observations":
        ingest_observations(run_date=args.date)
    else:
        ingest_historical(args.year, args.month)


if __name__ == "__main__":
    main()

