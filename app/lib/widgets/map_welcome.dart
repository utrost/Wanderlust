import 'package:flutter/material.dart';

class MapWelcome extends StatelessWidget {
  const MapWelcome({super.key, required this.actions});
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_outlined, size: 56),
              const SizedBox(height: 24),
              const Text(
                'Your walks, your neighbourhood',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tap Start recording and put your phone away. Walking, cycling and other journeys appear together on your map.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Walks stay on your phone. Nearby maps download as you walk using Wi-Fi or mobile data. You can turn this off in Settings.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ...actions,
            ],
          ),
        ),
      ),
    ),
  );
}
