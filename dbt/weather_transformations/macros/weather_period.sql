{% macro weather_period_start(date_expression, period_expression) -%}
(({{ date_expression }})::timestamp +
    case when {{ period_expression }} = 'Day' then interval '6 hours'
         else interval '-6 hours' end) at time zone 'Europe/Tallinn'
{%- endmacro %}

{% macro weather_period_end(date_expression, period_expression) -%}
(({{ date_expression }})::timestamp +
    case when {{ period_expression }} = 'Day' then interval '18 hours'
         else interval '6 hours' end) at time zone 'Europe/Tallinn'
{%- endmacro %}
