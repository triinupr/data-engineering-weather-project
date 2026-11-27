-- Weather Forecast Accuracy
-- Project 2: Analytical queries

-- These queries answer the business questions defined in Project 1 and address the feedback received.

-- All eligible forecast snapshots are included in the analysis, rather than selecting only the latest snapshot for each period.
-- Each KPI is calculated using its corresponding eligibility flag.


-- Q0. Dataset overview and KPI eligibility

SELECT
    COUNT(*) AS total_forecast_rows,
    COUNT(*) FILTER (
        WHERE is_temperature_eligible = TRUE
    ) AS temperature_eligible_rows,
    COUNT(*) FILTER (
        WHERE is_precipitation_eligible = TRUE
    ) AS precipitation_eligible_rows,
    COUNT(*) FILTER (
        WHERE is_phenomenon_eligible = TRUE
    ) AS phenomenon_eligible_rows
FROM public_gold.fact_forecast_accuracy;


-- Q1. How accurately do weather forecasts predict the observed temperature?

SELECT
    ROUND(AVG(absolute_error)::numeric, 2) AS temperature_mae,
    COUNT(*) AS number_of_comparisons
FROM public_gold.fact_forecast_accuracy
WHERE is_temperature_eligible = TRUE;


-- Q2. Does forecast accuracy differ between daytime and nighttime forecasts?

SELECT
    p.period_name,
    ROUND(AVG(f.absolute_error)::numeric, 2) AS temperature_mae,
    COUNT(*) AS number_of_comparisons
FROM public_gold.fact_forecast_accuracy f
JOIN public_gold.dim_period p
    ON f.period_key = p.period_key
WHERE f.is_temperature_eligible = TRUE
GROUP BY p.period_name
ORDER BY temperature_mae;

-- Q3. Which weather stations or geographical areas have the highest and lowest temperature forecast errors?

-- Forecasts without a matching station or sufficient observation data are retained in the fact table but excluded from the analysis.

SELECT
    l.location_name,
    s.station_name,
    ROUND(AVG(f.absolute_error)::numeric, 2) AS temperature_mae,
    COUNT(*) AS number_of_comparisons
FROM public_gold.fact_forecast_accuracy f
JOIN public_gold.dim_forecast_location l
    ON f.location_key = l.location_key
JOIN public_gold.dim_station s
    ON f.station_key = s.station_key
WHERE f.is_temperature_eligible = TRUE
GROUP BY
    l.location_name,
    s.station_name
ORDER BY temperature_mae DESC;


-- Q4. Does temperature forecast accuracy vary by month or season?

-- Results are grouped by year and month to avoid combining the same months from different years.

SELECT
    d.year,
    d.month,
    d.season,
    ROUND(AVG(f.absolute_error)::numeric, 2) AS temperature_mae,
    COUNT(*) AS number_of_comparisons
FROM public_gold.fact_forecast_accuracy f
JOIN public_gold.dim_date d
    ON f.date_key = d.date_key
WHERE f.is_temperature_eligible = TRUE
GROUP BY
    d.year,
    d.month,
    d.season
ORDER BY
    d.year,
    d.month;


-- Q5. Under which weather conditions are temperature forecasts least accurate?
-- Only comparisons eligible for both temperature and weather phenomenon analysis are included.

SELECT
    wp.category AS observed_weather_condition,
    ROUND(AVG(f.absolute_error)::numeric, 2) AS temperature_mae,
    COUNT(*) AS number_of_comparisons
FROM public_gold.fact_forecast_accuracy f
JOIN public_gold.dim_weather_phenomenon wp
    ON f.observed_phenomenon_key = wp.phenomenon_key
WHERE f.is_temperature_eligible = TRUE
    AND f.is_phenomenon_eligible = TRUE
GROUP BY wp.category
ORDER BY temperature_mae DESC;



-- Q6. Are forecast errors systematically biased, for example, are temperatures more often predicted too high or too low?

-- Positive errors indicate overprediction, while negative errors indicate underprediction. 

SELECT
    CASE
        WHEN temperature_error > 0 THEN 'Overprediction'
        WHEN temperature_error < 0 THEN 'Underprediction'
        ELSE 'Exact prediction'
    END AS bias_direction,
    COUNT(*) AS number_of_comparisons,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2
    ) AS percentage_of_comparisons,
    ROUND(AVG(temperature_error)::numeric, 2) AS average_signed_error
FROM public_gold.fact_forecast_accuracy
WHERE is_temperature_eligible = TRUE
GROUP BY bias_direction
ORDER BY number_of_comparisons DESC;


-- Q6b. Overall temperature forecast bias
SELECT
    ROUND(AVG(temperature_error)::numeric, 2) AS mean_error,
    COUNT(*) AS number_of_comparisons
FROM public_gold.fact_forecast_accuracy
WHERE is_temperature_eligible = TRUE;


-- Q7. How accurately do weather forecasts predict the occurrence of precipitation?

-- Precipitation accuracy was defined as a KPI in Project 1, but no corresponding business question or SQL query was included.
-- This query was added based on the feedback received.

SELECT
    COUNT(*) AS number_of_comparisons,
    COUNT(*) FILTER (
        WHERE precipitation_match = TRUE
    ) AS correct_predictions,
    COUNT(*) FILTER (
        WHERE precipitation_match = FALSE
    ) AS incorrect_predictions,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE precipitation_match = TRUE
        ) / NULLIF(COUNT(*), 0), 2
    ) AS precipitation_accuracy_pct
FROM public_gold.fact_forecast_accuracy
WHERE is_precipitation_eligible = TRUE;




-- Q8. How accurately do weather forecasts predict observed weather phenomena?

-- Weather phenomenon accuracy was defined as a KPI in Project 1, but no corresponding business question or SQL query was included.

SELECT
    COUNT(*) AS number_of_comparisons,
    COUNT(*) FILTER (
        WHERE phenomenon_match = TRUE
    ) AS correct_predictions,
    COUNT(*) FILTER (
        WHERE phenomenon_match = FALSE
    ) AS incorrect_predictions,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE phenomenon_match = TRUE
        ) / NULLIF(COUNT(*), 0), 2
    ) AS phenomenon_accuracy_pct
FROM public_gold.fact_forecast_accuracy
WHERE is_phenomenon_eligible = TRUE;