import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xml/xml.dart';

import '../recording/activity_type.dart';
import '../recording/gps_diagnostics.dart';
import '../recording/saved_walk.dart';

/// Bounded, versioned interchange. All validation completes before any DB write.
class WalkCodec {
  static const maxBytes = 32 * 1024 * 1024;
  static const maxPoints = 100000;
  static const maxWalks = 10000;
  static const _gpxNs = 'http://www.topografix.com/GPX/1/1';
  static const _wlNs = 'https://wanderlust.local/gpx/1';

  static List<int> _confirmedSections(Object? value) {
    if (value == null) return const [];
    if (value is! List ||
        value.length > 10000 ||
        value.any((v) => v is! int || v <= 0 || v > 9007199254740991)) {
      throw const FormatException('Invalid confirmed sections');
    }
    return value.cast<int>().toSet().toList()..sort();
  }

  static String decodeBytes(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('File exceeds the 32 MiB limit.');
    }
    return utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
  }

  static void _bounded(String text) {
    if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
      throw const FormatException('File exceeds the 32 MiB limit.');
    }
  }

  static double _number(
    String value,
    String field, {
    double? min,
    double? max,
  }) {
    final n = double.tryParse(value);
    if (n == null ||
        !n.isFinite ||
        (min != null && n < min) ||
        (max != null && n > max)) {
      throw FormatException('Invalid $field.');
    }
    return n;
  }

  static DateTime _time(String text) {
    // Require an explicit timezone and reject DateTime's overflow normalization.
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(text);
    if (m == null) {
      throw const FormatException('Invalid timestamp or missing timezone.');
    }
    final year = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    final date = DateTime.utc(year, month, day);
    final zone = m[7]!;
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        int.parse(m[4]!) > 23 ||
        int.parse(m[5]!) > 59 ||
        int.parse(m[6]!) > 59 ||
        (zone != 'Z' &&
            (int.parse(zone.substring(1, 3)) > 23 ||
                int.parse(zone.substring(4)) > 59))) {
      throw const FormatException('Invalid timestamp.');
    }
    return DateTime.parse(text).toUtc();
  }

  static SavedWalk importGpx(String text, {DateTime? importedAt}) {
    _bounded(text);
    final doc = XmlDocument.parse(text);
    if (doc.children.any((e) => e is XmlDoctype)) {
      throw const FormatException(
        'GPX document declarations are not supported.',
      );
    }
    final root = doc.rootElement;
    final ns = root.namespaceUri;
    if (root.localName != 'gpx' ||
        ![null, '', _gpxNs, 'http://www.topografix.com/GPX/1/0'].contains(ns)) {
      throw const FormatException('Choose a GPX track file.');
    }
    Iterable<XmlElement> children(XmlElement e, String name) => e.childElements
        .where((c) => c.localName == name && c.namespaceUri == ns);
    String? value(XmlElement e, String name) {
      final found = children(e, name).toList();
      if (found.length > 1) {
        throw FormatException('Repeated $name in GPX point.');
      }
      return found.isEmpty ? null : found.single.innerText.trim();
    }

    final points = <Position>[];
    final starts = <int>[];
    final untimed = <int>[];
    for (final track in children(root, 'trk')) {
      for (final segment in children(track, 'trkseg')) {
        final fixes = children(segment, 'trkpt').toList();
        if (fixes.isEmpty) continue;
        starts.add(points.length);
        for (final p in fixes) {
          if (points.length >= maxPoints) {
            throw const FormatException('GPX exceeds 100,000 points.');
          }
          final lat = _number(
            p.getAttribute('lat') ?? '',
            'latitude',
            min: -90,
            max: 90,
          );
          final lon = _number(
            p.getAttribute('lon') ?? '',
            'longitude',
            min: -180,
            max: 180,
          );
          final time = value(p, 'time');
          if (time == null) untimed.add(points.length);
          final elevation = value(p, 'ele');
          final accuracies = children(p, 'extensions')
              .expand((e) => e.childElements)
              .where(
                (e) => e.localName == 'accuracy' && e.namespaceUri == _wlNs,
              )
              .toList();
          if (accuracies.length > 1) {
            throw const FormatException('Repeated accuracy.');
          }
          points.add(
            Position(
              latitude: lat,
              longitude: lon,
              timestamp: time == null
                  ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
                  : _time(time),
              accuracy: accuracies.isEmpty
                  ? 0
                  : _number(
                      accuracies.single.innerText.trim(),
                      'accuracy',
                      min: 0,
                    ),
              altitude: elevation == null ? 0 : _number(elevation, 'elevation'),
              hasAccuracy: accuracies.isNotEmpty,
              hasAltitude: elevation != null,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            ),
          );
        }
      }
    }
    if (points.isEmpty) {
      throw const FormatException(
        'No track points found. Routes and waypoints are not walks.',
      );
    }
    final missing = untimed.toSet();
    final times = [
      for (var i = 0; i < points.length; i++)
        if (!missing.contains(i)) points[i].timestamp,
    ]..sort();
    final start = times.isEmpty
        ? (importedAt ?? DateTime.now()).toUtc()
        : times.first;
    final end = times.isEmpty ? start : times.last;
    final activities = children(root, 'extensions')
        .expand((e) => e.childElements)
        .where((e) => e.localName == 'activity' && e.namespaceUri == _wlNs)
        .toList();
    final activity = WalkActivity.parse(
      activities.firstOrNull?.innerText.trim(),
    );
    final walk = SavedWalk(
      0,
      start,
      end,
      'completed',
      points,
      activity: activity,
      segmentStarts: starts.where((i) => i > 0).toList(),
      untimed: untimed,
    );
    return SavedWalk(
      0,
      start,
      end,
      'completed',
      points,
      uid: walk.traceKey.substring(0, 32),
      activity: activity,
      segmentStarts: walk.segmentStarts,
      untimed: untimed,
    );
  }

  static String exportGpx(SavedWalk walk) {
    if (walk.isSummary) {
      throw StateError('Load the walk trace before exporting.');
    }
    final breaks = walk.segmentStarts.toSet();
    final missing = walk.untimed.toSet();
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n')
      ..writeln(
        '<gpx version="1.1" creator="wanderlust" xmlns="$_gpxNs" xmlns:wl="$_wlNs"><trk><trkseg>',
      );
    for (var i = 0; i < walk.points.length; i++) {
      if (i > 0 && breaks.contains(i)) b.writeln('</trkseg><trkseg>');
      final p = walk.points[i];
      b.write(
        '<trkpt lat="${p.latitude}" lon="${p.longitude}"><ele>${p.altitude}</ele>',
      );
      if (!missing.contains(i)) {
        b.write('<time>${p.timestamp.toUtc().toIso8601String()}</time>');
      }
      if (p.hasAccuracy || p.accuracy > 0) {
        b.write(
          '<extensions><wl:accuracy>${p.accuracy}</wl:accuracy></extensions>',
        );
      }
      b.writeln('</trkpt>');
    }
    return (b..writeln(
          '</trkseg></trk><extensions><wl:activity>${walk.activity.name}</wl:activity><wl:matching>auto</wl:matching></extensions></gpx>',
        ))
        .toString();
  }

  static String exportBackup(List<SavedWalk> walks) {
    if (walks.any((w) => w.status == 'recording')) {
      throw StateError('Finish recording before creating a backup.');
    }
    final payload = jsonEncode({
      'walks': walks.map((w) => w.toBackup()).toList(),
    });
    final text = jsonEncode({
      'format': 'wanderlust-backup',
      'version': 1,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
    // Never emit a backup that this version cannot restore.
    importBackup(text);
    return text;
  }

  static List<SavedWalk> importBackup(String text) {
    _bounded(text);
    try {
      final envelope = jsonDecode(text) as Map<String, dynamic>;
      if (envelope['format'] != 'wanderlust-backup' ||
          envelope['version'] != 1) {
        throw const FormatException('Unsupported backup format or version.');
      }
      final payload = envelope['payload'] as String;
      if (sha256.convert(utf8.encode(payload)).toString() !=
          envelope['sha256']) {
        throw const FormatException('Backup checksum does not match.');
      }
      final rows =
          (jsonDecode(payload) as Map<String, dynamic>)['walks'] as List;
      if (rows.length > maxWalks) {
        throw const FormatException('Backup exceeds 10,000 walks.');
      }
      final walks = <SavedWalk>[];
      final uids = <String>{};
      var total = 0;
      for (final row in rows) {
        final r = row as Map<String, dynamic>;
        final uid = r['uid'] as String;
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(uid) || !uids.add(uid)) {
          throw const FormatException('Invalid or repeated walk identity.');
        }
        if (r.containsKey('favourite') && r['favourite'] is! bool) {
          throw const FormatException('Invalid favourite flag.');
        }
        final status = r['status'];
        if (status != 'completed' && status != 'interrupted') {
          throw const FormatException('Invalid walk status.');
        }
        final start = _time(r['startedAt'] as String);
        final end = _time(r['endedAt'] as String);
        final raw = r['points'] as List;
        total += raw.length;
        if (total > maxPoints) {
          throw const FormatException('Backup exceeds 100,000 points.');
        }
        final points = <Position>[];
        for (final value in raw) {
          final p = value as Map<String, dynamic>;
          for (final field in [
            'latitude',
            'longitude',
            'accuracy',
            'altitude',
            'altitude_accuracy',
            'heading',
            'heading_accuracy',
            'speed',
            'speed_accuracy',
          ]) {
            if (p[field] is! num || !(p[field] as num).isFinite) {
              throw FormatException('Invalid position $field.');
            }
          }
          _number(p['latitude'].toString(), 'latitude', min: -90, max: 90);
          _number(p['longitude'].toString(), 'longitude', min: -180, max: 180);
          for (final field in [
            'accuracy',
            'altitude_accuracy',
            'heading_accuracy',
            'speed_accuracy',
          ]) {
            _number(p[field].toString(), field, min: 0);
          }
          if (p['timestamp'] is! int ||
              (p['timestamp'] as int).abs() > 253402300799999 ||
              p['is_mocked'] is! bool) {
            throw const FormatException(
              'Invalid position timestamp or mock flag.',
            );
          }
          final time = _time(p['timestampUtc'] as String);
          if (time.millisecondsSinceEpoch != p['timestamp']) {
            throw const FormatException('Inconsistent position timestamp.');
          }
          if (p['floor'] != null && p['floor'] is! int) {
            throw const FormatException('Invalid floor.');
          }
          for (final key in [
            'has_accuracy',
            'has_altitude',
            'has_altitude_accuracy',
            'has_heading',
            'has_heading_accuracy',
            'has_speed',
            'has_speed_accuracy',
          ]) {
            if (p[key] is! bool) {
              throw const FormatException('Invalid measurement flag.');
            }
          }
          points.add(positionAt(Position.fromMap(p), time));
        }
        List<int> indices(String key) {
          final values = (r[key] as List).cast<int>();
          var previous = -1;
          for (final v in values) {
            if (v <= previous ||
                v < 0 ||
                v >= points.length ||
                (key == 'segmentStarts' && v == 0)) {
              throw const FormatException(
                'Invalid track segment or timestamp metadata.',
              );
            }
            previous = v;
          }
          return values;
        }

        final starts = indices('segmentStarts');
        final untimed = indices('untimed');
        for (final i in untimed) {
          if (points[i].timestamp.millisecondsSinceEpoch != 0) {
            throw const FormatException(
              'Invalid missing timestamp placeholder.',
            );
          }
        }
        walks.add(
          SavedWalk(
            0,
            start,
            end,
            status as String,
            points,
            uid: uid,
            favourite: r['favourite'] == true,
            activity: WalkActivity.parse(r['activity']),
            gpsDiagnostics: readGpsDiagnostics(r['gpsDiagnostics']),
            confirmedSections: _confirmedSections(r['confirmedSections']),
            segmentStarts: starts,
            untimed: untimed,
          ),
        );
      }
      return walks;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed Wanderlust backup.');
    }
  }
}
