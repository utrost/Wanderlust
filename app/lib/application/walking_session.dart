import '../recording/activity_type.dart';
import '../exploration/exploration.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../coverage/coverage_controller.dart';
import '../coverage/coverage_store.dart';
import '../maps/area_store.dart';
import '../maps/automatic_maps.dart';
import '../recording/walk_history.dart';
import '../recording/native_recording.dart';
import '../recording/walk_journal.dart';
import '../recording/walk_recorder.dart';
import '../settings/preferences_store.dart';
import '../settings/walk_preferences.dart';
import 'preferences_controller.dart';

/// Owns the shared database, recording journal and derived coverage lifetime.
/// Coordinates recording previews and preferences; navigation stays in the UI.
class WalkingSession extends ChangeNotifier {
  WalkingSession({
    required WalkStore journal,
    required WalkHistory history,
    required AreaStore maps,
    required CoverageStore coverageStore,
    required PreferencesStore preferencesStore,
    LocationSource? location,
  }) {
    exploration = ExplorationController(history.loadWalk);
    exploration.addListener(notifyListeners);
    recorder = WalkRecorder(
      store: journal,
      nativeRecording:
          Platform.isAndroid &&
              location == null &&
              journal is NativeRecordingStore
          ? AndroidRecordingBackend(journal as NativeRecordingStore)
          : null,
      location:
          location ??
          DeviceLocationSource(
            gpsIntervalSeconds: () => recorder.requestedGpsInterval,
          ),
      gpsInterval: () => preferences.effectiveGpsInterval,
      automaticGps: () => preferences.automaticGpsSampling,
      activityType: () => WalkActivity.auto,
      showElapsed: () => preferences.showTime,
      loadHistory: () => history.listSummaries(recover: true),
    );
    coverage = CoverageController(
      store: coverageStore,
      loadWalk: history.loadWalk,
      loadSavedNetworks: () async => [
        for (final area in await maps.listAreas())
          if (await maps.readArea(area.version) case final source?) source,
      ],
      loadNetwork: () async {
        final selected = await maps.readActiveArea();
        if (selected != null) return selected;
        final saved = await maps.listAreas();
        return saved.isEmpty ? null : maps.readArea(saved.first.version);
      },
    );
    automaticMaps = AutomaticMaps(
      store: maps,
      networks: () => coverage.networks,
      onSaved: () async {
        await coverage.refreshMaps();
        await coverage.synchronize(recorder.savedWalks);
      },
    );
    _preferences = PreferencesController(
      store: preferencesStore,
      onApplied: (value) async {
        recorder.refreshDisplayClock();
        exploration.update(
          value.fogOfWar,
          recorder.savedWalks,
          recorder.recordingSnapshot,
        );
        automaticMaps.setEnabled(value.autoDownloadMaps);
        await coverage.setFillSmallGaps(
          value.fillSmallGaps,
          recorder.savedWalks,
          autoFillGaps: value.autoFillGaps,
        );
      },
    );
    _preferences.addListener(notifyListeners);
    recorder.addListener(_recordingChanged);
  }
  late final PreferencesController _preferences;
  WalkPreferences get preferences => _preferences.value;
  bool _foreground = true;
  Future<void> loadPreferences() => _preferences.load();
  Future<void> savePreferences(WalkPreferences value) =>
      _preferences.save(value);

  void setForeground(bool visible) {
    _foreground = visible;
    coverage.setPreviewActive(visible);
    recorder.setForeground(visible);
  }

  void _recordingChanged() {
    if (_closed) return;
    if (recorder.isRecording) {
      unawaited(automaticMaps.consider(recorder.latestPosition));
    } else if (automaticMaps.busy) {
      automaticMaps.cancel();
    }
    if (!_foreground) return;
    exploration.update(
      preferences.fogOfWar,
      recorder.savedWalks,
      recorder.recordingSnapshot,
    );
    if (recorder.isRecording) {
      final walk = recorder.recordingSnapshot;
      if (walk != null) coverage.updateLive(walk);
    } else if (!recorder.isBusy && !recorder.needsSaveRetry) {
      unawaited(coverage.synchronize(recorder.savedWalks));
    }
  }

  late final ExplorationController exploration;
  late final AutomaticMaps automaticMaps;
  late final WalkRecorder recorder;
  late final CoverageController coverage;
  bool _closed = false;
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    recorder.removeListener(_recordingChanged);
    exploration.dispose();
    _preferences.dispose();
    automaticMaps.dispose();
    coverage.dispose();
    unawaited(
      Future.wait([
        coverage.settled,
        automaticMaps.settled,
        _preferences.settled,
      ]).whenComplete(recorder.dispose),
    );
    super.dispose();
  }
}
