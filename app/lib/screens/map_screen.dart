import 'dart:async';

import 'walk_library_screen.dart';

import 'package:flutter/material.dart';

import '../coverage/coverage_controller.dart';
import '../recording/walk_store.dart';
import '../geo/live_match.dart';
import '../recording/walk_recorder.dart';
import '../theme/wanderlust_theme.dart';
import '../widgets/area_map.dart';

/// Real offline Bremen streets painted from persisted per-walk coverage.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Proves the native geo-core loads and matches on the device.
  late final Future<GeoDiagnostic> _liveMatch = runSampleMatch();

  final SqliteWalkStore _store = SqliteWalkStore();
  late final WalkRecorder _recorder = WalkRecorder(store: _store);
  late final CoverageController _coverage = CoverageController(store: _store);

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_walkChanged);
    _coverage.initialize();
    _recorder.initialize();
  }

  @override
  void dispose() {
    _recorder.removeListener(_walkChanged);
    // Finish pending coverage work before the recorder closes the shared DB.
    _coverage.dispose();
    unawaited(_coverage.settled.whenComplete(_recorder.dispose));
    super.dispose();
  }

  void _walkChanged() {
    if (!_recorder.isRecording &&
        !_recorder.isBusy &&
        !_recorder.needsSaveRetry) {
      unawaited(_coverage.synchronize(_recorder.savedWalks));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WanderlustColors.paperBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: _coverage,
            builder: (context, _) => _coverage.network == null
                ? const Center(child: Text('Loading Bremen streets…'))
                : AreaMap(
                    network: _coverage.network!,
                    counts: _coverage.counts,
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
                        _coverageStatus(),
                        if (_recorder.lastError != null)
                          Text(
                            _errorMessage(_recorder.lastError!),
                            textAlign: TextAlign.center,
                          ),
                        TextButton(
                          onPressed:
                              _recorder.isRecording ||
                                  _recorder.isBusy ||
                                  _recorder.needsSaveRetry
                              ? null
                              : _showSavedWalks,
                          child: Text(
                            'Saved walks (${_recorder.savedWalks.length})',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: _recorder.isBusy
                              ? const CircularProgressIndicator()
                              : _recorder.isRecording
                              ? _recordingPanel()
                              : GestureDetector(
                                  onTap: _recorder.needsSaveRetry
                                      ? _recorder.retrySave
                                      : _onStartWalk,
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
          Text(
            'Bremen center',
            style: WanderlustTheme.serif.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WanderlustColors.ink,
            ),
          ),
          Text(
            'stays on your phone',
            style: TextStyle(fontSize: 10.5, color: WanderlustColors.inkMuted),
          ),
        ],
      ),
    );
  }

  /// Small on-device readout of the native geo-core matching the bundled
  /// sample walk over FFI. Confirms the Rust `.so` loaded and ran.
  Widget _geoStatusChip() {
    return FutureBuilder<GeoDiagnostic>(
      future: _liveMatch,
      builder: (context, snap) {
        final String label;
        if (snap.connectionState != ConnectionState.done) {
          label = 'geo-core · matching…';
        } else if (snap.data case final r?) {
          label = r.label;
        } else {
          label = 'geo-core · diagnostics unavailable';
        }
        return Tooltip(
          message: snap.data?.detail ?? 'Bundled sample diagnostic',
          triggerMode: TooltipTriggerMode.tap,
          child: Container(
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
          ),
        );
      },
    );
  }

  Widget _coverageStatus() => ListenableBuilder(
    listenable: _coverage,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_coverage.busy)
          const Text('Updating your streets…')
        else
          Text('${_coverage.counts.length} street segments walked'),
        if (_coverage.error case final error?)
          TextButton(
            onPressed: () => _coverage.synchronize(_recorder.savedWalks),
            child: Tooltip(
              message: error.detail,
              child: Text('${error.stage} · Retry'),
            ),
          ),
        TextButton(
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: 'Wanderlust',
            children: [
              const SelectableText(
                'Map data © OpenStreetMap contributors, ODbL 1.0\nhttps://www.openstreetmap.org/copyright\nOffline street view of Bremen center. Pinch to zoom. Streets update after saving a walk.',
              ),
            ],
          ),
          child: const Text(
            '© OpenStreetMap contributors · ODbL',
            style: TextStyle(fontSize: 10),
          ),
        ),
      ],
    ),
  );

  Future<void> _onStartWalk() async {
    final ok = await _recorder.start();
    if (ok || !mounted) return;
    if (_recorder.lastError == null) return;
    final message = _errorMessage(_recorder.lastError!);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(RecorderError error) => switch (error) {
    RecorderError.locationServiceDisabled =>
      'Turn on location to record a walk.',
    RecorderError.permissionDenied =>
      'Allow location access in Android settings to record a walk.',
    RecorderError.locationFailed =>
      'Location stopped working. Your saved points are retained.',
    RecorderError.storageFailed =>
      'Could not save all walk data. Check available device storage before recording again.',
  };

  Future<void> _showSavedWalks() async {
    await _recorder.initialize();
    if (!mounted ||
        _recorder.isRecording ||
        _recorder.isBusy ||
        _recorder.needsSaveRetry) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalkLibraryScreen(
          store: _store,
          onChanged: () async {
            await _recorder.refreshSavedWalks();
            await _coverage.synchronize(_recorder.savedWalks);
          },
        ),
      ),
    );
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
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: WanderlustColors.accent,
              shape: BoxShape.circle,
            ),
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
            onTap: () => _recorder.stop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: WanderlustColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFBF8F2),
                ),
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
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_walk,
              size: 16,
              color: WanderlustColors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              _recorder.needsSaveRetry ? 'Retry saving walk' : 'Start walk',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WanderlustColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
