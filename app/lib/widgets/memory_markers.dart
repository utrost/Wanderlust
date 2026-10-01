import 'package:flutter/material.dart';
import '../memories/memory.dart';
import '../theme/wanderlust_theme.dart';

/// Screen-sized targets; geographic projection is shared with the route painter.
class MemoryMarkers extends StatelessWidget {
  const MemoryMarkers({
    super.key,
    required this.memories,
    required this.project,
    required this.size,
    required this.open,
  });
  final List<WalkMemory> memories;
  final Offset Function(Offset) project;
  final Size size;
  final void Function(WalkMemory) open;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final m in memories.where((m) => !m.draft && m.hasLocation))
        if ((Offset.zero & size)
            .inflate(24)
            .contains(project(Offset(m.longitude!, m.latitude!))))
          Positioned(
            left: project(Offset(m.longitude!, m.latitude!)).dx - 24,
            top: project(Offset(m.longitude!, m.latitude!)).dy - 24,
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: 'Memory: ${m.title}',
              onPressed: () => open(m),
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: WanderlustColors.paperCard,
                  border: Border.all(color: WanderlustColors.memoryAccent),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  m.hasPhoto ? Icons.photo_outlined : Icons.bookmark_outline,
                  size: 16,
                  color: WanderlustColors.memoryAccent,
                ),
              ),
            ),
          ),
    ],
  );
}
