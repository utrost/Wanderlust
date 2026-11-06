import 'dart:math' as math;
import '../diagnostics/map_diagnostics.dart';
import '../diagnostics/map_report_dialog.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../recording/walk_recorder.dart';
import 'package:geolocator/geolocator.dart';

import '../data/area_network.dart';
import '../maps/area_store.dart';
import '../maps/map_download.dart';
import '../widgets/gps_hud.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({
    super.key,
    required this.store,
    required this.position,
    required this.activeVersion,
    required this.onSelect,
    this.fetch,
    this.initialSizeKm = 4,
    this.onSizeChanged,
    this.locate,
    this.onMapsChanged,
    this.diagnostics,
  });
  final MapDiagnostics? diagnostics;
  final AreaStore store;
  final Position? position;
  final String? activeVersion;
  final Future<bool> Function(String geojson, String? savedVersion) onSelect;
  final FetchMap? fetch;
  final int initialSizeKm;
  final Future<void> Function(int)? onSizeChanged;
  final Future<Position> Function()? locate;
  final Future<void> Function()? onMapsChanged;

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final _download = MapDownload();
  MapDiagnostics get _diagnostics =>
      widget.diagnostics ?? MapDiagnostics.instance;
  List<OfflineArea> _areas = [];
  bool _busy = false;
  bool _closeAfterOperation = false;
  bool _loaded = false;
  bool _fetching = false;
  bool _cancelRequested = false;
  String? _error;
  String? _active;
  late int _sizeKm = widget.initialSizeKm.clamp(1, 25);
  int? _previewSizeKm;
  String _progress = 'Loading saved maps…';
  late Position? _position = widget.position;

  @override
  void initState() {
    super.initState();
    _active = widget.activeVersion;
    _run(_load);
  }

  @override
  void dispose() {
    _download.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    MapAttempt.current?.mark(MapStage.listing);
    _areas = await widget.store.listAreas();
    _loaded = true;
  }

  Future<void> _run(
    Future<void> Function() action, {
    String operation = 'library',
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _closeAfterOperation = false;
    final attempt = MapAttempt(operation);
    if (operation == 'library') attempt.mark(MapStage.listing);
    try {
      await attempt.run(action);
    } catch (e, stack) {
      attempt.capture(e, stack);
      _error = attempt.saved
          ? attempt.userMessage
          : e is FormatException
          ? e.message
          : e is StateError
          ? e.message
          : attempt.userMessage;
    } finally {
      if ((operation == 'download' || operation == 'refresh') &&
          _cancelRequested) {
        attempt.cancelled = true;
      }
      await _diagnostics.finish(attempt);
      if (mounted) {
        setState(() => _busy = false);
        if (_closeAfterOperation && _error == null) Navigator.pop(context);
      }
    }
  }

  Future<void> _select(String source, String? version) async {
    MapAttempt.current?.mark(MapStage.activation);
    _progress = 'Opening map and updating walked streets…';
    if (mounted) setState(() {});
    final ok = await widget.onSelect(source, version);
    if (!ok) {
      throw StateError(
        'Could not open this map. The previous map is still selected.',
      );
    }
    _active = AreaNetwork.parse(source).version;
  }

  void _close() {
    _closeAfterOperation = true;
  }

  Future<void> _nearby() async {
    final p = _position;
    if (p == null) return;
    _progress = 'Downloading nearby streets…';
    final area = NearbyArea.around(p.latitude, p.longitude, sizeKm: _sizeKm);
    _cancelRequested = false;
    setState(() => _fetching = true);
    late final String source;
    try {
      MapAttempt.current?.mark(MapStage.request);
      source = await (widget.fetch ?? _download.fetch)(area);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
    if (_cancelRequested || !mounted) {
      MapAttempt.current?.cancelled = true;
      return;
    }
    // Commit a complete, validated map before switching away from the old map.
    MapAttempt.current?.mark(MapStage.save);
    await widget.store.saveArea(source);
    MapAttempt.current?.saved = true;
    await _load();
    await _select(source, AreaNetwork.parse(source).version);
    _close();
  }

  Future<void> _refresh(OfflineArea old) async {
    MapAttempt.current?.mark(MapStage.validation);
    final source = await widget.store.readArea(old.version);
    if (source == null) throw StateError('Saved map is unavailable.');
    final area = AreaNetwork.parse(source);
    _progress = 'Refreshing streets, parks and water…';
    _cancelRequested = false;
    setState(() => _fetching = true);
    late final String updated;
    try {
      MapAttempt.current?.mark(MapStage.request);
      updated = await (widget.fetch ?? _download.fetch)(NearbyArea(area.bbox));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
    if (!mounted || _cancelRequested) {
      MapAttempt.current?.cancelled = true;
      return;
    }
    MapAttempt.current?.mark(MapStage.save);
    await widget.store.saveArea(updated);
    MapAttempt.current?.saved = true;
    await _load();
    final version = AreaNetwork.parse(updated).version;
    await _select(updated, version);
    if (version != old.version) await widget.store.deleteArea(old.version);
    await _load();
    _close();
  }

  Future<void> _locate() async {
    _progress = 'Finding your location…';
    setState(() {});
    try {
      Position p;
      if (widget.locate != null) {
        p = await widget.locate!();
      } else {
        final error = await DeviceLocationSource(
          forRecording: false,
        ).authorize();
        if (error != null) {
          throw FormatException(
            error == RecorderError.locationServiceDisabled
                ? 'Turn on location, then try again.'
                : 'Allow location access to find nearby streets. You can retry when ready.',
          );
        }
        p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      }
      if (!p.latitude.isFinite ||
          !p.longitude.isFinite ||
          p.latitude.abs() > 80 ||
          p.longitude.abs() > 180 ||
          !p.accuracy.isFinite ||
          p.accuracy < 0) {
        throw const FormatException(
          'A usable location was not found. Try again outdoors.',
        );
      }
      if (mounted) _position = p;
    } on TimeoutException {
      throw const FormatException('No GPS fix yet. Try again outdoors.');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Location unavailable. Check GPS and permissions, then retry.',
      );
    }
  }

  Future<void> _remove(OfflineArea area) async {
    final wasActive = _active == area.version;
    if (wasActive) await widget.store.selectArea(null);
    await widget.store.deleteArea(area.version);
    await _load();
    if (wasActive) {
      _active = null;
      if (_areas.isNotEmpty) {
        final next = _areas.first;
        final source = await widget.store.readArea(next.version);
        if (source != null) await _select(source, next.version);
      }
    }
    await widget.onMapsChanged?.call();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Offline maps')),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Download streets around me',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a square street map centred on your GPS fix for offline walking and coverage. Parks and water are included for orientation. Saved maps appear together automatically. Internet is needed only for the download.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_previewSizeKm ?? _sizeKm} × ${_previewSizeKm ?? _sizeKm} km · ${(_previewSizeKm ?? _sizeKm) * (_previewSizeKm ?? _sizeKm)} km²',
                    key: const Key('map-size-label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    key: const Key('map-size'),
                    min: 1,
                    max: 25,
                    divisions: 24,
                    value: (_previewSizeKm ?? _sizeKm).toDouble(),
                    label: '${_previewSizeKm ?? _sizeKm} km per side',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _previewSizeKm = v.round()),
                    onChangeEnd: _busy
                        ? null
                        : (v) {
                            _progress = 'Saving map size…';
                            _run(() async {
                              try {
                                await widget.onSizeChanged?.call(v.round());
                                _sizeKm = v.round();
                              } finally {
                                _previewSizeKm = null;
                              }
                            });
                          },
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('1 km'), Text('25 km')],
                  ),
                  if ((_previewSizeKm ?? _sizeKm) >= 10)
                    const Text(
                      'Large areas take longer and may be too detailed to download. If a download fails, choose a smaller size.',
                    ),
                  const SizedBox(height: 8),
                  if (_position case final p?)
                    Text(
                      'Around ${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)} · GPS fix ${fixAge(p, DateTime.now()).inSeconds}s ago',
                    )
                  else
                    const Text(
                      'Find your location to choose the streets around you.',
                    ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _run(_locate),
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      _position == null
                          ? 'Find my location'
                          : 'Refresh my location',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Download sends this surrounding map area to OpenStreetMap’s Overpass service. Your recorded walks stay on your phone.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || !_loaded || _position == null
                        ? null
                        : () => _run(_nearby, operation: 'download'),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download nearby map'),
                  ),

                  if (_fetching)
                    TextButton(
                      onPressed: () {
                        _cancelRequested = true;
                        _download.cancel();
                      },
                      child: const Text('Cancel download'),
                    ),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    Text(_progress),
                  ],
                  if (_error != null)
                    Text(_error!, key: const Key('map-download-error')),
                  if (_error != null && !_busy)
                    TextButton(
                      onPressed: () => showMapReports(context, _diagnostics),
                      child: const Text('Details'),
                    ),
                  if (!_busy && !_loaded)
                    TextButton(
                      onPressed: () => _run(_load),
                      child: const Text('Retry loading maps'),
                    ),
                ],
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('Saved maps · tap to focus'),
              subtitle: Text(
                'Refresh older maps to add place names, parks and water. Refresh sends the saved map area to Overpass and needs internet.',
              ),
            ),
            if (_loaded && _areas.isEmpty)
              const ListTile(
                title: Text('No downloaded maps yet'),
                subtitle: Text(
                  'Your first map will appear here. Saved walks are kept even if you remove a map.',
                ),
              ),
            ListTile(
              title: Text(
                '${_areas.length} saved maps · ${(_areas.fold<int>(0, (n, a) => n + a.bytes + a.cacheBytes) / (1024 * 1024)).toStringAsFixed(1)} MiB stored\nMap data and locally generated cache. The cache can be rebuilt.',
              ),
              subtitle: const Text(
                'Includes downloaded maps and their rebuildable street index. Nearby maps load automatically; other downloads stay available offline.',
              ),
            ),
            for (final area in _areas)
              ListTile(
                title: Text(area.name),
                subtitle: Text(
                  '${area.bounds == null ? '' : '${(area.bounds!.width * area.bounds!.height * 111.32 * 111.32 * math.cos(area.bounds!.center.dy * math.pi / 180)).toStringAsFixed(1)} km² · '}${((area.bytes + area.cacheBytes) / (1024 * 1024)).toStringAsFixed(1)} MiB total · ${(area.bytes / (1024 * 1024)).toStringAsFixed(1)} MiB map + ${(area.cacheBytes / (1024 * 1024)).toStringAsFixed(1)} MiB cache · saved ${area.downloadedAt.toLocal().toString().split(' ').first}${_active == area.version ? ' · selected' : ''}',
                ),
                leading: const Icon(Icons.offline_pin_outlined),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Refresh map with parks and water',
                      icon: const Icon(Icons.refresh),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _refresh(area),
                              operation: 'refresh',
                            ),
                    ),
                    IconButton(
                      tooltip: 'Remove downloaded map',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _run(() => _remove(area)),
                    ),
                  ],
                ),
                onTap: _busy
                    ? null
                    : () => _run(() async {
                        MapAttempt.current?.mark(MapStage.activation);
                        final source = await widget.store.readArea(
                          area.version,
                        );
                        if (source == null) {
                          throw StateError('Saved map is unavailable.');
                        }
                        await _select(source, area.version);
                        _close();
                      }),
              ),
            ListTile(
              title: const Text('Recent map reports'),
              leading: const Icon(Icons.bug_report_outlined),
              onTap: () => showMapReports(context, _diagnostics),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '© OpenStreetMap contributors · ODbL 1.0\nOffline streets, parks and water. Buildings and terrain are still planned.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
