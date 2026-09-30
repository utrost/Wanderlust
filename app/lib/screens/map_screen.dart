import 'dart:async';

import 'walk_library_screen.dart';
import 'offline_maps_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'memories_screen.dart';
import '../memories/memory.dart';
import '../memories/memory_photos.dart';
import '../memories/memory_location.dart';
import '../settings/walk_preferences.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/gps_hud.dart';
import '../maps/map_extent.dart';
import '../maps/map_download.dart';

import '../coverage/coverage_controller.dart';
import '../recording/walk_store.dart';
import '../geo/live_match.dart';
import '../recording/walk_recorder.dart';
import '../theme/wanderlust_theme.dart';
import '../widgets/area_map.dart';

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

  late final SqliteWalkStore _store = widget.store ?? SqliteWalkStore();
  late final WalkRecorder _recorder = WalkRecorder(
    store: _store,
    location:
        widget.location ??
        DeviceLocationSource(detailedGps: () => _preferences.detailedGps),
  );
  late final CoverageController _coverage = CoverageController(
    store: _store,
    loadSavedNetworks: () async => [
      for (final area in await _store.listAreas())
        if (await _store.readArea(area.version) case final source?) source,
    ],
    loadNetwork: () async {
      final selected = await _store.readActiveArea();
      if (selected != null) return selected;
      final maps = await _store.listAreas();
      return maps.isEmpty ? null : _store.readArea(maps.first.version);
    },
  );

  List<WalkMemory> _memories = [];
  bool _memoryReady = false;
  bool _addingMemory = false;
  String? _memoryError;
  Future<void> _loadMemories({bool recover = false}) async {
    try {
      if (recover) {
        try {
          await DeviceMemoryPhotos().recover(_store.memories);
        } catch (_) {
          if (mounted) {
            setState(
              () => _memoryError =
                  'Photo recovery needs attention. Open Memories to continue your draft.',
            );
          }
        }
      }
      final items = await _store.memories.list();
      if (mounted) setState(() => _memories = items);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _memoryError = 'Could not load memories. Tap Memories to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _memoryReady = true);
    }
  }

  Future<void> _editMemory(WalkMemory memory, {bool isNew = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryEditor(
          store: _store.memories,
          memory: memory,
          isNew: isNew,
          locate: () => locateMemory(current: () => _currentFix),
        ),
      ),
    );
    if (mounted) setState(() => _memoryError = null);
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
        setState(() => _memoryError = 'Could not open a memory. Please retry.');
      }
    } finally {
      _addingMemory = false;
    }
  }

  Future<void> _showMemories() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoriesScreen(store: _store.memories, add: _addMemory),
      ),
    );
    if (mounted) setState(() => _memoryError = null);
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

  WalkPreferences _preferences = const WalkPreferences();
  Position? _previewPosition;
  bool _locating = false;
  String? _gpsError;
  int _centerRequest = 0;
  int _areaRequest = 0;
  Timer? _gpsClock;
  bool _visible = true;
  bool _centerWhenFresh = false;
  int _cameraIntent = 0;

  void _browseMap() {
    _cameraIntent++;
    _centerWhenFresh = false;
  }

  Future<void> _autoCenter() async {
    if (!mounted || !_visible || _coverage.network == null) return;
    await _centerOnMe(automatic: true);
  }

  Position? get _currentFix {
    final recorded = _recorder.latestPosition;
    if (_recorder.isRecording) return recorded;
    if (recorded == null) return _previewPosition;
    if (_previewPosition == null ||
        recorded.timestamp.isAfter(_previewPosition!.timestamp)) {
      return recorded;
    }
    return _previewPosition;
  }

  Future<void> _centerOnMe({bool automatic = false}) async {
    if (_locating) return;
    final intent = ++_cameraIntent;
    if (_recorder.isRecording) {
      setState(() {
        _centerWhenFresh = true;
        _gpsError = null;
      });
      _centerOnFreshRecordingFix();
      return;
    }
    setState(() {
      _locating = true;
      _gpsError = null;
    });
    try {
      // Returning to the app must not open a permission dialog. The explicit
      // location button and first-map setup still request permission normally.
      if (automatic) {
        if (!await Geolocator.isLocationServiceEnabled()) return;
        final permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return;
        }
      }
      final error = automatic
          ? null
          : await DeviceLocationSource(forRecording: false).authorize();
      if (!mounted) return;
      if (error != null) {
        setState(
          () => _gpsError = error == RecorderError.locationServiceDisabled
              ? 'Turn on location to find your position.'
              : 'Allow location access in Android settings to show your position.',
        );
        return;
      }
      final position =
          await (widget.locate?.call() ??
              Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 20),
                ),
              ));
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        throw const FormatException('Invalid location fix');
      }
      if (isOldFix(position, DateTime.now())) {
        throw TimeoutException('Waiting for a current fix');
      }
      if (!mounted) return;
      setState(() {
        _previewPosition = position;
        if (_visible && intent == _cameraIntent) _centerRequest++;
      });
    } on TimeoutException {
      if (mounted) {
        setState(() => _gpsError = 'No GPS fix yet. Try again outdoors.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _gpsError = 'Location unavailable. Check GPS and permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
          onSizeChanged: (size) async {
            final value = _preferences.copyWith(mapSizeKm: size);
            await _store.savePreferences(value);
            if (mounted) setState(() => _preferences = value);
          },
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

  Future<void> _loadPreferences() async {
    try {
      final value = await _store.readPreferences();
      if (mounted) {
        setState(() => _preferences = value);
        await _coverage.setFillSmallGaps(
          value.fillSmallGaps,
          _recorder.savedWalks,
        );
      }
    } catch (_) {
      /* Calm defaults remain available if storage is unavailable. */
    }
  }

  Future<void> _showSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initial: _preferences,
          diagnostic: _geoStatusChip(),
          save: (value) async {
            await _store.savePreferences(value);
            final changed = value.fillSmallGaps != _preferences.fillSmallGaps;
            if (mounted) setState(() => _preferences = value);
            if (changed) {
              await _coverage.setFillSmallGaps(
                value.fillSmallGaps,
                _recorder.savedWalks,
              );
            }
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadMemories(recover: true));
    WidgetsBinding.instance.addObserver(this);
    _recorder.addListener(_walkChanged);
    unawaited(_coverage.initialize().then((_) => _autoCenter()));
    _recorder.initialize();
    unawaited(_loadPreferences());
    _startGpsClock();
  }

  void _startGpsClock() {
    _gpsClock?.cancel();
    _gpsClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_recorder.isRecording && _currentFix != null) {
        setState(() {});
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
    _visible = visible;
    _coverage.setPreviewActive(visible);
    _recorder.setForeground(visible);
    if (visible) {
      _startGpsClock();
      if (returning) unawaited(_autoCenter());
    } else {
      _centerWhenFresh = false;
      _gpsClock?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsClock?.cancel();
    _recorder.removeListener(_walkChanged);
    // Finish pending coverage work before the recorder closes the shared DB.
    _coverage.dispose();
    unawaited(_coverage.settled.whenComplete(_recorder.dispose));
    super.dispose();
  }

  void _centerOnFreshRecordingFix() {
    final fix = _recorder.latestPosition;
    if (_centerWhenFresh && fix != null && !isOldFix(fix, DateTime.now())) {
      _centerWhenFresh = false;
      _centerRequest++;
    }
  }

  void _walkChanged() {
    if (!_visible) return;
    _centerOnFreshRecordingFix();
    if (mounted) setState(() {});
    if (_recorder.isRecording) {
      final walk = _recorder.recordingSnapshot;
      if (walk != null) _coverage.updateLive(walk);
    }
    if (!_recorder.isRecording &&
        !_recorder.isBusy &&
        !_recorder.needsSaveRetry) {
      unawaited(_coverage.synchronize(_recorder.savedWalks));
    }
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
                            const Spacer(),
                            ListenableBuilder(
                              listenable: _recorder,
                              builder: (context, _) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _mapDock(),
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
                                            icon: const Icon(
                                              Icons.directions_walk,
                                            ),
                                            label: Text(
                                              _recorder.needsSaveRetry
                                                  ? 'Retry saving walk'
                                                  : 'Start walk',
                                            ),
                                          ),
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

  Widget _welcome() => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_outlined, size: 56),
              const SizedBox(height: 24),
              const Text(
                'Your walks, your neighbourhood',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26),
              ),
              const SizedBox(height: 16),
              const Text(
                'Start by downloading streets around your location. Then put your phone away and explore at your own pace.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Maps and walks stay on your phone. You only need internet to download a map.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
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
                TextButton(
                  onPressed: _showSettings,
                  child: const Text('Settings'),
                ),
                if (_recorder.isBusy)
                  const CircularProgressIndicator()
                else if (_recorder.isRecording)
                  _recordingPanel()
                else if (_recorder.needsSaveRetry)
                  TextButton(
                    onPressed: _recorder.retrySave,
                    child: const Text('Retry saving walk'),
                  )
                else
                  TextButton(
                    onPressed: _showSavedWalks,
                    child: const Text('Saved walks and import'),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _surface(Widget child) => Material(
    color: WanderlustColors.paperCard,
    elevation: 2,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _mapToolbar() => _surface(
    Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: _showMaps,
            icon: const Tooltip(
              message: 'Offline maps',
              child: Icon(Icons.map_outlined),
            ),
            label: Text(
              (_coverage.network?.name ?? 'Offline maps').split(' · ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: _showSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          tooltip: 'Show map area',
          onPressed: () {
            _browseMap();
            setState(() => _areaRequest++);
          },
          icon: const Icon(Icons.zoom_out_map),
        ),
        IconButton(
          tooltip: 'Center on me',
          onPressed: _locating ? null : () => _centerOnMe(),
          icon: _locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
        ),
      ],
    ),
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

  Widget _locationControl() {
    final p = _currentFix;
    final old = p != null && isOldFix(p, DateTime.now());
    final coordinate = p == null ? null : Offset(p.longitude, p.latitude);
    final extent = MapExtent(_coverage.networks);
    final outside = coordinate != null && !extent.contains(coordinate);
    final near =
        coordinate != null &&
        !old &&
        extent.distanceToBoundary(coordinate) <= 500;
    final status = _gpsError != null
        ? 'Location needs attention'
        : _locating
        ? 'Finding your location…'
        : p == null
        ? 'Location unavailable'
        : old
        ? 'Last known location'
        : 'Location ready';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _surface(
          IconButton(
            tooltip: '$status · Location details',
            onPressed: _showLocationDetails,
            icon: Icon(
              _gpsError != null
                  ? Icons.location_off_outlined
                  : old || p == null
                  ? Icons.location_searching
                  : Icons.gps_fixed,
            ),
          ),
        ),
        if (_preferences.showGps && p != null)
          _surface(
            TextButton(
              onPressed: _showLocationDetails,
              child: Text(
                '±${p.accuracy.round()} m${old ? ' · Last fix' : ''}',
              ),
            ),
          ),
        if (outside || near)
          _surface(
            TextButton.icon(
              onPressed: _showMaps,
              icon: const Icon(Icons.download_outlined),
              label: Text(outside ? 'Map needed here' : 'Map edge nearby'),
            ),
          ),
      ],
    );
  }

  Widget _mapDock() => _surface(
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _coverageStatus(),
                    ),
                  ),
                ),
                icon: const Icon(Icons.route_outlined),
                label: Tooltip(
                  message: 'Street sections explored',
                  child: Text('${_coverage.displayCounts.length}'),
                ),
              ),
              IconButton(
                tooltip: 'Add memory',
                onPressed: _memoryReady ? _addMemory : null,
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
              IconButton(
                tooltip: 'Memories',
                onPressed: _memoryReady ? _showMemories : null,
                icon: Badge(
                  isLabelVisible: _memories.any((m) => m.draft),
                  child: const Icon(Icons.collections_bookmark_outlined),
                ),
              ),
              IconButton(
                tooltip: 'Saved walks (${_recorder.savedWalks.length})',
                onPressed:
                    _recorder.isRecording ||
                        _recorder.isBusy ||
                        _recorder.needsSaveRetry
                    ? null
                    : _showSavedWalks,
                icon: const Icon(Icons.history),
              ),
            ],
          ),
          if (_memoryError != null)
            Text(_memoryError!, textAlign: TextAlign.center),
          if (_recorder.lastError != null)
            Text(
              _errorMessage(_recorder.lastError!),
              textAlign: TextAlign.center,
            ),
          if (_coverage.error != null || _coverage.liveError != null)
            _coverageStatus(),
        ],
      ),
    ),
  );

  Widget _attribution() => _surface(
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

  Widget _coverageStatus() => ListenableBuilder(
    listenable: _coverage,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_coverage.busy)
          const Text('Updating your streets…')
        else
          Text(
            '${_coverage.displayCounts.length} street ${_coverage.displayCounts.length == 1 ? 'section' : 'sections'} explored',
          ),
        if (_recorder.isRecording && _coverage.liveError != null)
          Text(_coverage.liveError!),
        if (_coverage.error case final error?)
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(error.stage),
                content: SingleChildScrollView(
                  child: SelectableText(error.detail),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_coverage.synchronize(_recorder.savedWalks));
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            child: Text('${error.stage} · Details'),
          ),
      ],
    ),
  );

  Future<void> _onStartWalk() async {
    final ok = await _recorder.start();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _centerRequest++;
        _gpsError = null;
      });
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
        _recorder.needsSaveRetry) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalkLibraryScreen(
          store: _store,
          showSamples: _preferences.showSamples,
          networks: _coverage.networks,
          fillSmallGaps: _preferences.fillSmallGaps,
          showStreetNames: _preferences.showStreetNames,
          showMemories: _preferences.showMemories,
          onChanged: () async {
            await _recorder.refreshSavedWalks();
            await _loadMemories();
            await _coverage.synchronize(_recorder.savedWalks);
          },
        ),
      ),
    );
    await _loadMemories();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  Widget _recordingPanel() {
    final e = _recorder.elapsed;
    final clock = '${_twoDigits(e.inMinutes)}:${_twoDigits(e.inSeconds % 60)}';
    final km = (_recorder.distanceMeters / 1000).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: WanderlustColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              [
                if (_preferences.showTime) clock,
                '$km km',
                if (_preferences.showSamples)
                  '${_recorder.pointCount} GPS samples',
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: WanderlustColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: () => _recorder.stop(),
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
