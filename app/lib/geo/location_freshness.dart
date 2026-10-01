import 'package:geolocator/geolocator.dart';

Duration fixAge(Position point, DateTime now) {
  final age = now.toUtc().difference(point.timestamp.toUtc());
  return age.isNegative ? Duration.zero : age;
}

bool isOldFix(Position point, DateTime now) =>
    fixAge(point, now).inSeconds > 30;
