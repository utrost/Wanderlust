# Wanderlust — Roadmap

A phased plan from nothing to a lifetime map. Ordering follows the architecture:
**de-risk the geo-core first, wrap platforms around it, defer routing.** See
[ARCHITECTURE.md](ARCHITECTURE.md).

Status legend: 🔴 not started · 🟡 in progress · 🟢 done.

Current status: **Android pre-alpha in field testing**. The core walk → street
colour loop has been confirmed on the tester's phone. Offline maps, GPS controls,
live colouring, parks/water, calm settings, adjustable line width and 1–25 km
map sides are implemented. GPX import/export and raw-walk backup/restore exist. Notes and photos are implemented
with offline memory pins, drafts, saved-walk associations and full backup/restore
([UX concept](MEMORIES.md)); actual-phone validation remains open.
Screen-off recording and persistent APK signing are implemented, and the signing
credential is provisioned. Actual-phone battery testing remains open.
See [screen-off recording](SCREEN_OFF_RECORDING.md), [Android updates](ANDROID_UPDATES.md)
and [nearby maps](NEARBY_MAPS.md).

---

## Phase 0 — Foundations 🟡
Prove the risky pieces in isolation, before any polished app.

- 🟢 **Geo-core skeleton** (platform-agnostic): data model, SQLite-oriented
  schema sketch, routing graph, and segment-count model
  ([`geo-core`](../geo-core/)).
- 🟡 **Map-matching spike**: snap-to-edge + shortest-path fill, *with the
  don't-paint-what-you-didn't-walk guardrail* (see
  [ADR-0001](adr/0001-pragmatic-map-matching.md)). Implemented and tested;
  reachable from the app through the FFI boundary + GeoJSON loader
  ([`geo-ffi`](../geo-ffi/)), validated end-to-end (GeoJSON network + GPX in →
  correct street ids out) on a real-coordinate sample. Real OSM data and an initial outdoor walk are validated; broader
  messy/flâneur GPS field evaluation remains open.
- 🟢 **Routing graph** load + query for Bremen center, using an OSM-derived
  network with explicit node topology and stable ids.
