import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/area_network.dart';
import '../recording/saved_walk.dart';
import '../review/walk_review.dart';
import '../widgets/area_map.dart';
import '../widgets/walk_overlay.dart';
import '../memories/memory.dart';
import '../memories/memory_store.dart';
import 'memories_screen.dart';

typedef ReviewMatcher =
    Future<WalkReviewResult> Function(List<String>, SavedWalk, bool);

class WalkReviewScreen extends StatefulWidget {
  const WalkReviewScreen({
    super.key,
    required this.walk,
    this.networks = const [],
    this.fillSmallGaps = false,
    this.showStreetNames = true,
    this.memoryStore,
    this.showMemories = true,
    this.match = matchWalkReview,
  });
  final SavedWalk walk;
  final List<AreaNetwork> networks;
  final bool fillSmallGaps;
  final bool showStreetNames;
  final MemoryStore? memoryStore;
  final bool showMemories;
  final ReviewMatcher match;
  @override
  State<WalkReviewScreen> createState() => _WalkReviewScreenState();
}

class _WalkReviewScreenState extends State<WalkReviewScreen> {
  List<WalkMemory> memories = [];
  Future<void> _loadMemories() async {
    if (widget.memoryStore == null) return;
    try {
      final items = await widget.memoryStore!.list(walkUid: widget.walk.uid);
      if (mounted) setState(() => memories = items);
    } catch (_) {
      /* Library offers a retry; route review remains usable. */
    }
  }

  Future<void> _openMemory(WalkMemory m) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryEditor(
          store: widget.memoryStore!,
          memory: m,
          networks: widget.networks,
        ),
      ),
    );
    await _loadMemories();
  }

  bool gps = true, matched = true, inferred = true, busy = true;
  late bool fill = widget.fillSmallGaps;
  late final trace = reviewTrace(widget.walk);
  late final coordinates = trace.expand((s) => s).toList();
  List<AreaNetwork> maps = [];
  AreaNetwork? viewport;
  WalkReviewResult result = const WalkReviewResult({}, {});
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
    _loadMemories();
  }

  Future<void> _load() async {
    final token = ++generation;
    setState(() {
      busy = true;
      error = null;
      result = const WalkReviewResult({}, {});
    });
    try {
      if (maps.isEmpty) {
        maps = widget.networks;
        viewport = maps.firstOrNull ?? AreaNetwork.emptyViewport();
        if (coordinates.isNotEmpty) {
          final xs = coordinates.map((p) => p.dx).toList()..sort(),
              ys = coordinates.map((p) => p.dy).toList()..sort();
          final dx = math.max(xs.last - xs.first, 0.002),
              dy = math.max(ys.last - ys.first, 0.002);
          viewport = viewport!.withViewport([
            (xs.first - dx * .1).clamp(-180, 180).toDouble(),
            (ys.first - dy * .1).clamp(-90, 90).toDouble(),
            (xs.last + dx * .1).clamp(-180, 180).toDouble(),
            (ys.last + dy * .1).clamp(-90, 90).toDouble(),
          ]);
        }
      }
      final value = await widget.match(
        maps.map((m) => m.geojson).toList(),
        widget.walk,
        fill,
      );
      if (mounted && token == generation) setState(() => result = value);
    } catch (_) {
      if (mounted && token == generation) {
        setState(
          () => error =
              'Street matching could not load. Your recorded GPS trace is unchanged.',
        );
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Widget layer(
    String name,
    bool value,
    Color color,
    void Function(bool) change,
  ) => FilterChip(
    label: Text(name),
    avatar: Icon(Icons.circle, size: 12, color: color),
    selected: value,
    showCheckmark: false,
    onSelected: change,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review walk')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            children: [
              layer(
                'GPS trace',
                gps,
                reviewTraceColor,
                (v) => setState(() => gps = v),
              ),
              layer(
                'Matched streets',
                matched,
                const Color(0xFFC4A080),
                (v) => setState(() => matched = v),
              ),
              layer(
                'Inferred gaps',
                inferred,
                reviewInferredColor,
                (v) => setState(() => inferred = v),
              ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Preview gap filling'),
          subtitle: const Text(
            'Review only · does not change your saved coverage',
          ),
          value: fill,
          onChanged: busy
              ? null
              : (v) {
                  setState(() => fill = v);
                  _load();
                },
        ),
        if (widget.memoryStore != null)
          TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemoriesScreen(
                    networks: widget.networks,
                    store: widget.memoryStore!,
                    walkUid: widget.walk.uid,
                  ),
                ),
              );
              await _loadMemories();
            },
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('Memories from this walk'),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: Text(error!)),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        if (widget.walk.points.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('This walk has no GPS readings.'),
          ),
        if (!busy && coordinates.any((p) => !maps.any((m) => m.contains(p))))
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Part of this trace is outside your saved street maps.',
            ),
          ),
        Expanded(
          child: viewport == null
              ? const Center(child: Text('Loading map…'))
              : AreaMap(
                  showStreetNames: widget.showStreetNames,
                  memories: widget.showMemories ? memories : const [],
                  onMemory: widget.memoryStore == null ? null : _openMemory,
                  network: viewport!,
                  coverageScreenWidth: 4,
                  networks: maps,
                  counts: matched
                      ? {for (final id in result.direct) id: 1}
                      : {},
                  trace: gps ? trace : const [],
                  inferred: inferred ? result.inferred : const {},
                  fitCoordinates: coordinates,
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Blue: recorded GPS · Brown: matched streets\nPurple dashes: inferred connections\n© OpenStreetMap contributors · ODbL',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
