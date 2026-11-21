select station_name, observation_timestamp_utc
from {{ ref('int_unified_observations') }}
group by station_name, observation_timestamp_utc
having count(*) > 1
