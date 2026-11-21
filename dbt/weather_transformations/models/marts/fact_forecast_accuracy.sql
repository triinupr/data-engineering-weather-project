{{ config(materialized='table', schema='gold') }}
with forecasts as (
    select f.*,
        {{ weather_period_start('f.forecast_date', 'f.period') }} as period_start_utc,
        {{ weather_period_end('f.forecast_date', 'f.period') }} as period_end_utc
    from {{ ref('int_latest_forecasts') }} f
),
comparisons as (
    select
        row_number() over (
            order by f.forecast_retrieved_at, f.forecast_date, f.period,
                f.location_name, f.file_name
        ) as accuracy_key,
        d.date_key, p.period_key, l.location_key, s.station_key,
        fp.phenomenon_key as forecast_phenomenon_key,
        case when o.phenomenon_observation_count = o.expected_observation_count
            then op.phenomenon_key end as observed_phenomenon_key,
        f.forecast_retrieved_at as retrieved_at, f.file_name as source_file,
        f.period_start_utc, f.period_end_utc,
        coalesce(f.forecast_retrieved_at < f.period_start_utc, false) as collected_before_period,
        f.forecast_temperature,
        case when o.observation_count = o.expected_observation_count
            then o.actual_temperature end as observed_temperature,
        case when o.precipitation_observation_count = o.expected_observation_count
            then o.actual_precipitation_mm end as observed_precipitation_mm,
        fp.has_precipitation as forecast_has_precipitation,
        case when o.precipitation_observation_count = o.expected_observation_count
            then o.actual_precipitation_mm > 0 end as observed_has_precipitation,
        fp.category as forecast_category, op.category as observed_category,
        coalesce(o.observation_count, 0) as observation_count,
        coalesce(o.precipitation_observation_count, 0) as precipitation_observation_count,
        coalesce(o.phenomenon_observation_count, 0) as phenomenon_observation_count,
        (extract(epoch from (f.period_end_utc - f.period_start_utc)) / 3600)::integer
            as expected_observation_count
    from forecasts f
    left join {{ ref('int_daily_observations') }} o
        on f.forecast_date = o.observation_date and f.location_name = o.location_name
        and f.period = o.period
    join {{ ref('dim_date') }} d on f.forecast_date = d.full_date
    join {{ ref('dim_period') }} p on f.period = p.period_name
    join {{ ref('dim_forecast_location') }} l on f.location_name = l.location_name
    left join {{ ref('dim_station') }} s
        on o.station_name = s.station_name
        and (
            (f.forecast_retrieved_at >= s.valid_from
             and (f.forecast_retrieved_at < s.valid_to or s.valid_to is null))
            or (f.forecast_retrieved_at < s.valid_from and s.valid_from = (
                select min(s2.valid_from) from {{ ref('dim_station') }} s2
                where s2.station_name = s.station_name
            ))
        )
    left join {{ ref('dim_weather_phenomenon') }} fp
        on f.forecast_phenomenon = fp.phenomenon_name
    left join {{ ref('dim_weather_phenomenon') }} op
        on o.observed_phenomenon = op.phenomenon_name
),
eligibility as (
    select *,
        collected_before_period and period_end_utc <= current_timestamp
            and station_key is not null and forecast_temperature is not null
            and observation_count = expected_observation_count
            and observed_temperature is not null as is_temperature_eligible,
        collected_before_period and period_end_utc <= current_timestamp
            and station_key is not null and forecast_has_precipitation is not null
            and precipitation_observation_count = expected_observation_count
            and observed_has_precipitation is not null as is_precipitation_eligible,
        collected_before_period and period_end_utc <= current_timestamp
            and station_key is not null and forecast_category <> 'Other'
            and phenomenon_observation_count = expected_observation_count
            and observed_phenomenon_key is not null and observed_category <> 'Other'
            as is_phenomenon_eligible
    from comparisons
)
select accuracy_key, date_key, period_key, location_key, station_key,
    forecast_phenomenon_key, observed_phenomenon_key, retrieved_at, source_file,
    collected_before_period, forecast_temperature, observed_temperature,
    case when is_temperature_eligible then forecast_temperature - observed_temperature end
        as temperature_error,
    case when is_temperature_eligible then abs(forecast_temperature - observed_temperature) end
        as absolute_error,
    observed_precipitation_mm, forecast_has_precipitation, observed_has_precipitation,
    case when is_precipitation_eligible then forecast_has_precipitation = observed_has_precipitation end
        as precipitation_match,
    case when is_phenomenon_eligible then forecast_category = observed_category end
        as phenomenon_match,
    observation_count, precipitation_observation_count, phenomenon_observation_count,
    expected_observation_count, period_start_utc, period_end_utc,
    coalesce(is_temperature_eligible, false) as is_temperature_eligible,
    coalesce(is_precipitation_eligible, false) as is_precipitation_eligible,
    coalesce(is_phenomenon_eligible, false) as is_phenomenon_eligible
from eligibility
