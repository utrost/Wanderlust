import 'dart:async';
import '../coverage/coverage_controller.dart';
import '../recording/walk_recorder.dart';
import '../recording/walk_store.dart';
import '../transfer/backup_archive.dart';

/// Owns the shared database, recording journal and derived coverage lifetime.
/// Navigation and camera intent remain presentation responsibilities.
class WalkingSession {
  WalkingSession({
    required this.store,
    LocationSource? location,
    required bool Function() detailedGps,
    required bool Function() showElapsed,
  }) {
    unawaited(BackupArchive.cleanAbandonedFiles().catchError((Object _) {}));
    recorder = WalkRecorder(
      store: store,
      location: location ?? DeviceLocationSource(detailedGps: detailedGps),
      showElapsed: showElapsed,
      loadHistory: () => store.listSummaries(recover: true),
    );
    coverage = CoverageController(
      store: store,
      loadWalk: store.loadWalk,
      loadSavedNetworks: () async => [
        for (final area in await store.listAreas())
          if (await store.readArea(area.version) case final source?) source,
      ],
      loadNetwork: () async {
        final selected = await store.readActiveArea();
        if (selected != null) return selected;
        final maps = await store.listAreas();
        return maps.isEmpty ? null : store.readArea(maps.first.version);
      },
    );
  }
  final SqliteWalkStore store;
  late final WalkRecorder recorder;
  late final CoverageController coverage;
  bool _closed = false;
  void dispose() {
    if (_closed) return;
    _closed = true;
    coverage.dispose();
    unawaited(coverage.settled.whenComplete(recorder.dispose));
  }
}
