select 'AJHARK01'::text as station_code, 'Tallinn-Harku'::text as station_name,
    '2024-10-27T00:00:00Z'::timestamptz as observation_timestamp_utc,
    '2024-10-27T00:00:00Z'::timestamptz at time zone 'Europe/Tallinn' as observation_datetime,
    9::numeric as temperature, '2024-10-28T00:00:00Z'::timestamptz as source_updated_at,
    '2024_10/page_0001.json'::text as source_file
