with stamped as (
    select *, substring(file_name from '([0-9]{8}T[0-9]{6}Z)') as utc_stamp
    from {{ ref('stg_forecasts') }}
)
select forecast_date, period, location_name, temperature as forecast_temperature,
    phenomenon_name as forecast_phenomenon, file_name,
    -- UTC construction is independent of the database session timezone.
    make_timestamptz(
        substring(utc_stamp, 1, 4)::integer, substring(utc_stamp, 5, 2)::integer,
        substring(utc_stamp, 7, 2)::integer, substring(utc_stamp, 10, 2)::integer,
        substring(utc_stamp, 12, 2)::integer, substring(utc_stamp, 14, 2)::double precision,
        'UTC'
    ) as forecast_retrieved_at
from stamped
