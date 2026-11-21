{{ config(materialized='table', schema='gold') }}
with names as (
    select phenomenon_name from {{ ref('stg_forecasts') }}
    union
    select phenomenon_name from {{ ref('stg_observations') }}
),
classified as (
    select phenomenon_name, {{ weather_category('phenomenon_name') }} as category
    from names where phenomenon_name is not null and trim(phenomenon_name) <> ''
)
select row_number() over (order by phenomenon_name) as phenomenon_key,
    phenomenon_name, category,
    case
        when category in ('Rain', 'Snow or sleet', 'Hail') then true
        when category in ('Clear', 'Cloudy', 'Fog or mist') then false
        else null
    end as has_precipitation,
    case
        when category = 'Hail' then 'Hail'
        when lower(phenomenon_name) like '%sleet%' then 'Sleet'
        when lower(phenomenon_name) like '%snow%' then 'Snow'
        when category = 'Rain' then 'Rain'
    end as precipitation_type,
    case
        when lower(phenomenon_name) like '%light%' then 'Light'
        when lower(phenomenon_name) like '%moderate%' then 'Moderate'
        when lower(phenomenon_name) like '%heavy%' then 'Heavy'
    end as intensity
from classified
