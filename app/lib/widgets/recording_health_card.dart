import 'package:flutter/material.dart';
import '../recording/recording_health.dart';
import '../recording/saved_walk.dart';

class RecordingHealthCard extends StatelessWidget {
  const RecordingHealthCard({super.key, required this.walk});
  final SavedWalk walk;
  @override
  Widget build(BuildContext context) {
    final health = RecordingHealth.fromWalk(walk);
    return ExpansionTile(
      leading: Icon(
        health.hasGaps ? Icons.location_off_outlined : Icons.route_outlined,
      ),
      title: Text(health.title),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [Text(health.detail)],
    );
  }
}
