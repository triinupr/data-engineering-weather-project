{{
    config(
        materialized='table',
        schema='gold'
    )
}}

WITH forecast_phenomena AS (
    SELECT unnest(
        xpath('//forecast/night/phenomenon/text()', raw_payload)
    )::text AS phenomenon_name
    FROM bronze.raw_forecasts

    UNION

    SELECT unnest(
        xpath('//forecast/day/phenomenon/text()', raw_payload)
    )::text AS phenomenon_name
    FROM bronze.raw_forecasts
),

observation_phenomena AS (
    SELECT
        (xpath('//phenomenon/text()', station))[1]::text
            AS phenomenon_name
    FROM (
        SELECT unnest(
            xpath('//observations/station', raw_payload)
        ) AS station
        FROM bronze.raw_observations
    ) AS stations
),

all_phenomena AS (
    SELECT phenomenon_name FROM forecast_phenomena
    UNION
    SELECT phenomenon_name FROM observation_phenomena
),

classified AS (
    SELECT
        phenomenon_name,

        CASE
            WHEN phenomenon_name ILIKE '%snow%'
              OR phenomenon_name ILIKE '%sleet%'
                THEN 'Snow or sleet'
            WHEN phenomenon_name ILIKE '%rain%'
              OR phenomenon_name ILIKE '%shower%'
                THEN 'Rain'
            WHEN phenomenon_name ILIKE '%fog%'
              OR phenomenon_name ILIKE '%mist%'
                THEN 'Fog or mist'
            WHEN phenomenon_name ILIKE '%cloud%'
              OR phenomenon_name = 'Overcast'
                THEN 'Cloudy'
            WHEN phenomenon_name = 'Clear'
                THEN 'Clear'
            ELSE 'Other'
        END AS category,

        CASE
            WHEN phenomenon_name ILIKE '%rain%'
              OR phenomenon_name ILIKE '%shower%'
              OR phenomenon_name ILIKE '%snow%'
              OR phenomenon_name ILIKE '%sleet%'
                THEN TRUE
            ELSE FALSE
        END AS has_precipitation,

        CASE
            WHEN phenomenon_name ILIKE '%snow%'
                THEN 'Snow'
            WHEN phenomenon_name ILIKE '%sleet%'
                THEN 'Sleet'
            WHEN phenomenon_name ILIKE '%rain%'
              OR phenomenon_name ILIKE '%shower%'
                THEN 'Rain'
            ELSE NULL
        END AS precipitation_type,

        CASE
            WHEN phenomenon_name ILIKE '%light%'
                THEN 'Light'
            WHEN phenomenon_name ILIKE '%moderate%'
                THEN 'Moderate'
            WHEN phenomenon_name ILIKE '%heavy%'
                THEN 'Heavy'
            ELSE NULL
        END AS intensity

    FROM all_phenomena
    WHERE phenomenon_name IS NOT NULL
      AND phenomenon_name <> ''
)

SELECT
    ROW_NUMBER() OVER (
        ORDER BY phenomenon_name
    ) AS phenomenon_key,
    phenomenon_name,
    category,
    has_precipitation,
    precipitation_type,
    intensity
FROM classified