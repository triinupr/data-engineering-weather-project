"""Verify failure propagation and lock lifetime without a database or dbt install."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import call, patch


class RefreshTests(unittest.TestCase):
    def load_runner(self, driver):
        path = Path(__file__).resolve().parents[1] / "src/refresh_warehouse.py"
        spec = importlib.util.spec_from_file_location("refresh_test", path)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"psycopg2": driver}):
            spec.loader.exec_module(module)
        return module

    def test_failed_dbt_build_propagates_and_unlocks(self):
        from unittest.mock import MagicMock
        driver = MagicMock()
        runner = self.load_runner(driver)
        connection = driver.connect.return_value
        cursor = connection.cursor.return_value.__enter__.return_value
        error = subprocess.CalledProcessError(1, "dbt build")
        with patch.object(runner.subprocess, "run", side_effect=[None, error]) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                runner.main()
        self.assertEqual(run.call_count, 2)
        self.assertIn("build", run.call_args.args[0])
        self.assertEqual(cursor.execute.call_args, call("SELECT pg_advisory_unlock(20261121, 12)"))
        connection.close.assert_called_once()

    def test_lock_covers_load_build_and_docs(self):
        from unittest.mock import MagicMock
        driver = MagicMock()
        runner = self.load_runner(driver)
        cursor = driver.connect.return_value.cursor.return_value.__enter__.return_value
        def check_locked(*args, **kwargs):
            self.assertEqual(cursor.execute.call_args, call("SELECT pg_advisory_lock(20261121, 12)"))
            self.assertTrue(kwargs["check"])
        with patch.object(runner.subprocess, "run", side_effect=check_locked) as run:
            runner.main()
        self.assertEqual(run.call_count, 3)
        self.assertIn("build", run.call_args_list[1].args[0])
        self.assertIn("generate", run.call_args_list[2].args[0])


if __name__ == "__main__":
    unittest.main()
