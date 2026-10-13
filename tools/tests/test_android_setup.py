import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AndroidSetupTest(unittest.TestCase):
    def test_overlay_preserves_app_and_is_idempotent(self):
        module = load('configure_android')
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / 'app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.INTERNET"/><application android:label="wanderlust"><activity android:name=".MainActivity"/></application></manifest>')
            module.configure(directory)
            module.configure(directory)
            root = ET.parse(manifest).getroot()
            permissions = [p.get(f'{{{module.ANDROID}}}name') for p in root.findall('uses-permission')]
            self.assertEqual(len(permissions), len(set(permissions)))
            self.assertIn('android.permission.FOREGROUND_SERVICE_LOCATION', permissions)
            self.assertIn('android.permission.WAKE_LOCK', permissions)
            self.assertIn('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS', permissions)
            self.assertNotIn('android.permission.ACCESS_BACKGROUND_LOCATION', permissions)
            self.assertIsNotNone(root.find('application/activity'))
            self.assertTrue((manifest.parent / 'kotlin/com/simiono/wanderlust/MainActivity.kt').exists())
            application = root.find('application')
            services = application.findall('service')
            self.assertEqual(len(services), 1)
            self.assertEqual(services[0].get(f'{{{module.ANDROID}}}name'), 'com.simiono.wanderlust.RecordingService')
            self.assertEqual(services[0].get(f'{{{module.ANDROID}}}exported'), 'false')
            self.assertEqual(services[0].get(f'{{{module.ANDROID}}}foregroundServiceType'), 'location')
            self.assertEqual(services[0].get(f'{{{module.ANDROID}}}stopWithTask'), 'false')
            self.assertEqual(application.get(f'{{{module.ANDROID}}}allowBackup'), 'false')
            for filename, sections in [('backup_rules.xml', [None]),
                                       ('data_extraction_rules.xml', ['cloud-backup', 'device-transfer'])]:
                rules = ET.parse(manifest.parent / 'res/xml' / filename).getroot()
                for section in sections:
                    excludes = (rules if section is None else rules.find(section)).findall('exclude')
                    domains = {e.get('domain') for e in excludes if e.get('path') == '.'}
                    self.assertTrue({'database', 'file', 'root', 'sharedpref', 'external',
                                     'device_root', 'device_file', 'device_database', 'device_sharedpref'} <= domains)
            gradle = (Path(directory) / 'app/build.gradle.kts').read_text()
            self.assertNotIn('signingConfigs.getByName("debug")', gradle)
            self.assertIn('namespace = "com.simiono.wanderlust"', gradle)
            self.assertIn('applicationId = "com.simiono.wanderlust"', gradle)
            for name in ('MainActivity.kt', 'RecordingBattery.kt', 'BackupFiles.kt', 'RecordingService.kt', 'RecordingJournal.kt', 'RecordingPolicy.kt'):
                self.assertTrue((manifest.parent / 'kotlin/com/simiono/wanderlust' / name).read_text().startswith('package com.simiono.wanderlust'))


    def test_missing_or_wrong_signing_key_never_replaces_existing_key(self):
        module = load('install_test_signing')
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'debug.keystore'
            destination.write_bytes(b'existing key')
            with self.assertRaises(ValueError):
                module.install('', destination, 'pinned certificate')
            with patch.object(module.subprocess, 'run') as run:
                run.return_value.stdout = b'wrong certificate'
                with self.assertRaises(ValueError):
                    module.install(base64.b64encode(b'new key').decode(), destination, 'pinned certificate')
            self.assertEqual(destination.read_bytes(), b'existing key')

    def test_publication_rejects_wrong_certificate_or_build_number(self):
        module = load('verify_android_release')
        with patch.object(module.subprocess, 'run') as run:
            run.return_value.stdout = 'Signer #1 certificate SHA-256 digest: deadbeef\n'
            with self.assertRaises(ValueError):
                module.verify(Path('test.apk'), Path('/tools'), 1010, 'abcdef')
            with self.assertRaises(ValueError):
                module.verify(Path('test.apk'), Path('/tools'), 1010, 'deadbeef')
            run.side_effect = [
                type('Result', (), {'stdout': 'Signer #1 certificate SHA-256 digest: deadbeef\n'})(),
                type('Result', (), {'stdout': "package: name='com.simiono.wanderlust' versionCode='1010' versionName='0.0.1'"})(),
            ]
            module.verify(Path('test.apk'), Path('/tools'), 1010, 'deadbeef')

    def test_publication_rejects_a_different_application_id(self):
        module = load('verify_android_release')
        with patch.object(module.subprocess, 'run') as run:
            run.side_effect = [
                type('Result', (), {'stdout': 'Signer #1 certificate SHA-256 digest: deadbeef\n'})(),
                type('Result', (), {'stdout': "package: name='com.example.other' versionCode='1010' versionName='0.0.1'"})(),
            ]
            with self.assertRaises(ValueError):
                module.verify(Path('test.apk'), Path('/tools'), 1010, 'deadbeef')

    def test_build_tools_37_certificate_labels_and_multiple_signers(self):
        module = load('verify_android_release')
        package = "package: name='com.simiono.wanderlust' versionCode='1015' versionName='0.0.1'"
        for certificate in (
            'Signer #1 certificate SHA-256 digest: deadbeef\n',
            'V3.0 Signer: certificate SHA-256 digest: deadbeef\n',
            'V3.0 Signer: certificate SHA-256 digest: deadbeef\nV3.1 Signer: certificate SHA-256 digest: DEADBEEF\n',
        ):
            with self.subTest(certificate=certificate), patch.object(module.subprocess, 'run') as run:
                run.side_effect = [
                    type('Result', (), {'stdout': certificate})(),
                    type('Result', (), {'stdout': package})(),
                ]
                module.verify(Path('test.apk'), Path('/tools'), 1015, 'deadbeef')
        with patch.object(module.subprocess, 'run') as run:
            run.return_value.stdout = 'V3.0 Signer: certificate SHA-256 digest: deadbeef\nV3.1 Signer: certificate SHA-256 digest: abcdef\n'
            with self.assertRaises(ValueError):
                module.verify(Path('test.apk'), Path('/tools'), 1015, 'deadbeef')
