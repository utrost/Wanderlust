import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  });
  final AreaStore store;
  final Position? position;
  final String? activeVersion;
  final Future<bool> Function(String geojson, String? savedVersion) onSelect;
  final FetchMap? fetch;

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final _download = MapDownload();
  List<OfflineArea> _areas = [];
  bool _busy = false;
  bool _loaded = false;
  bool _fetching = false;
  bool _cancelRequested = false;
  String? _error;
  String? _active;
  String _progress = 'Loading saved maps…';

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
    _areas = await widget.store.listAreas();
    _loaded = true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      _error = e.message;
    } on StateError catch (e) {
      _error = e.message;
    } catch (_) {
      _error =
          'Could not save or open the map. Check available storage and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(String source, String? version) async {
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
    if (mounted) Navigator.pop(context);
  }

  Future<void> _nearby() async {
    final p = widget.position;
    if (p == null) return;
    _progress = 'Downloading nearby streets…';
    final area = NearbyArea.around(p.latitude, p.longitude);
    _cancelRequested = false;
    setState(() => _fetching = true);
    late final String source;
    try {
      source = await (widget.fetch ?? _download.fetch)(area);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
    if (_cancelRequested || !mounted) return;
    // Commit a complete, validated map before switching away from the old map.
    await widget.store.saveArea(source);
    await _load();
    await _select(source, AreaNetwork.parse(source).version);
    _close();
  }

  Future<void> _bundled() async {
    await _select(
      await rootBundle.loadString('assets/geo/bremen-center.streets.geojson'),
      null,
    );
  }

  Future<void> _remove(OfflineArea area) async {
    if (_active == area.version) await _bundled();
    await widget.store.deleteArea(area.version);
    await _load();
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
                    'Save a roughly 4 × 4 km street map for offline walking and coverage. Saved maps appear together automatically. Internet is needed only for the download.',
                  ),
                  const SizedBox(height: 8),
                  if (widget.position case final p?)
                    Text(
                      'Around ${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)} · GPS fix ${fixAge(p, DateTime.now()).inSeconds}s ago',
                    )
                  else
                    const Text(
                      'Return to the map and tap Center on me to get a GPS fix first.',
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Download sends this surrounding map area to OpenStreetMap’s Overpass service. Your recorded walks stay on your phone.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed:
                        _busy ||
                            !_loaded ||
                            widget.position == null ||
                            _areas.length >= 8
                        ? null
                        : () => _run(_nearby),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download nearby map'),
                  ),
                  if (_areas.length >= 8)
                    const Text(
                      'Eight maps saved. Remove an unused map to download another.',
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
                  if (!_busy && !_loaded)
                    TextButton(
                      onPressed: () => _run(_load),
                      child: const Text('Retry loading maps'),
                    ),
                ],
              ),
            ),
            const Divider(),
            const ListTile(title: Text('Saved maps · tap to focus')),
            ListTile(
              title: const Text('Bremen center'),
              subtitle: const Text('Bundled · available offline'),
              leading: const Icon(Icons.map_outlined),
              onTap: _busy
                  ? null
                  : () => _run(() async {
                      await _bundled();
                      _close();
                    }),
            ),
            for (final area in _areas)
              ListTile(
                title: Text(area.name),
                subtitle: Text(
                  '${(area.bytes / (1024 * 1024)).toStringAsFixed(1)} MiB · saved ${area.downloadedAt.toLocal().toString().split(' ').first}${_active == area.version ? ' · selected' : ''}',
                ),
                leading: const Icon(Icons.offline_pin_outlined),
                trailing: IconButton(
                  tooltip: 'Remove downloaded map',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _run(() => _remove(area)),
                ),
                onTap: _busy
                    ? null
                    : () => _run(() async {
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '© OpenStreetMap contributors · ODbL 1.0\nStreet maps only; a detailed basemap with buildings and terrain is still planned.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
