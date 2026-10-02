# data-engineering-weather-project
# Weather Forecast Accuracy – Data Engineering Project

This project collects weather forecast and observation data from the
Estonian Environment Agency for analysing weather forecast accuracy.
It is group project for UT Data Engienering course.

Team members:
* Gailin Savi
* Eliise Ševtšenko
* Karoliine Inselberg
* Triinu Prants 


Data source:
Estonian Environment Agency Weather Service

## Requirements

Run Docker Desktop.

## Initial setup

Clone the repository:

    git clone <REPOSITORY-URL>
    cd <REPOSITORY-NAME>

Build the Docker image:

    docker compose build

## Collect forecast data manually

Run:

    docker compose run --rm ingestion python src/ingest.py forecast

The downloaded XML file will appear in:

    data/raw/forecasts/

## Collect observation data manually

Run:

    docker compose run --rm ingestion python src/ingest.py observations

The downloaded XML file will appear in:

    data/raw/observations/

## Verify that ingestion works

Run:

    ls data/raw/forecasts
    ls data/raw/observations

Both directories should contain timestamped XML files.

## Data collection schedule

Forecast:
- retrieved once per day

Observations:
- retrieved once per hour

Historical observations:
- loaded separately as an initial batch

## Important

Files under `data/raw/` are not committed to GitHub.
