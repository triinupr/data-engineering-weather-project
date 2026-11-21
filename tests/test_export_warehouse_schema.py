"""Check export scope and database-error propagation without a running server."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import MagicMock, patch


class SchemaExportTests(unittest.TestCase):
    def load_exporter(self):
        extensions = MagicMock()
        extensions.parse_dsn.return_value = {
            'host': 'postgres', 'port': '5432', 'dbname': 'weather',
            'user': 'student', 'password': 'secret',
        }
        spec = importlib.util.spec_from_file_location(
            'schema_export_test', Path(__file__).resolve().parents[1] / 'src/export_warehouse_schema.py')
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {'psycopg2': MagicMock(), 'psycopg2.extensions': extensions}):
            spec.loader.exec_module(module)
        return module

    def test_export_excludes_airflow_and_keeps_password_out_of_arguments(self):
        exporter = self.load_exporter()
        with patch.object(exporter.subprocess, 'run', return_value=MagicMock(stdout='-- DDL')) as run:
            content = exporter.schema_dump('test-dsn')
        self.assertEqual(run.call_count, 2)
        for invocation in run.call_args_list:
            argv = invocation.args[0]
            self.assertNotIn('--schema=public', argv)
            self.assertNotIn('secret', ' '.join(argv))
            self.assertEqual(invocation.kwargs['env']['PGPASSWORD'], 'secret')
            self.assertTrue(invocation.kwargs['check'])
        self.assertIn('--schema=public_gold', run.call_args_list[0].args[0])
        self.assertIn('--table=public.int_daily_observations', run.call_args_list[1].args[0])
        self.assertEqual(content.count('-- DDL'), 2)

    def test_failed_dump_propagates(self):
        exporter = self.load_exporter()
        with patch.object(exporter.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'pg_dump')):
            with self.assertRaises(subprocess.CalledProcessError):
                exporter.schema_dump('test-dsn')
