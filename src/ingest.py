from pathlib import Path
from datetime import datetime, timezone
import argparse
import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
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

        seen_stations = {}
        exact_duplicates = 0
        null_temp_count = 0

        for station in stations:
            name = station.findtext("name")
            temp_str = station.findtext("airtemperature")

            # Null check
            if not name or not name.strip():
                raise ValueError("Data Quality Failed: Found observation record with missing/NULL station name")

            # Duplicate check within payload
            clean_name = name.strip()
            longitude = (station.findtext("longitude") or "").strip()
            latitude = (station.findtext("latitude") or "").strip()
            station_identity = (clean_name, longitude, latitude)
            signature = tuple((child.tag, (child.text or "").strip()) for child in station)
            if station_identity in seen_stations:
                if seen_stations[station_identity] != signature:
                    raise ValueError(f"Data Quality Failed: Conflicting duplicate station '{clean_name}'")
                exact_duplicates += 1
                continue
            seen_stations[station_identity] = signature

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

        print(f"Data Quality Passed: {len(stations)} observation stations validated ({null_temp_count} null temps; {exact_duplicates} identical duplicate records retained in raw)")

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


def existing_run_file(dataset: str, extension: str, run_date: str = None):
    if not run_date:
        return None
    if not re.fullmatch(r"[0-9TtZz:_-]+", run_date):
        raise ValueError("Run date must contain only date/time characters")
    directory = RAW_DATA_DIR / dataset
    matches = sorted(directory.glob(f"{dataset}_*_run_{run_date}.{extension}"))
    legacy = directory / f"{dataset}_{run_date}.{extension}"
    return matches[0] if matches else (legacy if legacy.exists() else None)


def save_bytes(data: bytes, dataset: str, extension: str, run_date: str = None) -> Path:
    existing = existing_run_file(dataset, extension, run_date)
    if existing:
        return existing
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_suffix = f"_run_{run_date}" if run_date else ""
    output_dir = RAW_DATA_DIR / dataset
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f"{dataset}_{timestamp}{run_suffix}.{extension}"
    if output_file.exists():
        return output_file
    # Publish only complete files: Bronze never sees a partially written XML.
    with tempfile.NamedTemporaryFile(dir=output_dir, suffix=".tmp", delete=False) as f:
        temporary = Path(f.name)
        f.write(data)
    try:
        temporary.chmod(0o644)
        temporary.replace(output_file)
    finally:
        temporary.unlink(missing_ok=True)
    return output_file


def ingest_forecast(run_date: str = None):
    existing = existing_run_file("forecasts", "xml", run_date)
    if existing:
        print(f"Reusing {existing}")
        return
    data = fetch_xml(FORECAST_URL)
    validate_xml_data_quality(data, "forecast")
    output_file = save_bytes(data, "forecasts", "xml", run_date=run_date)
    print(f"Forecast saved to {output_file}")


def ingest_observations(run_date: str = None):
    existing = existing_run_file("observations", "xml", run_date)
    if existing:
        print(f"Reusing {existing}")
        return
    data = fetch_xml(OBSERVATIONS_URL)
    validate_xml_data_quality(data, "observations")
    output_file = save_bytes(data, "observations", "xml", run_date=run_date)
    print(f"Observations saved to {output_file}")


def validate_historical_page(payload, year: int, month: int):
    if not isinstance(payload, list):
        raise ValueError("Historical response must be a JSON array")
    for row in payload:
        if not isinstance(row, dict):
            raise ValueError("Each historical record must be a JSON object")
        for key in ("jaam_kood", "jaam_nimi", "element_kood"):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError(f"Missing historical identifier: {key}")
        if row["element_kood"] != "TA":
            raise ValueError("Expected the requested TA air-temperature metric")
        for key in ("aasta", "kuu", "paev", "tund"):
            if type(row.get(key)) is not int:
                raise ValueError(f"Historical {key} must be an integer")
        datetime(row["aasta"], row["kuu"], row["paev"], row["tund"], tzinfo=timezone.utc)
        if (row["aasta"], row["kuu"]) != (year, month):
            raise ValueError("Historical response contains a different requested month")
        if "vaartus" not in row:
            raise ValueError("Historical record is missing vaartus (JSON null is allowed)")
        value = row["vaartus"]
        if value is not None:
            if isinstance(value, bool) or not (-50 <= float(value) <= 50):
                raise ValueError(f"Historical temperature outside [-50, 50]: {value}")


def ingest_historical(year: int, month: int):
    """Fetch one month of UTC hourly TA records; publish only a complete batch."""
    datetime(year, month, 1)
    params = {
        "aasta": f"eq.{year}",
        "kuu": f"eq.{month}",
        "element_kood": "eq.TA",
        "order": "jaam_kood.asc,element_kood.asc,paev.asc,tund.asc,avaandmed_ts.asc",
    }
    parent = RAW_DATA_DIR / "historical_observations"
    output_dir = parent / f"{year}_{month:02d}"
    if output_dir.exists():
        if any(output_dir.glob("*.json")):
            print(f"Reusing archived month {output_dir}; no files overwritten")
            return
        output_dir.rmdir()
    parent.mkdir(parents=True, exist_ok=True)
    page_size = 10000
    total_rows = 0
    # A failed request leaves no published month, so a retry cannot silently
    # mistake the first few downloaded pages for a complete successful batch.
    with tempfile.TemporaryDirectory(prefix=".historical-", dir=RAW_DATA_DIR) as temporary:
        staging = Path(temporary) / "batch"
        staging.mkdir()
        page_number = 1
        while True:
            response = requests.get(
                HISTORICAL_HOURLY_URL,
                params={**params, "limit": page_size, "offset": (page_number - 1) * page_size},
                # Use the climate endpoint's default schema. The unrelated
                # apijahialad profile causes PostgREST to reject this request.
                headers={"Accept": "application/json"},
                timeout=120,
            )
            try:
                response.raise_for_status()
            except requests.HTTPError as exc:
                raise ValueError(
                    f"Historical API returned HTTP {response.status_code}: "
                    f"{response.text[:500]}"
                ) from exc
            try:
                payload = response.json()
            except requests.JSONDecodeError as exc:
                raise ValueError("Historical response is not valid JSON") from exc
            validate_historical_page(payload, year, month)
            if not payload:
                break
            (staging / f"page_{page_number:04d}.json").write_bytes(response.content)
            total_rows += len(payload)
            if len(payload) < page_size:
                break
            page_number += 1
        if not total_rows:
            raise ValueError(f"No validated TA observations available for {year}-{month:02d}")
        staging.rename(output_dir)
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

