select station_code, observation_timestamp_utc
from {{ ref('stg_historical_observations') }}
group by station_code, observation_timestamp_utc
having count(*) > 1
