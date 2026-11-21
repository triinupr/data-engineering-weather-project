with forecasts as (
    select file_name, retrieved_at, unnest(xpath('//forecast', raw_payload)) as forecast_node
    from {{ source('bronze', 'raw_forecasts') }}
),
places as (
    select file_name, retrieved_at,
        (xpath('/forecast/@date', forecast_node))[1]::text::date as forecast_date,
        p.period,
        unnest(xpath('/forecast/' || lower(p.period) || '/place', forecast_node)) as place
    from forecasts
    cross join (values ('Day'), ('Night')) as p(period)
)
select file_name, retrieved_at, forecast_date, period,
    -- Use each location's own phenomenon, not the regional summary.
    nullif((xpath('/place/phenomenon/text()', place))[1]::text, '') as phenomenon_name,
    (xpath('/place/name/text()', place))[1]::text as location_name,
    nullif((xpath('/place/' || case when period = 'Day' then 'tempmax' else 'tempmin' end
        || '/text()', place))[1]::text, '')::numeric as temperature
from places
