{% snapshot station_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='station_name',
        strategy='check',
        check_cols=['wmo_code']
    )
}}

WITH stations AS (
    SELECT
        (xpath('//name/text()', station))[1]::text AS station_name,
        NULLIF(
            (xpath('//wmocode/text()', station))[1]::text,
            ''
        )::integer AS wmo_code
    FROM (
        SELECT
            unnest(xpath('//observations/station', raw_payload)) AS station
        FROM bronze.raw_observations
    ) AS raw_stations
),

selected_stations AS (
    SELECT
        station_name,
        MAX(wmo_code) AS wmo_code
    FROM stations
    WHERE station_name IN (
        'Tallinn-Harku',
        'Jõhvi',
        'Tartu-Tõravere',
        'Pärnu',
        'Kuressaare linn',
        'Türi'
    )
    GROUP BY station_name
)

SELECT
    station_name,
    wmo_code
FROM selected_stations

{% endsnapshot %}