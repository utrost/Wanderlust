# ADR-0007: "Fog of war" as an optional reveal lens ("Uncharted"), not a default

- **Status:** Proposed
- **Date:** 2026-07-11

## Context

A recurring suggestion for map/exploration apps — and one raised for Wanderlust —
is **fog of war**: the map starts hidden under a dark mask, and walking reveals
it. The appeal is real. Revealing is a stronger short-term reward than
accumulating, "developing" a hidden world is satisfying, and it would make the
GPX-import moment (see [DESIGN.md §4](../DESIGN.md#4-feature-set)) go from "watch
it fill" to "watch it *light up*."

But classic fog of war collides with the stance the whole product traces back to
([DESIGN.md §1](../DESIGN.md#1-philosophy)):

- **It hides the gaps.** The core loop is *invitation, not instruction* — "the
  map already shows your gaps." The "Inviting an unwalked street" flow depends on
  you *seeing* a nearby street you've never walked and being tempted. A dark mask
  conceals precisely the street the app wants to offer you.
- **It inverts the emotional register.** Wanderlust's mechanic is **additive** —
  warm ink accumulates on a calm, always-visible paper map, and "an almost-empty
  map should feel like an invitation." Fog of war is **subtractive** — the world
  is a void you must earn back. Same data, opposite feeling.
- **The metaphor is the wrong one.** "Fog of war" is RTS/military vocabulary —
  concealed enemy territory, revealed for competitive advantage. That is the
  exact register ("Not Strava. Collecting, not competing.") the product defines
  itself against. Even setting the mechanic aside, the framing pulls toward
  conquest and completionist pressure, which the design deliberately excludes.

So the question is not "reveal or don't," but whether there is a version of the
reveal delight that serves the stance instead of undermining it.

## Decision

We will **not** ship classic fog of war — a dark mask that hides unwalked ground
— as the default or the only map.

We will explore, and tentatively adopt, an **optional reveal lens** with three
properties that reconcile it with the philosophy:

1. **Mist, not blackout.** Unwalked ground sits under a soft, pale cartographer's
   *mist* (a warm parchment haze, not black). Streets stay **faintly legible**
   through it — the map still invites rather than conceals. Walking clears the
   haze into full ink; the cleared corridor widens with the segment's walk count,
   so a daily route opens a broad swath and a one-off walk opens a thread.
2. **A lens, not the mode.** It is a **third position on the Streets ↔ Memories
   toggle**, never the default. The default stays the calm ink-on-paper map. The
   reveal view is there for the person who wants that particular delight.
3. **Tied to completeness we already have.** As an area approaches 100%, its
   remaining mist **burns off** and the existing "claimed" seal
   ([DESIGN.md §3](../DESIGN.md#3-gamification--personal-only)) can land. The
   reveal folds into the nested-completeness mechanic rather than bolting on a
   parallel game.

We will **rename it** away from "fog of war." Working name: **Uncharted** (the
map draws itself in) — a *terra incognita* / cartographer framing, consistent
with the README's "cartographer of your own world," not a battlefield.

A working visual prototype of all three life stages (light and dark) lives at
[`design/mood-map/`](../../design/mood-map/) under the "Uncharted" section, so
the tradeoff can be judged by eye rather than in the abstract.

## Consequences

- **Easier / wins:** A genuinely strong "wow" moment, especially in dark mode
  (glowing trails emerging from darkness) and at GPX import. It reuses the
  existing walk-count data and completeness structure — no new mechanic to
  balance, and (below) no new sensitive data.
- **Privacy: unchanged.** The "revealed" area is *derived* by buffering the GPS
  tracks already stored on-device; it is new rendering, not new data, and does
  not touch the offline/local-first model ([ADR-0004](0004-local-first-no-cloud.md)).
- **Harder / knowingly accepted:**
  - *Completionist pressure.* Any reveal mechanic nudges toward "clear the
    board." Keeping it opt-in and non-default is the guardrail; if the lens
    starts to feel like an obligation in testing, that is a signal to cut it, not
    to soften it.
  - *A render layer.* The mist is a feathered mask over the basemap; it must stay
    cheap and legible at map zoom levels on real tiles, not just on the mock
    street grid. Feasibility on MapLibre + PMTiles
    ([ADR-0005](0005-offline-rendering-maplibre-pmtiles.md)) is unproven and is
    the main open risk.
  - *Denominator coupling.* "Mist burns off at 100%" inherits the unresolved
    completeness-denominator question
    ([DESIGN.md §3](../DESIGN.md#3-gamification--personal-only),
    [ROADMAP open questions](../ROADMAP.md#open-questions)): what counts as
    "walkable" here decides when the haze can ever fully clear.
- **Follow-up:** validate the reveal against real tiles and confirm it reads as
  *invitation* (streets still legible through mist), not concealment; decide
  whether the burn-off is tied to the same denominator as the completeness
  percentage; settle the name.

## Alternatives considered

- **Classic dark fog, on by default** — hides the gaps, inverts the invitation,
  and imports the competitive "conquest" framing; contradicts
  [DESIGN.md §1](../DESIGN.md#1-philosophy) directly. Rejected.
- **Reveal as the only map** (replacing the paper map) — throws away the calm,
  keepsake default that is the product's signature, for a single mechanic.
  Rejected; the reveal is a lens, not the foundation.
- **Do nothing** — safe, and defensible, since the filling map already rewards
  exploration. But it leaves a strong, cheap-to-derive delight on the table,
  particularly for import. Deferred rather than rejected: worth prototyping
  (done) before committing.
- **Hard "spotlight" radius around the walker** (a crisp cleared circle, common
  in step-counter games) — reads as a game HUD and produces ugly hard edges over
  a paper map. Rejected in favor of the feathered, per-street mist, which keeps
  the cartographic tone.
