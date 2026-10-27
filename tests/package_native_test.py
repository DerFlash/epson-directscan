import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/package-native.sh'


@unittest.skipUnless(sys.platform == 'darwin', 'Mac disk image and signing tools required')
class NativePackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = pathlib.Path(tempfile.mkdtemp(prefix='directscan-package-fixture-'))
        cls.app = cls.base / 'Epson DirectScan Beta.app'
        contents = cls.app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Helpers').mkdir()
        (contents / 'Resources').mkdir()
        shutil.copy2(ROOT / 'LICENSE', contents / 'Resources/LICENSE.txt')
        shutil.copy2(ROOT / 'LICENSING.md', contents / 'Resources/LICENSING.md')
        info = dict(CFBundleIdentifier='org.scansmart.directscan.beta', CFBundleExecutable='EpsonDirectScan',
                    CFBundleName='Epson DirectScan Beta', CFBundlePackageType='APPL',
                    CFBundleShortVersionString='0.3.0', CFBundleVersion='15', DirectScanVersion='0.3.0-beta.2')
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        source = cls.base / 'fixture.c'
        source.write_text('int main(void) { return 0; }\n')
        subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=13.0', str(source), '-o',
                        str(contents / 'MacOS/EpsonDirectScan')], check=True, capture_output=True)
        for name in ['EpsonButtonReceiver', 'EpsonFeedingWorker']:
            target = contents / 'Helpers' / name
            shutil.copy2(contents / 'MacOS/EpsonDirectScan', target)
            subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True, capture_output=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(cls.app)], check=True, capture_output=True)
        cls.app.chmod(0o700)
        (contents / 'Info.plist').chmod(0o600)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.base)

    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp(prefix='directscan-package-test-'))
        self.addCleanup(shutil.rmtree, self.temp)

    def package(self, app=None, output=None, *extra):
        return subprocess.run(['bash', str(SCRIPT), '--app', str(app or self.app),
                               '--output', str(output or self.temp / 'release'), *extra],
                              text=True, capture_output=True, timeout=120)

    def test_downloads_preserve_app_bytes_permissions_signatures_and_install_link(self):
        before = (self.app / 'Contents/MacOS/EpsonDirectScan').read_bytes()
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.temp / 'release'
        stem = 'epson-directscan-0.3.0-beta.2-macos-arm64'
        info = json.loads((output / 'PACKAGE-INFO.json').read_text())
        self.assertEqual((info['version'], info['build'], info['architecture']), ('0.3.0-beta.2', '15', 'arm64'))
        self.assertEqual(info['signing'], 'ad-hoc')
        self.assertIs(info['notarized'], False)
        sums = dict(line.split('  ', 1)[::-1] for line in (output / 'SHA256SUMS').read_text().splitlines())
        self.assertEqual(set(sums), {stem + '.dmg', stem + '.zip'})
        for name, digest in sums.items():
            self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), digest)
        extracted = self.temp / 'extracted'
        subprocess.run(['ditto', '-x', '-k', str(output / (stem + '.zip')), str(extracted)], check=True, capture_output=True)
        copied = extracted / self.app.name
        self.assertEqual((copied / 'Contents/Resources/LICENSE.txt').read_bytes(), (ROOT / 'LICENSE').read_bytes())
        self.assertEqual((copied / 'Contents/Resources/LICENSING.md').read_bytes(), (ROOT / 'LICENSING.md').read_bytes())
        self.assertEqual((copied / 'Contents/MacOS/EpsonDirectScan').read_bytes(), before)
        self.assertTrue(os.access(copied / 'Contents/MacOS/EpsonDirectScan', os.X_OK))
        self.assertEqual(copied.stat().st_mode & 0o555, 0o555)
        self.assertEqual((copied / 'Contents/Info.plist').stat().st_mode & 0o444, 0o444)
        subprocess.run(['codesign', '--verify', '--strict', '--deep', str(copied)], check=True, capture_output=True)
        mounted = plistlib.loads(subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(output / (stem + '.dmg'))]))
        volume = next(pathlib.Path(e['mount-point']) for e in mounted['system-entities'] if 'mount-point' in e)
        try:
            self.assertEqual(os.readlink(volume / 'Applications'), '/Applications')
            self.assertEqual((volume / 'LICENSE.txt').read_bytes(), (ROOT / 'LICENSE').read_bytes())
            self.assertEqual((volume / 'LICENSING.md').read_bytes(), (ROOT / 'LICENSING.md').read_bytes())
            self.assertEqual(volume.stat().st_mode & 0o555, 0o555)
            self.assertEqual((volume / 'Installation.txt').stat().st_mode & 0o444, 0o444)
            self.assertEqual((volume / self.app.name / 'Contents/MacOS/EpsonDirectScan').read_bytes(), before)
            subprocess.run(['codesign', '--verify', '--strict', '--deep', str(volume / self.app.name)], check=True, capture_output=True)
            self.assertIn('nicht notarisiert', (volume / 'Installation.txt').read_text())
        finally:
            subprocess.run(['hdiutil', 'detach', str(volume)], check=True, capture_output=True)
        self.assertEqual((self.app / 'Contents/MacOS/EpsonDirectScan').read_bytes(), before)
        self.assertEqual(self.app.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.app / 'Contents/Info.plist').stat().st_mode & 0o777, 0o600)

    def test_missing_or_stale_license_notice_produces_no_package(self):
        for filename in ['LICENSE.txt', 'LICENSING.md']:
            for missing in [True, False]:
                with self.subTest(filename=filename, missing=missing):
                    case = filename.replace('.', '-') + ('-missing' if missing else '-stale')
                    app = self.temp / (case + '.app')
                    shutil.copytree(self.app, app)
                    notice = app / 'Contents/Resources' / filename
                    if missing:
                        notice.unlink()
                    else:
                        notice.write_text('Stale licensing notice\n')
                    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
                    target = self.temp / (case + '-output')
                    result = self.package(app, target)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(target.exists())
                    self.assertIn('licensing notice', result.stderr.lower())

    def test_wrong_bundle_or_damaged_helper_produces_no_package(self):
        for wrong_id in [True, False]:
            with self.subTest(wrong_id=wrong_id):
                app = self.temp / ('wrong.app' if wrong_id else 'damaged.app')
                shutil.copytree(self.app, app)
                if wrong_id:
                    path = app / 'Contents/Info.plist'
                    info = plistlib.loads(path.read_bytes()); info['CFBundleIdentifier'] = 'other.app'
                    path.write_bytes(plistlib.dumps(info))
                    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
                else:
                    path = app / 'Contents/Helpers/EpsonButtonReceiver'
                    data = bytearray(path.read_bytes()); data[4096] ^= 1; path.write_bytes(data)
                target = self.temp / ('bad-id-output' if wrong_id else 'bad-signature-output')
                result = self.package(app, target)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(target.exists())
                self.assertIn('bundle' if wrong_id else 'signature', result.stderr.lower())

    def test_existing_output_is_preserved_and_ad_hoc_cannot_claim_notarization(self):
        output = self.temp / 'existing'; output.mkdir()
        sentinel = output / 'keep.txt'; sentinel.write_text('keep existing downloads')
        result = self.package(output=output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exists', result.stderr.lower())
        self.assertEqual(sentinel.read_text(), 'keep existing downloads')
        self.assertEqual(list(output.iterdir()), [sentinel])
        target = self.temp / 'notarized'
        result = self.package(None, target, '--require-notarized')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('notar', result.stderr.lower())
        self.assertFalse(target.exists())

    def test_private_build_paths_in_a_valid_signed_app_are_refused(self):
        app = self.temp / 'private.app'
        shutil.copytree(self.app, app)
        source = self.temp / 'private.c'
        source.write_text('const char *marker="/Users/synthetic-builder/private-project"; int main(void) { return marker[0]; }\n')
        subprocess.run(['clang', '-arch', 'arm64', '-mmacosx-version-min=13.0', str(source), '-o',
                        str(app / 'Contents/MacOS/EpsonDirectScan')], check=True, capture_output=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
        target = self.temp / 'private-output'
        result = self.package(app, target)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(target.exists())
        self.assertIn('private', result.stderr.lower())
