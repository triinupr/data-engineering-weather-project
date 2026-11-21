select station_name, observation_datetime
from {{ ref('int_unified_observations') }}
group by station_name, observation_datetime
having count(*) > 1
