import 'package:flutter/services.dart' show rootBundle;

import 'geo_core_ffi.dart';

/// Runs the bundled sample walk through the real Rust geo-core over FFI. This is
/// the on-device proof that the native library loads and matches: import a GPX,
/// get the streets it lit. Returns `null` (rather than throwing) when the native
/// library isn't present — e.g. on a host/test run — so callers can show a calm
/// "unavailable" state instead of crashing.
Future<MatchResult?> runSampleMatch() async {
  try {
    final geojson = await rootBundle.loadString('assets/geo/kreuzberg-sample.geojson');
    final gpx = await rootBundle.loadString('assets/geo/walk-goerli.gpx');

    final geo = WanderlustGeo.open();
    final matcher = geo.loadNetwork(geojson);
    try {
      return matcher.matchGpx(gpx);
    } finally {
      matcher.dispose();
    }
  } catch (_) {
    return null;
  }
}
