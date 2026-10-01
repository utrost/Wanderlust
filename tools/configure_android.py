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
    'POST_NOTIFICATIONS',
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
    # the visible activity. It continues while hidden, until Stop or process death.
    application = root.find('application')
    application.set(f'{{{ANDROID}}}label', 'Wanderlust')
    application.set(f'{{{ANDROID}}}allowBackup', 'false')
    application.set(f'{{{ANDROID}}}fullBackupContent', '@xml/backup_rules')
    application.set(f'{{{ANDROID}}}dataExtractionRules', '@xml/data_extraction_rules')
    ET.indent(tree, space='    ')
    tree.write(manifest, encoding='unicode')
    sources = Path(__file__).parent / 'android'
    for source, relative in (
        ('MainActivity.kt', 'kotlin/com/wanderlust/wanderlust/MainActivity.kt'),
        ('BackupFiles.kt', 'kotlin/com/wanderlust/wanderlust/BackupFiles.kt'),
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
    shutil.copyfile(sources / 'app.build.gradle.kts', Path(directory) / 'app/build.gradle.kts')


if __name__ == '__main__':
    configure(sys.argv[1])
