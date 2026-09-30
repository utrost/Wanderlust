import 'dart:convert';
import '../memories/memory_backup.dart';
import '../memories/memory_photos.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../recording/walk_store.dart';
import '../data/area_network.dart';
import '../settings/walk_preferences.dart';
import 'walk_review_screen.dart';
import '../transfer/walk_codec.dart';
import '../transfer/walk_files.dart';

MemoryBackup _readBackup(Uint8List bytes) => MemoryBackup.decode(bytes);
SavedWalk _readGpx(Uint8List bytes) =>
    WalkCodec.importGpx(WalkCodec.decodeBytes(bytes));
Uint8List _writeBackup(MemoryBackup backup) =>
    MemoryBackup.encode(backup, compressed: true);
Uint8List _writeGpx(SavedWalk walk) =>
    Uint8List.fromList(utf8.encode(WalkCodec.exportGpx(walk)));

class WalkLibraryScreen extends StatefulWidget {
  const WalkLibraryScreen({
    super.key,
    required this.store,
    required this.onChanged,
    this.files,
    this.showSamples = false,
    this.networks = const [],
    this.fillSmallGaps = false,
    this.showStreetNames = true,
    this.showMemories = true,
  });
  final SqliteWalkStore store;
  final Future<void> Function() onChanged;
  final WalkFiles? files;
  final bool showSamples;
  final List<AreaNetwork> networks;
  final bool fillSmallGaps;
  final bool showStreetNames;
  final bool showMemories;

  @override
  State<WalkLibraryScreen> createState() => _WalkLibraryScreenState();
}

