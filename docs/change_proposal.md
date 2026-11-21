# Part 2 integration changes

The implementation was prepared against repository commit `badf080`. Triinu approved the scope on 21 November 2026, and the changes have been applied to the local weather-project repository.

## Changes to existing files

| Existing file | Proposed change | Reason |
|---|---|---|
| `src/ingest.py` | Fix missing XML import and broken indentation; handle identical/conflicting duplicates; immutable live-run retries; validated, paginated, atomic historical TA batches | Current script cannot compile; valid supplied XML contains identical duplicates; overwriting a loaded file conflicts with Bronze’s skip-existing behaviour |
| `dbt/weather_transformations/models/intermediate/int_observations.sql` | Change a single `ref` from `stg_observations` to `int_unified_observations` | Allows historical JSON temperatures to reach the existing period aggregation and Gold fact |
| `dags/weather_ingestion.py` | Add Gold refresh after each live collector, retries and timeouts; retain the two schedules | Completes Triinu’s orchestration assignment |
| `docker-compose.yml` | Add dbt service and mounts/environment; pause newly created recurring DAGs initially; stop masking database-migration failures | Makes orchestration runnable and setup errors visible |
| `Dockerfile.airflow` | Add an isolated, pinned dbt environment and explicit PostgreSQL driver | Lets Airflow invoke dbt without mixing its dependencies into Airflow |
| `Dockerfile.dbt` | Pin the same dbt versions | Keeps manual and orchestrated transformations consistent |
| `README.md` | Replace inconsistent setup instructions with the integrated workflow, diagrams, configuration, evidence commands and limitations | Requested documentation update |

The Bronze loader, original dbt profile, sample data, station mapping rules, period aggregation, fact, dimensions and snapshot SQL remain unchanged. The one changed dbt reference connects the new source views to the existing analytical model.

## New files

- Manual historical-month and saved-file replay DAGs.
- A warehouse refresh runner that serializes Bronze loading and dbt work across DAGs.
- Correctly named `dbt/profiles.yml` and a `.dockerignore` that excludes the raw archive and generated artifacts from image build contexts.
- Historical JSON staging, unified observations, documentation and nine dbt data tests.
- Eleven offline regression tests and a Docker replay/idempotency verification script.
- Supporting extra-credit SQL, comparison documentation and a candid validation record.

## Verification so far

11 offline tests, all 1,005 supplied XML files, Python syntax, Compose configuration, shell syntax and static dbt references passed. Full Airflow/dbt/PostgreSQL execution and actual historical JSON results remain unverified because of session restrictions and the absence of historical JSON in the backup. See `docs/validation.md` for details.

This approved scope has been applied locally. No commit, push, deployment or Google Docs edit has been made.
