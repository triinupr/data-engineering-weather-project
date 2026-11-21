{{ config(materialized='view', schema='silver') }}

-- Bronze preserves API response arrays as JSONB. Each element is one metric
-- for a station and UTC hour; it is not a wide weather-observation record.
with records as (
    select
        b.file_name as source_file,
        b.retrieved_at,
        r.record
    from {{ source('bronze', 'raw_historical_observations') }} b
    cross join lateral jsonb_array_elements(b.raw_payload) as r(record)
),
temperature_records as (
    select
        source_file,
        record ->> 'jaam_kood' as station_code,
        case record ->> 'jaam_nimi'
            when 'Harku' then 'Tallinn-Harku'
            when 'Tõravere' then 'Tartu-Tõravere'
            else record ->> 'jaam_nimi'
        end as station_name,
        make_timestamptz(
            (record ->> 'aasta')::integer,
            (record ->> 'kuu')::integer,
            (record ->> 'paev')::integer,
            (record ->> 'tund')::integer, 0, 0, 'UTC'
        ) as observation_timestamp_utc,
        nullif(record ->> 'vaartus', '')::numeric as temperature,
        nullif(record ->> 'avaandmed_ts', '')::timestamptz as source_updated_at,
        retrieved_at
    from records
    where record ->> 'element_kood' = 'TA'
),
ranked as (
    select *, row_number() over (
        partition by station_code, observation_timestamp_utc
        order by source_updated_at desc nulls last, retrieved_at desc, source_file desc
    ) as version_rank
    from temperature_records
)
select
    station_code,
    station_name,
    observation_timestamp_utc,
    observation_timestamp_utc at time zone 'Europe/Tallinn' as observation_datetime,
    temperature,
    source_updated_at,
    source_file
from ranked
where version_rank = 1