class _WalkLibraryScreenState extends State<WalkLibraryScreen> {
  late final WalkFiles _files = widget.files ?? DeviceWalkFiles();
  List<SavedWalk> _walks = [];
  late List<AreaNetwork> _networks = widget.networks;
  WalkPreferences? _restoredPreferences;
  bool _busy = true;
  bool _loaded = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    _walks = await widget.store.listSaved();
    _loaded = true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      _message = 'File could not be read: ${e.message}';
    } catch (_) {
      _message =
          'Could not complete the operation. Check file access and available storage, then retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(bool backup) async {
    final bytes = await _files.pick();
    if (bytes == null) return;
    final bundle = backup
        ? await compute(_readBackup, bytes)
        : MemoryBackup([await compute(_readGpx, bytes)], const []);
    for (final memory in bundle.memories) {
      if (memory.photo != null) await validatePhoto(memory.photo!);
    }
    var restoreMaps = bundle.maps.isNotEmpty;
    var restoreSettings = false;
    if (backup && (bundle.maps.isNotEmpty || bundle.preferences != null)) {
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Restore backup'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${bundle.walks.length} walks · ${bundle.memories.length} memories and drafts',
                ),
                const Text('Existing walks and memories are kept.'),
                if (bundle.maps.isNotEmpty)
                  CheckboxListTile(
                    title: Text('Include ${bundle.maps.length} offline maps'),
                    value: restoreMaps,
                    onChanged: (v) => update(() => restoreMaps = v!),
                  ),
                if (bundle.preferences != null)
                  CheckboxListTile(
                    title: const Text('Replace my settings'),
                    value: restoreSettings,
                    onChanged: (v) => update(() => restoreSettings = v!),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ),
      );
      if (approved != true) return;
    }
    final walks = bundle.walks;
    final added = await widget.store.mergeWalks(
      walks,
      deduplicateTrace: !backup,
      memories: bundle.memories,
      maps: restoreMaps ? bundle.maps : const [],
      preferences: restoreSettings ? bundle.preferences : null,
      activeMap: restoreMaps ? bundle.activeMap : null,
    );
    await _load();
    if (restoreSettings) _restoredPreferences = bundle.preferences;
    if (restoreMaps) {
      _networks = [
        for (final area in await widget.store.listAreas())
          if (await widget.store.readArea(area.version) case final source?)
            AreaNetwork.parse(source),
      ];
    }
    // Raw data is committed before matching. A matching failure cannot lose it.
    await widget.onChanged();
    _message =
        '$added walk${added == 1 ? '' : 's'} added; ${walks.length - added} already saved. '
        '${backup ? 'Backup restored with memories${restoreMaps ? ', offline maps' : ''}${restoreSettings ? ' and settings' : ''}.' : 'Streets update for walks inside saved maps.'}';
  }

  Future<void> _backup() async {
    final maps = <String>[];
    for (final area in await widget.store.listAreas()) {
      final source = await widget.store.readArea(area.version);
      if (source == null) throw StateError('Saved map is unavailable');
      maps.add(source);
    }
    final selected = await widget.store.readActiveArea();
    final bytes = await compute(
      _writeBackup,
      MemoryBackup(
        _walks,
        await widget.store.memories.exportAll(),
        maps: maps,
        preferences: await widget.store.readPreferences(),
        activeMap: selected == null
            ? null
            : AreaNetwork.parse(selected).version,
      ),
    );
    final saved = await _files.save(
      'wanderlust-backup.json.gz',
      'application/gzip',
      bytes,
    );
    if (saved) {
      _message =
          'Backup saved: ${_walks.length} walks, memories, photos, settings and ${maps.length} maps.';
    }
  }

  Future<void> _export(SavedWalk walk) async {
    final bytes = await compute(_writeGpx, walk);
    final saved = await _files.save(
      'wanderlust-walk-${walk.uid}.gpx',
      'application/gpx+xml',
      bytes,
    );
    if (saved) _message = 'GPX saved.';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Saved walks')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Import GPX tracks or restore a Wanderlust backup. Backups include memories, photos, settings and offline maps. Restore adds missing items and keeps existing local entries.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy || !_loaded
                          ? null
                          : () => _run(() => _import(false)),
                      child: const Text('Import GPX'),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !_loaded
                          ? null
                          : () => _run(() => _import(true)),
                      child: const Text('Restore backup'),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !_loaded ? null : () => _run(_backup),
                      child: const Text('Create backup'),
                    ),
                  ],
                ),
                const Text(
                  'Compressed backups include your maps and settings (up to 128 MiB expanded). GPX contains only the walk. Choose where to save exports.',
                  style: TextStyle(fontSize: 12),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message!, key: const Key('transfer-message')),
                  ),
                if (!_busy && !_loaded)
                  TextButton(
                    onPressed: () => _run(_load),
                    child: const Text('Retry loading walks'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _walks.isEmpty
                ? const Center(child: Text('No saved walks yet'))
                : ListView.builder(
                    itemCount: _walks.length,
                    itemBuilder: (context, index) {
                      final walk = _walks[index];
                      return ListTile(
                        onTap: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => WalkReviewScreen(
                                    walk: walk,
                                    networks: _networks,
                                    fillSmallGaps:
                                        _restoredPreferences?.fillSmallGaps ??
                                        widget.fillSmallGaps,
                                    showStreetNames:
                                        _restoredPreferences?.showStreetNames ??
                                        widget.showStreetNames,
                                    memoryStore: widget.store.memories,
                                    showMemories:
                                        _restoredPreferences?.showMemories ??
                                        widget.showMemories,
                                  ),
                                ),
                              ),
                        leading: const Icon(Icons.route_outlined),
                        title: Text(
                          walk.untimed.length == walk.points.length &&
                                  walk.points.isNotEmpty
                              ? 'Undated track'
                              : walk.startedAt
                                    .toLocal()
                                    .toString()
                                    .split('.')
                                    .first,
                        ),
                        subtitle: Text(
                          '${walk.status} · Tap to review${(_restoredPreferences?.showSamples ?? widget.showSamples) ? ' · ${walk.points.length} GPS samples' : ''}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Export GPX',
                          onPressed: _busy
                              ? null
                              : () => _run(() => _export(walk)),
                          icon: const Icon(Icons.file_download_outlined),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
