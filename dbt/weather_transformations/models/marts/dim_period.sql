{{
    config(
        materialized='table',
        schema='gold'
    )
}}

SELECT
    CASE
        WHEN period = 'Day' THEN 1
        WHEN period = 'Night' THEN 2
    END AS period_key,
    period AS period_name
FROM {{ ref('stg_forecasts') }}
WHERE period IN ('Day', 'Night')
GROUP BY period