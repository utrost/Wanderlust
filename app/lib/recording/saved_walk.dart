import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';

import 'activity_type.dart';

class SavedWalk {
  const SavedWalk(
    this.id,
    this.startedAt,
    this.endedAt,
    this.status,
    this.points, {
    this.uid = '',
    this.activity = WalkActivity.walk,
    this.segmentStarts = const [],
    this.untimed = const [],
    this.favourite = false,
    this.confirmedSections = const [],
    this.storedPointCount,
    this.fingerprint,
  });
  final WalkActivity activity;
  final int? storedPointCount;
  final String? fingerprint;
  int get pointCount => storedPointCount ?? points.length;
  bool get isSummary => storedPointCount != null;
  final bool favourite;
  final List<int> confirmedSections;
  final int id;
  final String uid;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final List<Position> points;
  // Empty means one segment; missing times use an internal epoch placeholder.
  // Neither placeholder times nor connections across segments are exported.
  final List<int> segmentStarts;
  final List<int> untimed;

  String get traceKey {
    final missing = untimed.toSet();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              segmentStarts.where((i) => i > 0).toList(),
              for (var i = 0; i < points.length; i++)
                [
                  points[i].latitude == 0 ? 0.0 : points[i].latitude,
                  points[i].longitude == 0 ? 0.0 : points[i].longitude,
                  missing.contains(i)
                      ? null
                      : points[i].timestamp.toUtc().toIso8601String(),
                ],
              if (points.isEmpty) startedAt.toUtc().toIso8601String(),
            ]),
          ),
        )
        .toString();
  }

  SavedWalk withActivity(WalkActivity value) => SavedWalk(
    id,
    startedAt,
    endedAt,
    status,
    points,
    uid: uid,
    activity: value,
    segmentStarts: segmentStarts,
    untimed: untimed,
    favourite: favourite,
    confirmedSections: confirmedSections,
    storedPointCount: storedPointCount,
  );

  SavedWalk withFavourite(bool value) => SavedWalk(
    id,
    startedAt,
    endedAt,
    status,
    points,
    uid: uid,
    activity: activity,
    segmentStarts: segmentStarts,
    untimed: untimed,
    favourite: value,
    confirmedSections: confirmedSections,
    storedPointCount: storedPointCount,
    fingerprint: fingerprint,
  );

  Map<String, Object?> toBackup({bool includeFavourite = true}) {
    if (isSummary) throw StateError('Load the walk trace before backing up.');
    return {
      if (includeFavourite) 'favourite': favourite,
      'uid': uid,
      'activity': activity.name,
      'confirmedSections': confirmedSections,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt?.toUtc().toIso8601String(),
      'status': status,
      'segmentStarts': segmentStarts,
      'untimed': untimed,
      'points': points
          .map(
            (p) => {
              ...p.toJson(),
              'timestampUtc': p.timestamp.toUtc().toIso8601String(),
            },
          )
          .toList(),
    };
  }
}

// Position.toJson stores milliseconds; the journal and backups retain the
// original timestamp separately so sub-millisecond GPX fixes round-trip.
Position positionAt(Position p, DateTime timestamp) => Position(
  latitude: p.latitude,
  longitude: p.longitude,
  timestamp: timestamp,
  accuracy: p.accuracy,
  altitude: p.altitude,
  altitudeAccuracy: p.altitudeAccuracy,
  heading: p.heading,
  headingAccuracy: p.headingAccuracy,
  speed: p.speed,
  speedAccuracy: p.speedAccuracy,
  floor: p.floor,
  isMocked: p.isMocked,
  hasAccuracy: p.hasAccuracy,
  hasAltitude: p.hasAltitude,
  hasAltitudeAccuracy: p.hasAltitudeAccuracy,
  hasHeading: p.hasHeading,
  hasHeadingAccuracy: p.hasHeadingAccuracy,
  hasSpeed: p.hasSpeed,
  hasSpeedAccuracy: p.hasSpeedAccuracy,
);
