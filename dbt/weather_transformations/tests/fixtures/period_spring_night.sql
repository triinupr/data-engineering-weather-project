select h as observation_timestamp_utc,
    h at time zone 'Europe/Tallinn' as observation_datetime,
    'Tallinn-Harku'::text as station_name, 'Harku'::text as location_name,
    case when h < '2024-03-31 03:00Z'::timestamptz then 5 end::numeric as temperature,
    case when h < '2024-03-31 03:00Z'::timestamptz then 'Clear' end::text as phenomenon_name,
    case when h > '2024-03-30 16:00Z'::timestamptz then 0 end::numeric as precipitation_mm
from generate_series('2024-03-30 16:00Z'::timestamptz,
                     '2024-03-31 03:00Z'::timestamptz, interval '1 hour') as t(h)
