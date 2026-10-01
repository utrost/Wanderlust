import 'dart:async';

import 'package:flutter/foundation.dart';

import '../coverage/coverage_controller.dart';
import '../coverage/coverage_store.dart';
import '../maps/area_store.dart';
import '../recording/walk_history.dart';
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
    recorder = WalkRecorder(
      store: journal,
      location:
          location ??
          DeviceLocationSource(detailedGps: () => preferences.detailedGps),
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
    _preferences = PreferencesController(
      store: preferencesStore,
      onApplied: (value) async {
        recorder.refreshDisplayClock();
        await coverage.setFillSmallGaps(
          value.fillSmallGaps,
          recorder.savedWalks,
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
    if (_closed || !_foreground) return;
    if (recorder.isRecording) {
      final walk = recorder.recordingSnapshot;
      if (walk != null) coverage.updateLive(walk);
    } else if (!recorder.isBusy && !recorder.needsSaveRetry) {
      unawaited(coverage.synchronize(recorder.savedWalks));
    }
  }

  late final WalkRecorder recorder;
  late final CoverageController coverage;
  bool _closed = false;
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    recorder.removeListener(_recordingChanged);
    _preferences.dispose();
    coverage.dispose();
    unawaited(
      Future.wait([
        coverage.settled,
        _preferences.settled,
      ]).whenComplete(recorder.dispose),
    );
    super.dispose();
  }
}
