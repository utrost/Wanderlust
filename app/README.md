# Wanderlust — app (Flutter surface)

The cross-platform UI layer (ADR-0003). Android-first (ADR-0002); the heavy,
correctness-critical geo logic lives in the Rust [`geo-core`](../geo-core/) and
is linked via FFI.

> **Scaffold stage.** This renders the filling-map home screen (ramp + street
> network from the design mocks) and calls the **real Rust geo-core over FFI** on
> startup — matching a bundled sample walk and showing the result in a status
> chip ("geo-core · lit N streets · 0 phantom blocked"). The native
> `libwanderlust_geo.so` is cross-compiled with cargo-ndk in CI and bundled into
> the APK. Live GPS and offline MapLibre tiles are the next steps (see
> [ROADMAP](../docs/ROADMAP.md), Phase 1).

CI publishes a **debug APK** artifact (`wanderlust-debug-apk`) on every run —
download it from the run's Summary page to sideload on Android without a local
Flutter setup.

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
