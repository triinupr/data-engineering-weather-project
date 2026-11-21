select * from {{ ref('stg_historical_observations') }}
where temperature is not null and not (temperature between -50 and 50)
