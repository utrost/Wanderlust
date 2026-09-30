import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../recording/walk_store.dart';
import '../data/area_network.dart';
import 'walk_review_screen.dart';
import '../transfer/walk_codec.dart';
import '../transfer/walk_files.dart';

List<SavedWalk> _readBackup(Uint8List bytes) =>
    WalkCodec.importBackup(WalkCodec.decodeBytes(bytes));
SavedWalk _readGpx(Uint8List bytes) =>
    WalkCodec.importGpx(WalkCodec.decodeBytes(bytes));
Uint8List _writeBackup(List<SavedWalk> walks) =>
    Uint8List.fromList(utf8.encode(WalkCodec.exportBackup(walks)));
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
  });
  final SqliteWalkStore store;
  final Future<void> Function() onChanged;
  final WalkFiles? files;
  final bool showSamples;
  final List<AreaNetwork> networks;
  final bool fillSmallGaps;
  final bool showStreetNames;

  @override
  State<WalkLibraryScreen> createState() => _WalkLibraryScreenState();
}

class _WalkLibraryScreenState extends State<WalkLibraryScreen> {
  late final WalkFiles _files = widget.files ?? DeviceWalkFiles();
  List<SavedWalk> _walks = [];
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
    final walks = backup
        ? await compute(_readBackup, bytes)
        : [await compute(_readGpx, bytes)];
    final added = await widget.store.mergeWalks(
      walks,
      deduplicateTrace: !backup,
    );
    await _load();
    // Raw data is committed before matching. A matching failure cannot lose it.
    await widget.onChanged();
    _message =
        '$added walk${added == 1 ? '' : 's'} added; ${walks.length - added} already saved. Streets update for walks inside the selected map.';
  }

  Future<void> _backup() async {
    final bytes = await compute(_writeBackup, _walks);
    final saved = await _files.save(
      'wanderlust-backup.json',
      'application/json',
      bytes,
    );
    if (saved) _message = 'Backup saved (${_walks.length} walks).';
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
                  'Import GPX tracks or restore a Wanderlust backup. Restore adds missing walks and keeps your existing walks.',
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
                  'Exports contain your location history. Choose where to save them.',
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
                                    networks: widget.networks,
                                    fillSmallGaps: widget.fillSmallGaps,
                                    showStreetNames: widget.showStreetNames,
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
                          '${walk.status} · Tap to review${widget.showSamples ? ' · ${walk.points.length} GPS samples' : ''}',
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
