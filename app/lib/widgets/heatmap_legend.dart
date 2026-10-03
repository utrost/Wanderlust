import 'package:flutter/material.dart';
import '../theme/heat_ramp.dart';

/// Shared by Settings and the on-demand map sheet; no extra map overlay.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Your walking heatmap',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 20,
        runSpacing: 16,
        children: [
          for (final count in [1, 2, 5, 10, 100])
            Semantics(
              label: '$count ${count == 1 ? 'walk' : 'walks'}',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: HeatRamp.color(count, dark: false),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('$count ${count == 1 ? 'walk' : 'walks'}'),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Darker streets are more familiar. A section counts once per walk, even if you pass it several times. The current walk adds a live preview. Dashed grey-green trails show reliable GPS movement that could not be matched to a street; they do not increase street counts.',
      ),
    ],
  );
}
