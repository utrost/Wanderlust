import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlust/recording/walk_distance.dart';

Position point(double meters, int seconds, {double accuracy = 5}) => Position(
  latitude: meters / 111320,
  longitude: 0,
  timestamp: DateTime.utc(2026).add(Duration(seconds: seconds)),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test('counts walking, ignores a spike and its return, then resumes', () {
    final distance = WalkDistance();
    for (final p in [
      point(0, 0),
      point(10, 5),
      point(2000, 6),
      point(10, 7),
      point(20, 12),
    ]) {
      distance.add(p);
    }
    expect(distance.meters, closeTo(20, 0.1));
  });
  test('poor accuracy and outages break distance continuity', () {
    final distance = WalkDistance();
    for (final p in [
      point(0, 0),
      point(20, 10, accuracy: 100),
      point(30, 15),
      point(40, 20),
      point(200, 80),
      point(210, 85),
    ]) {
      distance.add(p);
    }
    expect(distance.meters, closeTo(20, 0.1));
  });
  test('duplicate and backwards timestamps cannot move the anchor', () {
    final distance = WalkDistance();
    for (final p in [
      point(0, 0),
      point(100, 0),
      point(100, -1),
      point(10, 5),
    ]) {
      distance.add(p);
    }
    expect(distance.meters, closeTo(10, 0.1));
  });
  test('stationary sub-metre jitter does not accumulate', () {
    final distance = WalkDistance()..add(point(0, 0));
    for (var i = 1; i < 100; i++) {
      distance.add(point(i.isEven ? 0 : 0.5, i));
    }
    expect(distance.meters, 0);
  });
}
