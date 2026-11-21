{% macro weather_category(expression) -%}
case
    when lower({{ expression }}) like '%hail%' then 'Hail'
    when lower({{ expression }}) like '%snow%'
      or lower({{ expression }}) like '%sleet%' then 'Snow or sleet'
    when lower({{ expression }}) like '%rain%'
      or lower({{ expression }}) like '%shower%'
      or lower({{ expression }}) like '%drizzle%'
      or lower({{ expression }}) = 'thunderstorm' then 'Rain'
    when lower({{ expression }}) like '%fog%'
      or lower({{ expression }}) like '%mist%' then 'Fog or mist'
    when lower({{ expression }}) like '%cloud%'
      or lower({{ expression }}) = 'overcast' then 'Cloudy'
    when lower({{ expression }}) = 'clear' then 'Clear'
    else 'Other'
end
{%- endmacro %}
