import 'dart:convert';
import 'dart:io';
import '../transfer/backup_archive.dart';
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
  bool _favouritesOnly = false;
  List<SavedWalk> get _visibleWalks => _favouritesOnly
      ? _walks.where((walk) => walk.favourite).toList()
      : _walks;

  Future<void> _toggleFavourite(SavedWalk walk) async {
    await widget.store.setFavourite(walk.uid, !walk.favourite);
    await _load();
  }

  String? _message;
  BackupProgress? _archiveProgress;
  int _archiveRecords = 0;
  BackupProgress _beginArchive() {
    _archiveRecords = 0;
    return _archiveProgress = BackupProgress(
      onProgress: (records) {
        if (mounted) setState(() => _archiveRecords = records);
      },
    );
  }

  Future<void> _cancelArchive() async {
    _archiveProgress?.cancelled = true;
    if (_files is ArchiveFiles) await (_files as ArchiveFiles).cancelArchive();
  }

  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    _walks = await widget.store.listSummaries();
    _loaded = true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on BackupCancelled {
      _message = 'Backup operation cancelled. Your data is unchanged.';
    } on FormatException catch (e) {
      _message = 'File could not be read: ${e.message}';
    } catch (_) {
      _message =
          'Could not complete the operation. Check file access and available storage, then retry.';
    } finally {
      _archiveProgress = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(bool backup) async {
    if (backup && _files is ArchiveFiles) {
      final progress = _beginArchive();
      final directory = await Directory.systemTemp.createTemp(
        'wanderlust-restore-',
      );
      File? input;
      try {
        input = await (_files as ArchiveFiles).pickArchive();
        if (input == null) return;
        progress.check();
        if (await BackupArchive.recognizes(input)) {
          final staged = await BackupArchive.read(input, directory, progress);
          await _restore(staged.metadata, true, staged: staged);
        } else {
          if (await input.length() > MemoryBackup.maxBytes) {
            throw const FormatException('Legacy backup exceeds 128 MiB.');
          }
          await _restore(
            await compute(_readBackup, await input.readAsBytes()),
            true,
          );
        }
      } finally {
        if (input != null && await input.exists()) await input.delete();
        await directory.delete(recursive: true);
      }
      return;
    }
    final bytes = await _files.pick();
    if (bytes == null) return;
    final bundle = backup
        ? await compute(_readBackup, bytes)
        : MemoryBackup([await compute(_readGpx, bytes)], const []);
    await _restore(bundle, backup);
  }

  Future<void> _restore(
    MemoryBackup bundle,
    bool backup, {
    StagedBackup? staged,
  }) async {
    await for (final memory
        in staged?.memories() ?? Stream.fromIterable(bundle.memories)) {
      _archiveProgress?.check();
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
    _archiveProgress?.check();
    // The validated import commits atomically; cancellation ends before commit.
    if (mounted) setState(() => _archiveProgress = null);
    final walks = bundle.walks;
    final added = await widget.store.mergeWalks(
      walks,
      deduplicateTrace: !backup,
      memories: staged == null ? bundle.memories : const [],
      memoryStream: staged?.memories(),
      walkStream: staged?.walks(),
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
    if (_files is ArchiveFiles) {
      final progress = _beginArchive();
      final directory = await Directory.systemTemp.createTemp(
        'wanderlust-export-',
      );
      try {
        final file = File('${directory.path}/backup.wanderlust');
        await BackupArchive.write(file, widget.store, progress);
        progress.check();
        if (await (_files as ArchiveFiles).saveArchive(file)) {
          _message =
              'Backup saved: walks, memories, photos, settings and offline maps.';
        }
      } finally {
        await directory.delete(recursive: true);
      }
      return;
    }
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
        await widget.store.listSaved(),
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
    final full = walk.isSummary ? await widget.store.loadWalk(walk.id) : walk;
    final bytes = await compute(_writeGpx, full);
    final saved = await _files.save(
      'wanderlust-walk-${walk.uid}.gpx',
      'application/gpx+xml',
      bytes,
    );
    if (saved) _message = 'GPX saved.';
  }

  Future<void> _review(SavedWalk summary) async {
    final walk = summary.isSummary
        ? await widget.store.loadWalk(summary.id)
        : summary;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalkReviewScreen(
          walk: walk,
          networks: _networks,
          fillSmallGaps:
              _restoredPreferences?.fillSmallGaps ?? widget.fillSmallGaps,
          showStreetNames:
              _restoredPreferences?.showStreetNames ?? widget.showStreetNames,
          memoryStore: widget.store.memories,
          showMemories:
              _restoredPreferences?.showMemories ?? widget.showMemories,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Walk history'),
        actions: [
          if (_busy && _archiveProgress != null)
            TextButton(onPressed: _cancelArchive, child: const Text('Cancel')),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_busy && _archiveProgress != null) ...[
                        const LinearProgressIndicator(),
                        Text('Processing backup · $_archiveRecords items'),
                        const SizedBox(height: 8),
                      ],
                      const Text(
                        'Every recorded walk counts towards your heatmap. Favourites simply help you find special walks. GPX files are created only when you export.',
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
                            onPressed: _busy || !_loaded
                                ? null
                                : () => _run(_backup),
                            child: const Text('Create backup'),
                          ),
                        ],
                      ),
                      const Text(
                        'Backups include walks, photos, maps and settings. Keep a copy somewhere safe. GPX contains only the walk.',
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
                          child: Text(
                            _message!,
                            key: const Key('transfer-message'),
                          ),
                        ),
                      if (!_busy && !_loaded)
                        TextButton(
                          onPressed: () => _run(_load),
                          child: const Text('Retry loading walks'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All walks'),
                        selected: !_favouritesOnly,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _favouritesOnly = false),
                      ),
                      ChoiceChip(
                        label: const Text('Favourites'),
                        avatar: const Icon(Icons.star, size: 18),
                        selected: _favouritesOnly,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _favouritesOnly = true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _visibleWalks.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      _favouritesOnly
                          ? 'Star a walk to find it here.'
                          : 'No walks yet',
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: _visibleWalks.length,
                  itemBuilder: (context, index) {
                    final walk = _visibleWalks[index];
                    return ListTile(
                      onTap: _busy ? null : () => _run(() => _review(walk)),
                      leading: IconButton(
                        tooltip: walk.favourite
                            ? 'Remove from favourites'
                            : 'Add to favourites',
                        onPressed: _busy
                            ? null
                            : () => _run(() => _toggleFavourite(walk)),
                        icon: Icon(
                          walk.favourite ? Icons.star : Icons.star_border,
                        ),
                      ),
                      title: Text(
                        walk.untimed.length == walk.pointCount &&
                                walk.pointCount > 0
                            ? 'Undated track'
                            : walk.startedAt
                                  .toLocal()
                                  .toString()
                                  .split('.')
                                  .first,
                      ),
                      subtitle: Text(
                        '${walk.status} · Tap to review${(_restoredPreferences?.showSamples ?? widget.showSamples) ? ' · ${walk.pointCount} GPS samples' : ''}',
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
        ],
      ),
    ),
  );
}
