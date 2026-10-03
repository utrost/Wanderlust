# Wanderlust

**Paint the streets you've walked.**

Wanderlust is an offline-first, privacy-respecting walking app. As you walk, it
colors the streets of your city onto the *real* street network — the more often
you walk a street, the more intense its color and width. No pace, no calories,
no streaks, no leaderboards. Just the quiet, addictive pleasure of watching your
personal territory grow.

It is the opposite of a fitness tracker. You are not an athlete here — you are a
cartographer of your own world.

> **Status: Android pre-alpha, in phone testing.** Offline street downloads,
> live coverage, parks/water, calm settings, GPX import/export and walk
> backup/restore are implemented. Android screen-off recording is implemented;
> real-phone battery and longer-walk validation remain open. See
> [Roadmap](docs/ROADMAP.md) and [screen-off recording](docs/SCREEN_OFF_RECORDING.md).

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
  bundled, with diagnostics available in Settings.
- **Walk recording**: permission flow, distance, optional elapsed time/GPS
  samples, and an Android foreground service for screen-off walks; fixes are journaled to SQLite with timestamps and accuracy.
  Saved walks survive restarts, interrupted sessions are recovered, and failed
  saves can be retried. Saved GPX is viewable/copyable in the app.
- **Matching safeguards**: GPX segment/time boundaries, conservative ambiguity
  handling, and explicit native diagnostics. See [recording notes](docs/RECORDING.md).
- **CI** (`.github/workflows/ci.yml`) for Rust format/clippy/tests plus Flutter
  analyze/test/debug APK build. The dedicated
  [Test APK](.github/workflows/test-apk.yml) workflow publishes a downloadable
  prerelease APK on `main`, manual runs, and `test-apk-*` tags. Get the APK from
  [Releases](https://github.com/utrost/Wanderlust/releases); downloads do not
  depend on Actions artifact storage.

**Bremen coverage slice:** a reproducible OSM network, versioned/idempotent street
counts, and an offline pan/zoom street view driven by saved walks now exist.
See [implementation and evaluation](docs/BREMEN_SLICE.md).

Still open:

- Real-phone battery and long-walk validation for screen-off recording.
- Field validation of matching on varied, noisy GPS traces.
- Richer offline basemap/labels (PMTiles + MapLibre remains a possible approach).
- Continuous recording after OS process termination (committed fixes recover).

Test APKs now have a persistent-signing build path and increasing version codes.
The signing credential is provisioned; see [Android updates](docs/ANDROID_UPDATES.md)
for the one-time transition from older builds.

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

GPX import/export and local backup/restore are available from **Walk history**.
See [formats, limits, and phone acceptance checks](docs/IMPORT_EXPORT.md).

On first launch, choose **Set up my map → Find my location → Download nearby map**.
No city map is selected automatically. Returning users open their downloaded maps
offline; add more through **Offline maps**. Choose
1–25 km per side (4 × 4 km by default); large, dense areas may require a smaller
size. Walked-line thickness is adjustable in Settings.
See [download behavior and phone checks](docs/NEARBY_MAPS.md).

The map recenters on a current GPS fix when you open the app or return from
another app, if location access is already allowed. During a walk it uses the
recording's next fresh fix. Panning while a fix is loading keeps your chosen
view; the location button centers again on demand. New installations still
start with local map setup before requesting location access.

Map actions sit on opaque panels for readability. Tap the map name to manage
offline maps; the location-status icon opens GPS details. The bottom icons show
explored sections, add a memory, open memories, and open saved walks. Long-press
icons for labels. Start/Stop remains labelled, and map-edge warnings stay visible.

**Settings → GPS interval** offers 2, 5, 10 and 20 seconds, starting with the next walk. Five seconds is the default; longer intervals may miss short turns. The movement filter is two metres at 2 s and five metres otherwise.
Street colouring now requires movement along the street in a compatible direction;
see [matching changes, regression tests and limits](docs/MATCHING_EVIDENCE.md).

**Settings → Fill small gaps** optionally fills short missing street sections
between confidently matched parts of a walk. It updates both live and saved
walks; switch it off to remove the extra estimates. Ambiguous routes and long GPS
outages remain unfilled. See [matching evidence](docs/MATCHING_EVIDENCE.md).

**Walk history → tap a walk** opens a read-only review with GPS, matched streets
and dashed inferred gaps. Preview gap filling there without changing your saved
coverage. Street labels work with existing maps; refresh downloaded maps to add
place labels and clearer area names. See [walk review](docs/WALK_REVIEW.md).

### About and acknowledgements

**Settings → About Wanderlust** shows the creator, installed Android version and
build number, source-code address, current app licence, and OpenStreetMap
attribution. The app licence and open-source library notices are readable offline.
Flutter supplies its dependency notices; `tools/generate_licenses.py` bundles
licences from the enabled Rust dependency sources and copies the repository
licence. Android preparation regenerates these assets after compiling the native
matcher; run it when updating Cargo dependencies.

**Settings → Show street names** toggles road labels on both the main map and
saved-walk review. Place and park names remain visible. The choice persists
between launches; existing installations retain street names by default.

The main heatmap counts each street section once per distinct walk. Repeated GPS
fixes or multiple passes within one recording do not add visits. A new walk adds
one live preview visit, confirmed on saving; overlapping offline maps are
combined without double-counting the same walk. Warm colours now have stronger
contrast between 1, 2, 5 and 10 walks, then deepen more gradually up to 1,000.
Tap the street-count button on the main map for a compact colour key; the same
key appears in Settings. It shows 1, 2, 5, 10 and 100 walks. Your line-width
setting is unchanged. Saved-walk review shows that individual walk rather than
the accumulated heatmap.

### Notes and photos during a walk

**Add memory** saves a note, one optional photo and an optional location without
stopping your walk. **Memories** opens the library; saved-walk review offers the
entries linked to that walk. Tap a map marker to open an entry. Back keeps edits
as a draft; Save publishes them. Camera interruption recovery is supported on
Android. A missing or stale GPS fix never prevents a note and is not silently
used for its pin.

Everything stays in app-private storage. Settings → Show memory markers hides
pins without removing entries. Create backup includes memories, drafts and actual
photo bytes. GPX does not include memories. See the [UX concept and workflows](docs/MEMORIES.md).

Complete backups use `wanderlust-backup.wanderlust` (version 4), with streamed,
checksummed walk and photo records, settings and offline maps. Restore merges
missing items and replaces settings only when selected. Limits are 2 GiB per
archive and 8 MiB per photo. Earlier JSON/gzip backups are no longer supported.

The Android package for registration is **`com.simiono.wanderlust`**. This is a
fresh-install baseline: it does not update or automatically migrate the former
experimental app. Current `.wanderlust` archives can still be restored manually.

In a memory editor, **Choose on map** lets you position or move a pin without GPS.
Tap a location inside a downloaded map and confirm **Use this spot**. Cancelling
leaves the previous pin untouched. Add a note or photo before saving the memory.

### Walk history and favourites

Every recorded walk is kept privately in Walk history and contributes to matching
and the heatmap. A GPX file is created only by explicitly choosing Export GPX.
Star a walk to find it in Favourites; removing its star does not remove its
heatmap contribution. Full backups always include all walks, even when the
Favourites filter is selected, and retain stars on a fresh restore. Existing
local favourite choices take precedence when merging a backup.
