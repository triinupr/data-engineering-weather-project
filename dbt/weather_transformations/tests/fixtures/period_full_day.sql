select h as observation_timestamp_utc,
    h at time zone 'Europe/Tallinn' as observation_datetime,
    'Tallinn-Harku'::text as station_name, 'Harku'::text as location_name,
    case when h < '2024-01-01 16:00Z'::timestamptz
        then extract(hour from h at time zone 'UTC') - 3 end::numeric as temperature,
    case when h = '2024-01-01 15:00Z'::timestamptz then 'Clear'
         when h < '2024-01-01 16:00Z'::timestamptz then 'Overcast' end::text as phenomenon_name,
    case when h = '2024-01-01 04:00Z'::timestamptz then null
         when h = '2024-01-01 16:00Z'::timestamptz then 3 else 0 end::numeric as precipitation_mm
from generate_series('2024-01-01 04:00Z'::timestamptz,
                     '2024-01-01 16:00Z'::timestamptz, interval '1 hour') as t(h)
