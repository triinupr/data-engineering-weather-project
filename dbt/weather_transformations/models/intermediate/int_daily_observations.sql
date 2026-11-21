with events as (
    -- Point samples belong to the hour starting at the UTC key.
    select observation_timestamp_utc as event_hour_utc,
        observation_datetime as event_local_time,
        location_name, station_name, temperature, phenomenon_name,
        null::numeric as precipitation_mm
    from {{ ref('int_observations') }}
    union all
    -- Rain reported at 18:00 closes 17:00-18:00 and belongs to Day.
    select observation_timestamp_utc - interval '1 hour',
        (observation_timestamp_utc - interval '1 hour') at time zone 'Europe/Tallinn',
        location_name, station_name, null::numeric, null::text, precipitation_mm
    from {{ ref('int_observations') }}
),
periods as (
    select *,
        event_local_time::date + case when extract(hour from event_local_time) >= 18
            then 1 else 0 end as observation_date,
        case when extract(hour from event_local_time) >= 6
                   and extract(hour from event_local_time) < 18
            then 'Day' else 'Night' end as period,
        {{ weather_category('phenomenon_name') }} as category
    from events
    where temperature is not null or precipitation_mm is not null
        or nullif(trim(phenomenon_name), '') is not null
),
summary as (
    select observation_date, location_name, station_name, period,
        case when period = 'Day' then max(temperature) else min(temperature) end
            as actual_temperature,
        sum(precipitation_mm) as actual_precipitation_mm,
        count(distinct event_hour_utc) filter (where temperature is not null)::integer
            as observation_count,
        count(distinct event_hour_utc) filter (where precipitation_mm is not null)::integer
            as precipitation_observation_count,
        count(distinct event_hour_utc) filter (where category <> 'Other')::integer
            as phenomenon_observation_count
    from periods
    group by observation_date, location_name, station_name, period
),
category_counts as (
    select observation_date, location_name, station_name, period, category, count(*) as frequency
    from periods where category <> 'Other'
    group by observation_date, location_name, station_name, period, category
),
category_ranks as (
    select *, row_number() over (
        partition by observation_date, location_name, station_name, period
        order by frequency desc, category asc
    ) as category_rank
    from category_counts
),
name_counts as (
    select p.observation_date, p.location_name, p.station_name, p.period,
        p.phenomenon_name, c.category, count(*) as frequency
    from periods p
    join category_ranks c
        on p.observation_date = c.observation_date and p.location_name = c.location_name
        and p.station_name = c.station_name and p.period = c.period
        and p.category = c.category and c.category_rank = 1
    group by p.observation_date, p.location_name, p.station_name, p.period,
        p.phenomenon_name, c.category
),
name_ranks as (
    select *, row_number() over (
        partition by observation_date, location_name, station_name, period
        order by frequency desc, phenomenon_name asc
    ) as name_rank
    from name_counts
),
bounded as (
    select s.*, n.phenomenon_name as observed_phenomenon,
        n.category as observed_category,
        {{ weather_period_start('s.observation_date', 's.period') }} as period_start_utc,
        {{ weather_period_end('s.observation_date', 's.period') }} as period_end_utc
    from summary s
    left join name_ranks n
        on s.observation_date = n.observation_date and s.location_name = n.location_name
        and s.station_name = n.station_name and s.period = n.period and n.name_rank = 1
)
select *, (extract(epoch from (period_end_utc - period_start_utc)) / 3600)::integer
    as expected_observation_count
from bounded
