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
# Generates android/, injects location permissions, builds the geo-core .so
# into jniLibs (needs Rust android targets + cargo-ndk + ANDROID_NDK_HOME):
../tools/prepare_android.sh
cd app
flutter pub get
flutter run          # on an attached Android device or emulator
```

`prepare_android.sh` runs `flutter create` (which adds `android/` without
touching `lib/`), adds the walk-recorder's location permissions, and
cross-compiles the native geo-core. For a UI-only run without the native library
or GPS, plain `flutter create --platforms=android .` is enough — the FFI status
chip just shows "not loaded".

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
