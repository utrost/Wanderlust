import 'dart:async';

import 'package:flutter/foundation.dart';

import '../coverage/coverage_controller.dart';
import '../recording/walk_recorder.dart';
import '../recording/walk_store.dart';
import '../settings/walk_preferences.dart';
import '../transfer/backup_archive.dart';

/// Owns the shared database, recording journal and derived coverage lifetime.
/// Coordinates recording previews and preferences; navigation stays in the UI.
class WalkingSession extends ChangeNotifier {
  WalkingSession({required this.store, LocationSource? location}) {
    unawaited(BackupArchive.cleanAbandonedFiles().catchError((Object _) {}));
    recorder = WalkRecorder(
      store: store,
      location:
          location ??
          DeviceLocationSource(detailedGps: () => preferences.detailedGps),
      showElapsed: () => preferences.showTime,
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
    recorder.addListener(_recordingChanged);
  }
  WalkPreferences _preferences = const WalkPreferences();
  WalkPreferences get preferences => _preferences;
  bool _foreground = true;

  Future<void> loadPreferences() async {
    try {
      final value = await store.readPreferences();
      if (_closed) return;
      await _applyPreferences(value);
    } catch (_) {
      // Calm defaults remain available if storage is unavailable.
    }
  }

  Future<void> savePreferences(WalkPreferences value) async {
    await store.savePreferences(value);
    if (!_closed) await _applyPreferences(value);
  }

  Future<void> _applyPreferences(WalkPreferences value) async {
    final changed = preferences.fillSmallGaps != value.fillSmallGaps;
    _preferences = value;
    recorder.refreshDisplayClock();
    notifyListeners();
    if (changed) {
      await coverage.setFillSmallGaps(value.fillSmallGaps, recorder.savedWalks);
    }
  }

  void setForeground(bool visible) {
    _foreground = visible;
    coverage.setPreviewActive(visible);
    recorder.setForeground(visible);
  }

  void _recordingChanged() {
    if (_closed || !_foreground) return;
    if (recorder.isRecording) {
      final walk = recorder.recordingSnapshot;
      if (walk != null) coverage.updateLive(walk);
    } else if (!recorder.isBusy && !recorder.needsSaveRetry) {
      unawaited(coverage.synchronize(recorder.savedWalks));
    }
  }

  final SqliteWalkStore store;
  late final WalkRecorder recorder;
  late final CoverageController coverage;
  bool _closed = false;
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    recorder.removeListener(_recordingChanged);
    coverage.dispose();
    unawaited(coverage.settled.whenComplete(recorder.dispose));
    super.dispose();
  }
}
