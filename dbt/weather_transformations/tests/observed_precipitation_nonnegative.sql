select * from {{ ref('stg_observations') }}
where precipitation_mm < 0 or precipitation_mm::text in ('NaN', 'Infinity', '-Infinity')
