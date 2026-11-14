WITH observation_stations AS (
    SELECT
        file_name,
        retrieved_at,
        to_timestamp(
            (xpath('//observations/@timestamp', raw_payload))[1]::text::bigint
        ) AT TIME ZONE 'Europe/Tallinn' AS observation_datetime,
        unnest(
            xpath('//observations/station', raw_payload)
        ) AS station
    FROM bronze.raw_observations
)

SELECT
    file_name,
    retrieved_at,
    observation_datetime,
    (xpath('//name/text()', station))[1]::text AS station_name,
    NULLIF(
        (xpath('//airtemperature/text()', station))[1]::text,
        ''
    )::numeric AS temperature,
    NULLIF(
        (xpath('//phenomenon/text()', station))[1]::text,
        ''
    ) AS phenomenon_name
FROM observation_stations