-- Run after weather_historical_month, with a month overlapping saved forecasts.
-- These are evidence queries, not precomputed or fabricated result claims.

-- 1. Show preserved response arrays and the number of metric records per file.
SELECT file_name, jsonb_typeof(raw_payload) AS payload_type,
       jsonb_array_length(raw_payload) AS metric_records
FROM bronze.raw_historical_observations
ORDER BY file_name;

-- 2. Show extraction to typed, local-time observations with source lineage.
SELECT station_code, station_name, observation_timestamp_utc,
       observation_datetime, temperature, source_file
FROM public_silver.stg_historical_observations
ORDER BY observation_timestamp_utc, station_code
LIMIT 12;

-- 3. Quantify actual use of each source after overlap resolution.
SELECT observation_source, COUNT(*) AS selected_station_hours,
       MIN(observation_datetime) AS first_local_hour,
       MAX(observation_datetime) AS last_local_hour
FROM public_silver.int_unified_observations
GROUP BY observation_source
ORDER BY observation_source;

-- 4. Prove selected JSON temperatures participate in the existing Gold fact.
-- EXISTS avoids multiplying facts when several hours share the period extreme.
-- int_observations retains the existing default dbt schema: public.
SELECT COUNT(*) AS matched_forecast_rows,
       AVG(f.absolute_error) AS temperature_mae_celsius
FROM public_gold.fact_forecast_accuracy f
JOIN public_gold.dim_date d ON d.date_key = f.date_key
JOIN public_gold.dim_period p ON p.period_key = f.period_key
JOIN public_gold.dim_forecast_location l ON l.location_key = f.location_key
JOIN public_gold.dim_station s ON s.station_key = f.station_key
WHERE f.collected_before_period
  AND f.observed_temperature IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public_silver.int_unified_observations o
    WHERE o.observation_source = 'historical_json'
      AND o.station_name = s.station_name
      AND o.temperature = f.observed_temperature
      AND (
        (p.period_name = 'Day'
         AND o.observation_datetime >= d.full_date + INTERVAL '6 hours'
         AND o.observation_datetime < d.full_date + INTERVAL '18 hours')
        OR
        (p.period_name = 'Night'
         AND o.observation_datetime >= d.full_date - INTERVAL '6 hours'
         AND o.observation_datetime < d.full_date + INTERVAL '6 hours')
      )
  );
