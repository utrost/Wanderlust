import 'package:flutter/material.dart';

import 'heat_ramp.dart';

/// Warm paper and sepia colours shared by controls and map overlays.
class WanderlustColors {
  static final Color paperBg = oklch(0.95, 0.012, 80); // light basemap
  static const Color paperCard = Color(0xFFFBF8F2);
  static const Color canvasBg = Color(0xFFE7E2D7);
  static final Color darkBg = oklch(0.22, 0.014, 75); // dark basemap
  static final Color ink = oklch(0.25, 0.02, 75); // primary text
  static final Color inkMuted = oklch(0.5, 0.02, 75);
  static final Color accent = oklch(0.42, 0.09, 50); // amber CTA
  static final Color water = oklch(0.90, 0.014, 220);
  static final Color park = oklch(0.90, 0.02, 140);
  static final Color darkWater = oklch(0.27, 0.02, 230);
  static const Color memoryAccent = Color(0xFF75638C);
  static const Color mapPark = Color(0xFFDCE4D2);
  static const Color mapWater = Color(0xFFC4DAE2);
  static const Color mapLabel = Color(0xFF665F55);
  static final Color darkPark = oklch(0.26, 0.02, 140);
}

class WanderlustTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: WanderlustColors.paperBg,
      colorScheme: base.colorScheme.copyWith(
        primary: WanderlustColors.accent,
        surface: WanderlustColors.paperCard,
        secondary: WanderlustColors.accent,
        secondaryContainer: WanderlustColors.canvasBg,
        onSecondaryContainer: WanderlustColors.ink,
      ),
      // Use the platform font explicitly until offline brand fonts are bundled.
      textTheme: base.textTheme.apply(
        bodyColor: WanderlustColors.ink,
        displayColor: WanderlustColors.ink,
      ),
    );
  }
}
