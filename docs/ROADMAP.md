# Wanderlust — Roadmap

A phased plan from nothing to a lifetime map. Ordering follows the architecture:
**de-risk the geo-core first, wrap platforms around it, defer routing.** See
[ARCHITECTURE.md](ARCHITECTURE.md).

Status legend: 🔴 not started · 🟡 in progress · 🟢 done. Phase 0 is underway —
the geo-core map-matching spike and its guardrail are implemented and tested.

---

## Phase 0 — Foundations 🔴
Prove the risky pieces in isolation, before any polished app.

- 🟢 **Geo-core skeleton** (platform-agnostic): data model, SQLite schema
  ([`geo-core`](../geo-core/)).
- 🟡 **Map-matching spike**: snap-to-edge + shortest-path fill, *with the
  don't-paint-what-you-didn't-walk guardrail* (see
  [ADR-0001](adr/0001-pragmatic-map-matching.md)). Implemented and unit-tested on
  synthetic networks; still to validate on real GPX traces, including
  messy/flâneur ones.
- 🟡 **Routing graph** load + query for one region. Build + Dijkstra done;
  region loading pending.
- 🔴 **PMTiles + MapLibre** render of one area, offline.

**Exit criteria:** feed a GPX file in → correct per-segment counts out, no
phantom streets.

## Phase 1 — Walkable MVP (Android) 🔴
The smallest thing that delivers the core joy: walk → map fills.

- 🔴 **Background GPS recording** with adaptive sampling + battery budget as an
  explicit acceptance criterion (see [Architecture](ARCHITECTURE.md#background-gps--a-first-class-risk)).
- 🔴 **Live filling map**: counts drive color + width (faint/thin 1× →
  saturated/broad 20×).
- 🔴 **Area selection**: admin boundary or drawn rectangle; per-area PMTiles.
- 🔴 **GPX import** — the onboarding wow-moment; prioritized early so first run
  isn't a blank map.
- 🔴 **Export**: GeoJSON (with `count`), GPX, ZIP backup.

**Exit criteria:** a real person can pick an area, import history, walk for a
week, and watch their map fill — fully offline.

## Phase 2 — The life map 🔴
Turn the heatmap into a keepsake.

- 🔴 **First-time sparkle** on never-walked streets.
- 🔴 **Nested completeness**: street → neighborhood → district → city, with a
  "claimed" seal. Depends on resolving the *completeness denominator* question.
- 🔴 **Finds**: collectible POIs from OSM.
- 🔴 **Notes & photos** pinned to positions / finds (local only).
- 🔴 **Multiple areas** (the "passport").

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

## Open questions

Tracked here until decided; each blocks the phase noted.

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
