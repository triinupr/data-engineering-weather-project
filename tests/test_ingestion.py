"""Offline regression tests; network responses are synthetic and explicitly mocked."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import requests

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("weather_ingest", ROOT / "src/ingest.py")
ingest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ingest)


def record(**changes):
    return {
        "jaam_kood": "SYNTHETIC_TEST_STATION",
        "jaam_nimi": "Tallinn-Harku",
        "aasta": 2026, "kuu": 10, "paev": 7, "tund": 3,
        "element_kood": "TA", "vaartus": 8.5,
        "avaandmed_ts": "2026-11-01T00:00:00Z",
        **changes,
    }


def response(rows):
    result = Mock()
    result.json.return_value = rows
    result.content = json.dumps(rows).encode()
    return result


class IngestionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.path_patch = patch.object(ingest, "RAW_DATA_DIR", self.directory)
        self.path_patch.start()

    def tearDown(self):
        self.path_patch.stop()
        self.temporary.cleanup()

    def test_xml_samples_and_bad_xml(self):
        for kind, filename in [("forecast", "forecast_sample.xml"),
                               ("observations", "observations_sample.xml")]:
            ingest.validate_xml_data_quality((ROOT / "data/sample" / filename).read_bytes(), kind)
        with self.assertRaises(ValueError):
            ingest.validate_xml_data_quality(b"<broken", "forecast")

    def test_conflicting_duplicate_observations_fail(self):
        xml = b'<observations><station><name>Test</name><airtemperature>1</airtemperature></station><station><name>Test</name><airtemperature>2</airtemperature></station></observations>'
        with self.assertRaisesRegex(ValueError, "Conflicting duplicate"):
            ingest.validate_xml_data_quality(xml, "observations")

    def test_live_retry_reuses_original_without_refetching(self):
        with patch.object(ingest, "fetch_xml", return_value=(ROOT / "data/sample/forecast_sample.xml").read_bytes()) as fetch:
            ingest.ingest_forecast("20261121T110000Z")
            first = list((self.directory / "forecasts").glob("*.xml"))
            ingest.ingest_forecast("20261121T110000Z")
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(first, list((self.directory / "forecasts").glob("*.xml")))
            self.assertIn("_run_20261121T110000Z", first[0].name)

    def test_invalid_partition_cannot_escape_raw_directory(self):
        with self.assertRaises(ValueError):
            ingest.save_bytes(b"data", "forecasts", "xml", "../../escape")

    def test_json_allows_nulls_and_extra_keys(self):
        ingest.validate_historical_page([record(vaartus=None, extra_field={"new": True})], 2026, 10)

    def test_json_rejects_bad_structure_and_measurements(self):
        invalid = [None, {}, [None], [record(jaam_kood="")],
                   [record(tund=24)], [record(kuu=9)],
                   [record(vaartus=51)], [record(vaartus="NaN")],
                   [record(vaartus=True)], [record(element_kood="RH")]]
        for rows in invalid:
            with self.subTest(rows=rows), self.assertRaises((ValueError, TypeError)):
                ingest.validate_historical_page(rows, 2026, 10)

    def test_failed_page_does_not_publish_incomplete_month(self):
        first_page = response([record()] * 10000)
        with patch.object(ingest.requests, "get", side_effect=[first_page, requests.Timeout("page 2")]):
            with self.assertRaises(requests.Timeout):
                ingest.ingest_historical(2026, 10)
        self.assertFalse((self.directory / "historical_observations/2026_10").exists())
        with patch.object(ingest.requests, "get", return_value=response([record()])):
            ingest.ingest_historical(2026, 10)
        self.assertTrue((self.directory / "historical_observations/2026_10/page_0001.json").exists())

    def test_existing_month_is_immutable(self):
        with patch.object(ingest.requests, "get", return_value=response([record()])) as get:
            ingest.ingest_historical(2026, 10)
            ingest.ingest_historical(2026, 10)
            self.assertEqual(get.call_count, 1)
            query = get.call_args.kwargs["params"]
            self.assertEqual(query["element_kood"], "eq.TA")

    def test_climate_request_does_not_force_an_unrelated_schema(self):
        with patch.object(ingest.requests, "get", return_value=response([record()])) as get:
            ingest.ingest_historical(2026, 10)
        headers = get.call_args.kwargs["headers"]
        self.assertEqual(headers["Accept"], "application/json")
        self.assertNotIn("Accept-Profile", headers)

    def test_api_error_includes_response_details_without_publishing(self):
        error_response = response([])
        error_response.status_code = 406
        error_response.text = '{"message":"The requested schema is not exposed"}'
        error_response.raise_for_status.side_effect = requests.HTTPError("Not Acceptable")
        with patch.object(ingest.requests, "get", return_value=error_response):
            with self.assertRaisesRegex(ValueError, "HTTP 406.*schema is not exposed"):
                ingest.ingest_historical(2026, 10)
        self.assertFalse((self.directory / "historical_observations/2026_10").exists())

    def test_empty_month_fails_instead_of_claiming_ingestion(self):
        with patch.object(ingest.requests, "get", return_value=response([])):
            with self.assertRaisesRegex(ValueError, "No validated TA"):
                ingest.ingest_historical(2026, 10)
        self.assertFalse((self.directory / "historical_observations/2026_10").exists())


if __name__ == "__main__":
    unittest.main()
