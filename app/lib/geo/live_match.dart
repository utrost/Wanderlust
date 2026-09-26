import 'package:flutter/services.dart' show rootBundle;

import 'geo_core_ffi.dart';

enum GeoStage { assets, library, network, matching }

class GeoDiagnostic {
  const GeoDiagnostic.success(this.result) : stage = null, detail = null;
  const GeoDiagnostic.failure(this.stage, this.detail) : result = null;
  final MatchResult? result;
  final GeoStage? stage;
  final String? detail;

  String get label {
    if (result case final r?) {
      return 'geo-core · matched ${r.walked.length} streets · ${r.gapsRejected} gaps rejected';
    }
    return switch (stage) {
      GeoStage.assets => 'geo-core · sample assets unavailable',
      GeoStage.library => 'geo-core · native library or ABI unavailable',
      GeoStage.network => 'geo-core · street network rejected',
      GeoStage.matching => 'geo-core · matching failed',
      null => 'geo-core · unavailable',
    };
  }
}

/// Stage-specific diagnostics without swallowing the underlying error. Details
/// are exposed on demand in the tester UI and are never transmitted.
Future<GeoDiagnostic> runSampleMatch() async {
  return diagnoseSample(
    loadAsset: rootBundle.loadString,
    open: WanderlustGeo.open,
    loadNetwork: (geo, json) => (geo as WanderlustGeo).loadNetwork(json),
    match: (matcher, gpx) => (matcher as Matcher).matchGpx(gpx),
    dispose: (matcher) => (matcher as Matcher).dispose(),
  );
}

Future<GeoDiagnostic> diagnoseSample({
  required Future<String> Function(String) loadAsset,
  required Object Function() open,
  required Object Function(Object, String) loadNetwork,
  required MatchResult Function(Object, String) match,
  required void Function(Object) dispose,
}) async {
  var stage = GeoStage.assets;
  try {
    final geojson = await loadAsset('assets/geo/kreuzberg-sample.geojson');
    final gpx = await loadAsset('assets/geo/walk-goerli.gpx');
    stage = GeoStage.library;
    final geo = open();
    stage = GeoStage.network;
    final matcher = loadNetwork(geo, geojson);
    try {
      stage = GeoStage.matching;
      return GeoDiagnostic.success(match(matcher, gpx));
    } finally {
      dispose(matcher);
    }
  } catch (error) {
    return GeoDiagnostic.failure(stage, error.toString());
  }
}
