import 'package:flutter/material.dart';

import '../theme/wanderlust_theme.dart';

class RecordingPanel extends StatelessWidget {
  const RecordingPanel({
    super.key,
    required this.elapsed,
    required this.distanceMeters,
    required this.pointCount,
    required this.showTime,
    required this.showSamples,
    required this.onStop,
    this.gpsStale = false,
  });
  final Duration elapsed;
  final double distanceMeters;
  final int pointCount;
  final bool showTime, showSamples;
  final bool gpsStale;
  final VoidCallback onStop;
  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final e = elapsed;
    final clock = '${_twoDigits(e.inMinutes)}:${_twoDigits(e.inSeconds % 60)}';
    final km = (distanceMeters / 1000).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gpsStale)
            const Tooltip(
              message: 'GPS updates paused · trying to reconnect',
              child: Icon(
                Icons.gps_off,
                size: 20,
                semanticLabel: 'GPS updates paused, trying to reconnect',
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: WanderlustColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              [
                if (showTime) clock,
                '$km km',
                if (showSamples) '$pointCount GPS samples',
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: WanderlustColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
