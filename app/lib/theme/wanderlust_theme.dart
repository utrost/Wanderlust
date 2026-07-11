import 'package:flutter/material.dart';

import 'heat_ramp.dart';

/// The Wanderlust palette and typography, from the visual-direction canvas
/// (design/mood-map). Warm paper, sepia ink, Newsreader for warmth and Work
/// Sans for chrome. Colours come through the shared [oklch] helper so they match
/// the mocks exactly.
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
      ),
      // Font families are declared in pubspec (Newsreader, Work Sans). Until the
      // fonts are bundled, these fall back gracefully to the platform serif/sans.
      textTheme: base.textTheme.apply(
        bodyColor: WanderlustColors.ink,
        displayColor: WanderlustColors.ink,
        fontFamily: 'Work Sans',
      ),
    );
  }

  /// Newsreader serif, for the "keepsake" moments (place names, headings).
  static const TextStyle serif = TextStyle(fontFamily: 'Newsreader');
}
