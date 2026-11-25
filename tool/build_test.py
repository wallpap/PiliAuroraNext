"""Exercise the real PowerShell build entry with isolated SDK and compiler substitutes."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is required')
class DefaultBuildTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for directory in ('tool', 'lib/scripts', '.dart_tool', 'sdk/bin', 'bin', 'android'):
            (self.root / directory).mkdir(parents=True)
        shutil.copyfile(ROOT / 'tool/build.ps1', self.root / 'tool/build.ps1')
        shutil.copyfile(ROOT / 'lib/scripts/build.ps1', self.root / 'lib/scripts/build.ps1')
        (self.root / '.dart_tool/package_config.json').write_text('{}')
        (self.root / 'pubspec.yaml').write_text('version: 2.0.0+555\n')
        self.git('init', '-q')
        self.git('add', 'pubspec.yaml')
        self.git('-c', 'user.name=Build Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')
        (self.root / 'sdk/bin/flutter.bat').touch()
        (self.root / 'sdk/bin/flutter').touch()
        (self.root / 'bin/fvm.ps1').write_text('')
        (self.root / 'bin/dart.ps1').write_text(r'''
ConvertTo-Json -InputObject @('dart', $args) -Compress -Depth 5 | Add-Content "$env:BUILD_FIXTURE/calls.jsonl"
$global:LASTEXITCODE = 0
if ($args -contains 'pwsh') { Write-Output "$env:BUILD_FIXTURE/sdk/bin/flutter.bat"; return }
if ($args -contains 'build') {
    $mode = if ($args -contains '--debug') { 'Debug' } else { 'Release' }
    $runtime = "$env:BUILD_FIXTURE/build/windows/x64/runner/$mode"
    New-Item -ItemType Directory -Force $runtime | Out-Null
    Set-Content "$runtime/PiliAuroraNext.exe" 'app'
    Set-Content "$runtime/flutter_windows.dll" 'stock'
}
''', encoding='utf-8')
        (self.root / 'bin/python.ps1').write_text(r'''
ConvertTo-Json -InputObject @('python', $args) -Compress -Depth 5 | Add-Content "$env:BUILD_FIXTURE/calls.jsonl"
$global:LASTEXITCODE = 0
if ($args -contains 'unpack') {
    if ($env:FAIL_ENGINE -eq 'true') { $global:LASTEXITCODE = 7; return }
    $output = $args[[array]::IndexOf($args, '--output') + 1]
    New-Item -ItemType Directory -Force $output | Out-Null
    Set-Content "$output/flutter_windows.dll" 'verified-engine'
    Set-Content "$output/libflutter.so" 'verified-engine'
    return
}
if ($args[0] -like '*build_apk.py') {
    $output = $args[[array]::IndexOf($args, '--output') + 1]
    New-Item -ItemType Directory -Force (Split-Path $output) | Out-Null
    Set-Content $output 'signed-apk'
    Set-Content ([IO.Path]::ChangeExtension($output, '.json')) '{"identityDigest":"verified"}'
    New-Item -ItemType Directory -Force 'build/app/outputs/flutter-apk' | Out-Null
    Set-Content 'build/app/outputs/flutter-apk/app-release.apk' 'stock-apk'
    return
}
if ($args -contains '--verify-standard-output') { return }
$profile = $args[[array]::IndexOf($args, '--profile') + 1]
$library = $args[[array]::IndexOf($args, '--library') + 1]
$hash = if ($profile -eq 'standard') { '' } else { (Get-FileHash $library).Hash.ToLowerInvariant() }
@{ identityDigest = 'verified'; identity = @{ binarySha256 = $hash }; dartDefines = @("PILIAURORANEXT_PRESENTATION_PROFILE=$profile", 'PILIAURORANEXT_ENGINE_IDENTITY=verified') } | ConvertTo-Json -Compress -Depth 5
''', encoding='utf-8')

    def git(self, *arguments):
        return subprocess.run(['git', *arguments], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout.strip()

    def test_patch_finds_fvm_sdk_without_local_properties(self):
        shutil.copyfile(ROOT / 'lib/scripts/patch.ps1', self.root / 'lib/scripts/patch.ps1')
        (self.root / '.fvmrc').write_text('{"flutter":"fixture"}')
        configuration = self.root / 'config/fvm'
        configuration.mkdir(parents=True)
        cache = self.root / 'fvm-cache'
        sdk = cache / 'versions/fixture'
        sdk.mkdir(parents=True)
        (configuration / '.fvmrc').write_text(json.dumps({'cachePath': str(cache)}))
        harness = self.root / 'resolve-sdk.ps1'
        harness.write_text(r'''
$ErrorActionPreference = 'Stop'
$Workspace = $PSScriptRoot
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $Workspace 'lib/scripts/patch.ps1'), [ref]$tokens, [ref]$parseErrors)
$definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Resolve-FlutterRoot'
}, $true)
. ([scriptblock]::Create($definition.Extent.Text))
Resolve-FlutterRoot
''', encoding='utf-8')
        result = subprocess.run(
            ['pwsh', '-NoProfile', '-File', str(harness)], check=False, cwd=self.root,
            env={**os.environ, 'FLUTTER_ROOT': '', 'APPDATA': str(configuration.parent)},
            capture_output=True, text=True, encoding='utf-8', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(Path(result.stdout.strip()), sdk)

    def run_build(self, *arguments, **environment):
        env = {**os.environ, 'BUILD_FIXTURE': str(self.root),
               'PATH': str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
               'ANDROID_HOME': str(self.root / 'android'), 'FAIL_ENGINE': '',
               'PILIAURORANEXT_TEST_RELEASE': '', **environment}
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(self.root / 'tool/build.ps1'),
                                 '-SkipPubGet', '-SkipPatch', *arguments],
                                check=False, cwd=self.root, env=env, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=60)
        calls = self.root / 'calls.jsonl'
        self.calls = [json.loads(line) for line in calls.read_text(encoding='utf-8-sig').splitlines()] if calls.exists() else []
        return result

    def test_default_windows_binds_and_installs_verified_release(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        runtime = self.root / 'build/windows/x64/runner/Release'
        self.assertEqual((runtime / 'flutter_windows.dll').read_text().strip(), 'verified-engine')
        self.assertEqual(json.loads((runtime / 'engine-identity.json').read_text())['identityDigest'], 'verified')
        self.assertTrue((self.root / 'build/windows-engine-config.json').is_file())
        build = next(args for tool, args in self.calls if tool == 'dart' and 'build' in args)
        self.assertIn('--release', build)
        self.assertIn('--dart-define=pili.name=2.0.0', build)
        self.assertIn('--dart-define=pili.code=1', build)
        self.assertIn('--build-name=2.0.0', build)
        self.assertIn('--build-number=1', build)
        self.assertEqual((self.root / 'pubspec.yaml').read_text(), 'version: 2.0.0+555\n')
        self.assertIn('--dart-define=PILIAURORANEXT_PRESENTATION_PROFILE=windowsDwmPaced', build)

    def test_android_default_builds_each_abi_with_matching_engine(self):
        result = self.run_build('-Platform', 'android')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        builds = [args for tool, args in self.calls if tool == 'python' and args[0].endswith('build_apk.py')]
        self.assertEqual(len(builds), 3)
        for args, abi, arch in zip(builds, ('armeabi-v7a', 'arm64-v8a', 'x86_64'), ('arm', 'arm64', 'x64')):
            self.assertEqual(args[args.index('--abi') + 1], abi)
            self.assertIn('--dart-define=pili.code=1', args)
            self.assertIn(f'android-{arch}', args[args.index('--engine-library') + 1])
            self.assertTrue((self.root / args[args.index('--output') + 1]).is_file())

    def test_new_commit_automatically_increments_build_number(self):
        self.git('-c', 'user.name=Build Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'next')
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = next(args for tool, args in self.calls if tool == 'dart' and 'build' in args)
        self.assertIn('--build-number=2', build)
        self.assertIn('--dart-define=pili.code=2', build)

    def test_shallow_history_stops_before_compilation(self):
        (self.root / '.git/shallow').write_text(self.git('rev-parse', 'HEAD') + '\n')
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('git fetch --unshallow', result.stdout + result.stderr)
        self.assertEqual(self.calls, [])

    def test_ci_uses_same_metadata_and_updates_release_files(self):
        result = subprocess.run(['pwsh', '-NoProfile', '-File', 'lib/scripts/build.ps1',
                                 'android', '-Version', 'v2.0.0'], check=False, cwd=self.root,
                                env={**os.environ, 'GITHUB_ENV': str(self.root / 'github.env')},
                                capture_output=True, text=True, encoding='utf-8', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        metadata = json.loads((self.root / 'pili_release.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(metadata['pili.name'], '2.0.0')
        self.assertEqual(metadata['pili.code'], 1)
        self.assertEqual(metadata['pili.hash'], self.git('rev-parse', 'HEAD'))
        self.assertEqual((self.root / 'pubspec.yaml').read_text().strip(), 'version: 2.0.0+1')
        self.assertIn('version=2.0.0+1', (self.root / 'github.env').read_text())

    def test_ci_versions_and_timestamp_match_for_the_same_release(self):
        build_time = 1795600000
        for tag, expected in (('', '2.0.0'), ('v2.1.0-rc.1', '2.1.0-rc.1')):
            with self.subTest(tag=tag):
                pubspec = self.root / 'pubspec.yaml'
                pubspec.write_text('version: 2.0.0+555\n')
                env_file = self.root / 'github.env'
                env_file.write_text('')
                command = ['pwsh', '-NoProfile', '-Command',
                           '& ./lib/scripts/build.ps1 -MetadataOnly -Version $env:RELEASE_VERSION '
                           '-BuildTime $env:RELEASE_TIME | ConvertTo-Json -Compress']
                result = subprocess.run(
                    command, check=False, cwd=self.root,
                    env={**os.environ, 'GITHUB_ENV': str(env_file), 'RELEASE_VERSION': tag,
                         'RELEASE_TIME': str(build_time)},
                    capture_output=True, text=True, encoding='utf-8', timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                metadata = json.loads(result.stdout)
                self.assertEqual(metadata['pili.name'], expected)
                self.assertEqual(metadata['pili.code'], 1)
                self.assertEqual(metadata['pili.hash'], self.git('rev-parse', 'HEAD'))
                self.assertEqual(metadata['pili.time'], build_time)
                self.assertEqual(pubspec.read_text().strip(), 'version: 2.0.0+555')
                self.assertEqual(env_file.read_text(), '')

                result = subprocess.run(
                    ['pwsh', '-NoProfile', '-File', 'lib/scripts/build.ps1', '-Version', tag,
                     '-BuildTime', str(metadata['pili.time'])], check=False, cwd=self.root,
                    env={**os.environ, 'GITHUB_ENV': str(env_file)},
                    capture_output=True, text=True, encoding='utf-8', timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads((self.root / 'pili_release.json').read_text(encoding='utf-8-sig')), metadata)
                self.assertEqual(pubspec.read_text().strip(), f'version: {expected}+1')
                self.assertEqual(env_file.read_text().strip(), f'version={expected}+1')

    def test_ci_rejects_versions_the_update_checker_cannot_parse(self):
        for version in ('v02.0.0', 'v2.0.0-rc.01', 'v2.0.0;bad'):
            with self.subTest(version=version):
                result = subprocess.run(
                    ['pwsh', '-NoProfile', '-File', 'lib/scripts/build.ps1', '-Version', version],
                    check=False, cwd=self.root, capture_output=True, text=True, encoding='utf-8', timeout=60)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.root / 'pubspec.yaml').read_text(), 'version: 2.0.0+555\n')
                self.assertFalse((self.root / 'pili_release.json').exists())

    def test_dev_release_uses_arm64_and_retains_final_signed_flutter_output(self):
        result = self.run_build('-Platform', 'android', PILIAURORANEXT_TEST_RELEASE='true')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        builds = [args for tool, args in self.calls if tool == 'python' and args[0].endswith('build_apk.py')]
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0][builds[0].index('--mode') + 1], 'dev-release')
        self.assertEqual(builds[0][builds[0].index('--abi') + 1], 'arm64-v8a')
        self.assertEqual((self.root / 'build/app/outputs/flutter-apk/app-release.apk').read_text().strip(), 'signed-apk')

    def test_failed_artifact_validation_prevents_application_compilation(self):
        result = self.run_build(FAIL_ENGINE='true')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(tool == 'dart' and 'build' in args for tool, args in self.calls))

    def test_debug_verifies_sdk_output_without_unpacking_release(self):
        result = self.run_build('-Mode', 'debug')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any('unpack' in args for _, args in self.calls))
        self.assertTrue(any('--verify-standard-output' in args for _, args in self.calls))

    def test_profile_requires_matching_artifact_before_build(self):
        result = self.run_build('-Mode', 'profile')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls, [])

    def test_default_capture_rejects_main_application_before_launch(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for relative in ('tool/probes/windows/measure_danmaku.ps1',
                         'tool/engine/windows_frame_pacing/engine_identity.ps1'):
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, destination)
        result = subprocess.run([
            'pwsh', '-NoProfile', '-File', str(self.root / 'tool/probes/windows/measure_danmaku.ps1'),
            '-PresentMonPath', str(self.root / 'build/windows/x64/runner/Release/PiliAuroraNext.exe'),
            '-SkipBuild', '-OutputDirectory', str(self.root / 'capture')],
            check=False, cwd=self.root, env={**os.environ, 'BUILD_FIXTURE': str(self.root), 'FAIL_ENGINE': '',
                                'PATH': str(self.root / 'bin') + os.pathsep + os.environ['PATH']},
            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('输出不是当前弹幕探针', result.stderr)


if __name__ == '__main__':
    unittest.main()
