import 'geo_core_ffi.dart';

class MatchingFailure implements Exception {
  const MatchingFailure(this.stage, this.detail);
  final String stage;
  final String detail;
  @override
  String toString() => '$stage: $detail';
}

/// Native resources belong to the isolate that creates this session. Live
/// coverage and review use the same matching policy and bounded graph cache.
class MatchingSession {
  final _matchers = <String, Matcher>{};
  bool _closed = false;

  List<MatchResult> match(
    String source,
    List<String> walks, {
    required bool fillSmallGaps,
  }) {
    if (_closed) throw StateError('Matching session is closed');
    var matcher = _matchers.remove(source);
    if (matcher == null) {
      if (_matchers.length == 2) {
        _matchers.remove(_matchers.keys.first)!.dispose();
      }
      late final WanderlustGeo geo;
      try {
        geo = WanderlustGeo.open();
      } catch (error) {
        throw MatchingFailure('Native library / ABI unavailable', '$error');
      }
      try {
        matcher = geo.loadNetwork(source);
      } catch (error) {
        throw MatchingFailure('Street network rejected', '$error');
      }
    }
    _matchers[source] = matcher;
    try {
      return [
        for (final walk in walks)
          matcher.matchGpx(walk, fillSmallGaps: fillSmallGaps),
      ];
    } catch (error) {
      throw MatchingFailure('Walk matching failed', '$error');
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final matcher in _matchers.values) {
      matcher.dispose();
    }
    _matchers.clear();
  }
}
