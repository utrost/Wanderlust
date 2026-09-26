# Building Wanderlust

Wanderlust is a monorepo: a Rust **geo-core** (the map-matching and routing
brains) and a Flutter **app** (the cross-platform surface) that links it via
FFI. Android-first; iOS is a later veneer. See the ADRs
([0002](docs/adr/0002-android-first-ios-later.md),
[0003](docs/adr/0003-flutter-with-native-geo-core.md)) for why.

> **Pre-alpha scaffold.** The geo-core map-matching spike, guardrail, FFI bridge,
> Flutter filling-map surface, foreground walk recorder, and CI-built Android
> debug APK exist. The app now bundles real Bremen street geometry and durable
> per-walk coverage, GPX import/export, and JSON backup/restore. A richer offline
> basemap, field validation,
> and background GPS are still needed for a walkable MVP. Track
> progress in [ROADMAP](docs/ROADMAP.md).

## Layout

| Path | What |
| --- | --- |
| [`geo-core/`](geo-core/) | Rust: map-matching, routing graph, data model. Built and tested in CI. |
| [`geo-ffi/`](geo-ffi/) | Rust: C ABI + GeoJSON loader over geo-core, for the app to call via FFI. Built and tested in CI. |
| [`app/`](app/) | Flutter surface. Scaffolded; analyzed, tested, and built as a debug APK in CI. |
| [`design/mood-map/`](design/mood-map/) | The visual-direction prototype (runnable HTML). |
| [`docs/`](docs/) | Design spec, architecture, roadmap, ADRs. |
| [`tools/`](tools/) | Tested OSM → street GeoJSON pipeline and matching evaluation; PMTiles profile integration pending. |

## Current verification source

CI (`.github/workflows/ci.yml`) is the authoritative build verification until a
local machine has both the Rust and Flutter/Android toolchains installed. CI runs
on every push and pull request:

- `cargo fmt --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo test --workspace`
- `tools/prepare_android.sh`
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug --target-platform android-arm64,android-x64`
- verify both native architectures and the exact Bremen asset with `tools/verify_apk.py`
- the separate Test APK workflow publishes a prerelease APK for testers

## geo-core (Rust)

Needs a normal Rust toolchain.

```bash
cargo test --workspace
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --check
```

## app (Flutter / Android)

Needs Flutter 3.41+ / Dart 3.11+, Android SDK/NDK, Rust Android targets, and `cargo-ndk`.
Per-platform folders are generated on first setup. See [`app/README.md`](app/README.md).

```bash
# From repo root. Generates android/, injects location permissions, and builds
# the native geo-core .so into the Android jniLibs directory.
bash tools/prepare_android.sh

cd app
flutter pub get
flutter analyze
flutter test
flutter run          # on an attached Android device or emulator
```

For a UI-only run without the native library or GPS, plain
`flutter create --platforms=android .` is enough; the FFI status chip should show
that the native library is not loaded instead of crashing.

## Test APK pipeline

The dedicated [Test APK workflow](.github/workflows/test-apk.yml) builds an
Android APK specifically for testers.

It runs automatically on:

- every push to `main`
- tags named `test-apk-*`

It can also be started manually from GitHub Actions with **Run workflow**.
Every successful run publishes a GitHub prerelease with an APK asset. Manual
runs have an optional `release_tag` field; tagged runs use their `test-apk-*`
tag. Other runs use `test-apk-<short-sha>`.

The asset is named `wanderlust-test-<short-sha>.apk`. Download it directly from
[Releases](https://github.com/utrost/Wanderlust/releases), or follow the link in
the workflow summary. No Actions-artifact ZIP extraction is needed on the phone.

## Debug APK from CI

CI analyzes, tests, builds, and verifies the APK. The Test APK workflow handles
distribution through release assets. Neither workflow uploads an Actions
artifact: that shared storage quota previously blocked uploads even after
successful builds. Existing artifacts and releases are left intact.

Smoke-test checklist:

- App launches.
- Filling map renders.
- Geo-core status chip reports a successful sample match. A native library/ABI
  failure is a failed APK smoke test; tap the chip for details.
- `Start walk` asks for location permission.
- Foreground recording starts when permission is granted.
- Elapsed time, distance, and point count update.
- `Stop` ends the recording without a crash.
- `Saved walks` contains the walk and its timestamped GPX.
- A saved walk within Bremen center paints matched streets. Refresh/restart does
  not increment counts; a second distinct walk increments each matched edge once.
- Restarting the app retains completed walks; an interrupted walk retains its
  committed fixes. See [recording notes](docs/RECORDING.md).

## What can be built where

| Piece | Generic Linux dev container | Needs |
| --- | --- | --- |
| geo-core | ✅ with Rust installed | Rust toolchain |
| Android app | ⚙️ CI builds the APK | Flutter SDK, Android SDK/NDK, Rust Android targets, `cargo-ndk`, device/emulator to run |
| iOS app | ❌ not here | macOS + Xcode + Apple Developer account |
