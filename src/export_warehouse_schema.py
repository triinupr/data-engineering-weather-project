"""Export actual warehouse DDL without Airflow's public-schema metadata tables."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from psycopg2.extensions import parse_dsn


def schema_dump(connection_string):
    parameters = parse_dsn(connection_string)
    environment = os.environ.copy()
    for key, variable in {
        "host": "PGHOST", "port": "PGPORT", "user": "PGUSER",
        "password": "PGPASSWORD", "dbname": "PGDATABASE", "sslmode": "PGSSLMODE",
    }.items():
        if key in parameters:
            environment[variable] = parameters[key]
    common = ["pg_dump", "--schema-only", "--no-owner", "--no-privileges"]
    # The first dump includes schema definitions, raw tables/sequences, Silver,
    # Gold and snapshots. Public also contains Airflow tables, so only the three
    # named intermediate views are included in the second, dependency-ordered dump.
    selections = [
        ["--schema=bronze", "--schema=public_silver", "--schema=public_gold", "--schema=snapshots"],
        ["--strict-names", "--table=public.int_observations",
         "--table=public.int_daily_observations", "--table=public.int_latest_forecasts"],
    ]
    sections = ["-- Generated warehouse schema; dbt models are the transformation source.\n"]
    for selected in selections:
        result = subprocess.run(common + selected, env=environment, check=True,
                                capture_output=True, text=True)
        sections.append(result.stdout)
    return "\n".join(sections)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write atomically to a file instead of stdout")
    args = parser.parse_args()
    content = schema_dump(os.environ.get(
        "POSTGRES_CONN_STR", "postgresql://airflow:airflow@postgres:5432/airflow"
    ))
    if args.output is None:
        sys.stdout.write(content)
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent,
                                     suffix=".tmp", delete=False) as f:
        temporary = Path(f.name)
        f.write(content)
    try:
        temporary.chmod(0o644)
        temporary.replace(args.output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Warehouse schema written to {args.output}")


if __name__ == "__main__":
    main()
