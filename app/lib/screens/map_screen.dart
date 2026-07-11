import 'package:flutter/material.dart';

import '../data/street_network.dart';
import '../geo/geo_core_ffi.dart';
import '../geo/live_match.dart';
import '../recording/walk_recorder.dart';
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

  // Proves the native geo-core loads and matches on the device.
  late final Future<MatchResult?> _liveMatch = runSampleMatch();

  final WalkRecorder _recorder = WalkRecorder();

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

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
                  const SizedBox(height: 10),
                  _geoStatusChip(),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: _recorder,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_recorder.isRecording) _stagePicker(),
                        const SizedBox(height: 12),
                        Center(
                          child: _recorder.isRecording
                              ? _recordingPanel()
                              : GestureDetector(
                                  onTap: _onStartWalk,
                                  child: _startWalkPill(),
                                ),
                        ),
                      ],
                    ),
                  ),
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

  /// Small on-device readout of the native geo-core matching the bundled
  /// sample walk over FFI. Confirms the Rust `.so` loaded and ran.
  Widget _geoStatusChip() {
    return FutureBuilder<MatchResult?>(
      future: _liveMatch,
      builder: (context, snap) {
        final String label;
        if (snap.connectionState != ConnectionState.done) {
          label = 'geo-core · matching…';
        } else if (snap.data case final r?) {
          label = 'geo-core · lit ${r.walked.length} streets · ${r.gapsRejected} phantom blocked';
        } else {
          label = 'geo-core · native library not loaded';
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: WanderlustColors.paperCard.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: WanderlustColors.inkMuted,
            ),
          ),
        );
      },
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

  Future<void> _onStartWalk() async {
    final ok = await _recorder.start();
    if (ok || !mounted) return;
    final message = _recorder.lastError == RecorderError.locationServiceDisabled
        ? 'Turn on location to record a walk.'
        : 'Location permission is needed to record a walk.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  Widget _recordingPanel() {
    final e = _recorder.elapsed;
    final clock = '${_twoDigits(e.inMinutes)}:${_twoDigits(e.inSeconds % 60)}';
    final km = (_recorder.distanceMeters / 1000).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: WanderlustColors.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            '$clock · $km km · ${_recorder.pointCount} pts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: WanderlustColors.ink,
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _recorder.stop,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: WanderlustColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFFBF8F2)),
              ),
            ),
          ),
        ],
      ),
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
