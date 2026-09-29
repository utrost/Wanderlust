# Wanderlust — Roadmap

A phased plan from nothing to a lifetime map. Ordering follows the architecture:
**de-risk the geo-core first, wrap platforms around it, defer routing.** See
[ARCHITECTURE.md](ARCHITECTURE.md).

Status legend: 🔴 not started · 🟡 in progress · 🟢 done.

Current status: **Android pre-alpha in field testing**. The core walk → street
colour loop has been confirmed on the tester's phone. Offline maps, GPS controls,
live colouring, parks/water, calm settings, adjustable line width and 1–25 km
map sides are implemented. GPX import/export and raw-walk backup/restore exist.
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
  durable counts and GPX imports are implemented across bundled and downloaded networks
  ([#7](https://github.com/utrost/Wanderlust/issues/7)).
- 🟢 **Filling street map**: live provisional colour/section counts, saved counts,
  GPS marker/recenter, calm optional details and adjustable line thickness exist.
  Parks and water render offline; labels and richer basemap styling remain open.
- 🟡 **Area selection**: GPS-centered 1–25 km-per-side street downloads (4 km default), persistent
  offline map picker, and per-area coverage implemented. Admin boundaries, drawn
  rectangles, and per-area PMTiles remain open. See [nearby maps](NEARBY_MAPS.md).
- 🟢 **GPX import** — document picker, strict validation, segment/time preservation,
  duplicate detection, and coverage updates. Native phone picker validation pending.
- 🟡 **Export and backup** — per-walk GPX and versioned JSON backup/merge restore
  implemented, including atomic restore and corruption checks. GeoJSON with
  counts and compressed/streaming ZIP archives remain open.
  See [behavior and acceptance checks](IMPORT_EXPORT.md).

**Exit criteria:** a real person can pick an area, import history, walk for a
week, and watch their map fill — fully offline.

## Phase 2 — The life map 🔴
Turn the heatmap into a keepsake.

- 🔴 **First-time sparkle** on never-walked streets.
- 🔴 **Nested completeness**: street → neighborhood → district → city, with a
  "claimed" seal. Depends on resolving the *completeness denominator* question.
- 🔴 **Finds**: collectible POIs from OSM.
- 🔴 **Notes & photos** pinned to positions / finds (local only).
- 🟡 **Multiple areas**: eight downloadable street maps plus the bundled map;
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

1. **Migrate to the persistent-key APK** — existing temporary-key installs need
   one final backup/reinstall/restore. Subsequent builds update in place; do not
   uninstall between them. See [Android updates](ANDROID_UPDATES.md).
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
5. **Backup completeness and phone dialogs** — include settings and optionally
   offline maps; exercise Android import/export/restore selectors on device.
6. **Map presentation** — street/place labels and clearer area names; evaluate
   MapLibre/PMTiles against the existing offline renderer before adopting it.

---

## Open questions

Tracked here until decided; each blocks the phase noted.

- **Screen-off field result** — sustained trace quality and battery consumption
  on the actual Android phone. Initial foreground smoke testing is complete. *(Phase 1)*
- **Onboarding flow** — area selection + the optional GPX-import step. *(Phase 1)*
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
