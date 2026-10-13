#!/usr/bin/env python3
"""Apply Wanderlust's tracked Android overlay to Flutter's generated scaffold."""
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

ANDROID = 'http://schemas.android.com/apk/res/android'
PERMISSIONS = (
    'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'INTERNET',
    'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_LOCATION', 'WAKE_LOCK',
    'POST_NOTIFICATIONS', 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
)


def configure(directory):
    main = Path(directory) / 'app/src/main'
    manifest = main / 'AndroidManifest.xml'
    ET.register_namespace('android', ANDROID)
    tree = ET.parse(manifest)
    root = tree.getroot()
    existing = {p.get(f'{{{ANDROID}}}name') for p in root.findall('uses-permission')}
    for permission in PERMISSIONS:
        name = f'android.permission.{permission}'
        if name not in existing:
            root.insert(0, ET.Element('uses-permission', {f'{{{ANDROID}}}name': name}))
    # No ACCESS_BACKGROUND_LOCATION: the user starts the location service from
    # the visible activity. Android may restart the durable sticky recording service.
    application = root.find('application')
    application.set(f'{{{ANDROID}}}label', 'Wanderlust')
    application.set(f'{{{ANDROID}}}allowBackup', 'false')
    application.set(f'{{{ANDROID}}}fullBackupContent', '@xml/backup_rules')
    application.set(f'{{{ANDROID}}}dataExtractionRules', '@xml/data_extraction_rules')
    service_name = 'com.simiono.wanderlust.RecordingService'
    if not any(s.get(f'{{{ANDROID}}}name') == service_name for s in application.findall('service')):
        ET.SubElement(application, 'service', {
            f'{{{ANDROID}}}name': service_name,
            f'{{{ANDROID}}}exported': 'false',
            f'{{{ANDROID}}}foregroundServiceType': 'location',
            f'{{{ANDROID}}}stopWithTask': 'false',
        })
    ET.indent(tree, space='    ')
    tree.write(manifest, encoding='unicode')
    sources = Path(__file__).parent / 'android'
    for source, relative in (
        ('RecordingBattery.kt', 'kotlin/com/simiono/wanderlust/RecordingBattery.kt'),
        ('MainActivity.kt', 'kotlin/com/simiono/wanderlust/MainActivity.kt'),
        ('CompassEvents.kt', 'kotlin/com/simiono/wanderlust/CompassEvents.kt'),
        ('RecordingService.kt', 'kotlin/com/simiono/wanderlust/RecordingService.kt'),
        ('RecordingJournal.kt', 'kotlin/com/simiono/wanderlust/RecordingJournal.kt'),
        ('RecordingPolicy.kt', 'kotlin/com/simiono/wanderlust/RecordingPolicy.kt'),
        ('BackupFiles.kt', 'kotlin/com/simiono/wanderlust/BackupFiles.kt'),
        ('ic_walk_notification.xml', 'res/drawable/ic_walk_notification.xml'),
        ('backup_rules.xml', 'res/xml/backup_rules.xml'),
        ('data_extraction_rules.xml', 'res/xml/data_extraction_rules.xml'),
        ('ic_launcher.xml', 'res/drawable/ic_wanderlust.xml'),
    ):
        destination = main / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(sources / source, destination)
    application.set(f'{{{ANDROID}}}icon', '@drawable/ic_wanderlust')
    tree.write(manifest, encoding='unicode')
    tests = sources / 'tests'
    if tests.exists():
        destination = Path(directory) / 'app/src/test/kotlin/com/simiono/wanderlust'
        destination.mkdir(parents=True, exist_ok=True)
        for source in tests.glob('*.kt'):
            shutil.copyfile(source, destination / source.name)
    shutil.copyfile(sources / 'app.build.gradle.kts' , Path(directory) / 'app/build.gradle.kts')


if __name__ == '__main__':
    configure(sys.argv[1])
