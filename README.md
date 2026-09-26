# Wanderlust

**Paint the streets you've walked.**

Wanderlust is an offline-first, privacy-respecting walking app. As you walk, it
colors the streets of your city onto the *real* street network — the more often
you walk a street, the more intense its color and width. No pace, no calories,
no streaks, no leaderboards. Just the quiet, addictive pleasure of watching your
personal territory grow.

It is the opposite of a fitness tracker. You are not an athlete here — you are a
cartographer of your own world.

> **Status: pre-alpha scaffold.** Wanderlust now contains a Rust geo-core, a
> Flutter Android-first app scaffold, foreground GPS recording, FFI wiring, and a
> CI-built debug APK. It now also has real offline Bremen street geometry and
> persistent per-walk coverage. The product is not yet a walkable MVP: the richer
> offline basemap, GPX import, export/backup, and background GPS are still open. See [Current state](#current-state) and
> [Roadmap](docs/ROADMAP.md).

---

## Current state

Implemented, with automated checks configured in CI:

- **Rust geo-core** (`geo-core/`) with the platform-independent data model,
  routing graph, snap-to-edge map matching, shortest-path fill, and the
  "don't paint what you didn't walk" guardrail.
- **FFI layer** (`geo-ffi/`) with a C ABI, GeoJSON street-network loading, GPX
  matching, and integration tests.
- **Flutter app scaffold** (`app/`) that renders the filling-map surface, calls
  the real Rust geo-core through FFI on startup when the native library is
  bundled, and shows the result in a status chip.
- **Foreground walk recording**: permission flow, elapsed time, distance, and
  point count; fixes are journaled to SQLite with timestamps and accuracy.
  Saved walks survive restarts, interrupted sessions are recovered, and failed
  saves can be retried. Saved GPX is viewable/copyable in the app.
- **Matching safeguards**: GPX segment/time boundaries, conservative ambiguity
  handling, and explicit native diagnostics. See [recording notes](docs/RECORDING.md).
- **CI** (`.github/workflows/ci.yml`) for Rust format/clippy/tests plus Flutter
  analyze/test/debug APK build. The debug APK is uploaded as the
  `wanderlust-debug-apk` artifact on successful CI runs. A dedicated
  [Test APK](.github/workflows/test-apk.yml) workflow also builds tester-friendly
  APK artifacts on `main` and can publish prerelease APKs from manual runs or
  `test-apk-*` tags.

**Bremen coverage slice:** a reproducible OSM network, versioned/idempotent street
counts, and an offline pan/zoom street view driven by saved walks now exist.
See [implementation and evaluation](docs/BREMEN_SLICE.md).

Still not implemented:

- Offline PMTiles + MapLibre rendering of a real selected area.
- Field validation of matching on real noisy GPS traces.
- Continuous map updates during a walk (coverage currently updates after saving).
- GPX import, user export, and ZIP backup flows.
- Background GPS with battery and app-kill resilience.

---

## Installing the Android test app

Wanderlust is not in the Play Store yet. For now, testers install a test APK by
hand. This is called sideloading.

1. Open the APK download link from the project maintainer on your Android phone.
2. Download the file. It may be named `wanderlust-test-...apk`,
   `wanderlust-debug-apk`, or `app-debug.apk`.
3. If the download is a `.zip` file, open it first and extract the `.apk` file
   inside.
4. Tap the `.apk` file.
5. If Android blocks the install, tap **Settings**, enable **Allow from this
   source**, then go back to the install screen.
6. Tap **Install**.
7. Open **Wanderlust**.
8. When Android asks for location access, choose **Allow while using the app**.

After installing, you can turn **Allow from this source** off again in Android
settings if you want. Only install Wanderlust APKs from links sent by the project
maintainer.

---

## What makes it different

- **Collecting, not competing.** The filling map *is* the reward. No leaderboards,
  no social ranking, no streaks.
- **Serendipity over navigation.** The app invites you into unwalked alleys; it
  never commands a route.
- **A life map, not a log.** Over years it becomes a portrait of how you move
  through the world — a keepsake, not a statistic.
- **Local by default.** No account, no login, no telemetry. Your location data —
  the most sensitive thing an app can know about you — never leaves your device.

---

## Documentation

| Doc | For whom | What's in it |
| --- | --- | --- |
| [Build Guide](BUILD.md) | Developers | Repo layout, setup, CI, and what can be built where |
| [Design Spec](docs/DESIGN.md) | Anyone who wants the "why" | Philosophy, core mechanic, gamification, full feature set, non-goals |
| [Design Brief](docs/DESIGN_BRIEF.md) | Designers | Visual & UX briefing: tone, the heat-ramp brand, screens to design, constraints |
| [User Guide](docs/USER_GUIDE.md) | Future users | How the app works from the outside: walking, maps, finds, notes, import/export |
| [Architecture](docs/ARCHITECTURE.md) | Contributors | System shape, map-matching approach, data model, stack, key risks |
| [Roadmap](docs/ROADMAP.md) | Contributors & the curious | Phased plan from geo-core to iOS, what's deferred and why |
| [Decision Records](docs/adr/README.md) | Contributors | The load-bearing technical decisions and their rationale |

If you're new, read the [Design Spec](docs/DESIGN.md) first — everything else
follows from it. If you want to run or change code, read [BUILD.md](BUILD.md).

---

## License

Licensed under the **GNU Affero General Public License v3.0** — see
[`LICENSE`](LICENSE). The choice is still under discussion for a local-first
client that never talks to a server; see
[ADR-0006](docs/adr/0006-license.md).

GPX import/export and local backup/restore are available from **Saved walks**.
See [formats, limits, and phone acceptance checks](docs/IMPORT_EXPORT.md).
