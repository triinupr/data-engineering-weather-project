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
    EXTRACT(DAY FROM date)::integer AS day,
    EXTRACT(QUARTER FROM date)::integer AS quarter,
    EXTRACT(ISODOW FROM date)::integer AS day_of_week
FROM dates