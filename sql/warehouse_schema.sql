-- Generated warehouse schema; dbt models are the transformation source.

--
-- PostgreSQL database dump
--

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 17.2 (Debian 17.2-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bronze; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bronze;


--
-- Name: public_gold; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public_gold;


--
-- Name: public_silver; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public_silver;


--
-- Name: snapshots; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA snapshots;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: raw_forecasts; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.raw_forecasts (
    id bigint NOT NULL,
    file_name character varying(255) NOT NULL,
    retrieved_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    raw_payload xml NOT NULL
);


--
-- Name: raw_forecasts_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.raw_forecasts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: raw_forecasts_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.raw_forecasts_id_seq OWNED BY bronze.raw_forecasts.id;


--
-- Name: raw_historical_observations; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.raw_historical_observations (
    id bigint NOT NULL,
    file_name character varying(255) NOT NULL,
    retrieved_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    raw_payload jsonb NOT NULL
);


--
-- Name: raw_historical_observations_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.raw_historical_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: raw_historical_observations_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.raw_historical_observations_id_seq OWNED BY bronze.raw_historical_observations.id;


--
-- Name: raw_observations; Type: TABLE; Schema: bronze; Owner: -
--

CREATE TABLE bronze.raw_observations (
    id bigint NOT NULL,
    file_name character varying(255) NOT NULL,
    retrieved_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    raw_payload xml NOT NULL
);


--
-- Name: raw_observations_id_seq; Type: SEQUENCE; Schema: bronze; Owner: -
--

CREATE SEQUENCE bronze.raw_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: raw_observations_id_seq; Type: SEQUENCE OWNED BY; Schema: bronze; Owner: -
--

ALTER SEQUENCE bronze.raw_observations_id_seq OWNED BY bronze.raw_observations.id;


--
-- Name: int_unified_observations; Type: TABLE; Schema: public_silver; Owner: -
--

CREATE TABLE public_silver.int_unified_observations (
    station_name text,
    observation_timestamp_utc timestamp with time zone,
    observation_datetime timestamp without time zone,
    temperature numeric,
    phenomenon_name text,
    precipitation_mm numeric,
    observation_source text,
    source_file character varying(255)
);


--
-- Name: stg_forecasts; Type: VIEW; Schema: public_silver; Owner: -
--

CREATE VIEW public_silver.stg_forecasts AS
 WITH forecasts AS (
         SELECT raw_forecasts.file_name,
            raw_forecasts.retrieved_at,
            unnest(xpath('//forecast'::text, raw_forecasts.raw_payload)) AS forecast_node
           FROM bronze.raw_forecasts
        ), places AS (
         SELECT forecasts.file_name,
            forecasts.retrieved_at,
            (((xpath('/forecast/@date'::text, forecasts.forecast_node))[1])::text)::date AS forecast_date,
            p.period,
            unnest(xpath((('/forecast/'::text || lower(p.period)) || '/place'::text), forecasts.forecast_node)) AS place
           FROM (forecasts
             CROSS JOIN ( VALUES ('Day'::text), ('Night'::text)) p(period))
        )
 SELECT file_name,
    retrieved_at,
    forecast_date,
    period,
    NULLIF(((xpath('/place/phenomenon/text()'::text, place))[1])::text, ''::text) AS phenomenon_name,
    ((xpath('/place/name/text()'::text, place))[1])::text AS location_name,
    (NULLIF(((xpath((('/place/'::text ||
        CASE
            WHEN (period = 'Day'::text) THEN 'tempmax'::text
            ELSE 'tempmin'::text
        END) || '/text()'::text), place))[1])::text, ''::text))::numeric AS temperature
   FROM places;


--
-- Name: dim_date; Type: TABLE; Schema: public_gold; Owner: -
--

CREATE TABLE public_gold.dim_date (
    date_key integer,
    full_date date,
    year integer,
    month integer,
    season text,
    day integer,
    quarter integer,
    day_of_week integer
);


--
-- Name: dim_forecast_location; Type: TABLE; Schema: public_gold; Owner: -
--

CREATE TABLE public_gold.dim_forecast_location (
    location_key bigint,
    location_name text
);


--
-- Name: dim_period; Type: TABLE; Schema: public_gold; Owner: -
--

CREATE TABLE public_gold.dim_period (
    period_key integer,
    period_name text
);


--
-- Name: dim_station; Type: TABLE; Schema: public_gold; Owner: -
--

CREATE TABLE public_gold.dim_station (
    station_key bigint,
    station_name text,
    wmo_code integer,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    is_current boolean
);


--
-- Name: dim_weather_phenomenon; Type: TABLE; Schema: public_gold; Owner: -
--

CREATE TABLE public_gold.dim_weather_phenomenon (
    phenomenon_key bigint,
    phenomenon_name text,
    category text,
    has_precipitation boolean,
    precipitation_type text,
    intensity text
);


--
-- Name: fact_forecast_accuracy; Type: TABLE; Schema: public_gold; Owner: -
--

CREATE TABLE public_gold.fact_forecast_accuracy (
    accuracy_key bigint,
    date_key integer,
    period_key integer,
    location_key bigint,
    station_key bigint,
    forecast_phenomenon_key bigint,
    observed_phenomenon_key bigint,
    retrieved_at timestamp with time zone,
    source_file character varying(255),
    collected_before_period boolean,
    forecast_temperature numeric,
    observed_temperature numeric,
    temperature_error numeric,
    absolute_error numeric,
    observed_precipitation_mm numeric,
    forecast_has_precipitation boolean,
    observed_has_precipitation boolean,
    precipitation_match boolean,
    phenomenon_match boolean,
    observation_count integer,
    precipitation_observation_count integer,
    phenomenon_observation_count integer,
    expected_observation_count integer,
    period_start_utc timestamp with time zone,
    period_end_utc timestamp with time zone,
    is_temperature_eligible boolean,
    is_precipitation_eligible boolean,
    is_phenomenon_eligible boolean
);


--
-- Name: stg_historical_observations; Type: VIEW; Schema: public_silver; Owner: -
--

CREATE VIEW public_silver.stg_historical_observations AS
 WITH records AS (
         SELECT b.file_name AS source_file,
            b.retrieved_at,
            r.record
           FROM (bronze.raw_historical_observations b
             CROSS JOIN LATERAL jsonb_array_elements(b.raw_payload) r(record))
        ), temperature_records AS (
         SELECT records.source_file,
            (records.record ->> 'jaam_kood'::text) AS station_code,
                CASE (records.record ->> 'jaam_nimi'::text)
                    WHEN 'Harku'::text THEN 'Tallinn-Harku'::text
                    WHEN 'Tõravere'::text THEN 'Tartu-Tõravere'::text
                    ELSE (records.record ->> 'jaam_nimi'::text)
                END AS station_name,
            make_timestamptz(((records.record ->> 'aasta'::text))::integer, ((records.record ->> 'kuu'::text))::integer, ((records.record ->> 'paev'::text))::integer, ((records.record ->> 'tund'::text))::integer, 0, (0)::double precision, 'UTC'::text) AS observation_timestamp_utc,
            (NULLIF((records.record ->> 'vaartus'::text), ''::text))::numeric AS temperature,
            (NULLIF((records.record ->> 'avaandmed_ts'::text), ''::text))::timestamp with time zone AS source_updated_at,
            records.retrieved_at
           FROM records
          WHERE ((records.record ->> 'element_kood'::text) = 'TA'::text)
        ), ranked AS (
         SELECT temperature_records.source_file,
            temperature_records.station_code,
            temperature_records.station_name,
            temperature_records.observation_timestamp_utc,
            temperature_records.temperature,
            temperature_records.source_updated_at,
            temperature_records.retrieved_at,
            row_number() OVER (PARTITION BY temperature_records.station_code, temperature_records.observation_timestamp_utc ORDER BY temperature_records.source_updated_at DESC NULLS LAST, temperature_records.retrieved_at DESC, temperature_records.source_file DESC) AS version_rank
           FROM temperature_records
        )
 SELECT station_code,
    station_name,
    observation_timestamp_utc,
    (observation_timestamp_utc AT TIME ZONE 'Europe/Tallinn'::text) AS observation_datetime,
    temperature,
    source_updated_at,
    source_file
   FROM ranked
  WHERE (version_rank = 1);


--
-- Name: stg_observations; Type: VIEW; Schema: public_silver; Owner: -
--

CREATE VIEW public_silver.stg_observations AS
 WITH files AS MATERIALIZED (
         SELECT raw_observations.file_name,
            raw_observations.retrieved_at,
            to_timestamp(((((xpath('/observations/@timestamp'::text, raw_observations.raw_payload))[1])::text)::bigint)::double precision) AS observation_timestamp_utc,
            xpath('/observations/station'::text, raw_observations.raw_payload) AS station_nodes
           FROM bronze.raw_observations
        ), stations AS (
         SELECT files.file_name,
            files.retrieved_at,
            files.observation_timestamp_utc,
            unnest(files.station_nodes) AS station
           FROM files
        )
 SELECT file_name,
    retrieved_at,
    observation_timestamp_utc,
    (observation_timestamp_utc AT TIME ZONE 'Europe/Tallinn'::text) AS observation_datetime,
    ((xpath('/station/name/text()'::text, station))[1])::text AS station_name,
    (NULLIF(((xpath('/station/airtemperature/text()'::text, station))[1])::text, ''::text))::numeric AS temperature,
    NULLIF(((xpath('/station/phenomenon/text()'::text, station))[1])::text, ''::text) AS phenomenon_name,
    (NULLIF(((xpath('/station/precipitations/text()'::text, station))[1])::text, ''::text))::numeric AS precipitation_mm
   FROM stations;


--
-- Name: station_snapshot; Type: TABLE; Schema: snapshots; Owner: -
--

CREATE TABLE snapshots.station_snapshot (
    station_name text,
    wmo_code integer,
    dbt_scd_id text,
    dbt_updated_at timestamp without time zone,
    dbt_valid_from timestamp without time zone,
    dbt_valid_to timestamp without time zone
);


--
-- Name: raw_forecasts id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_forecasts ALTER COLUMN id SET DEFAULT nextval('bronze.raw_forecasts_id_seq'::regclass);


--
-- Name: raw_historical_observations id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_historical_observations ALTER COLUMN id SET DEFAULT nextval('bronze.raw_historical_observations_id_seq'::regclass);


--
-- Name: raw_observations id; Type: DEFAULT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_observations ALTER COLUMN id SET DEFAULT nextval('bronze.raw_observations_id_seq'::regclass);


--
-- Name: raw_forecasts raw_forecasts_file_name_key; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_forecasts
    ADD CONSTRAINT raw_forecasts_file_name_key UNIQUE (file_name);


--
-- Name: raw_forecasts raw_forecasts_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_forecasts
    ADD CONSTRAINT raw_forecasts_pkey PRIMARY KEY (id);


--
-- Name: raw_historical_observations raw_historical_observations_file_name_key; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_historical_observations
    ADD CONSTRAINT raw_historical_observations_file_name_key UNIQUE (file_name);


--
-- Name: raw_historical_observations raw_historical_observations_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_historical_observations
    ADD CONSTRAINT raw_historical_observations_pkey PRIMARY KEY (id);


--
-- Name: raw_observations raw_observations_file_name_key; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_observations
    ADD CONSTRAINT raw_observations_file_name_key UNIQUE (file_name);


--
-- Name: raw_observations raw_observations_pkey; Type: CONSTRAINT; Schema: bronze; Owner: -
--

ALTER TABLE ONLY bronze.raw_observations
    ADD CONSTRAINT raw_observations_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--


--
-- PostgreSQL database dump
--

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 17.2 (Debian 17.2-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: int_observations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.int_observations AS
 SELECT observation_timestamp_utc,
    observation_datetime,
    station_name,
        CASE
            WHEN (station_name = 'Tallinn-Harku'::text) THEN 'Harku'::text
            WHEN (station_name = 'Tartu-Tõravere'::text) THEN 'Tartu'::text
            WHEN (station_name = 'Kuressaare linn'::text) THEN 'Kuressaare'::text
            ELSE station_name
        END AS location_name,
    temperature,
    phenomenon_name,
    precipitation_mm
   FROM public_silver.int_unified_observations
  WHERE (station_name = ANY (ARRAY['Tallinn-Harku'::text, 'Jõhvi'::text, 'Tartu-Tõravere'::text, 'Pärnu'::text, 'Kuressaare linn'::text, 'Türi'::text]));


--
-- Name: int_daily_observations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.int_daily_observations AS
 WITH events AS (
         SELECT int_observations.observation_timestamp_utc AS event_hour_utc,
            int_observations.observation_datetime AS event_local_time,
            int_observations.location_name,
            int_observations.station_name,
            int_observations.temperature,
            int_observations.phenomenon_name,
            NULL::numeric AS precipitation_mm
           FROM public.int_observations
        UNION ALL
         SELECT (int_observations.observation_timestamp_utc - '01:00:00'::interval),
            ((int_observations.observation_timestamp_utc - '01:00:00'::interval) AT TIME ZONE 'Europe/Tallinn'::text) AS timezone,
            int_observations.location_name,
            int_observations.station_name,
            NULL::numeric AS "numeric",
            NULL::text AS text,
            int_observations.precipitation_mm
           FROM public.int_observations
        ), periods AS (
         SELECT events.event_hour_utc,
            events.event_local_time,
            events.location_name,
            events.station_name,
            events.temperature,
            events.phenomenon_name,
            events.precipitation_mm,
            ((events.event_local_time)::date +
                CASE
                    WHEN (EXTRACT(hour FROM events.event_local_time) >= (18)::numeric) THEN 1
                    ELSE 0
                END) AS observation_date,
                CASE
                    WHEN ((EXTRACT(hour FROM events.event_local_time) >= (6)::numeric) AND (EXTRACT(hour FROM events.event_local_time) < (18)::numeric)) THEN 'Day'::text
                    ELSE 'Night'::text
                END AS period,
                CASE
                    WHEN (lower(events.phenomenon_name) ~~ '%hail%'::text) THEN 'Hail'::text
                    WHEN ((lower(events.phenomenon_name) ~~ '%snow%'::text) OR (lower(events.phenomenon_name) ~~ '%sleet%'::text)) THEN 'Snow or sleet'::text
                    WHEN ((lower(events.phenomenon_name) ~~ '%rain%'::text) OR (lower(events.phenomenon_name) ~~ '%shower%'::text) OR (lower(events.phenomenon_name) ~~ '%drizzle%'::text) OR (lower(events.phenomenon_name) = 'thunderstorm'::text)) THEN 'Rain'::text
                    WHEN ((lower(events.phenomenon_name) ~~ '%fog%'::text) OR (lower(events.phenomenon_name) ~~ '%mist%'::text)) THEN 'Fog or mist'::text
                    WHEN ((lower(events.phenomenon_name) ~~ '%cloud%'::text) OR (lower(events.phenomenon_name) = 'overcast'::text)) THEN 'Cloudy'::text
                    WHEN (lower(events.phenomenon_name) = 'clear'::text) THEN 'Clear'::text
                    ELSE 'Other'::text
                END AS category
           FROM events
          WHERE ((events.temperature IS NOT NULL) OR (events.precipitation_mm IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM events.phenomenon_name), ''::text) IS NOT NULL))
        ), summary AS (
         SELECT periods.observation_date,
            periods.location_name,
            periods.station_name,
            periods.period,
                CASE
                    WHEN (periods.period = 'Day'::text) THEN max(periods.temperature)
                    ELSE min(periods.temperature)
                END AS actual_temperature,
            sum(periods.precipitation_mm) AS actual_precipitation_mm,
            (count(DISTINCT periods.event_hour_utc) FILTER (WHERE (periods.temperature IS NOT NULL)))::integer AS observation_count,
            (count(DISTINCT periods.event_hour_utc) FILTER (WHERE (periods.precipitation_mm IS NOT NULL)))::integer AS precipitation_observation_count,
            (count(DISTINCT periods.event_hour_utc) FILTER (WHERE (periods.category <> 'Other'::text)))::integer AS phenomenon_observation_count
           FROM periods
          GROUP BY periods.observation_date, periods.location_name, periods.station_name, periods.period
        ), category_counts AS (
         SELECT periods.observation_date,
            periods.location_name,
            periods.station_name,
            periods.period,
            periods.category,
            count(*) AS frequency
           FROM periods
          WHERE (periods.category <> 'Other'::text)
          GROUP BY periods.observation_date, periods.location_name, periods.station_name, periods.period, periods.category
        ), category_ranks AS (
         SELECT category_counts.observation_date,
            category_counts.location_name,
            category_counts.station_name,
            category_counts.period,
            category_counts.category,
            category_counts.frequency,
            row_number() OVER (PARTITION BY category_counts.observation_date, category_counts.location_name, category_counts.station_name, category_counts.period ORDER BY category_counts.frequency DESC, category_counts.category) AS category_rank
           FROM category_counts
        ), name_counts AS (
         SELECT p.observation_date,
            p.location_name,
            p.station_name,
            p.period,
            p.phenomenon_name,
            c.category,
            count(*) AS frequency
           FROM (periods p
             JOIN category_ranks c ON (((p.observation_date = c.observation_date) AND (p.location_name = c.location_name) AND (p.station_name = c.station_name) AND (p.period = c.period) AND (p.category = c.category) AND (c.category_rank = 1))))
          GROUP BY p.observation_date, p.location_name, p.station_name, p.period, p.phenomenon_name, c.category
        ), name_ranks AS (
         SELECT name_counts.observation_date,
            name_counts.location_name,
            name_counts.station_name,
            name_counts.period,
            name_counts.phenomenon_name,
            name_counts.category,
            name_counts.frequency,
            row_number() OVER (PARTITION BY name_counts.observation_date, name_counts.location_name, name_counts.station_name, name_counts.period ORDER BY name_counts.frequency DESC, name_counts.phenomenon_name) AS name_rank
           FROM name_counts
        ), bounded AS (
         SELECT s.observation_date,
            s.location_name,
            s.station_name,
            s.period,
            s.actual_temperature,
            s.actual_precipitation_mm,
            s.observation_count,
            s.precipitation_observation_count,
            s.phenomenon_observation_count,
            n.phenomenon_name AS observed_phenomenon,
            n.category AS observed_category,
            (((s.observation_date)::timestamp without time zone +
                CASE
                    WHEN (s.period = 'Day'::text) THEN '06:00:00'::interval
                    ELSE '-06:00:00'::interval
                END) AT TIME ZONE 'Europe/Tallinn'::text) AS period_start_utc,
            (((s.observation_date)::timestamp without time zone +
                CASE
                    WHEN (s.period = 'Day'::text) THEN '18:00:00'::interval
                    ELSE '06:00:00'::interval
                END) AT TIME ZONE 'Europe/Tallinn'::text) AS period_end_utc
           FROM (summary s
             LEFT JOIN name_ranks n ON (((s.observation_date = n.observation_date) AND (s.location_name = n.location_name) AND (s.station_name = n.station_name) AND (s.period = n.period) AND (n.name_rank = 1))))
        )
 SELECT observation_date,
    location_name,
    station_name,
    period,
    actual_temperature,
    actual_precipitation_mm,
    observation_count,
    precipitation_observation_count,
    phenomenon_observation_count,
    observed_phenomenon,
    observed_category,
    period_start_utc,
    period_end_utc,
    ((EXTRACT(epoch FROM (period_end_utc - period_start_utc)) / (3600)::numeric))::integer AS expected_observation_count
   FROM bounded;


--
-- Name: int_latest_forecasts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.int_latest_forecasts AS
 WITH stamped AS (
         SELECT stg_forecasts.file_name,
            stg_forecasts.retrieved_at,
            stg_forecasts.forecast_date,
            stg_forecasts.period,
            stg_forecasts.phenomenon_name,
            stg_forecasts.location_name,
            stg_forecasts.temperature,
            "substring"((stg_forecasts.file_name)::text, '([0-9]{8}T[0-9]{6}Z)'::text) AS utc_stamp
           FROM public_silver.stg_forecasts
        )
 SELECT forecast_date,
    period,
    location_name,
    temperature AS forecast_temperature,
    phenomenon_name AS forecast_phenomenon,
    file_name,
    make_timestamptz(("substring"(utc_stamp, 1, 4))::integer, ("substring"(utc_stamp, 5, 2))::integer, ("substring"(utc_stamp, 7, 2))::integer, ("substring"(utc_stamp, 10, 2))::integer, ("substring"(utc_stamp, 12, 2))::integer, ("substring"(utc_stamp, 14, 2))::double precision, 'UTC'::text) AS forecast_retrieved_at
   FROM stamped;


--
-- PostgreSQL database dump complete
--

