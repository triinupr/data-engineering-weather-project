-- Extract file-level XML once before expanding the station array. Otherwise
-- PostgreSQL can repeat the root timestamp XPath for every station/hour.
with files as materialized (
    select file_name, retrieved_at,
        to_timestamp((xpath('/observations/@timestamp', raw_payload))[1]::text::bigint)
            as observation_timestamp_utc,
        xpath('/observations/station', raw_payload) as station_nodes
    from {{ source('bronze', 'raw_observations') }}
),
stations as (
    select file_name, retrieved_at, observation_timestamp_utc,
        unnest(station_nodes) as station
    from files
)
select file_name, retrieved_at, observation_timestamp_utc,
    observation_timestamp_utc at time zone 'Europe/Tallinn' as observation_datetime,
    (xpath('/station/name/text()', station))[1]::text as station_name,
    nullif((xpath('/station/airtemperature/text()', station))[1]::text, '')::numeric as temperature,
    nullif((xpath('/station/phenomenon/text()', station))[1]::text, '') as phenomenon_name,
    -- Amount for the preceding hour. Blank means unknown, not zero.
    nullif((xpath('/station/precipitations/text()', station))[1]::text, '')::numeric
        as precipitation_mm
from stations
