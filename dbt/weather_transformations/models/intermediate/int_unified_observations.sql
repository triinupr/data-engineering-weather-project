{{ config(materialized='view', schema='silver') }}

-- Preserve the existing model's local-time interface. Collapse repeated live
-- responses within an hour before combining them with validated JSON data.
with live_ranked as (
    select *, row_number() over (
        partition by station_name, date_trunc('hour', observation_datetime)
        order by observation_datetime desc, file_name desc
    ) as hour_rank
    from {{ ref('stg_observations') }}
    where temperature is not null
),
live as (
    select * from live_ranked where hour_rank = 1
),
historical_ranked as (
    select *, row_number() over (
        partition by station_name, date_trunc('hour', observation_datetime)
        order by observation_timestamp_utc desc, source_updated_at desc nulls last,
                 source_file desc
    ) as hour_rank
    from {{ ref('stg_historical_observations') }}
    where temperature is not null
),
historical as (
    select * from historical_ranked where hour_rank = 1
)
select
    coalesce(h.station_name, l.station_name) as station_name,
    coalesce(h.observation_datetime, date_trunc('hour', l.observation_datetime)) as observation_datetime,
    coalesce(h.temperature, l.temperature) as temperature,
    -- The JSON TA metric has no phenomenon field. Retain the live value when
    -- present; otherwise keep it null rather than inventing a condition.
    l.phenomenon_name,
    case when h.station_name is not null then 'historical_json' else 'live_xml' end as observation_source,
    coalesce(h.source_file, l.file_name) as source_file
from historical h
full outer join live l
    on h.station_name = l.station_name
   and h.observation_datetime = date_trunc('hour', l.observation_datetime)
