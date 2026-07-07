# ADR-0001: Pragmatic map-matching (snap + graph fill), not HMM

- **Status:** Accepted
- **Date:** 2026-07-07

## Context

Wanderlust's core mechanic is a per-segment walk count: each walk must be turned
into "which OSM street segments did I plausibly traverse, and how often." Raw GPS
polylines are too noisy to answer "how often" cleanly, so some form of
map-matching is required.

The gold-standard approach is a Hidden Markov Model matcher (the class of
algorithm inside Valhalla / GraphHopper). Running that on-device is hard,
compute-heavy, and navigation-grade — more than a *personal art map* needs. This
matching problem is one of the two biggest technical risks in the project (the
other is background GPS), so reducing it is high-leverage.

Key context: while walking, GPS sampling is dense, which makes a simpler approach
viable most of the time.

## Decision

Use a pragmatic two-step matcher in the geo-core:

1. **Snap** each GPS point to the nearest OSM edge within a distance tolerance.
2. **Fill** between two consecutive snaps along the routing graph using the
   shortest path.

Treat this as the v1 contract, explicitly upgradeable to a full HMM matcher later
without changing the data model.

**Correctness guardrail (part of the decision, not optional):** because the
filling map *is* the reward, a lit street that was never walked is the worst
failure mode, and the paint is permanent. Shortest-path fill assumes people walk
shortest paths; flâneurs — the target user — do not. Therefore:

- Compare graph distance between two snaps to the distance implied by elapsed
  time at a plausible walking speed; if the graph path is far longer, **leave a
  gap** instead of guessing.
- Bound the maximum gap that fill will bridge; beyond it, treat as a track break.
- When uncertain, **under-paint rather than over-paint.**

## Consequences

- **Easier:** dramatically simpler than HMM; feasible on-device; removes the
  project's biggest algorithmic risk; small enough to validate on real GPX in
  Phase 0.
- **Harder / accepted risk:** lower accuracy than HMM in ambiguous geometry
  (dense grids, parallel ways, tunnels). The guardrail trades some coverage
  (occasional gaps) for trust (no phantom streets) — the right trade for an art
  map.
- **Follow-up:** the matcher must be validated against messy, meandering traces,
  not just clean ones, before Phase 1.

## Alternatives considered

- **Full on-device HMM matcher** — most accurate, but heavy, complex, and
  overkill for the use case; rejected as v1, kept as a possible upgrade.
- **Raw GPS polylines, no matching** — can't answer "how often" per street and
  looks noisy on the map; defeats the core mechanic.
- **Server-side matching** — accurate and easy to run, but violates the
  local-first, never-phone-home stance ([ADR-0004](0004-local-first-no-cloud.md)).
