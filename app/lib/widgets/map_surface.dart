import 'package:flutter/material.dart';

import '../theme/wanderlust_theme.dart';

class MapSurface extends StatelessWidget {
  const MapSurface(this.child, {super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: WanderlustColors.paperCard,
    elevation: 2,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
