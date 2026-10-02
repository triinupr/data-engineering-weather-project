from pathlib import Path
from datetime import datetime, timezone
import argparse
import requests


FORECAST_URL = "https://ilmateenistus.ee/ilma_andmed/xml/forecast.php?lang=eng"
OBSERVATIONS_URL = "https://ilmateenistus.ee/ilma_andmed/xml/observations.php"

RAW_DATA_DIR = Path("/app/data/raw")


def fetch_xml(url: str) -> bytes:
    response = requests.get(url, timeout=30)
    response.raise_for_status()

    data = response.content

    if not data.strip().startswith(b"<?xml"):
        raise ValueError("Response does not appear to be XML")

    return data


def save_xml(data: bytes, dataset: str) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    output_dir = RAW_DATA_DIR / dataset
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / f"{dataset}_{timestamp}.xml"
    output_file.write_bytes(data)

    return output_file


def ingest_forecast():
    data = fetch_xml(FORECAST_URL)
    output_file = save_xml(data, "forecasts")
    print(f"Forecast saved to {output_file}")


def ingest_observations():
    data = fetch_xml(OBSERVATIONS_URL)
    output_file = save_xml(data, "observations")
    print(f"Observations saved to {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "dataset",
        choices=["forecast", "observations"],
        help="Dataset to retrieve",
    )

    args = parser.parse_args()

    if args.dataset == "forecast":
        ingest_forecast()
    else:
        ingest_observations()