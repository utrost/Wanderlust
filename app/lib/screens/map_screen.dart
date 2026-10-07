import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../application/map_location_controller.dart';
import '../application/map_memories_controller.dart';
import '../application/walking_session.dart';
import '../coverage/coverage_controller.dart';
import '../geo/live_match.dart';
import '../maps/map_download.dart';
import '../memories/memory.dart';
import '../memories/memory_location.dart';
import '../recording/activity_type.dart';
import '../recording/walk_recorder.dart';
import '../recording/walk_store.dart';
import '../settings/walk_preferences.dart';
import '../theme/wanderlust_theme.dart';
import '../transfer/walk_files.dart';
import '../transfer/walk_transfer.dart';
import '../widgets/activity_selector.dart';
import '../widgets/area_map.dart';
import '../widgets/coverage_status.dart';
import '../widgets/gps_hud.dart';
import '../widgets/heatmap_legend.dart';
import '../widgets/map_dock.dart';
import '../widgets/map_location_control.dart';
import '../widgets/map_surface.dart';
import '../widgets/map_toolbar.dart';
import '../widgets/map_welcome.dart';
import '../widgets/recording_panel.dart';
import 'about_screen.dart';
import 'memories_screen.dart';
import 'offline_maps_screen.dart';
import 'settings_screen.dart';
import 'walk_library_screen.dart';

