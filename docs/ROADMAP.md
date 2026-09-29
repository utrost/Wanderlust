# Wanderlust — Roadmap

A phased plan from nothing to a lifetime map. Ordering follows the architecture:
**de-risk the geo-core first, wrap platforms around it, defer routing.** See
[ARCHITECTURE.md](ARCHITECTURE.md).

Status legend: 🔴 not started · 🟡 in progress · 🟢 done.

Current status: **pre-alpha scaffold**. The core map-matching spike, FFI bridge,
Flutter surface, foreground walk recorder, and CI-built Android debug APK exist.
The saved-walk → real Bremen street coverage loop now exists and passes a
host-native integration test. Device validation and the richer offline basemap
remain open; see [slice evaluation](BREMEN_SLICE.md). GPX import, per-walk GPX
export, and JSON backup/restore are implemented and tested locally; see
[import/export](IMPORT_EXPORT.md).

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
  correct street ids out) on a real-coordinate sample. Still to validate on real
  OSM data and messy/flâneur GPX.
- 🟢 **Routing graph** load + query for Bremen center, using an OSM-derived
  network with explicit node topology and stable ids.
- 🟡 **Tile/data pipeline**: reproducible OSM extraction, conservative pedestrian
  filtering, normalized street GeoJSON, and synthetic matching evaluation exist.
  Planetiler/PMTiles integration and field validation remain pending
  ([#6](https://github.com/utrost/Wanderlust/issues/6)).
- 🔴 **PMTiles + MapLibre** render of one area, offline
  ([#8](https://github.com/utrost/Wanderlust/issues/8)).
- 🟡 **Real-device debug APK smoke test**: installation, launch, FFI load,
  permission prompt, and an initial GPS fix confirmed on Android. Full outdoor
  recording/coverage and updated location controls still need field validation
  ([#5](https://github.com/utrost/Wanderlust/issues/5)).

**Exit criteria:** choose one real area, render it offline, feed a GPX file in →
correct per-segment counts out, no phantom streets.

## Phase 1 — Walkable MVP (Android) 🟡
The smallest thing that delivers the core joy: walk → map fills.

- 🟡 **GPS recording** — foreground recording (a walk as a live GPS trace with
  duration/distance, exportable as GPX) is implemented in the app. *Background*
  recording with adaptive sampling + battery budget as an explicit acceptance
  criterion (see [Architecture](ARCHITECTURE.md#background-gps--a-first-class-risk))
  is still the open, first-class risk.
- 🟡 **Persistent walk state**: raw walks now use a SQLite recording journal
  with interruption recovery and save retries. Per-walk edge memberships and
  durable counts and GPX imports are implemented for the bundled network
  ([#7](https://github.com/utrost/Wanderlust/issues/7)).
- 🟡 **Filling map**: persisted counts now drive real Bremen street color/width
  after saving a walk. Live location/accuracy marker, recenter, area reset, and
  GPS HUD are implemented. Continuous updates during recording and the richer
  PMTiles basemap remain pending
  ([#7](https://github.com/utrost/Wanderlust/issues/7)).
- 🟡 **Area selection**: GPS-centered 4 × 4 km street downloads, persistent
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

1. **Real-device APK smoke test** — download the latest `wanderlust-debug-apk`
   CI artifact and sideload it on Android. Verify launch, FFI status chip,
   permission request, foreground recording, distance/point updates, stop, and
   [import/export/backup document dialogs](IMPORT_EXPORT.md#phone-acceptance-checks)
   ([#5](https://github.com/utrost/Wanderlust/issues/5)).
2. **First real test area** — use **Bremen center**, anchored on the Roland /
   Marktplatz (`53.0759058, 8.8073262`) with an initial 1.5 km radius bbox
   (`8.784897,53.062431,8.829756,53.089380`) for the OSM extract → PMTiles +
   street GeoJSON pipeline proof (the street snapshot is now bundled and tested)
   ([#6](https://github.com/utrost/Wanderlust/issues/6)).
3. **Offline render proof** — load that PMTiles file through MapLibre in the app
   ([#8](https://github.com/utrost/Wanderlust/issues/8)).
4. **Validate recorded walk to counts on device** — the implementation and
   real-FFI integration test exist; verify actual GPS → saved counts → redraw
   ([#7](https://github.com/utrost/Wanderlust/issues/7)).
5. **Background GPS spike** — only after the foreground loop works, measure
   screen-off recording, app-kill resilience, trace quality, and battery drain
   ([#9](https://github.com/utrost/Wanderlust/issues/9)).

---

## Open questions

Tracked here until decided; each blocks the phase noted.

- **Android smoke-test result** — whether the CI-built APK actually loads the
  native geo-core and records foreground GPS on Uwe's device. *(Phase 0)*
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
colour and section counts during walks, and offline decorative parks/water with
refresh for older downloads. See [calm walking](CALM_WALKING.md).
