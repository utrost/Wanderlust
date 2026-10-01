import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/area_network.dart';
import '../geo/location_freshness.dart';
import '../maps/map_extent.dart';
import 'map_surface.dart';

class MapLocationControl extends StatelessWidget {
  const MapLocationControl({
    super.key,
    required this.position,
    required this.networks,
    required this.error,
    required this.locating,
    required this.showGps,
    required this.onDetails,
    required this.onMaps,
  });
  final Position? position;
  final List<AreaNetwork> networks;
  final String? error;
  final bool locating, showGps;
  final VoidCallback onDetails, onMaps;
  @override
  Widget build(BuildContext context) {
    final p = position;
    final old = p != null && isOldFix(p, DateTime.now());
    final coordinate = p == null ? null : Offset(p.longitude, p.latitude);
    final extent = MapExtent(networks);
    final outside = coordinate != null && !extent.contains(coordinate);
    final near =
        coordinate != null &&
        !old &&
        extent.distanceToBoundary(coordinate) <= 500;
    final status = error != null
        ? 'Location needs attention'
        : locating
        ? 'Finding your location…'
        : p == null
        ? 'Location unavailable'
        : old
        ? 'Last known location'
        : 'Location ready';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        MapSurface(
          IconButton(
            tooltip: '$status · Location details',
            onPressed: onDetails,
            icon: Icon(
              error != null
                  ? Icons.location_off_outlined
                  : old || p == null
                  ? Icons.location_searching
                  : Icons.gps_fixed,
            ),
          ),
        ),
        if (showGps && p != null)
          MapSurface(
            TextButton(
              onPressed: onDetails,
              child: Text(
                '±${p.accuracy.round()} m${old ? ' · Last fix' : ''}',
              ),
            ),
          ),
        if (outside || near)
          MapSurface(
            TextButton.icon(
              onPressed: onMaps,
              icon: const Icon(Icons.download_outlined),
              label: Text(outside ? 'Map needed here' : 'Map edge nearby'),
            ),
          ),
      ],
    );
  }
}
