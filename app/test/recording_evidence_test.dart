import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlust/recording/gps_diagnostics.dart';
import 'package:wanderlust/recording/saved_walk.dart';
import 'package:wanderlust/transfer/backup_contents.dart';
import 'backup_fixture.dart';

void main() {
  test(
    'evidence survives database and full backup round trip without GPS points',
    () async {
      const evidence = '[{"event":"heartbeat","elapsed":1000}]';
      final walk = SavedWalk(
        1,
        DateTime.utc(2026, 10, 7),
        DateTime.utc(2026, 10, 7, 1),
        'completed',
        [],
        uid: '11111111111111111111111111111111',
        gpsDiagnostics: {
          'evidenceLog': evidence,
          'stopSource': 'notification',
          'stopRequestedAt': 1790000000000,
        },
      );
      final restored = await decodeBackup(
        await encodeBackup(BackupContents([walk], [])),
      );
      expect(restored.walks.single.gpsDiagnostics['evidenceLog'], evidence);
      expect(
        restored.walks.single.gpsDiagnostics['stopSource'],
        'notification',
      );
      expect(
        restored.walks.single.gpsDiagnostics['stopRequestedAt'],
        1790000000000,
      );
    },
  );
  test('bounded evidence survives diagnostic serialization', () {
    const log = '[{"event":"heartbeat","elapsed":1000}]';
    expect(readGpsDiagnostics({'evidenceLog': log})['evidenceLog'], log);
    expect(readGpsDiagnostics({'evidenceLog': 'x' * 1000001}), isEmpty);
  });
}
