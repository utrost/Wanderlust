import 'package:flutter/material.dart';

import 'map_surface.dart';

class MapToolbar extends StatelessWidget {
  const MapToolbar({
    super.key,
    required this.name,
    required this.locating,
    required this.onMaps,
    required this.onSettings,
    required this.onArea,
    required this.onCenter,
  });
  final String name;
  final bool locating;
  final VoidCallback onMaps, onSettings, onArea, onCenter;
  @override
  Widget build(BuildContext context) => MapSurface(
    Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: onMaps,
            icon: const Tooltip(
              message: 'Offline maps',
              child: Icon(Icons.map_outlined),
            ),
            label: Text(
              name.split(' · ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          tooltip: 'Show map area',
          onPressed: onArea,
          icon: const Icon(Icons.zoom_out_map),
        ),
        IconButton(
          tooltip: 'Center on me',
          onPressed: locating ? null : onCenter,
          icon: locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
        ),
      ],
    ),
  );
}
