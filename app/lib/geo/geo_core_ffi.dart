import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Dart binding to the Rust geo-core over its C ABI (ADR-0003, see
/// geo-ffi/include/wanderlust_geo.h). Load a street network once, then match
/// walks against it. This is the seam through which "import a GPX → watch real
/// streets light up" runs.
///
/// Scaffold: the native library (`libwanderlust_geo.so`) is produced by
/// cross-compiling geo-ffi with cargo-ndk into the Android `jniLibs`. Until that
/// build step is wired into the Gradle setup, this module is not yet imported by
/// the UI — the map screen renders bundled sample data.
library;

// ── native signatures ───────────────────────────────────────────────────────
typedef _FromGeoJsonNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _FromGeoJson = Pointer<Void> Function(Pointer<Utf8>);

typedef _MatchGpxNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _MatchGpx = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);

typedef _FreeMatcherNative = Void Function(Pointer<Void>);
typedef _FreeMatcher = void Function(Pointer<Void>);

typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeString = void Function(Pointer<Utf8>);

/// Result of matching one walk.
class MatchResult {
  const MatchResult({
    required this.walked,
    required this.gapsFilled,
    required this.gapsRejected,
  });

  /// Segment ids the walker plausibly traversed.
  final List<int> walked;

  /// Gaps the guardrail bridged with a shortest path.
  final int gapsFilled;

  /// Gaps the guardrail refused to fill (would have been phantom streets).
  final int gapsRejected;

  factory MatchResult.fromJson(Map<String, dynamic> j) => MatchResult(
        walked: (j['walked'] as List).cast<int>(),
        gapsFilled: j['gaps_filled'] as int,
        gapsRejected: j['gaps_rejected'] as int,
      );
}

/// Loads the native library and exposes the geo-core entry points.
class WanderlustGeo {
  WanderlustGeo._(DynamicLibrary lib)
      : _fromGeoJson =
            lib.lookupFunction<_FromGeoJsonNative, _FromGeoJson>('wanderlust_matcher_from_geojson'),
        _matchGpx = lib.lookupFunction<_MatchGpxNative, _MatchGpx>('wanderlust_match_gpx'),
        _freeMatcher =
            lib.lookupFunction<_FreeMatcherNative, _FreeMatcher>('wanderlust_matcher_free'),
        _freeString =
            lib.lookupFunction<_FreeStringNative, _FreeString>('wanderlust_string_free');

  final _FromGeoJson _fromGeoJson;
  final _MatchGpx _matchGpx;
  final _FreeMatcher _freeMatcher;
  final _FreeString _freeString;

  factory WanderlustGeo.open() => WanderlustGeo._(_openLibrary());

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libwanderlust_geo.so');
    }
    if (Platform.isMacOS) return DynamicLibrary.open('libwanderlust_geo.dylib');
    if (Platform.isIOS) return DynamicLibrary.process(); // statically linked
    throw UnsupportedError('Unsupported platform for geo-core');
  }

  /// Load a GeoJSON street network for one area. Throws on invalid input.
  Matcher loadNetwork(String geojson) {
    final ptr = geojson.toNativeUtf8();
    try {
      final handle = _fromGeoJson(ptr);
      if (handle == nullptr) {
        throw const FormatException('geo-core rejected the street network');
      }
      return Matcher._(this, handle);
    } finally {
      malloc.free(ptr);
    }
  }
}

/// A loaded street network. Call [dispose] when done.
class Matcher {
  Matcher._(this._geo, this._handle);

  final WanderlustGeo _geo;
  Pointer<Void> _handle;

  /// Match a GPX track, returning the streets it lit.
  MatchResult matchGpx(String gpx) {
    if (_handle == nullptr) throw StateError('Matcher already disposed');
    final gpxPtr = gpx.toNativeUtf8();
    Pointer<Utf8> out = nullptr;
    try {
      out = _geo._matchGpx(_handle, gpxPtr);
      if (out == nullptr) throw const FormatException('match failed');
      final json = out.toDartString();
      return MatchResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } finally {
      malloc.free(gpxPtr);
      if (out != nullptr) _geo._freeString(out);
    }
  }

  void dispose() {
    if (_handle != nullptr) {
      _geo._freeMatcher(_handle);
      _handle = nullptr;
    }
  }
}
