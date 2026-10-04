import 'package:flutter/material.dart';

import '../recording/saved_walk.dart';
import '../review/gap_routes.dart';

class GapReviewPanel extends StatefulWidget {
  const GapReviewPanel({
    super.key,
    required this.walk,
    required this.maps,
    required this.save,
    required this.onPreview,
    required this.onConfirmed,
    this.suggest = suggestGapRoutes,
  });
  final Future<List<ReviewGap>> Function(List<String>, SavedWalk) suggest;
  final SavedWalk walk;
  final List<String> maps;
  final Future<void> Function(List<int>) save;
  final void Function(GapRoute?) onPreview;
  final void Function(Set<int>) onConfirmed;
  @override
  State<GapReviewPanel> createState() => _GapReviewPanelState();
}

class _GapReviewPanelState extends State<GapReviewPanel> {
  List<ReviewGap>? gaps;
  late Set<int> confirmed = widget.walk.confirmedSections.toSet();
  int gap = 0, option = 0;
  bool busy = false;
  String? error;
  GapRoute? get selected =>
      gaps == null || gaps!.isEmpty || gaps![gap].routes.isEmpty
      ? null
      : gaps![gap].routes[option];
  @override
  void didUpdateWidget(covariant GapReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walk.activity != widget.walk.activity) {
      gaps = null;
      gap = 0;
      option = 0;
    }
  }

  Future<void> load() async {
    final activity = widget.walk.activity;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.suggest(widget.maps, widget.walk);
      if (!mounted || activity != widget.walk.activity) return;
      setState(() {
        gaps = result;
        gap = 0;
        option = 0;
      });
      widget.onPreview(selected);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not suggest routes. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(Set<int> value) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(value.toList()..sort());
      if (!mounted) return;
      setState(() => confirmed = value);
      widget.onConfirmed(value);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.route),
              label: const Text('Review GPS gaps'),
            ),
            if (confirmed.isNotEmpty)
              IconButton(
                tooltip: 'Undo all confirmed gaps for this walk',
                onPressed: busy ? null : () => save({}),
                icon: const Icon(Icons.undo),
              ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (gaps != null && gaps!.isEmpty)
          const Text('No reviewable GPS gaps (30 seconds–5 minutes).'),
        if (gaps != null && gaps!.isNotEmpty) ...[
          Row(
            children: [
              IconButton(
                tooltip: 'Previous gap',
                onPressed: busy || gap == 0
                    ? null
                    : () {
                        setState(() {
                          gap--;
                          option = 0;
                        });
                        widget.onPreview(selected);
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'Gap ${gap + 1}/${gaps!.length} · ${gaps![gap].end.difference(gaps![gap].start).inSeconds} s',
                ),
              ),
              IconButton(
                tooltip: 'Next gap',
                onPressed: busy || gap == gaps!.length - 1
                    ? null
                    : () {
                        setState(() {
                          gap++;
                          option = 0;
                        });
                        widget.onPreview(selected);
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (selected == null)
            const Text('No plausible connection in your saved maps.')
          else
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  value: option,
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() => option = v!);
                          widget.onPreview(selected);
                        },
                  items: [
                    for (var i = 0; i < gaps![gap].routes.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          'Route ${i + 1} · ${gaps![gap].routes[i].meters.round()} m',
                        ),
                      ),
                  ],
                ),
                FilledButton(
                  onPressed: busy || confirmed.containsAll(selected!.edges)
                      ? null
                      : () => save({...confirmed, ...selected!.edges}),
                  child: Text(
                    confirmed.containsAll(selected!.edges)
                        ? 'Confirmed'
                        : 'I walked this',
                  ),
                ),
              ],
            ),
          const Text(
            'Purple is a suggestion. Confirm only the route you walked.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
  );
}
