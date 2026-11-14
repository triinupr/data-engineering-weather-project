WITH observations AS (
    SELECT
        observation_datetime,
        observation_datetime::date AS observation_date,
        EXTRACT(HOUR FROM observation_datetime) AS observation_hour,
        location_name,
        station_name,
        temperature,
        phenomenon_name
    FROM {{ ref('int_observations') }}
),

period_observations AS (
    SELECT
        CASE
            WHEN observation_hour >= 18
                THEN observation_date + 1
            ELSE observation_date
        END AS observation_date,
        location_name,
        station_name,
        'Night' AS period,
        observation_datetime,
        temperature,
        phenomenon_name
    FROM observations
    WHERE observation_hour >= 18
       OR observation_hour < 6

    UNION ALL

    SELECT
        observation_date,
        location_name,
        station_name,
        'Day' AS period,
        observation_datetime,
        temperature,
        phenomenon_name
    FROM observations
    WHERE observation_hour >= 6
      AND observation_hour < 18
),

ranked_observations AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                observation_date,
                location_name,
                station_name,
                period
            ORDER BY
                CASE
                    WHEN period = 'Day' THEN temperature
                END DESC NULLS LAST,
                CASE
                    WHEN period = 'Night' THEN temperature
                END ASC NULLS LAST,
                observation_datetime ASC
        ) AS row_num
    FROM period_observations
)

SELECT
    observation_date,
    location_name,
    station_name,
    period,
    temperature AS actual_temperature,
    phenomenon_name AS observed_phenomenon
FROM ranked_observations
WHERE row_num = 1