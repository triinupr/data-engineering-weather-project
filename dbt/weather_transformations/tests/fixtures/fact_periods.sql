select d::date as observation_date, 'Harku'::text as location_name,
    'Tallinn-Harku'::text as station_name, p::text as period,
    temp::numeric as actual_temperature, rain::numeric as actual_precipitation_mm,
    tc::integer as observation_count, rc::integer as precipitation_observation_count,
    pc::integer as phenomenon_observation_count, ph::text as observed_phenomenon,
    cat::text as observed_category,
    (d::date::timestamp + case when p = 'Day' then interval '6 hours' else interval '-6 hours' end)
        at time zone 'Europe/Tallinn' as period_start_utc,
    (d::date::timestamp + case when p = 'Day' then interval '18 hours' else interval '6 hours' end)
        at time zone 'Europe/Tallinn' as period_end_utc,
    12::integer as expected_observation_count
from (values
    ('2024-01-01', 'Day', 12, 0, 12, 12, 12, 'Overcast', 'Cloudy'),
    ('2024-01-01', 'Night', 5, null, 12, 0, 0, null, null),
    ('2024-01-02', 'Day', 13, 2, 12, 12, 12, 'Light rain', 'Rain'),
    ('2024-01-03', 'Day', 12, 1, 11, 11, 11, 'Light rain', 'Rain')
) as x(d, p, temp, rain, tc, rc, pc, ph, cat)
