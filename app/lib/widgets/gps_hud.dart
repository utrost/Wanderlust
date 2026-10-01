import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/area_network.dart';
import '../geo/location_freshness.dart';
import '../maps/map_extent.dart';
import '../theme/wanderlust_theme.dart';

export '../geo/location_freshness.dart';

class GpsHud extends StatelessWidget {
  const GpsHud({
    super.key,
    required this.position,
    required this.now,
    required this.recording,
    required this.locating,
    this.network,
    this.networks = const [],
    this.error,
    this.details = true,
  });
  final Position? position;
  final DateTime now;
  final bool recording;
  final bool locating;
  final AreaNetwork? network;
  final List<AreaNetwork> networks;
  final String? error;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final point = position;
    final old = point != null && isOldFix(point, now);
    final maps = networks.isNotEmpty
        ? networks
        : [if (network != null) network!];
    final extent = MapExtent(maps);
    final coordinate = point == null
        ? null
        : Offset(point.longitude, point.latitude);
    final outside =
        coordinate != null && maps.isNotEmpty && !extent.contains(coordinate);
    final distance = coordinate == null || maps.isEmpty
        ? double.infinity
        : extent.distanceToBoundary(coordinate);
    final age = point == null ? 0 : fixAge(point, now).inSeconds;
    final ageLabel = age < 60 ? '${age}s ago' : '${age ~/ 60}m ago';
    final title = point == null
        ? (recording || locating
              ? 'Waiting for GPS…'
              : 'GPS · tap Center on me')
        : '${old || !recording ? 'Last fix' : 'GPS'} · ${point.accuracy > 0 ? '±${point.accuracy.round()} m' : 'accuracy unavailable'} · $ageLabel';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WanderlustColors.paperCard.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              details
                  ? title
                  : point == null
                  ? (recording || locating
                        ? 'Finding your location…'
                        : 'Tap Center on me to locate yourself')
                  : old
                  ? 'Last known location'
                  : 'Location ready',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (details && point != null)
              Text(
                '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 11),
              ),
            if (outside)
              const Text(
                'Outside saved maps · recording can continue',
                style: TextStyle(fontSize: 11),
              ),
            if (!outside && !old && distance <= 500)
              Text(
                'Offline map edge ~${(distance / 50).round() * 50} m away',
                style: const TextStyle(fontSize: 11),
              ),
            if (old && recording)
              const Text(
                'No recent fix · waiting for an update',
                style: TextStyle(fontSize: 11),
              ),
            if (locating && point != null)
              const Text('Refreshing GPS…', style: TextStyle(fontSize: 11)),
            if (error != null)
              Text(error!, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
