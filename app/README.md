# Wanderlust — app (Flutter surface)

The cross-platform UI layer (ADR-0003). Android-first (ADR-0002); the heavy,
correctness-critical geo logic lives in the Rust [`geo-core`](../geo-core/) and
is linked via FFI.

> **Scaffold stage.** This currently renders the filling-map home screen with
> the ramp and street network from the design mocks, driven by bundled sample
> data. Live GPS, offline MapLibre tiles, and the geo-core FFI wiring are the
> next steps (see [ROADMAP](../docs/ROADMAP.md), Phase 1).

## First-time setup

This repo tracks the Dart source (`lib/`) and config, but not the generated
per-platform folders. Generate them once:

```bash
cd app
flutter create --org com.wanderlust --project-name wanderlust --platforms=android,ios .
flutter pub get
flutter run          # on an attached Android device or emulator
```

`flutter create` over an existing project adds the missing `android/` and
`ios/` scaffolding without touching `lib/`.

## Layout

| Path | What |
| --- | --- |
| `lib/main.dart` | App entry + theme wiring. |
| `lib/theme/heat_ramp.dart` | The walk-count heat ramp, ported from the mocks, with an OKLCH→sRGB conversion so colours match exactly. |
| `lib/theme/wanderlust_theme.dart` | Palette and typography. |
| `lib/data/street_network.dart` | Generated sample street network (from `design/mood-map/map-data.js`). |
| `lib/widgets/filling_map_painter.dart` | `CustomPainter` that draws the filling map. |
| `lib/screens/map_screen.dart` | The home screen. |

## Verification

The app is compiled and analyzed in CI (`.github/workflows/ci.yml`) against
Flutter stable, since it can't be built in the design/geo-core dev container
(no Flutter SDK there).
