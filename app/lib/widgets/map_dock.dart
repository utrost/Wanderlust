import 'package:flutter/material.dart';

import 'map_surface.dart';

class MapDock extends StatelessWidget {
  const MapDock({
    super.key,
    required this.sectionCount,
    required this.historyCount,
    required this.memoryReady,
    required this.hasDraft,
    required this.historyEnabled,
    required this.onCoverage,
    required this.onAddMemory,
    required this.onMemories,
    required this.onHistory,
    required this.errors,
    this.coverageStatus,
  });
  final int sectionCount, historyCount;
  final bool memoryReady, hasDraft, historyEnabled;
  final VoidCallback onCoverage, onAddMemory, onMemories, onHistory;
  final List<String> errors;
  final Widget? coverageStatus;
  @override
  Widget build(BuildContext context) => MapSurface(
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: onCoverage,
                icon: const Icon(Icons.route_outlined),
                label: Tooltip(
                  message: 'Heatmap legend · Street sections explored',
                  child: Text('$sectionCount'),
                ),
              ),
              IconButton(
                tooltip: 'Add memory',
                onPressed: memoryReady ? onAddMemory : null,
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
              IconButton(
                tooltip: 'Memories',
                onPressed: memoryReady ? onMemories : null,
                icon: Badge(
                  isLabelVisible: hasDraft,
                  child: const Icon(Icons.collections_bookmark_outlined),
                ),
              ),
              IconButton(
                tooltip: 'Walk history ($historyCount)',
                onPressed: historyEnabled ? onHistory : null,
                icon: const Icon(Icons.history),
              ),
            ],
          ),
          for (final error in errors) Text(error, textAlign: TextAlign.center),
          if (coverageStatus != null) coverageStatus!,
        ],
      ),
    ),
  );
}