/// User-selected offline streets painted from persisted per-walk coverage.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.store,
    this.fetchMap,
    this.locate,
    this.location,
  });
  final FetchMap? fetchMap;
  final LocationSource? location;
  final Future<Position> Function()? locate;
  final SqliteWalkStore? store;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // Proves the native geo-core loads and matches on the device.
  late final Future<GeoDiagnostic> _liveMatch = runSampleMatch();

  late final WalkingSession _session = WalkingSession(
    journal: _store,
    history: _store,
    maps: _store,
    coverageStore: _store,
    preferencesStore: _store,
    location: widget.location,
  );
  late final SqliteWalkStore _store = widget.store ?? SqliteWalkStore();
  WalkRecorder get _recorder => _session.recorder;
  CoverageController get _coverage => _session.coverage;

  late final _mapMemories = MapMemoriesController(_store.memories);
  List<WalkMemory> get _memories => _mapMemories.items;
  bool get _memoryReady => _mapMemories.ready;
  String? get _memoryError => _mapMemories.error;
  bool _addingMemory = false;
  Future<void> _loadMemories({bool recover = false}) =>
      _mapMemories.load(recover: recover);

  Future<void> _editMemory(WalkMemory memory, {bool isNew = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryEditor(
          store: _store.memories,
          memory: memory,
          isNew: isNew,
          networks: _coverage.networks,
          locate: () => locateMemory(current: () => _currentFix),
        ),
      ),
    );
    _mapMemories.clearError();
    await _loadMemories();
  }

  Future<void> _addMemory() async {
    if (_addingMemory) return;
    _addingMemory = true;
    // Freeze the fix and walk association before any asynchronous navigation.
    final fix = _currentFix;
    final walkId = _recorder.recordingSnapshot?.id;
    try {
      final uid = walkId == null ? null : await _store.walkUid(walkId);
      if (!mounted) return;
      await _editMemory(WalkMemory.create(walkUid: uid, fix: fix), isNew: true);
    } catch (_) {
      if (mounted) {
        _mapMemories.reportOpenFailure();
      }
    } finally {
      _addingMemory = false;
    }
  }

  Future<void> _showMemories() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoriesScreen(
          store: _store.memories,
          add: _addMemory,
          networks: _coverage.networks,
        ),
      ),
    );
    _mapMemories.clearError();
    await _loadMemories();
  }

  Widget _memoryControls() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _memoryReady ? _addMemory : null,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Add memory'),
          ),
          TextButton.icon(
            onPressed: _memoryReady ? _showMemories : null,
            icon: const Icon(Icons.collections_bookmark_outlined, size: 18),
            label: Text(
              _memories.any((m) => m.draft) ? 'Memories · draft' : 'Memories',
            ),
          ),
        ],
      ),
      if (_memoryError != null)
        Text(
          _memoryError!,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
    ],
  );

  WalkPreferences get _preferences => _session.preferences;
  late final _mapLocation = MapLocationController(
    recorder: _recorder,
    locate: widget.locate,
  );
  Position? get _currentFix => _mapLocation.currentFix;
  bool get _locating => _mapLocation.locating;
  String? get _gpsError => _mapLocation.error;
  int get _centerRequest => _mapLocation.centerRequest;
  bool get _visible => _mapLocation.visible;
  int _areaRequest = 0;
  Timer? _gpsClock;
  void _browseMap() => _mapLocation.browseMap();
  Future<void> _centerOnMe() => _mapLocation.centerOnMe();
  Future<void> _autoCenter() async {
    if (mounted && _visible && _coverage.network != null) {
      await _mapLocation.centerOnMe(automatic: true);
    }
  }

  void _locationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showMaps() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfflineMapsScreen(
          store: _store,
          fetch: widget.fetchMap,
          locate: widget.locate,
          position: _currentFix,
          initialSizeKm: _preferences.mapSizeKm,
          onSizeChanged: (size) =>
              _session.savePreferences(_preferences.copyWith(mapSizeKm: size)),
          activeVersion: _coverage.network?.version,
          onMapsChanged: () => _coverage.refreshMaps(),
          onSelect: (source, version) async {
            final ok = await _coverage.useNetwork(
              source,
              persistSelection: () => _store.selectArea(version),
            );
            if (!ok) return false;
            if (mounted) setState(() => _areaRequest++);
            await _coverage.synchronize(_recorder.savedWalks);
            return true;
          },
        ),
      ),
    );
    await _coverage.refreshMaps();
    await _coverage.synchronize(_recorder.savedWalks);
  }

  Future<void> _loadPreferences() => _session.loadPreferences();

  Future<void> _showSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initial: _preferences,
          diagnostic: _geoStatusChip(),
          save: _session.savePreferences,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _mapMemories.addListener(_locationChanged);
    unawaited(_loadMemories(recover: true));
    WidgetsBinding.instance.addObserver(this);
    _recorder.addListener(_walkChanged);
    _session.addListener(_locationChanged);
    _mapLocation.addListener(_locationChanged);
    unawaited(_coverage.initialize().then((_) => _autoCenter()));
    _recorder.initialize();
    unawaited(_loadPreferences());
    _startGpsClock();
  }

  void _startGpsClock() {
    _gpsClock?.cancel();
    bool? previousStale;
    _gpsClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_recorder.isRecording && _currentFix != null) {
        final stale = isOldFix(_currentFix!, DateTime.now());
        if (_preferences.showGps || stale != previousStale) setState(() {});
        previousStale = stale;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs temporarily make the activity inactive; they must not
    // cancel the user-initiated start. Hidden/paused mean it is actually away.
    if (state == AppLifecycleState.inactive) return;
    final visible = state == AppLifecycleState.resumed;
    final returning = visible && !_visible;
    _mapLocation.setVisible(visible);
    _session.setForeground(visible);
    if (visible) {
      _startGpsClock();
      if (returning) unawaited(_autoCenter());
    } else {
      _gpsClock?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsClock?.cancel();
    _recorder.removeListener(_walkChanged);
    _mapLocation.dispose();
    _mapMemories.dispose();
    // Finish pending coverage work before the recorder closes the shared DB.
    _session.dispose();
    super.dispose();
  }

  void _walkChanged() {
    if (!_visible) return;
    _mapLocation.onRecordingChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WanderlustColors.paperBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _coverage,
          builder: (context, _) => _coverage.network == null
              ? _welcome()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ListenableBuilder(
                      listenable: _coverage,
                      builder: (context, _) => _coverage.network == null
                          ? const Center(child: Text('Loading saved streets…'))
                          : AreaMap(
                              unmatchedTrails: _coverage.unmatchedTrails,
                              network: _coverage.network!,
                              networks: _coverage.networks,
                              counts: _coverage.displayCounts,
                              memories: _preferences.showMemories
                                  ? _memories
                                  : const [],
                              onMemory: (m) => _editMemory(m),
                              walkedLineWidth: _preferences.walkedLineWidth,
                              showStreetNames: _preferences.showStreetNames,
                              position: _currentFix,
                              stale:
                                  _currentFix != null &&
                                  isOldFix(_currentFix!, DateTime.now()),
                              centerRequest: _centerRequest,
                              areaRequest: _areaRequest,
                              onInteractionStart: _browseMap,
                            ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _mapToolbar(),
                            const SizedBox(height: 8),
                            _locationControl(),
                            ListenableBuilder(
                              listenable: _session.automaticMaps,
                              builder: (context, _) =>
                                  _session.automaticMaps.message == null
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      tooltip: _session.automaticMaps.message,
                                      onPressed: _showMaps,
                                      icon: Icon(
                                        _session.automaticMaps.busy
                                            ? Icons.downloading_outlined
                                            : Icons.cloud_off_outlined,
                                      ),
                                    ),
                            ),
                            const Spacer(),
                            ListenableBuilder(
                              listenable: _recorder,
                              builder: (context, _) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _mapDock(),
                                  if (!_recorder.isRecording &&
                                      !_recorder.isBusy &&
                                      !_recorder.hasRecoverableWalk)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Material(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(24),
                                        child: ActivitySelector(
                                          value: _preferences.activity,
                                          onChanged: _recorder.needsSaveRetry
                                              ? null
                                              : _selectActivity,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: _recorder.isBusy
                                        ? const CircularProgressIndicator()
                                        : _recorder.isRecording
                                        ? _recordingPanel()
                                        : FilledButton.icon(
                                            onPressed: _recorder.needsSaveRetry
                                                ? _recorder.retrySave
                                                : _onStartWalk,
                                            icon: Icon(
                                              _preferences.activity ==
                                                      WalkActivity.cycle
                                                  ? Icons.directions_bike
                                                  : Icons.directions_walk,
                                            ),
                                            label: Text(
                                              _recorder.needsSaveRetry
                                                  ? 'Retry saving walk'
                                                  : _recorder.hasRecoverableWalk
                                                  ? 'Continue your walk'
                                                  : _preferences.activity ==
                                                        WalkActivity.cycle
                                                  ? 'Start ride'
                                                  : 'Start walk',
                                            ),
                                          ),
                                  ),
                                  if (_recorder.hasRecoverableWalk &&
                                      !_recorder.isBusy)
                                    TextButton(
                                      onPressed: _recorder.stop,
                                      child: const Text('Finish this walk'),
                                    ),
                                  _attribution(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _welcome() => MapWelcome(
    actions: [
      if (!_coverage.initialized)
        const CircularProgressIndicator()
      else ...[
        FilledButton.icon(
          onPressed: _showMaps,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Set up my map'),
        ),
        if (_coverage.error != null) ...[
          const Text(
            'Could not load your saved maps. Your walks have not been removed.',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () => _coverage.refreshMaps(),
            child: const Text('Retry loading maps'),
          ),
        ],
        _memoryControls(),
        TextButton(onPressed: _showSettings, child: const Text('Settings')),
        if (_recorder.isBusy)
          const CircularProgressIndicator()
        else if (_recorder.isRecording)
          _recordingPanel()
        else if (_recorder.needsSaveRetry)
          TextButton(
            onPressed: _recorder.retrySave,
            child: const Text('Retry saving walk'),
          )
        else if (_recorder.hasRecoverableWalk) ...[
          FilledButton(
            onPressed: _onStartWalk,
            child: const Text('Continue your walk'),
          ),
          TextButton(
            onPressed: _recorder.stop,
            child: const Text('Finish this walk'),
          ),
        ] else ...[
          FilledButton(
            onPressed: _onStartWalk,
            child: const Text('Start walk'),
          ),
          TextButton(
            onPressed: _showSavedWalks,
            child: const Text('Walk history and import'),
          ),
        ],
      ],
    ],
  );

  Widget _mapToolbar() => MapToolbar(
    name: _coverage.network?.name ?? 'Offline maps',
    locating: _locating,
    onMaps: _showMaps,
    onSettings: _showSettings,
    onCenter: _centerOnMe,
    onArea: () {
      _browseMap();
      setState(() => _areaRequest++);
    },
  );

  void _showLocationDetails() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GpsHud(
              position: _currentFix,
              now: DateTime.now(),
              recording: _recorder.isRecording,
              locating: _locating,
              network: _coverage.network,
              networks: _coverage.networks,
              error: _gpsError,
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                unawaited(_centerOnMe());
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Center on me'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _locationControl() => MapLocationControl(
    position: _currentFix,
    networks: _coverage.networks,
    error: _gpsError,
    locating: _locating,
    showGps: _preferences.showGps,
    onDetails: _showLocationDetails,
    onMaps: _showMaps,
  );

  Widget _mapDock() => MapDock(
    sectionCount: _coverage.displayCounts.length,
    historyCount: _recorder.savedWalks.length,
    memoryReady: _memoryReady,
    hasDraft: _memories.any((m) => m.draft),
    historyEnabled:
        !_recorder.isRecording &&
        !_recorder.isBusy &&
        !_recorder.needsSaveRetry &&
        !_recorder.hasRecoverableWalk,
    onAddMemory: _addMemory,
    onMemories: _showMemories,
    onHistory: _showSavedWalks,
    errors: [
      if (_memoryError != null) _memoryError!,
      if (_recorder.lastError != null) _errorMessage(_recorder.lastError!),
    ],
    coverageStatus: _coverage.error != null || _coverage.liveError != null
        ? _coverageStatus()
        : null,
    onCoverage: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _coverageStatus(),
              const SizedBox(height: 20),
              const HeatmapLegend(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _attribution() => MapSurface(
    InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '© OpenStreetMap contributors · ODbL',
          style: TextStyle(fontSize: 10),
        ),
      ),
    ),
  );

  Widget _geoStatusChip() => IconButton(
    tooltip: 'Geo-core diagnostic',
    icon: const Icon(Icons.info_outline, size: 20),
    onPressed: () async {
      final result = await _liveMatch;
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bundled sample diagnostic'),
          content: Text(
            '${result.label}\n${result.detail ?? 'This checks a bundled sample walk.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );

  Widget _coverageStatus() => CoverageStatus(
    coverage: _coverage,
    recording: _recorder.isRecording,
    onRetry: () => unawaited(_coverage.synchronize(_recorder.savedWalks)),
  );

  Future<void> _selectActivity(WalkActivity activity) async {
    try {
      await _session.savePreferences(_preferences.copyWith(activity: activity));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save activity choice. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> _onStartWalk() async {
    await _mapLocation.prepareRecording();
    if (!mounted) return;
    final ok = await _recorder.start();
    if (!mounted) return;
    if (ok) {
      _mapLocation.recordingStarted();
      return;
    }
    if (_recorder.lastError == null) return;
    final message = _errorMessage(_recorder.lastError!);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(RecorderError error) => switch (error) {
    RecorderError.locationServiceDisabled =>
      'Turn on location to record a walk.',
    RecorderError.permissionDenied =>
      'Allow location access in Android settings to record a walk.',
    RecorderError.locationFailed =>
      'Location stopped working. Your saved points are retained.',
    RecorderError.storageFailed =>
      'Could not save all walk data. Check available device storage before recording again.',
  };

  Future<void> _showSavedWalks() async {
    await _recorder.initialize();
    if (!mounted ||
        _recorder.isRecording ||
        _recorder.isBusy ||
        _recorder.needsSaveRetry ||
        _recorder.hasRecoverableWalk) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalkLibraryScreen(
          transfer: WalkTransfer(
            data: _store.backupData,
            importer: _store,
            files: DeviceWalkFiles(),
          ),
          showSamples: _preferences.showSamples,
          networks: _coverage.networks,
          fillSmallGaps: _preferences.fillSmallGaps,
          autoFillGaps: _preferences.autoFillGaps,
          showStreetNames: _preferences.showStreetNames,
          showMemories: _preferences.showMemories,
          onChanged: () async {
            await _recorder.refreshSavedWalks();
            await _loadPreferences();
            await _coverage.refreshMaps();
            await _loadMemories();
            await _coverage.synchronize(_recorder.savedWalks);
          },
        ),
      ),
    );
    await _loadMemories();
  }

  Widget _recordingPanel() => RecordingPanel(
    gpsStale: _recorder.gpsStale,
    locating: _recorder.locating,
    elapsed: _recorder.elapsed,
    distanceMeters: _recorder.distanceMeters,
    pointCount: _recorder.pointCount,
    showTime: _preferences.showTime,
    showSamples: _preferences.showSamples,
    onStop: _recorder.stop,
  );
}
