import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'osm_network.dart';

class NearbyArea {
  NearbyArea(this.bbox);
  final List<double> bbox; // west, south, east, north
  factory NearbyArea.around(
    double latitude,
    double longitude, {
    int sizeKm = 4,
  }) {
    if (sizeKm < 1 || sizeKm > 25) {
      throw const FormatException(
        'Choose a map size between 1 and 25 km per side.',
      );
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 80 ||
        longitude.abs() > 180) {
      throw const FormatException(
        'Nearby downloads are not available at the poles or date line yet.',
      );
    }
    final latRadius = sizeKm * 500 / 111320;
    final lonRadius = latRadius / math.cos(latitude * math.pi / 180);
    // Coarse bounds, not a precise GPS fix, go to the map service.
    double floor(double n) => (n * 10000).floor() / 10000;
    double ceil(double n) => (n * 10000).ceil() / 10000;
    final bbox = <double>[
      floor(longitude - lonRadius),
      floor(latitude - latRadius),
      ceil(longitude + lonRadius),
      ceil(latitude + latRadius),
    ];
    if (bbox[0] < -180 || bbox[2] > 180 || bbox[1] < -90 || bbox[3] > 90) {
      throw const FormatException(
        'This map would cross the date line or a pole. Choose a smaller size.',
      );
    }
    return NearbyArea(bbox);
  }
  String get id => 'nearby-${bbox.join(',')}';
  String get name {
    final latitude = (bbox[1] + bbox[3]) / 2;
    final width =
        (OsmNetwork.metres([bbox[0], latitude], [bbox[2], latitude]) / 1000)
            .round();
    final height = ((bbox[3] - bbox[1]) * 111320 / 1000).round();
    return 'Near ${latitude.toStringAsFixed(3)}, ${((bbox[0] + bbox[2]) / 2).toStringAsFixed(3)} · $width × $height km';
  }

  String get query {
    final bounds = '${bbox[1]},${bbox[0]},${bbox[3]},${bbox[2]}';
    final scenery = [
      for (final filter in [
        r'["leisure"~"^(park|garden|nature_reserve)$"]',
        r'["natural"~"^(water|wood)$"]',
        r'["landuse"~"^(forest|grass|recreation_ground|reservoir)$"]',
      ])
        'way$filter($bounds);relation$filter($bounds);',
    ].join();
    return '[out:xml][timeout:45][maxsize:33554432];('
        'way["highway"]($bounds);'
        'way["waterway"~"^(river|stream|canal|drain|riverbank)\$"]($bounds);'
        '$scenery);(._;>>;);out body;';
  }
}

String _normalize((String, List<double>, String, String) input) =>
    OsmNetwork.normalize(input.$1, input.$2, areaId: input.$3, name: input.$4);

typedef FetchMap = Future<String> Function(NearbyArea area);

class MapDownload {
  MapDownload({Uri? endpoint})
    : endpoint =
          endpoint ?? Uri.parse('https://overpass-api.de/api/interpreter');
  final Uri endpoint;
  HttpClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<String> fetch(NearbyArea area) async {
    if (_client != null) throw StateError('A map download is already running.');
    _cancelled = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _client = client;
    try {
      return await _fetch(client, area).timeout(const Duration(seconds: 75));
    } on TimeoutException {
      throw const FormatException(
        'Map download timed out. Your saved maps are unchanged. Choose a smaller size or retry later.',
      );
    } on SocketException {
      if (_cancelled) throw const FormatException('Map download cancelled.');
      throw const FormatException(
        'Map download could not connect. Check your internet connection.',
      );
    } on IOException {
      throw FormatException(
        _cancelled
            ? 'Map download cancelled.'
            : 'Map download was interrupted. Check your connection and retry.',
      );
    } finally {
      client.close(force: true);
      _client = null;
    }
  }

  Future<String> _fetch(HttpClient client, NearbyArea area) async {
    final request = await client.postUrl(endpoint);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Wanderlust/0.0.1 (https://github.com/utrost/Wanderlust)',
    );
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write('data=${Uri.encodeQueryComponent(area.query)}');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw FormatException(
        response.statusCode == 429 || response.statusCode >= 500
            ? 'Map service is busy. Please retry later.'
            : 'Map service rejected the download (${response.statusCode}).',
      );
    }
    const maxBytes = 16 * 1024 * 1024;
    if (response.contentLength > maxBytes) {
      throw const FormatException(
        'This area is too detailed to download. Choose a smaller map size.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (_cancelled) throw const FormatException('Map download cancelled.');
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException(
          'This area is too detailed to download. Choose a smaller map size.',
        );
      }
      bytes.add(chunk);
    }
    final xml = utf8.decode(bytes.takeBytes());
    final network = await compute(_normalize, (
      xml,
      area.bbox,
      area.id,
      area.name,
    ));
    if (_cancelled) throw const FormatException('Map download cancelled.');
    return network;
  }
}
