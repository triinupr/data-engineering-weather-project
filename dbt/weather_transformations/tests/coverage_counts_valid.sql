select * from {{ ref('int_daily_observations') }}
where expected_observation_count not in (11, 12, 13)
    or observation_count not between 0 and expected_observation_count
    or precipitation_observation_count not between 0 and expected_observation_count
    or phenomenon_observation_count not between 0 and expected_observation_count
