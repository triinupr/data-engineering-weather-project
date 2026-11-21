select observation_timestamp_utc, observation_datetime, station_name,
    case
        when station_name = 'Tallinn-Harku' then 'Harku'
        when station_name = 'Tartu-Tõravere' then 'Tartu'
        when station_name = 'Kuressaare linn' then 'Kuressaare'
        else station_name
    end as location_name,
    temperature, phenomenon_name, precipitation_mm
from {{ ref('int_unified_observations') }}
where station_name in (
    'Tallinn-Harku', 'Jõhvi', 'Tartu-Tõravere', 'Pärnu', 'Kuressaare linn', 'Türi'
)
-- Retain other metrics even when temperature is unavailable.
