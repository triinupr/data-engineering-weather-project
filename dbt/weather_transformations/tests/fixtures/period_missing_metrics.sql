select h as observation_timestamp_utc,
    h at time zone 'Europe/Tallinn' as observation_datetime,
    'Kuressaare linn'::text as station_name, 'Kuressaare'::text as location_name,
    8::numeric as temperature, null::text as phenomenon_name, null::numeric as precipitation_mm
from generate_series('2024-01-01 04:00Z'::timestamptz,
                     '2024-01-01 15:00Z'::timestamptz, interval '1 hour') as t(h)
