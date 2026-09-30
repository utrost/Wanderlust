import 'package:flutter/material.dart';
import '../data/area_network.dart';
import '../maps/map_extent.dart';
import '../memories/memory.dart';
import '../widgets/area_map.dart';

/// Explicit placement; never requests GPS or changes a pin until confirmation.
class MemoryPinScreen extends StatefulWidget {
  const MemoryPinScreen({super.key, required this.networks, this.initial});
  final List<AreaNetwork> networks;
  final Offset? initial;
  @override
  State<MemoryPinScreen> createState() => _MemoryPinScreenState();
}

class _MemoryPinScreenState extends State<MemoryPinScreen> {
  late AreaNetwork area = widget.networks.firstWhere(
    (n) => widget.initial != null && MapExtent([n]).contains(widget.initial!),
    orElse: () => widget.networks.first,
  );
  late Offset? selected = widget.initial;
  final marker = WalkMemory.create().copyWith(
    note: 'Selected pin',
    draft: false,
  );
  int areaRequest = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a spot')),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.networks.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<AreaNetwork>(
                isExpanded: true,
                value: area,
                items: [
                  for (final map in widget.networks)
                    DropdownMenuItem(
                      value: map,
                      child: Text(
                        map.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (map) {
                  if (map != null) {
                    setState(() {
                      area = map;
                      areaRequest++;
                    });
                  }
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Tap the map to place your pin.'),
          ),
          Expanded(
            child: AreaMap(
              network: area,
              networks: widget.networks,
              counts: const {},
              areaRequest: areaRequest,
              fitCoordinates: areaRequest == 0 && widget.initial != null
                  ? [widget.initial!]
                  : const [],
              memories: [
                if (selected != null)
                  marker.copyWith(
                    pin: (latitude: selected!.dy, longitude: selected!.dx),
                  ),
              ],
              onMemory: (_) {},
              onMapTap: (p) {
                if (MapExtent(widget.networks).contains(p)) {
                  setState(() => selected = p);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Choose a spot inside a downloaded map.'),
                    ),
                  );
                }
              },
            ),
          ),
          const Text(
            '© OpenStreetMap contributors · ODbL',
            style: TextStyle(fontSize: 10),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              icon: const Icon(Icons.check),
              label: const Text('Use this spot'),
            ),
          ),
        ],
      ),
    ),
  );
}
