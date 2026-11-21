select * from {{ ref('fact_forecast_accuracy') }}
where (not is_temperature_eligible and (temperature_error is not null or absolute_error is not null))
   or (is_temperature_eligible and (temperature_error is null or absolute_error is null))
   or (not is_precipitation_eligible and precipitation_match is not null)
   or (is_precipitation_eligible and precipitation_match is null)
   or (not is_phenomenon_eligible and phenomenon_match is not null)
   or (is_phenomenon_eligible and phenomenon_match is null)
   or (observed_precipitation_mm is null and observed_has_precipitation is not null)
