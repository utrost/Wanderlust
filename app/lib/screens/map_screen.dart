import 'package:flutter/material.dart';

import '../data/street_network.dart';
import '../theme/wanderlust_theme.dart';
import '../widgets/filling_map_painter.dart';

/// The home screen: the filling map, full-bleed, with the calm "stays on your
/// phone" chrome from the design. The fill-level switch is a scaffold-stage
/// stand-in for live walk data — it lets us see the map at each life stage
/// before background GPS and the geo-core are connected.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  FillLevel _level = FillLevel.month;

  static const _labels = {
    FillLevel.week: 'First week',
    FillLevel.month: 'A few months in',
    FillLevel.year: 'Two years in',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WanderlustColors.paperBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: FillingMapPainter(level: _level, dark: false),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _areaChip(),
                  const Spacer(),
                  _stagePicker(),
                  const SizedBox(height: 12),
                  Center(child: _startWalkPill()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _areaChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Kreuzberg',
              style: WanderlustTheme.serif.copyWith(
                  fontSize: 14, fontWeight: FontWeight.w500, color: WanderlustColors.ink)),
          Text('stays on your phone',
              style: TextStyle(fontSize: 10.5, color: WanderlustColors.inkMuted)),
        ],
      ),
    );
  }

  // Scaffold-only control; removed once live counts drive the map.
  Widget _stagePicker() {
    return SegmentedButton<FillLevel>(
      segments: [
        for (final l in FillLevel.values)
          ButtonSegment(value: l, label: Text(_labels[l]!)),
      ],
      selected: {_level},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _level = s.first),
    );
  }

  Widget _startWalkPill() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_walk, size: 16, color: WanderlustColors.accent),
            const SizedBox(width: 8),
            Text('Start walk',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: WanderlustColors.ink)),
          ],
        ),
      ),
    );
  }
}
