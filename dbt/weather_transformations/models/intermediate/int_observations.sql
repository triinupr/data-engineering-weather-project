SELECT
    observation_datetime,
    station_name,
    CASE
        WHEN station_name = 'Tallinn-Harku' THEN 'Harku'
        WHEN station_name = 'Tartu-Tõravere' THEN 'Tartu'
        WHEN station_name = 'Kuressaare linn' THEN 'Kuressaare'
        ELSE station_name
    END AS location_name,
    temperature,
    phenomenon_name
FROM {{ ref('stg_observations') }}
WHERE station_name IN (
    'Tallinn-Harku',
    'Jõhvi',
    'Tartu-Tõravere',
    'Pärnu',
    'Kuressaare linn',
    'Türi'
)
AND temperature IS NOT NULL