{{
    config(
        materialized='table',
        schema='gold'
    )
}}

WITH locations AS (
    SELECT DISTINCT
        location_name
    FROM {{ ref('stg_forecasts') }}
    WHERE location_name IS NOT NULL
)

SELECT
    ROW_NUMBER() OVER (ORDER BY location_name) AS location_key,
    location_name
FROM locations