# Building Wanderlust

Wanderlust is a monorepo: a Rust **geo-core** (the map-matching and routing
brains) and a Flutter **app** (the cross-platform surface) that links it via
FFI. Android-first; iOS is a later veneer. See the ADRs
([0002](docs/adr/0002-android-first-ios-later.md),
[0003](docs/adr/0003-flutter-with-native-geo-core.md)) for why.

> **Pre-alpha scaffold.** The geo-core map-matching spike, guardrail, FFI bridge,
> Flutter filling-map surface, foreground walk recorder, and CI-built Android
> debug APK exist. The app is not a walkable MVP until one real offline area,
> persistent counts, GPX import/export, and background GPS are implemented. Track
> progress in [ROADMAP](docs/ROADMAP.md).

## Layout

| Path | What |
| --- | --- |
| [`geo-core/`](geo-core/) | Rust: map-matching, routing graph, data model. Built and tested in CI. |
| [`geo-ffi/`](geo-ffi/) | Rust: C ABI + GeoJSON loader over geo-core, for the app to call via FFI. Built and tested in CI. |
| [`app/`](app/) | Flutter surface. Scaffolded; analyzed, tested, and built as a debug APK in CI. |
| [`design/mood-map/`](design/mood-map/) | The visual-direction prototype (runnable HTML). |
| [`docs/`](docs/) | Design spec, architecture, roadmap, ADRs. |
| [`tools/`](tools/) | Tile pipeline: OSM extract → PMTiles + street GeoJSON. Scaffolded; profile/tuning pending. |

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
- `flutter build apk --debug`
- upload of `wanderlust-debug-apk`

## geo-core (Rust)

Needs a normal Rust toolchain.

```bash
cargo test --workspace
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --check
```

## app (Flutter / Android)

Needs the Flutter SDK, Android SDK/NDK, Rust Android targets, and `cargo-ndk`.
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
Manual runs have an optional `release_tag` field. If set, the workflow publishes
or updates a GitHub prerelease with the APK attached.

Outputs:

- A workflow artifact named like `wanderlust-test-<short-sha>.apk` on every run.
- A prerelease APK asset when run with `release_tag` or from a `test-apk-*` tag.

Use artifacts for quick internal checks. Use prereleases when you want to send a
more stable link to non-technical testers.

## Debug APK from CI

Every successful CI run uploads a `wanderlust-debug-apk` artifact. Use that for
real-device smoke tests when the local Android toolchain is not installed. The
Test APK workflow above is the preferred path for builds intended for testers.

Smoke-test checklist:

- App launches.
- Filling map renders.
- Geo-core status chip reports a successful sample match, or calmly reports that
  the native library is not loaded.
- `Start walk` asks for location permission.
- Foreground recording starts when permission is granted.
- Elapsed time, distance, and point count update.
- `Stop` ends the recording without a crash.

## What can be built where

| Piece | Generic Linux dev container | Needs |
| --- | --- | --- |
| geo-core | ✅ with Rust installed | Rust toolchain |
| Android app | ⚙️ CI builds the APK | Flutter SDK, Android SDK/NDK, Rust Android targets, `cargo-ndk`, device/emulator to run |
| iOS app | ❌ not here | macOS + Xcode + Apple Developer account |
