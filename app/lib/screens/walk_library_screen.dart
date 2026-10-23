import '../maps/area_store.dart';
import '../maps/active_maps.dart';
import 'package:flutter/material.dart';

import '../data/area_network.dart';
import '../recording/saved_walk.dart';
import '../review/gap_review_store.dart';
import '../settings/walk_preferences.dart';
import '../transfer/backup_archive.dart';
import '../transfer/walk_transfer.dart';
import 'walk_review_screen.dart';

class WalkLibraryScreen extends StatefulWidget {
  const WalkLibraryScreen({
    super.key,
    required this.transfer,
    required this.onChanged,
    this.showSamples = false,
    this.networks = const [],
    this.fillSmallGaps = false,
    this.autoFillGaps = true,
    this.showStreetNames = true,
    this.showMemories = true,
  });
  final WalkTransfer transfer;
  final Future<void> Function() onChanged;
  final bool showSamples;
  final List<AreaNetwork> networks;
  final bool fillSmallGaps;
  final bool autoFillGaps;
  final bool showStreetNames;
  final bool showMemories;

  @override
  State<WalkLibraryScreen> createState() => _WalkLibraryScreenState();
}

class _WalkLibraryScreenState extends State<WalkLibraryScreen> {
  WalkTransfer get _transfer => widget.transfer;
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
    await _transfer.data.history.setFavourite(walk.uid, !walk.favourite);
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
    await _transfer.cancel();
  }

  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    _walks = await _transfer.data.history.listSummaries();
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

  Future<RestoreOptions?> _chooseRestore(RestoreSummary summary) async {
    if (!mounted) return null;
    var restoreMaps = summary.maps > 0;
    var restoreSettings = false;
    return showDialog<RestoreOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Restore backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${summary.walks} walks · ${summary.memories} memories and drafts',
              ),
              const Text('Existing walks and memories are kept.'),
              if (summary.maps > 0)
                CheckboxListTile(
                  title: Text('Include ${summary.maps} offline maps'),
                  value: restoreMaps,
                  onChanged: (v) => update(() => restoreMaps = v!),
                ),
              if (summary.hasSettings)
                CheckboxListTile(
                  title: const Text('Replace my settings'),
                  value: restoreSettings,
                  onChanged: (v) => update(() => restoreSettings = v!),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                RestoreOptions(maps: restoreMaps, settings: restoreSettings),
              ),
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(bool backup) async {
    final progress = backup ? _beginArchive() : BackupProgress();
    final result = await _transfer.importFile(
      backup: backup,
      choose: _chooseRestore,
      progress: progress,
      onCommit: () {
        if (mounted) setState(() => _archiveProgress = null);
      },
    );
    if (result == null) return;
    await _load();
    if (result.preferences != null) _restoredPreferences = result.preferences;
    await widget.onChanged();
    _message =
        '${result.added} walk${result.added == 1 ? '' : 's'} added; ${result.existing} already saved. '
        '${backup ? 'Backup restored with memories${result.restoredMaps ? ', offline maps' : ''}${result.preferences != null ? ' and settings' : ''}.' : 'Streets update for walks inside saved maps.'}';
  }

  Future<void> _backup() async {
    if (await _transfer.backup(_beginArchive())) {
      _message =
          'Backup saved: walks, memories, photos, settings and offline maps.';
    }
  }

  Future<void> _export(SavedWalk walk) async {
    if (await _transfer.exportGpx(walk)) _message = 'GPX saved.';
  }

  Future<void> _review(SavedWalk summary) async {
    final walk = await _transfer.data.history.loadWalk(summary.id);
    if (_transfer.data.maps case final SpatialAreaStore spatial) {
      if (walk.points.isNotEmpty) {
        var bounds = Rect.fromLTWH(
          walk.points.first.longitude,
          walk.points.first.latitude,
          0,
          0,
        );
        for (final p in walk.points) {
          bounds = bounds.expandToInclude(
            Rect.fromLTWH(p.longitude, p.latitude, 0, 0),
          );
        }
        final window = ActiveMaps(spatial)..browsing = bounds.inflate(.002);
        try {
          await window.refresh();
          _networks = List.of(window.networks);
        } finally {
          window.dispose();
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalkReviewScreen(
          walk: walk,
          saveActivity: (activity) async {
            await _transfer.data.history.setActivity(walk.uid, activity);
            await widget.onChanged();
            await _load();
          },
          saveConfirmed: _transfer.data.history is GapReviewStore
              ? (edges) async {
                  await (_transfer.data.history as GapReviewStore)
                      .saveConfirmedSections(walk.uid, edges);
                  await widget.onChanged();
                }
              : null,
          networks: _networks,
          autoFillGaps:
              _restoredPreferences?.autoFillGaps ?? widget.autoFillGaps,
          fillSmallGaps:
              _restoredPreferences?.fillSmallGaps ?? widget.fillSmallGaps,
          showStreetNames:
              _restoredPreferences?.showStreetNames ?? widget.showStreetNames,
          memoryStore: _transfer.data.memories,
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
        title: const Text('Recording history'),
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
                        'Every recording contributes to the same map. Favourites help you find special journeys. GPX files are created only when you export.',
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
                        'Backups include recordings, photos, maps and settings. Keep a copy somewhere safe. GPX contains one journey.',
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
                          child: const Text('Retry loading recordings'),
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
                        label: const Text('All recordings'),
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
                          : 'No recordings yet',
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
                        '${walk.activity.label} · ${walk.status} · Tap to review${(_restoredPreferences?.showSamples ?? widget.showSamples) ? ' · ${walk.pointCount} GPS samples' : ''}',
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
