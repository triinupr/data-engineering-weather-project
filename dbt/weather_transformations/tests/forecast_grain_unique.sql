select file_name, forecast_date, period, location_name
from {{ ref('stg_forecasts') }}
group by file_name, forecast_date, period, location_name
having count(*) > 1
