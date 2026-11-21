{{ config(materialized='table', schema='silver') }}

-- Materialise once per refresh rather than parsing XML for every downstream
-- test/query. UTC keys preserve both clock hours at the autumn DST change.
with live_ranked as (
    select *, date_trunc('hour', observation_timestamp_utc, 'UTC') as observation_hour_utc,
        row_number() over (
            partition by station_name, date_trunc('hour', observation_timestamp_utc, 'UTC')
            order by observation_timestamp_utc desc, file_name desc
        ) as hour_rank
    from {{ ref('stg_observations') }}
),
live as (select * from live_ranked where hour_rank = 1),
historical_ranked as (
    select *, row_number() over (
        partition by station_name, observation_timestamp_utc
        order by source_updated_at desc nulls last, source_file desc
    ) as hour_rank
    from {{ ref('stg_historical_observations') }}
    where temperature is not null
),
historical as (select * from historical_ranked where hour_rank = 1)
select coalesce(h.station_name, l.station_name) as station_name,
    coalesce(h.observation_timestamp_utc, l.observation_hour_utc) as observation_timestamp_utc,
    coalesce(h.observation_timestamp_utc, l.observation_hour_utc)
        at time zone 'Europe/Tallinn' as observation_datetime,
    coalesce(h.temperature, l.temperature) as temperature,
    l.phenomenon_name, l.precipitation_mm,
    case when h.station_name is not null then 'historical_json' else 'live_xml' end
        as observation_source,
    coalesce(h.source_file, l.file_name) as source_file
from historical h
full outer join live l
    on h.station_name = l.station_name
   and h.observation_timestamp_utc = l.observation_hour_utc
