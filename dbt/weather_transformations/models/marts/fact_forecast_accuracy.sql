 {{ config(materialized='table', schema='gold') }}

SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            f.forecast_retrieved_at,
            f.forecast_date,
            f.period,
            f.location_name,
            f.file_name
    ) AS accuracy_key,

    d.date_key,
    p.period_key,
    l.location_key,
    s.station_key,
    fp.phenomenon_key AS forecast_phenomenon_key,
    op.phenomenon_key AS observed_phenomenon_key,

    f.forecast_retrieved_at AS retrieved_at,
    f.file_name AS source_file,
    CASE
        WHEN f.period = 'Day' THEN
            (f.forecast_retrieved_at AT TIME ZONE 'Europe/Tallinn')
                < f.forecast_date::timestamp + INTERVAL '6 hours'
        WHEN f.period = 'Night' THEN
            (f.forecast_retrieved_at AT TIME ZONE 'Europe/Tallinn')
                < f.forecast_date::timestamp - INTERVAL '6 hours'
        ELSE FALSE
    END AS collected_before_period,

    f.forecast_temperature,
    o.actual_temperature AS observed_temperature,

    f.forecast_temperature - o.actual_temperature
        AS temperature_error,

    ABS(f.forecast_temperature - o.actual_temperature)
        AS absolute_error

FROM {{ ref('int_latest_forecasts') }} f

LEFT JOIN {{ ref('int_daily_observations') }} o
    ON f.forecast_date = o.observation_date
    AND f.location_name = o.location_name
    AND f.period = o.period

JOIN {{ ref('dim_date') }} d
    ON f.forecast_date = d.full_date

JOIN {{ ref('dim_period') }} p
    ON f.period = p.period_name

JOIN {{ ref('dim_forecast_location') }} l
    ON f.location_name = l.location_name

LEFT JOIN {{ ref('dim_station') }} s
    ON o.station_name = s.station_name
    AND (
        (
            f.forecast_retrieved_at >= s.valid_from
            AND (
                f.forecast_retrieved_at < s.valid_to
                OR s.valid_to IS NULL
            )
        )
        OR (
            f.forecast_retrieved_at < s.valid_from
            AND s.valid_from = (
                SELECT MIN(s2.valid_from)
                FROM {{ ref('dim_station') }} s2
                WHERE s2.station_name = s.station_name
            )
        )
    )

LEFT JOIN {{ ref('dim_weather_phenomenon') }} fp
    ON f.forecast_phenomenon = fp.phenomenon_name

LEFT JOIN {{ ref('dim_weather_phenomenon') }} op
    ON o.observed_phenomenon = op.phenomenon_name