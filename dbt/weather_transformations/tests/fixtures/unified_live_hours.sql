select file_name::varchar, '2024-10-28T00:00:00Z'::timestamptz as retrieved_at,
    ts::timestamptz as observation_timestamp_utc,
    ts::timestamptz at time zone 'Europe/Tallinn' as observation_datetime,
    'Tallinn-Harku'::text as station_name, temp::numeric as temperature,
    'Clear'::text as phenomenon_name, 0.2::numeric as precipitation_mm
from (values
    ('a.xml', '2024-10-27T00:05:00Z', 10),
    ('b.xml', '2024-10-27T00:10:00Z', 11),
    ('c.xml', '2024-10-27T01:05:00Z', null)
) as x(file_name, ts, temp)
