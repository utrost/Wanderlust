import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../memories/memory.dart';
import '../memories/memory_store.dart';
import '../memories/memory_photos.dart';
import '../memories/memory_location.dart';

class MemoryEditor extends StatefulWidget {
  const MemoryEditor({
    super.key,
    required this.store,
    required this.memory,
    this.isNew = false,
    this.photos,
    this.locate = locateMemory,
  });
  final MemoryStore store;
  final WalkMemory memory;
  final bool isNew;
  final MemoryPhotos? photos;
  final Future<Position> Function() locate;
  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late WalkMemory value = widget.memory;
  late final TextEditingController note = TextEditingController(
    text: value.note,
  );
  late final MemoryPhotos photos = widget.photos ?? DeviceMemoryPhotos();
  bool busy = false, loaded = false, dirty = false, allowPop = false;
  String? error;
  bool locating = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on MemoryLocationError catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not complete this action. Your draft is still here. Check permissions or storage and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    if (!widget.isNew) {
      value =
          await widget.store.read(value.id, true) ??
          await widget.store.read(value.id, false) ??
          (throw StateError('Memory missing'));
      note.text = value.note;
    }
    loaded = true;
  });
  WalkMemory _snapshot({bool draft = true, bool pending = false}) => value
      .copyWith(note: note.text.trim(), draft: draft, pendingPhoto: pending);
  void _pop() {
    setState(() => allowPop = true);
    Navigator.of(context).pop(true);
  }

  Future<void> _leave() => _run(() async {
    if (loaded && dirty) await widget.store.put(_snapshot());
    if (mounted) _pop();
  });
  Future<void> _save() => _run(() async {
    final saved = _snapshot(draft: false);
    if (!saved.hasContent) {
      throw const FormatException('Add a note or photo before saving.');
    }
    await widget.store.put(saved);
    if (mounted) _pop();
  });
  Future<void> _photo(bool camera) => _run(() async {
    await widget.store.put(_snapshot(pending: true));
    final image = await photos.pick(camera);
    if (image != null) value = value.copyWith(photo: image);
    await widget.store.put(_snapshot());
    dirty = true;
  });
  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(value.draft ? 'Discard draft?' : 'Delete memory?'),
        content: Text(
          value.draft
              ? 'The draft and its photo will be removed. Any previously saved version remains.'
              : 'This note and photo will be removed from your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      await widget.store.delete(value.id, draftOnly: value.draft);
      if (mounted) _pop();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Add memory' : 'Memory'),
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: 'Delete memory',
              onPressed: busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'A small thing worth remembering. Stays on your phone.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: note,
                    enabled: loaded && !busy,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: 4000,
                    onChanged: (_) => dirty = true,
                    decoration: const InputDecoration(
                      labelText: 'What caught your attention?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (value.photo case final bytes?) ...[
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Photo')),
                            body: Center(
                              child: InteractiveViewer(
                                maxScale: 5,
                                child: Image.memory(
                                  bytes,
                                  errorBuilder: (_, _, _) =>
                                      const Text('Photo cannot be displayed'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: Image.memory(
                        bytes,
                        height: 200,
                        fit: BoxFit.contain,
                        cacheWidth: 600,
                        errorBuilder: (_, _, _) =>
                            const Text('Photo cannot be displayed'),
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              value = value.copyWith(removePhoto: true);
                              dirty = true;
                            }),
                      child: const Text('Remove photo'),
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy || !loaded ? null : () => _photo(true),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Take photo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy || !loaded ? null : () => _photo(false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          value.hasPhoto ? 'Replace photo' : 'Choose photo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    value.hasLocation
                        ? 'Location attached · ±${value.accuracy?.round() ?? 0} m\n${value.latitude!.toStringAsFixed(5)}, ${value.longitude!.toStringAsFixed(5)}'
                        : 'No location attached. You can save without a pin.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: busy || !loaded
                            ? null
                            : () => _run(() async {
                                setState(() => locating = true);
                                try {
                                  final fix = await widget.locate();
                                  if (!WalkMemory.usableFix(
                                    fix,
                                    DateTime.now(),
                                  )) {
                                    throw const MemoryLocationError(
                                      'No accurate recent fix. Try again outdoors; you can save without a pin.',
                                    );
                                  }
                                  value = value.copyWith(fix: fix);
                                  dirty = true;
                                } finally {
                                  if (mounted) setState(() => locating = false);
                                }
                              }),
                        icon: const Icon(Icons.my_location),
                        label: Text(
                          locating
                              ? 'Finding your location…'
                              : 'Use current location',
                        ),
                      ),
                      if (value.hasLocation)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  value = value.copyWith(removeLocation: true);
                                  dirty = true;
                                }),
                          child: const Text('Remove location'),
                        ),
                    ],
                  ),
                  const Text(
                    'Back keeps your changes as a draft. Photos and notes are included in full backups.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(error!),
                    ),
                  if (!loaded && !busy)
                    TextButton(
                      onPressed: _load,
                      child: const Text('Retry loading memory'),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy || !loaded ? null : _save,
                  child: const Text('Save memory'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({
    super.key,
    required this.store,
    this.walkUid,
    this.add,
  });
  final MemoryStore store;
  final String? walkUid;
  final Future<void> Function()? add;
  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<WalkMemory> items = [];
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.store.list(walkUid: widget.walkUid);
      final draftIds = all.where((m) => m.draft).map((m) => m.id).toSet();
      if (mounted) {
        setState(() {
          items = all
              .where((m) => m.draft || !draftIds.contains(m.id))
              .toList();
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load memories. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Memories'),
      actions: [
        if (widget.add != null)
          IconButton(
            tooltip: 'Add memory',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await widget.add!();
              await _load();
            },
          ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: TextButton(onPressed: _load, child: Text('$error Retry')),
          )
        : items.isEmpty
        ? const Center(
            child: Text(
              'Small things worth remembering.\nYour notes and photos will appear here.',
              textAlign: TextAlign.center,
            ),
          )
        : ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              return ListTile(
                leading: Icon(
                  m.hasPhoto ? Icons.photo_outlined : Icons.bookmark_outline,
                ),
                title: Text(
                  m.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${m.draft ? 'Draft · Continue · ' : ''}${m.createdAt.toLocal().toString().split('.').first}\n${m.hasLocation ? 'Location attached' : 'Without a map pin'}',
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MemoryEditor(store: widget.store, memory: m),
                    ),
                  );
                  await _load();
                },
              );
            },
          ),
  );
}
