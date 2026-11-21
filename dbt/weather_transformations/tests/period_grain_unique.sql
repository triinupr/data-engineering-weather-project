select observation_date, period, location_name, station_name
from {{ ref('int_daily_observations') }}
group by observation_date, period, location_name, station_name
having count(*) > 1
