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


def fetch_xml(url: str) -> bytes:
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    data = response.content
    if not data.strip().startswith(b"<?xml"):
        raise ValueError("Response does not appear to be XML")
    return data


def save_bytes(data: bytes, dataset: str, extension: str) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_dir = RAW_DATA_DIR / dataset
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f"{dataset}_{timestamp}.{extension}"
    output_file.write_bytes(data)
    return output_file


def ingest_forecast():
    data = fetch_xml(FORECAST_URL)
    output_file = save_bytes(data, "forecasts", "xml")
    print(f"Forecast saved to {output_file}")


def ingest_observations():
    data = fetch_xml(OBSERVATIONS_URL)
    output_file = save_bytes(data, "observations", "xml")
    print(f"Observations saved to {output_file}")


def ingest_historical(year: int, month: int):
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
    if output_dir.exists() and any(output_dir.glob("*.json")):
        raise FileExistsError(
            f"{output_dir} already contains raw files. Historical raw data is not overwritten."
        )
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

    print(
        f"Historical observations for {year}-{month:02d}: "
        f"{total_rows} rows in {page_number} raw file(s)"
    )


def main():
    parser = argparse.ArgumentParser(description="Weather data raw ingestion")
    subparsers = parser.add_subparsers(dest="dataset", required=True)
    subparsers.add_parser("forecast", help="Retrieve the current forecast XML")
    subparsers.add_parser("observations", help="Retrieve current observation XML")

    historical = subparsers.add_parser(
        "historical", help="Retrieve one month of historical hourly observations"
    )
    historical.add_argument("--year", type=int, required=True)
    historical.add_argument("--month", type=int, choices=range(1, 13), required=True)

    args = parser.parse_args()
    if args.dataset == "forecast":
        ingest_forecast()
    elif args.dataset == "observations":
        ingest_observations()
    else:
        ingest_historical(args.year, args.month)


if __name__ == "__main__":
    main()
