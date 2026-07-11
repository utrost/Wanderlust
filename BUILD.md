# Building Wanderlust

Wanderlust is a monorepo: a Rust **geo-core** (the map-matching and routing
brains) and a Flutter **app** (the cross-platform surface) that links it via
FFI. Android-first; iOS is a later veneer. See the ADRs
([0002](docs/adr/0002-android-first-ios-later.md),
[0003](docs/adr/0003-flutter-with-native-geo-core.md)) for why.

> **Pre-alpha.** Phase 0 (geo-core map-matching + guardrail) is implemented and
> tested; the app is a scaffold. Track progress in [ROADMAP](docs/ROADMAP.md).

## Layout

| Path | What |
| --- | --- |
| [`geo-core/`](geo-core/) | Rust: map-matching, routing graph, data model. Built + tested today. |
| [`geo-ffi/`](geo-ffi/) | Rust: C ABI + GeoJSON loader over geo-core, for the app to call via FFI. Built + tested today. |
| [`app/`](app/) | Flutter surface. Scaffolded; compiled in CI. |
| [`design/mood-map/`](design/mood-map/) | The visual-direction prototype (runnable HTML). |
| [`docs/`](docs/) | Design spec, architecture, roadmap, ADRs. |
| [`tools/`](tools/) | Tile pipeline: OSM extract → PMTiles + street GeoJSON. Scaffolded. |

## geo-core (Rust)

```bash
cargo test --workspace       # no external deps; builds anywhere
cargo clippy --all-targets
```

## app (Flutter)

Needs the Flutter SDK; per-platform folders are generated on first setup. See
[`app/README.md`](app/README.md).

```bash
cd app
flutter create --org com.wanderlust --project-name wanderlust --platforms=android,ios .
flutter pub get
flutter run
```

## What can be built where

| Piece | This dev container (Linux) | Needs |
| --- | --- | --- |
| geo-core | ✅ build + test | — |
| Android app | ⚙️ CI builds the APK | Android SDK / a device to run |
| iOS app | ❌ not here | macOS + Xcode + Apple Developer account |

CI (`.github/workflows/ci.yml`) runs the Rust checks and builds/analyzes the
Android app on every push.
