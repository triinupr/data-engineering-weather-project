{{
    config(
        materialized='table',
        schema='gold'
    )
}}

SELECT
    ROW_NUMBER() OVER (
        ORDER BY station_name, dbt_valid_from
    ) AS station_key,
    station_name,
    wmo_code,
    dbt_valid_from AS valid_from,
    dbt_valid_to AS valid_to,
    CASE
        WHEN dbt_valid_to IS NULL THEN TRUE
        ELSE FALSE
    END AS is_current
FROM {{ ref('station_snapshot') }}