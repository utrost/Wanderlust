# Wanderlust — app (Flutter surface)

The cross-platform UI layer (ADR-0003). Android-first (ADR-0002); the heavy,
correctness-critical geo logic lives in the Rust [`geo-core`](../geo-core/) and
is linked via FFI.

> **Pre-alpha in field testing.** Offline map downloads, live street heatmaps,
> repeat-visit colouring, screen-off recording, walk history, GPX exchange,
> full backups and notes/photos with map pins are implemented. New users download
> their first map around their location. See [the roadmap](../docs/ROADMAP.md).
> Android uses a source-only fork of Geolocator's platform provider without a
> Google Play Services dependency. Real-phone battery and release testing continue.

The Test APK workflow publishes a **debug APK** as a GitHub prerelease on every
push to `main`. Download the `.apk` from [Releases](https://github.com/utrost/Wanderlust/releases)
to sideload on Android without a local Flutter setup. The workflow summary also
links to the release.

Use the exact toolchain versions in `../tools/toolchain.env`. Production APK/AAB
builds and remaining submission gates are documented in
[Android releases](../docs/ANDROID_UPDATES.md#store-candidates-010).

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
chip reports that the native library or ABI is unavailable.

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

Run `flutter analyze` and `flutter test` from `app/`. CI also builds the host
Rust library and enables the real FFI/SQLite integration test. See
[the Bremen slice](../docs/BREMEN_SLICE.md) for evaluation and native-test setup.
