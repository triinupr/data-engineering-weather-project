# Extra-credit B: semi-structured historical observations

## What is integrated

The Environment Portal exposes hourly climate observations as JSON arrays through `f_kliima_tund`. The new historical DAG requests a calendar month of `TA` air-temperature measurements, then runs the same Bronze → dbt → Gold refresh as the live DAGs. October 2026 is the suggested first month because it overlaps the saved forecasts.

Official references:

- [Environment and weather data services](https://keskkonnaportaal.ee/et/avaandmed/keskkonna-ja-ilma-valdkonna-andmeteenused): JSON API, filtering, pagination and headers.
- [Climate dataset description](https://keskkonnaportaal.ee/et/avaandmed/kliimaandmestik/kliimaandmestiku-kirjeldus): `TA` identifies hourly air temperature; observations use UTC.
- [PostgreSQL JSON types](https://www.postgresql.org/docs/16/datatype-json.html): JSONB stores parsed documents rather than preserving their original text formatting.
- [dbt build](https://docs.getdbt.com/reference/commands/build): model, snapshot and test execution in dependency order.

## Extraction and structure

The API supplies one metric per station/hour, with measurement identity in `jaam_kood`, `element_kood`, `aasta`, `kuu`, `paev` and `tund`; `vaartus` holds the measurement. It is a long-form metric stream rather than a wide table with one column per weather variable.

1. `src/ingest.py` applies year/month and `TA` filters, deterministic ordering, and 10,000-record pagination. It sends the API's documented JSON and profile headers.
2. Every response must be an array of objects with station identifiers, valid measurement date/hour and the requested month/metric. Missing temperature values are allowed as JSON null; non-null temperatures must be within the project's −50…50 °C range.
3. Original response bytes are written outside the Bronze loader's scan directory while downloading. After the complete month succeeds, its directory is atomically published under `data/raw/historical_observations/YYYY_MM/`. A failed page cannot publish an incomplete month. Existing archived months are reused.
4. The unchanged `load_bronze.py` loads each page into `bronze.raw_historical_observations`, retaining file identity and JSONB payload. File bytes preserve original JSON formatting; JSONB preserves its logical structure and values but normalises formatting/key order.
5. `stg_historical_observations.sql` uses `jsonb_array_elements` to expand the response array. `->>` extracts named fields, SQL casts make typed values, and measurement components form a UTC timestamp. The latest `avaandmed_ts` wins when revisions repeat a station/hour. Missing optional metadata stays null, and unused extra fields remain available in Bronze.
6. `int_unified_observations.sql` reconciles historical and live measurements by station and local clock hour. A non-null validated historical temperature has priority. Live observations supply a phenomenon description when available; the JSON temperature metric does not invent one. Source file and source category remain available for evidence queries.
7. The existing `int_observations` station mapping reads this unified view. Existing period aggregation, dimensions and `fact_forecast_accuracy` then consume the JSON temperatures through their normal dependencies. The fact grain and existing column interface are preserved.

## Comparison with conventional PostgreSQL tables

| Concern | JSONB response pages in Bronze | Typed relational measurement rows in Bronze |
|---|---|---|
| Source changes | New optional keys remain stored without a table alteration | New stored attributes usually require a schema/load change |
| Validation | Intake checks structure; dbt explicitly extracts and casts selected fields | Column types and constraints can validate at insertion |
| Analytical queries | Array expansion and field extraction precede joins/aggregation | Typed values are immediately available to queries |
| Duplicate identity | File uniqueness protects raw loads; dbt resolves measurement revisions | A station/metric/time key can support row-level upserts |
| Reprocessing | Saved responses support adding new extraction rules later | Unselected source attributes must be retained separately if needed later |
| Cost at this scale | Simple source preservation, with repeated parsing on refresh | More ingestion modelling; less repeated extraction work |

This approach still uses PostgreSQL. The extra-credit claim is the implemented handling of semi-structured API documents, not the use of a different database. JSONB is appropriate for raw retention and evolving fields; typed views and the relational star remain appropriate for the team's analytical queries. There is no claimed speed advantage or benchmark.

## Scope and limitations

- Historical JSON supplies observed temperatures, not missing historical forecasts. A month must overlap archived forecasts to support accuracy comparisons.
- Historical station names `Harku` and `Tõravere` are normalised to the existing live station labels. The existing six-station selection remains in place. Different physical stations are not substituted for missing ones.
- JSON null temperatures are retained in staging and excluded from source selection. Live temperature is used when historical temperature is missing. Historical-only hours have a null phenomenon.
- The existing intermediate interface uses local timestamps without a timezone. UTC is retained in historical staging, but reconciliation collapses the repeated local clock hour at the autumn DST transition. This is documented rather than changing Gailin's period model.
- Day/Night boundaries, maximum/minimum selection, station snapshot semantics and missing-hour treatment remain the existing project assumptions. Within-hour extrema metrics are outside this integration.
- Complete existing month archives are immutable inputs. A revised archive with the same file names is not automatically updated by the existing Bronze loader.
- Whole Gold tables are rebuilt; this implementation does not claim incremental fact materialisation or an atomic swap of the entire star schema for concurrent readers.

## Required evidence before claiming the bonus

Run `weather_historical_month` successfully for an overlapping month. Execute [sql/extra_credit_b.sql](../sql/extra_credit_b.sql) and retain its real output under `results/`. The queries show raw arrays, typed extracted records, source-selection counts and a temperature MAE over facts whose observed extreme uses a selected historical measurement.

The final query should return a positive fact count. Empty historical tables or a zero count do not establish JSON use in the analytical model. Synthetic offline test responses establish regression behaviour only; they are not real-data results and must not be presented as such.
