import 'dart:async';

import 'walk_library_screen.dart';
import 'offline_maps_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/gps_hud.dart';
import '../maps/map_extent.dart';

import '../coverage/coverage_controller.dart';
import '../recording/walk_store.dart';
import '../geo/live_match.dart';
import '../recording/walk_recorder.dart';
import '../theme/wanderlust_theme.dart';
import '../widgets/area_map.dart';

/// Real offline Bremen streets painted from persisted per-walk coverage.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Proves the native geo-core loads and matches on the device.
  late final Future<GeoDiagnostic> _liveMatch = runSampleMatch();

  final SqliteWalkStore _store = SqliteWalkStore();
  late final WalkRecorder _recorder = WalkRecorder(store: _store);
  late final CoverageController _coverage = CoverageController(
    store: _store,
    loadSavedNetworks: () async => [
      await rootBundle.loadString('assets/geo/bremen-center.streets.geojson'),
      for (final area in await _store.listAreas())
        if (await _store.readArea(area.version) case final source?) source,
    ],
    loadNetwork: () async =>
        await _store.readActiveArea() ??
        await rootBundle.loadString('assets/geo/bremen-center.streets.geojson'),
  );

  Position? _previewPosition;
  bool _locating = false;
  String? _gpsError;
  int _centerRequest = 0;
  int _areaRequest = 0;
  Timer? _gpsClock;

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

  Future<void> _centerOnMe() async {
    if (_locating) return;
    if (_recorder.isRecording) {
      setState(() {
        _centerRequest++;
        _gpsError = null;
      });
      return;
    }
    setState(() {
      _locating = true;
      _gpsError = null;
    });
    try {
      final error = await DeviceLocationSource().authorize();
      if (!mounted) return;
      if (error != null) {
        setState(
          () => _gpsError = error == RecorderError.locationServiceDisabled
              ? 'Turn on location to find your position.'
              : 'Allow location access in Android settings to show your position.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        throw const FormatException('Invalid location fix');
      }
      if (!mounted) return;
      setState(() {
        _previewPosition = position;
        _centerRequest++;
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
          position: _currentFix,
          activeVersion: _coverage.network?.version,
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

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_walkChanged);
    _coverage.initialize();
    _recorder.initialize();
    _gpsClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_recorder.isRecording && _currentFix != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _gpsClock?.cancel();
    _recorder.removeListener(_walkChanged);
    // Finish pending coverage work before the recorder closes the shared DB.
    _coverage.dispose();
    unawaited(_coverage.settled.whenComplete(_recorder.dispose));
    super.dispose();
  }

  void _walkChanged() {
    if (mounted) setState(() {});
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: _coverage,
            builder: (context, _) => _coverage.network == null
                ? const Center(child: Text('Loading saved streets…'))
                : AreaMap(
                    network: _coverage.network!,
                    networks: _coverage.networks,
                    counts: _coverage.counts,
                    position: _currentFix,
                    stale:
                        _currentFix != null &&
                        isOldFix(_currentFix!, DateTime.now()),
                    centerRequest: _centerRequest,
                    areaRequest: _areaRequest,
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _coverage,
                          builder: (context, _) =>
                              InkWell(onTap: _showMaps, child: _areaChip()),
                        ),
                      ),
                      _geoStatusChip(),
                      IconButton.filledTonal(
                        tooltip: 'Show map area',
                        onPressed: () => setState(() => _areaRequest++),
                        icon: const Icon(Icons.map_outlined),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Center on me',
                        onPressed: _locating ? null : _centerOnMe,
                        icon: _locating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: _coverage,
                    builder: (context, _) => GpsHud(
                      position: _currentFix,
                      now: DateTime.now(),
                      recording: _recorder.isRecording,
                      locating: _locating,
                      network: _coverage.network,
                      networks: _coverage.networks,
                      error: _gpsError,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _coverage,
                    builder: (context, _) {
                      final p = _currentFix;
                      final extent = MapExtent(_coverage.networks);
                      final coordinate = p == null
                          ? null
                          : Offset(p.longitude, p.latitude);
                      final outside =
                          coordinate != null && !extent.contains(coordinate);
                      final nearEdge =
                          coordinate != null &&
                          !isOldFix(p!, DateTime.now()) &&
                          extent.distanceToBoundary(coordinate) <= 500;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _showMaps,
                          icon: Icon(
                            outside || nearEdge
                                ? Icons.download_outlined
                                : Icons.map_outlined,
                            size: 18,
                          ),
                          label: Text(
                            outside
                                ? 'Download a map here'
                                : nearEdge
                                ? 'Download more streets'
                                : 'Offline maps',
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: _recorder,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _coverageStatus(),
                        if (_recorder.lastError != null)
                          Text(
                            _errorMessage(_recorder.lastError!),
                            textAlign: TextAlign.center,
                          ),
                        TextButton(
                          onPressed:
                              _recorder.isRecording ||
                                  _recorder.isBusy ||
                                  _recorder.needsSaveRetry
                              ? null
                              : _showSavedWalks,
                          child: Text(
                            'Saved walks (${_recorder.savedWalks.length})',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: _recorder.isBusy
                              ? const CircularProgressIndicator()
                              : _recorder.isRecording
                              ? _recordingPanel()
                              : GestureDetector(
                                  onTap: _recorder.needsSaveRetry
                                      ? _recorder.retrySave
                                      : _onStartWalk,
                                  child: _startWalkPill(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _areaChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _coverage.network?.name ?? 'Bremen center',
            style: WanderlustTheme.serif.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WanderlustColors.ink,
            ),
          ),
          Text(
            '${_coverage.networks.length} offline maps · tap to manage',
            style: TextStyle(fontSize: 10.5, color: WanderlustColors.inkMuted),
          ),
        ],
      ),
    );
  }

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
          Text('${_coverage.counts.length} street segments walked'),
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
        TextButton(
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: 'Wanderlust',
            children: [
              const SelectableText(
                'Map data © OpenStreetMap contributors, ODbL 1.0\nhttps://www.openstreetmap.org/copyright\nOffline street view. Tap the area name to download or choose maps. Pinch to zoom. Streets update after saving a walk.',
              ),
            ],
          ),
          child: const Text(
            '© OpenStreetMap contributors · ODbL',
            style: TextStyle(fontSize: 10),
          ),
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
          onChanged: () async {
            await _recorder.refreshSavedWalks();
            await _coverage.synchronize(_recorder.savedWalks);
          },
        ),
      ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  Widget _recordingPanel() {
    final e = _recorder.elapsed;
    final clock = '${_twoDigits(e.inMinutes)}:${_twoDigits(e.inSeconds % 60)}';
    final km = (_recorder.distanceMeters / 1000).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.94),
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
          Text(
            '$clock · $km km · ${_recorder.pointCount} pts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: WanderlustColors.ink,
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _recorder.stop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: WanderlustColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFBF8F2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _startWalkPill() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.92),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_walk,
              size: 16,
              color: WanderlustColors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              _recorder.needsSaveRetry ? 'Retry saving walk' : 'Start walk',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WanderlustColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
