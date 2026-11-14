SELECT
    forecast_date,
    period,
    location_name,
    temperature AS forecast_temperature,
    phenomenon_name AS forecast_phenomenon,
    file_name,
    TO_TIMESTAMP(
        SUBSTRING(file_name FROM '([0-9]{8}T[0-9]{6}Z)'),
        'YYYYMMDD"T"HH24MISS"Z"'
    ) AS forecast_retrieved_at
FROM {{ ref('stg_forecasts') }}