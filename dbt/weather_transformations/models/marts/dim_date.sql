{{ config(
    materialized='table',
    schema='gold'
) }}

WITH dates AS (
    SELECT DISTINCT
        forecast_date AS date
    FROM {{ ref('stg_forecasts') }}
    WHERE forecast_date IS NOT NULL
)

SELECT
    TO_CHAR(date, 'YYYYMMDD')::integer AS date_key,
    date AS full_date,
    EXTRACT(YEAR FROM date)::integer AS year,
    EXTRACT(MONTH FROM date)::integer AS month,
    CASE
        WHEN EXTRACT(MONTH FROM date) IN (12, 1, 2) THEN 'Winter'
        WHEN EXTRACT(MONTH FROM date) IN (3, 4, 5) THEN 'Spring'
        WHEN EXTRACT(MONTH FROM date) IN (6, 7, 8) THEN 'Summer'
        ELSE 'Autumn'
    END::text AS season,
    EXTRACT(DAY FROM date)::integer AS day,
    EXTRACT(QUARTER FROM date)::integer AS quarter,
    EXTRACT(ISODOW FROM date)::integer AS day_of_week
FROM dates