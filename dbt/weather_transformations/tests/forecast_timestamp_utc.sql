select * from {{ ref('int_latest_forecasts') }}
where forecast_retrieved_at is null
   or to_char(forecast_retrieved_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"')
      is distinct from substring(file_name from '([0-9]{8}T[0-9]{6}Z)')
