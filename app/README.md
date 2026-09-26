# Wanderlust — app (Flutter surface)

The cross-platform UI layer (ADR-0003). Android-first (ADR-0002); the heavy,
correctness-critical geo logic lives in the Rust [`geo-core`](../geo-core/) and
is linked via FFI.

> **Pre-alpha.** The filling map now uses real bundled Bremen street geometry
> and saved per-walk coverage. Foreground GPS records
> durable walks in SQLite, including interruption recovery and failed-save
> retries. The saved-walk library imports/exports GPX and creates/restores JSON
> backups through native document dialogs. See [import/export](../docs/IMPORT_EXPORT.md). Startup runs a bundled walk
> through Rust FFI; tapping a failed status chip reveals the underlying error.
> A richer PMTiles basemap, continuous recording-time updates, and background
> recording remain open. See [coverage evaluation](../docs/BREMEN_SLICE.md).
> See [recording and matching behavior](../docs/RECORDING.md).

The Test APK workflow publishes a **debug APK** as a GitHub prerelease on every
push to `main`. Download the `.apk` from [Releases](https://github.com/utrost/Wanderlust/releases)
to sideload on Android without a local Flutter setup. The workflow summary also
links to the release.

Requires Flutter 3.41+ / Dart 3.11+ for the document-picker and XML dependencies.

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
