"""Exercise the CI test entry with real PowerShell and a recording Flutter shim."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is required')
class CiTestRunnerTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'tool').mkdir()
        (self.root / 'bin').mkdir()
        shutil.copyfile(ROOT / 'tool/run-ci-tests.ps1', self.root / 'tool/run-ci-tests.ps1')
        self.shared = ['test/shared_test.dart']
        self.windows = ['test/windows_test.dart']
        self.android = ['test/android/lifecycle_test.dart']
        self.both = ['test/platform_branch_test.dart']
        self.native = ['test/region_worker_test.dart']
        self.registry = {
            'windows': self.windows,
            'androidHost': ['test/android/'],
            'bothHosts': self.both,
            'nativeImages': self.native,
        }
        self.write_registry()
        for path in self.shared + self.windows + self.android + self.both + self.native:
            self.add_test_file(path)
        (self.root / 'capture.py').write_text('''\
import json, os, sys
from pathlib import Path
output = Path(os.environ['CI_RUNNER_CALLS'])
count = len(output.read_text(encoding='utf-8').splitlines()) + 1 if output.exists() else 1
with output.open('a', encoding='utf-8') as stream:
    stream.write(json.dumps({'tool': sys.argv[1], 'args': sys.argv[2:],
                             'native_required': os.environ.get('REGION_TEST_REQUIRED')}) + '\\n')
if os.environ.get('CI_RUNNER_FAIL_CALL') == str(count):
    sys.exit(17)
''', encoding='utf-8')
        for tool in ('flutter', 'fvm'):
            if os.name == 'nt':
                shim = self.root / 'bin' / f'{tool}.bat'
                shim.write_text(
                    '@echo off\n'
                    f'"%CI_RUNNER_PYTHON%" "%CI_RUNNER_CAPTURE%" {tool} %*\n'
                    'exit /b %ERRORLEVEL%\n', encoding='utf-8')
            else:
                shim = self.root / 'bin' / tool
                shim.write_text(
                    '#!/bin/sh\n'
                    f'exec "$CI_RUNNER_PYTHON" "$CI_RUNNER_CAPTURE" {tool} "$@"\n',
                    encoding='utf-8')
                shim.chmod(0o755)

    def add_test_file(self, path):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.touch()

    def write_registry(self):
        (self.root / 'tool/test-platforms.json').write_text(
            json.dumps(self.registry), encoding='utf-8')

    def run_entry(self, tool, *flags, fail_call=None):
        calls_file = self.root / 'calls.jsonl'
        calls_file.unlink(missing_ok=True)
        env = {
            **os.environ,
            'PATH': str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
            'CI_RUNNER_PYTHON': sys.executable,
            'CI_RUNNER_CAPTURE': str(self.root / 'capture.py'),
            'CI_RUNNER_CALLS': str(calls_file),
            'CI_RUNNER_FAIL_CALL': str(fail_call or ''),
        }
        command = ['pwsh', '-NoProfile', '-File', str(self.root / 'tool/run-ci-tests.ps1'),
                   '-FlutterTool', tool, '-Concurrency', '4', *flags]
        result = subprocess.run(
            command,
            check=False, cwd=self.root, env=env, capture_output=True, text=True,
            encoding='utf-8', errors='replace', timeout=30)
        calls = ([json.loads(line) for line in calls_file.read_text(encoding='utf-8').splitlines()]
                 if calls_file.exists() else [])
        return result, calls

    def platform_paths(self):
        return self.both + (self.windows if os.name == 'nt' else self.android)

    def test_runs_every_selected_path_with_requested_concurrency(self):
        new_shared = 'test/new_coverage_test.dart'
        self.add_test_file(new_shared)
        for tool in ('path', 'fvm'):
            with self.subTest(tool=tool):
                result, calls = self.run_entry(tool)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(calls), 1)
                paths = []
                for call in calls:
                    arguments = call['args']
                    if tool == 'fvm':
                        self.assertEqual(arguments.pop(0), 'flutter')
                    self.assertEqual(arguments[:4], ['test', '--no-pub', '--concurrency', '4'])
                    paths.extend(arguments[4:])
                self.assertCountEqual(paths, self.shared + self.platform_paths() + [new_shared])

    def test_failed_batch_returns_failure_after_other_batches_run(self):
        for index in range(110):
            path = f'test/many_tests/module_{index:03d}_long_fixture_for_batch_budget_test.dart'
            self.add_test_file(path)
            self.shared.append(path)
        result, calls = self.run_entry('path', fail_call=1)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), 2 if os.name == 'nt' else 1)
        if os.name == 'nt':
            for call in calls:
                self.assertLess(sum(len(arg) + 3 for arg in call['args']), 7000)
        self.assertCountEqual([path for call in calls for path in call['args'][4:]],
                              self.shared + self.platform_paths())

    def test_platform_only_runs_host_regressions_without_shared_suite(self):
        result, calls = self.run_entry('path', '-PlatformOnly')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        paths = [path for call in calls for path in call['args'][4:]]
        self.assertCountEqual(paths, self.platform_paths())

    def test_native_images_run_separately_and_require_fixtures(self):
        result, calls = self.run_entry('path', '-NativeImages')
        if os.name == 'nt':
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0]['args'][4:], self.native)
            self.assertEqual(calls[0]['native_required'], '1')
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('require Windows', result.stderr)
            self.assertEqual(calls, [])

    def test_list_does_not_invoke_flutter(self):
        result, calls = self.run_entry('path', '-List')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertCountEqual(result.stdout.splitlines(), self.shared + self.platform_paths())
        self.assertEqual(calls, [])

    def test_rejects_missing_or_overlapping_classifications(self):
        for path, message in [('test/missing_test.dart', 'matches no files'),
                              ('test/android/lifecycle_test.dart', 'more than one platform')]:
            with self.subTest(path=path):
                self.registry['windows'] = [*self.windows, path]
                self.write_registry()
                result, calls = self.run_entry('path')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertEqual(calls, [])

    def test_repository_classifications_match_test_tree(self):
        result = subprocess.run(
            ['pwsh', '-NoProfile', '-File', 'tool/run-ci-tests.ps1', '-List'],
            check=False, cwd=ROOT, capture_output=True, text=True,
            encoding='utf-8', errors='replace', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('test/utils/credential_migration_test.dart', result.stdout.splitlines())


if __name__ == '__main__':
    unittest.main()
