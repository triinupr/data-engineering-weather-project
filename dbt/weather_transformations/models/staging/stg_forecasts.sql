WITH night_forecasts AS (
    SELECT
        file_name,
        retrieved_at,
        (xpath('//forecast/@date', raw_payload))[1]::text::date
            AS forecast_date,
        'Night' AS period,
        (xpath('//forecast/night/phenomenon/text()', raw_payload))[1]::text
            AS phenomenon_name,
        unnest(xpath('//forecast/night/place', raw_payload)) AS place
    FROM bronze.raw_forecasts
),

day_forecasts AS (
    SELECT
        file_name,
        retrieved_at,
        (xpath('//forecast/@date', raw_payload))[1]::text::date
            AS forecast_date,
        'Day' AS period,
        (xpath('//forecast/day/phenomenon/text()', raw_payload))[1]::text
            AS phenomenon_name,
        unnest(xpath('//forecast/day/place', raw_payload)) AS place
    FROM bronze.raw_forecasts
),

combined AS (
    SELECT
        file_name,
        retrieved_at,
        forecast_date,
        period,
        phenomenon_name,
        (xpath('//name/text()', place))[1]::text AS location_name,
        (xpath('//tempmin/text()', place))[1]::text::numeric
            AS temperature
    FROM night_forecasts

    UNION ALL

    SELECT
        file_name,
        retrieved_at,
        forecast_date,
        period,
        phenomenon_name,
        (xpath('//name/text()', place))[1]::text AS location_name,
        (xpath('//tempmax/text()', place))[1]::text::numeric
            AS temperature
    FROM day_forecasts
)

SELECT * FROM combined