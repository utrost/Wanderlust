import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../data/area_network.dart';
import 'area_store.dart';
import 'map_download.dart';
import 'map_extent.dart';
import 'map_cells.dart';

/// Serial, bounded map extension driven by a user-started walk's GPS stream.
/// Never deletes maps, changes the selected map, or requests location itself.
class AutomaticMaps extends ChangeNotifier {
  AutomaticMaps({
    required this.store,
    required this.networks,
    required this.onSaved,
    FetchMap? fetch,
    void Function()? cancel,
    DateTime Function()? clock,
  }) : _fetch = fetch,
       _cancel = cancel,
       _clock = clock ?? DateTime.now;
  final AreaStore store;
  final List<AreaNetwork> Function() networks;
  final Future<void> Function() onSaved;
  final FetchMap? _fetch;
  final void Function()? _cancel;
  final DateTime Function() _clock;
  final _download = MapDownload();
  bool _enabled = true, _disposed = false;
  int _epoch = 0;
  DateTime? _nextAttempt;
  Future<void> _pending = Future.value();
  Future<void> get settled => _pending;
  bool busy = false;
  String? message;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) cancel();
    _nextAttempt = null;
  }

  void cancel() {
    _epoch++;
    _download.cancel();
    _cancel?.call();
    message = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> consider(Position? fix) async {
    final now = _clock();
    if (_disposed ||
        !_enabled ||
        busy ||
        fix == null ||
        (_nextAttempt != null && now.isBefore(_nextAttempt!)) ||
        !fix.accuracy.isFinite ||
        fix.accuracy < 0 ||
        fix.accuracy > 25 ||
        now.difference(fix.timestamp).inSeconds > 30 ||
        fix.timestamp.isAfter(now.add(const Duration(seconds: 5))) ||
        !fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 80 ||
        fix.longitude.abs() > 180) {
      return Future.value();
    }
    final epochBeforeRead = _epoch;
    final saved = await store.listAreas();
    if (_disposed ||
        !_enabled ||
        busy ||
        epochBeforeRead != _epoch ||
        (_nextAttempt != null && _clock().isBefore(_nextAttempt!))) {
      return;
    }
    // During a legacy backfill, unknown footprints must not cause duplicates.
    if (store is SpatialAreaStore && saved.any((a) => a.bounds == null)) return;
    final maps = [
      for (final area in saved)
        if (area.bounds case final bounds?)
          AreaNetwork.parse(
            emptyMap(area.name, boundsList(bounds), area.version),
          ),
    ];
    if (maps.isEmpty) maps.addAll(networks());
    // The first map remains an explicit setup action.
    if (maps.isEmpty ||
        MapExtent(
              maps,
            ).distanceToBoundary(Offset(fix.longitude, fix.latitude)) >
            500) {
      return Future.value();
    }
    busy = true;
    message = 'Downloading a nearby map';
    notifyListeners();
    final epoch = _epoch;
    _pending = _run(fix, epoch);
    return _pending;
  }

  Future<void> _run(Position fix, int epoch) async {
    try {
      if (_disposed || epoch != _epoch) return;
      final source = await (_fetch ?? _download.fetch)(
        NearbyArea.around(fix.latitude, fix.longitude, sizeKm: 2),
      );
      if (_disposed || epoch != _epoch || !_enabled) return;
      final area = AreaNetwork.parse(source);
      if (!area.contains(Offset(fix.longitude, fix.latitude))) {
        throw const FormatException(
          'Downloaded map does not cover the requested location',
        );
      }
      await store.saveArea(source);
      if (_disposed || epoch != _epoch) return;
      await onSaved();
      message = null;
      _nextAttempt = _clock().add(const Duration(minutes: 1));
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        message =
            'Map download unavailable. Walking continues; retrying in five minutes.';
        _nextAttempt = _clock().add(const Duration(minutes: 5));
      }
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
