import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/area_network.dart';
import '../memories/memory.dart';
import '../memories/memory_repository.dart';
import '../recording/activity_type.dart';
import '../recording/saved_walk.dart';
import '../review/gap_routes.dart';
import '../review/walk_review.dart';
import '../transfer/walk_codec.dart';
import '../widgets/activity_selector.dart';
import '../widgets/area_map.dart';
import '../widgets/gap_review_panel.dart';
import '../widgets/walk_overlay.dart';
import 'memories_screen.dart';

typedef ReviewMatcher =
    Future<WalkReviewResult> Function(List<String>, SavedWalk, bool);

class WalkReviewScreen extends StatefulWidget {
  const WalkReviewScreen({
    super.key,
    required this.walk,
    this.networks = const [],
    this.fillSmallGaps = false,
    this.autoFillGaps = true,
    this.showStreetNames = true,
    this.memoryStore,
    this.showMemories = true,
    this.match = matchWalkReview,
    this.saveConfirmed,
    this.saveActivity,
  });
  final Future<void> Function(List<int>)? saveConfirmed;
  final Future<void> Function(WalkActivity)? saveActivity;
  final SavedWalk walk;
  final List<AreaNetwork> networks;
  final bool fillSmallGaps;
  final bool autoFillGaps;
  final bool showStreetNames;
  final MemoryRepository? memoryStore;
  final bool showMemories;
  final ReviewMatcher match;
  @override
  State<WalkReviewScreen> createState() => _WalkReviewScreenState();
}

class _WalkReviewScreenState extends State<WalkReviewScreen> {
  late SavedWalk walk = widget.walk;
  bool changingActivity = false;
  GapRoute? proposal;
  late Set<int> confirmed = walk.confirmedSections.toSet();
  List<WalkMemory> memories = [];
  Future<void> _loadMemories() async {
    if (widget.memoryStore == null) return;
    try {
      final items = await widget.memoryStore!.list(walkUid: walk.uid);
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
  late final trace = reviewTrace(walk);
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
        walk,
        fill,
      );
      final automatic = <int>{};
      if (widget.autoFillGaps && hasReviewableGaps(walk)) {
        for (final map in maps) {
          automatic.addAll(
            (await automaticGapSections(
              map.geojson,
              [WalkCodec.exportGpx(walk)],
              [confirmed.toList()],
            )).single,
          );
        }
      }
      if (mounted && token == generation) {
        setState(
          () => result = WalkReviewResult(value.direct, {
            ...value.inferred,
            ...automatic.difference(value.direct),
          }),
        );
      }
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

  Future<void> _changeActivity(WalkActivity value) async {
    setState(() => changingActivity = true);
    try {
      await widget.saveActivity!(value);
      if (!mounted) return;
      setState(() {
        walk = walk.withActivity(value);
        proposal = null;
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not update activity. Please retry.');
      }
    } finally {
      if (mounted) setState(() => changingActivity = false);
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
    appBar: AppBar(
      title: Text(
        walk.activity == WalkActivity.cycle ? 'Review ride' : 'Review walk',
      ),
    ),
    body: Column(
      children: [
        if (widget.saveActivity != null)
          ActivitySelector(
            value: walk.activity,
            onChanged: busy || changingActivity ? null : _changeActivity,
          ),
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
        if (widget.saveConfirmed != null)
          GapReviewPanel(
            walk: walk,
            maps: maps.map((m) => m.geojson).toList(),
            save: widget.saveConfirmed!,
            onPreview: (route) => setState(() => proposal = route),
            onConfirmed: (edges) {
              setState(() => confirmed = edges);
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
                    walkUid: walk.uid,
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
        if (walk.points.isEmpty)
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
                  key: ValueKey(proposal),
                  showStreetNames: widget.showStreetNames,
                  memories: widget.showMemories ? memories : const [],
                  onMemory: widget.memoryStore == null ? null : _openMemory,
                  network: viewport!,
                  coverageScreenWidth: 4,
                  networks: maps,
                  counts: matched
                      ? {
                          for (final id in {...result.direct, ...confirmed})
                            id: 1,
                        }
                      : {},
                  trace: gps ? trace : const [],
                  inferred: {
                    ...(inferred ? result.inferred : <int>{}),
                    ...?proposal?.edges,
                  },
                  fitCoordinates: proposal?.coordinates ?? coordinates,
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
