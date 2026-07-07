# Wanderlust — Architecture

How Wanderlust is built, and — just as important — the risks that shape those
choices. For the product rationale behind any of this, see the
[Design Spec](DESIGN.md). Individual decisions are recorded as
[ADRs](adr/README.md).

---

## Guiding principle: separate a hard core from the surface

Two things in this app are genuinely tricky and platform-specific:

1. **Background GPS** — recording location reliably while the phone is asleep.
2. **Map-matching** — turning noisy GPS into per-segment walk counts.

Everything else (the filling map, counters, finds, notes) is "just app."

So: build the **geo logic as a standalone, platform-agnostic core**, and hang a
thin per-platform UI + sensor layer on top. The iOS step later becomes a veneer,
not a rewrite.

```
        ┌─────────────────────────────────────────────┐
        │   Per-platform surface (thin)               │
        │   • UI (map, counters, finds, notes)        │
        │   • Sensor + background-location adapters    │
        │   • File pickers, permissions               │
        └───────────────────┬─────────────────────────┘
                            │  FFI / plugin boundary
        ┌───────────────────▼─────────────────────────┐
        │   Geo-core (platform-agnostic)              │
        │   • Map-matching (snap + graph fill)        │
        │   • Per-segment counting                    │
        │   • Routing graph load / query              │
        │   • Import (GPX) / export (GeoJSON, GPX)    │
        └───────────────────┬─────────────────────────┘
                            │
        ┌───────────────────▼─────────────────────────┐
        │   Storage: SQLite  +  PMTiles (per area)    │
        └─────────────────────────────────────────────┘
```

---

## Platform order: Android first, iOS later

Android is the friendlier first platform for a sensor/map/background-location
app (fewer restrictions on background GPS, freer file handling). Because the
geo-core is reusable, iOS becomes an add-on rather than a second build. See
[ADR-0002](adr/0002-android-first-ios-later.md).

---

## Map-matching

**Goal:** answer "which streets did I plausibly walk, and how often" — *not*
navigation-grade reconstruction.

Running a full HMM matcher (Valhalla/GraphHopper-class) on a phone is hard and
unnecessary here. While walking, sampling is dense, so a pragmatic approach is
usually enough:

1. **Snap** each GPS point to the nearest OSM edge within a tolerance.
2. **Fill** between two consecutive snaps along the graph with the shortest path.

This is orders of magnitude simpler than true HMM matching and sufficient for a
personal art map. It removes the project's single biggest risk and can be
upgraded later. Full rationale: [ADR-0001](adr/0001-pragmatic-map-matching.md).

### Guardrail: don't paint streets you didn't walk

Because the filling map *is* the reward, **false positives are the worst failure
mode** — a lit street you never walked corrupts the whole premise, and the paint
is permanent. Shortest-path fill quietly assumes people walk shortest paths, but
flâneurs (the target user) don't. If GPS drops for a stretch, naive fill can
paint a straight diagonal that was never walked.

Mitigation, part of the core matching contract:

- Compare the **graph distance** between two snaps against the **distance implied
  by elapsed time** (a plausible walking speed). If the graph path is far longer,
  **leave a gap** rather than guess.
- Bound the maximum gap that fill will bridge; beyond it, treat as a track break.
- Prefer under-painting to over-painting when uncertain.

---

## Background GPS — a first-class risk

Reliable background location is arguably a *bigger* make-or-break than
map-matching: a walking app that drains the battery dies on contact with real
use, and both Android (Doze / background-location limits) and iOS have tightened
here over time.

Design consequences:

- Adaptive sampling (denser while clearly moving, sparser when still).
- Batch writes; avoid waking the CPU per fix.
- Treat "app was killed mid-walk" as normal: persist incrementally so a walk is
  never lost.
- Measure battery cost as an explicit acceptance criterion, not an afterthought.

Verify current platform constraints and background-location package maturity
before committing — this space moves quickly.

---

## Stable building blocks (independent of stack choice)

- **Offline map rendering:** MapLibre Native rendering from a regional **PMTiles**
  file. No tile server. See
  [ADR-0005](adr/0005-offline-rendering-maplibre-pmtiles.md).
- **Offline matching:** an on-device **routing graph** per region, downloaded once
  at first use.
- **State:** **SQLite** — `edge_id → count`, plus walks (list of edges +
  timestamp), finds, notes/photos.
- **Portability:** export as GeoJSON / GPX, backup via git or your own server.

---

## Stack

Leaning order, to be confirmed against current maturity:

1. **Flutter** *(leading)* — one codebase, a `maplibre` plugin, usable
   background-location packages. Best compromise for "Android now, iPhone later
   almost for free." Trade-off: the geo-core is written in Dart or wired in via
   FFI — and for the compute-heavy geo math, a native (e.g. Rust) core via FFI is
   the more defensible choice than pure Dart. See
   [ADR-0003](adr/0003-flutter-with-native-geo-core.md).
2. **Kotlin + Compose (possibly Compose Multiplatform)** — idiomatic Android,
   native quality, core shareable as a Kotlin module. The iOS path via Compose MP
   exists but is the shakier route — check current maturity before committing.
3. **React Native** — appealing given React experience; MapLibre binding exists.
   But background GPS + compute-heavy geo processing are least pleasant in JS. Not
   the first choice for *this* app.

> Stack maturity (especially Compose Multiplatform for iOS and
> background-location packages) moves quickly — verify the current state before
> committing.

---

## Data model (sketch)

- **edges** — OSM ways split at their nodes into short segments.
- **edge_counts** — `edge_id → count` (drives color / width).
- **walks** — one record per walk: the list of edges touched + a timestamp
  (enables undo, time-lapse, "this week" filters).
- **finds** — collected POIs (type + location + date collected).
- **notes / photos** — pinned to a position or a find, with a date. Local only.

```
edges (id, geometry, osm_way_id, ...)
edge_counts (edge_id → count)          -- 1:1 with edges that have been walked
walks (id, timestamp, ...)
walk_edges (walk_id, edge_id)          -- many:many; lets a walk be undone
finds (id, type, location, collected_at)
notes (id, location | find_id, body, photo_ref, created_at)
```
