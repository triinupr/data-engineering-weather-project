select 1::bigint as id, 'forecasts_20240101T030000Z.xml'::varchar as file_name,
    '2024-01-01T03:00:00Z'::timestamptz as retrieved_at,
    '<forecasts><forecast date="2024-01-01"><day><phenomenon>Variable clouds</phenomenon><place><name>Harku</name><phenomenon>Light shower</phenomenon><tempmax>8</tempmax></place></day></forecast><forecast date="2024-01-02"><day><phenomenon>Rain</phenomenon><place><name>Harku</name><phenomenon>Clear</phenomenon><tempmax>9</tempmax></place></day></forecast></forecasts>'::xml as raw_payload
