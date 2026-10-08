#!/usr/bin/env python3
"""Exercise release-tool rejection paths against real, locally built apps.

Build Debug and Release with Tools/build.sh first. No app is launched, no disk
image is produced, and no Keychain item or remote service is accessed here.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--derived-data', type=Path, default=Path('build/DerivedData'))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
derived = args.derived_data.resolve()


class ReleaseToolsChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.release = derived / 'Build/Products/Release/keep.app'
        cls.debug = derived / 'Build/Products/Debug/keep.app'
        for app in (cls.debug, cls.release):
            if not (app.parent / 'keep-build.json').is_file():
                raise RuntimeError(f'Build {app.parent.name} with Tools/build.sh first.')
        cls.info = plistlib.loads((cls.release / 'Contents/Info.plist').read_bytes())
        cls.tag = 'v' + cls.info['CFBundleShortVersionString']

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='keep-release-checks-')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)

    def rejected(self, script, arguments, message, environment=None):
        result = subprocess.run([str(repo / 'Tools' / script), *map(str, arguments)],
                                cwd=self.folder, capture_output=True, text=True, timeout=30,
                                env=environment)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stdout + result.stderr)

    def package_args(self, app=None):
        return ['--tag', self.tag, '--app', app or self.release,
                '--derived-data', derived, '--skip-appcast',
                '--output', self.folder / 'release output']

    def copy_release(self):
        app = self.folder / 'copy with spaces/keep.app'
        subprocess.run(['ditto', str(self.release), str(app)], check=True)
        receipt = app.parent / 'keep-build.json'
        receipt.write_bytes((self.release.parent / receipt.name).read_bytes())
        return app, receipt

    def test_unknown_build_option_fails(self):
        self.rejected('build.sh', ['--relese'], 'Unknown option')

    def test_missing_option_value_fails(self):
        for script, option in [('build.sh', '--derived-data'), ('package-release.sh', '--tag')]:
            with self.subTest(script=script):
                self.rejected(script, [option], 'requires a value')

    def test_unsigned_app_cannot_be_launched(self):
        self.rejected('build.sh', ['--unsigned', '--run'], '--run requires a signed build')

    def test_release_cannot_run_debug_checks(self):
        self.rejected('build.sh', ['--configuration', 'Release', '--check', 'UpdaterChecks'],
                      '--run and --check require Debug')

    def test_unknown_check_fails_before_building(self):
        self.rejected('build.sh', ['--check', '../KeepApp'], 'Unknown check')

    def test_invalid_tag_fails(self):
        self.rejected('package-release.sh', ['--tag', '../release'], 'Tag must be')

    def test_tag_must_match_built_version(self):
        arguments = self.package_args()
        arguments[1] = 'v99999.0.0'
        self.rejected('package-release.sh', arguments, 'Tag must match')

    def test_debug_app_cannot_be_packaged(self):
        self.rejected('package-release.sh', self.package_args(self.debug), 'Only Release builds')

    def test_unsigned_receipt_cannot_be_packaged(self):
        app, receipt = self.copy_release()
        data = json.loads(receipt.read_text())
        data['signing'] = 'unsigned'
        receipt.write_text(json.dumps(data))
        self.rejected('package-release.sh', self.package_args(app), 'Build with Tools/build.sh')

    def test_changed_version_is_rejected(self):
        app, _ = self.copy_release()
        plist = app / 'Contents/Info.plist'
        info = plistlib.loads(plist.read_bytes())
        info['CFBundleVersion'] = '99999'
        plist.write_bytes(plistlib.dumps(info))
        self.rejected('package-release.sh', self.package_args(app), 'Info.plist changed')

    def test_changed_resource_invalidates_signature(self):
        app, _ = self.copy_release()
        resource = next(p for p in (app / 'Contents/Resources').rglob('*') if p.is_file())
        with resource.open('ab') as file:
            file.write(b'\ntampered resource\n')
        self.rejected('package-release.sh', self.package_args(app), 'resource')
        self.assertFalse((self.folder / 'release output').exists())

    def test_debugging_entitlement_is_rejected(self):
        app, receipt = self.copy_release()
        result = subprocess.run(['codesign', '--display', '--entitlements', '-', '--xml', str(app)],
                                check=True, capture_output=True)
        entitlements = plistlib.loads(result.stdout)
        entitlements['com.apple.security.get-task-allow'] = True
        plist = self.folder / 'debugging.entitlements'
        plist.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(plist), str(app)],
                       check=True, capture_output=True)
        data = json.loads(receipt.read_text())
        data['executableSHA256'] = hashlib.sha256((app / 'Contents/MacOS/keep').read_bytes()).hexdigest()
        receipt.write_text(json.dumps(data))
        self.rejected('package-release.sh', self.package_args(app), 'debugging entitlement')

    def test_existing_output_is_preserved(self):
        output = self.folder / 'release output'
        output.mkdir()
        sentinel = output / 'existing-artifact'
        sentinel.write_text('preserve this release')
        self.rejected('package-release.sh', self.package_args(), 'Output already exists')
        self.assertEqual(sentinel.read_text(), 'preserve this release')
        self.assertEqual(list(output.iterdir()), [sentinel])

    def test_dangling_output_symlink_is_preserved(self):
        output = self.folder / 'release output'
        output.symlink_to(self.folder / 'missing target')
        self.rejected('package-release.sh', self.package_args(), 'Output already exists')
        self.assertTrue(output.is_symlink())
        self.assertFalse(output.exists())

    def test_packaging_failure_cleans_new_output(self):
        tools = self.folder / 'bin'
        tools.mkdir()
        hdiutil = tools / 'hdiutil'
        hdiutil.write_text('#!/bin/sh\necho "simulated disk-image failure" >&2\nexit 42\n')
        hdiutil.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(tools) + os.pathsep + environment['PATH']
        environment['TMPDIR'] = str(self.folder)
        self.rejected('package-release.sh', self.package_args(), 'simulated disk-image failure', environment)
        self.assertFalse((self.folder / 'release output').exists())
        self.assertEqual(list(self.folder.glob('keep-release.*')), [])


if __name__ == '__main__':
    unittest.main(argv=[__file__], verbosity=2)