- 🟡 **Tile/data pipeline**: reproducible OSM extraction, conservative pedestrian
  filtering, normalized street GeoJSON, and synthetic matching evaluation exist.
  Planetiler/PMTiles integration and field validation remain pending
  ([#6](https://github.com/utrost/Wanderlust/issues/6)).
- 🔴 **PMTiles + MapLibre** render of one area, offline
  ([#8](https://github.com/utrost/Wanderlust/issues/8)).
- 🟢 **Initial real-device debug APK smoke test**: installation, launch, FFI load,
  permission prompt, GPS positioning, downloaded maps and outdoor saved coverage
  confirmed on Android. Longer field testing remains ongoing
  ([#5](https://github.com/utrost/Wanderlust/issues/5)).

**Exit criteria:** choose one real area, render it offline, feed a GPX file in →
correct per-segment counts out, no phantom streets.

## Phase 1 — Walkable MVP (Android) 🟡
The smallest thing that delivers the core joy: walk → map fills.

- 🟡 **GPS recording** — foreground and user-started Android screen-off
  recording implemented with notification, scoped wake lock and SQLite journaling.
  Hidden display/matching work is deferred until return. Real-phone battery and
  long-walk trace acceptance remain open; process death recovers committed fixes
  rather than silently restarting. See [recording](SCREEN_OFF_RECORDING.md).
- 🟢 **Reliable APK updates** — persistent certificate, fail-closed credential
  loading, increasing build numbers and signature checks implemented. Signing
  credential provisioned; in-place upgrade tested. See [updates](ANDROID_UPDATES.md).
- 🟡 **Persistent walk state**: raw walks now use a SQLite recording journal
  with interruption recovery and save retries. Per-walk edge memberships and
  durable counts and GPX imports are implemented across downloaded networks
  ([#7](https://github.com/utrost/Wanderlust/issues/7)).
- 🟢 **Filling street map**: live provisional colour/section counts, saved counts,
  GPS marker/recenter, calm optional details and adjustable line thickness exist.
  Parks and water render offline; restrained street/place labels are implemented.
  Richer basemap styling remains open.
- 🟡 **Area selection**: GPS-centered 1–25 km-per-side street downloads (4 km default), persistent
  offline map picker, and per-area coverage implemented. Admin boundaries, drawn
  rectangles, and per-area PMTiles remain open. See [nearby maps](NEARBY_MAPS.md).
- 🟢 **GPX import** — document picker, strict validation, segment/time preservation,
  duplicate detection, and coverage updates. Native phone picker validation pending.
- 🟡 **Export and backup** — per-walk GPX and versioned JSON backup/merge restore
  implemented, including maps, settings, photos, atomic restore, corruption checks and gzip compression. GeoJSON with
  counts and streaming archives beyond the current size limit remain open.
  See [behavior and acceptance checks](IMPORT_EXPORT.md).

**Exit criteria:** a real person can pick an area, import history, walk for a
week, and watch their map fill — fully offline.

## Phase 2 — The life map 🟡
Turn the heatmap into a keepsake.

- 🔴 **First-time sparkle** on never-walked streets.
- 🔴 **Nested completeness**: street → neighborhood → district → city, with a
  "claimed" seal. Depends on resolving the *completeness denominator* question.
- 🔴 **Finds**: collectible POIs from OSM.
- 🟢 **Notes & photos** pinned to GPS or manually chosen map positions (local only). Drafts, walk associations and photo backups are implemented; multiple photos, search/tags and sharing remain later slices.
- 🟡 **Multiple areas**: eight downloadable street maps;
  seamless combined display, distinct-walk overlap counts and a 500 m outer-edge
  warning are implemented;
  the richer "passport" experience remains open.

## Phase 3 — iOS 🔴
The veneer, not a rewrite — enabled by the reusable geo-core.

- 🔴 iOS sensor + background-location adapter.
- 🔴 iOS UI parity.
- 🔴 Re-verify background-location constraints (they differ from Android).

## Phase 4 — Exploration suggestions 🔴 *(optional / deferred)*
The one routing-adjacent feature, deliberately last.

- 🔴 Generate a loop from current location that grazes unwalked terrain and
  returns home — a *suggestion*, never turn-by-turn.

---

## Immediate next steps

1. **Validate the complete backup on a phone** — compressed backups now include
   walks, memories/photos, settings and offline maps. Restore preserves local
   items and only replaces settings when explicitly selected. Check a round-trip
   with Android document providers; persistent-key APKs update in place.
2. **Validate pocket recording on the real phone** — screen locked and another
   app open, then Stop, force-stop recovery, notification refusal and GPS disabled.
   Target a one-hour walk with no unexplained moving gaps over 30 seconds and
   ≤5 percentage points battery use, compared with idle; see the
   [acceptance protocol](SCREEN_OFF_RECORDING.md).
3. **Field matching quality** — evaluate parallel streets, crossings, park paths
   and weak GPS against actual walks. Preserve uncertain gaps rather than falsely
   colouring neighbouring streets. Motion/direction confirmation, poor-accuracy
   rejection and configurable Detailed GPS are implemented; the junction
   regression and synthetic Bremen results are documented in
   [matching evidence](MATCHING_EVIDENCE.md). Actual exported phone traces remain
   the next validation step.
4. **Map download reliability** — large/dense areas, clear progress/failure handling
   and an explicit fresh-location option before selecting download bounds.
5. **Memories field check** — test GPS and manual pins, photos, drafts and restore
   on a real phone. Multiple photos, search/tags and individual sharing are future work.
6. **Map presentation** — street/place labels and clearer area names are implemented.
   Refresh older downloads for place labels and automatic area naming. Evaluate
   MapLibre/PMTiles against the existing offline renderer before adopting it.

---

## Open questions

Tracked here until decided; each blocks the phase noted.

- **Screen-off field result** — sustained trace quality and battery consumption
  on the actual Android phone. Initial foreground smoke testing is complete. *(Phase 1)*
- **Onboarding field check** — local map setup and optional pre-setup GPX import
  are implemented; verify the permission/download flow on new users’ phones. *(Phase 1)*
- **The completeness denominator** — what counts as "walkable" in an area (both
  sides of a divided road? park paths absent from OSM? private roads?). Directly
  shapes the completeness %. *(Phase 2)*
- **Find types** — which OSM POIs are worth collecting. *(Phase 2)*
- **Exploration-suggestion routing** — the one routing-adjacent feature.
  *(Phase 4)*
- **License** — AGPL is currently in the repo but may not fit a client that never
  talks to a server. *(see [ADR-0006](adr/0006-license.md))*

---

## Explicitly *not* on the roadmap

These are permanent non-goals, not backlog. See
[Design Spec §Non-goals](DESIGN.md#non-goals-deliberately-excluded).

- Leaderboards / social ranking · required cloud sync · accounts & logins · ads,
  analytics, telemetry · turn-by-turn navigation.

## Latest phone-feedback slice

Implemented calm-by-default recording details with persisted settings, live street
colour and section counts during walks, offline decorative parks/water with
refresh for older downloads, configurable finer lines and 1–25 km map sides. See [calm walking](CALM_WALKING.md).

### Optional gap filling (implemented)

Settings → Fill small gaps conservatively interpolates short, uniquely connected
missing sections between confirmed streets. Applies to live and saved walks;
turning it off removes the extra estimates. Synthetic routes and native
persistence tests pass; the next field check is the same walk with the setting
on/off, comparing recovered gaps against the route actually walked. See
[MATCHING_EVIDENCE.md](MATCHING_EVIDENCE.md#optional-short-gap-interpolation).

### Walk review and offline labels (implemented)

Saved walks now open a read-only review map with independent GPS trace, directly
matched streets and dashed inferred-connection layers. Gap filling can be
previewed without changing saved coverage. Street labels work with existing map
data; new/refreshed downloads add place and landmark names and readable area
names. See [WALK_REVIEW.md](WALK_REVIEW.md). Next: use exported phone traces and
this review screen to identify remaining matching errors; validate label density
and readability on the actual phone.

### Location-based first launch (implemented)

Fresh installs start with local map setup. Bremen is no longer selected or shown
as a default map. Existing downloaded maps open offline, with saved walks retained.
Location permission, map size and download are explicit steps; map-free review,
import, deletion recovery and ongoing Stop/save controls remain available.
See [NEARBY_MAPS.md](NEARBY_MAPS.md#first-launch-and-no-map-state).

### Complete backups and manual memory pins (implemented)

Backups now use a checksummed version-3 JSON bundle compressed with gzip and
include settings and offline maps. Legacy JSON walk-only and memory backups still
restore. A preview lets users omit maps and opt into replacing settings; capacity
or write failures roll back the entire restore. Existing map selection is kept.
The expanded archive remains limited to 128 MiB (80 MiB of photos).

Memory editors offer **Choose on map** across the main map, library and walk
review. Selection uses downloaded maps with pan/zoom, confirmation and cancel;
manual pins do not claim GPS accuracy. A note or photo is still required.

The latest synthetic matching rerun covered 18 five-metre-sampling cases, with
and without gap filling: no false-positive edges; noisy-route coverage gaps
remain. Actual exported phone traces are still needed before further tuning.

### Clearer repeat-visit heatmap (implemented)

The warm colour scale now reserves most contrast for the first ten distinct
walks, making 1, 2, 5 and 10 visits easier to distinguish. Higher counts continue
to deepen through 1,000. Tap the existing street-count button for a scrollable
legend; Settings uses the same 1/2/5/10/100 key. Matching, visit counts and stroke
widths are unchanged. Check the early-visit contrast on the actual phone outdoors.

### Walk history and favourites (implemented)

“Saved walks” is now “Walk history”. Every recorded trip remains part of the
heatmap without an automatic GPX export. Optional stars and a Favourites filter
keep memorable walks easy to find. Favourite status persists locally and in full
backups; restoring into existing history keeps local choices. Filtering does not
limit backup contents or affect counts, matching, or raw GPS data.
