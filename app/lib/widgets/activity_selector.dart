import 'package:flutter/material.dart';
import '../recording/activity_type.dart';

class ActivitySelector extends StatelessWidget {
  const ActivitySelector({super.key, required this.value, this.onChanged});
  final WalkActivity value;
  final ValueChanged<WalkActivity>? onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<WalkActivity>(
    segments: const [
      ButtonSegment(
        value: WalkActivity.walk,
        icon: Icon(Icons.directions_walk),
        label: Text('Walk'),
      ),
      ButtonSegment(
        value: WalkActivity.cycle,
        icon: Icon(Icons.directions_bike),
        label: Text('Cycle'),
      ),
    ],
    selected: {value},
    onSelectionChanged: onChanged == null ? null : (v) => onChanged!(v.single),
  );
}
