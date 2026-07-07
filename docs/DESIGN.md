# Wanderlust — Design Spec

This is the "why" behind Wanderlust. Every product and engineering decision is
meant to trace back to the stance in the first section. If a feature can't be
justified from here, it doesn't belong.

- **User Guide** (the "what it feels like"): [USER_GUIDE.md](USER_GUIDE.md)
- **Architecture** (the "how it's built"): [ARCHITECTURE.md](ARCHITECTURE.md)

---

## 1. Philosophy

The whole design follows from one stance:

> **Reward exploration and completeness, never frequency and discipline.**

- **Not Strava.** No tempo, no calorie counts, no competitive framing.
- **Serendipity over navigation.** The app invites; it never commands.
- **Collecting, not competing.** The filling map *is* the reward.
- **A life map, not a log.** Over years this becomes a portrait of how you move
  through the world — a keepsake, not a statistic.

### Non-goals (deliberately excluded)

These are not "later" — they are permanently out of scope, because each one
would undermine the stance above.

- **Leaderboards or social ranking.** We all start from different points —
  literally. A comparison would be meaningless.
- **Cloud sync as a requirement.** (Optional, self-hosted backup is fine; a
  required cloud is not.)
- **Accounts or logins.**
- **Ads, analytics, telemetry, or any form of data collection.**
- **Turn-by-turn navigation.**

---

## 2. Core mechanic

```
GPS trace  →  map-matched to OSM segments  →  per-segment walk count  →  data-driven heatmap on the street grid
```

The critical design decision is **map-matching, not raw GPS lines.** Raw GPS is
noisy and can't cleanly answer "how often." Instead, each recorded walk is
snapped onto the OSM street segments it plausibly traversed, and we keep a count
per segment. That count drives color and width when rendering — faint and thin
at 1×, saturated and broad at 20×. The result looks like a growing nervous
system of your city.

Because the *filling map is the reward*, correctness of the paint is a
first-class concern: a street lit that you never walked is worse than a street
left dark. The matching approach and its guardrails live in
[ARCHITECTURE.md](ARCHITECTURE.md#map-matching) and
[ADR-0001](adr/0001-pragmatic-map-matching.md).

---

## 3. Gamification — personal only

No competition. All of this is local and self-referential:

- **The filling map** is the primary reward. Each newly lit street is a small
  dopamine moment, no points required.
- **Nested completeness** gives collecting structure: street → neighborhood →
  district → city. A fully walked area gets a subtle "claimed" treatment (a
  small seal). Like passport stamps, but with no time pressure — the map waits
  patiently and never nags.
- **First-time sparkle.** A never-before-walked street briefly shimmers on first
  contact, gently nudging you toward the alleys you'd otherwise skip. The game
  mechanic directly serves the flâneur idea instead of betraying it.
- **Collectible finds.** OSM is full of small treasures — fountains, viewpoints,
  benches, monuments, old trees. These can be collected as a cabinet of
  curiosities of your surroundings.
- **The lifetime map.** The long game: a memory object built over years.

Because everyone starts from a different point (dense city vs. countryside, 20
years in place vs. freshly moved in), the completeness percentage always refers
to *your* self-chosen area. The only opponent is your past self. It doesn't get
more honest than that.

> **Open design question — the completeness denominator.** "100% of an area"
> requires deciding what counts as walkable there: both sides of a divided
> boulevard? Park paths with no OSM edge? Private roads? OSM's pedestrian
> coverage is uneven, so the denominator is a real design problem, not a detail.
> Tracked in [ROADMAP.md](ROADMAP.md#open-questions).

---

## 4. Feature set

### Navigation — invitation, not instruction
No turn-by-turn. The map already shows your gaps. Optionally, an "exploration
suggestion" can generate a loop from your location that grazes as much unwalked
terrain as possible and brings you home — but as a suggestion to look at, not a
command. Nearby unwalked streets may shimmer. *(This is the only feature that
edges toward routing complexity — flagged as later/optional; see the roadmap.)*

### Maps — several, but deliberately bounded
A home area as the main collection, plus optional travel areas (the "passport"
idea: a foreign city becomes its own little map with its own percentage). One
PMTiles file per area, loaded on demand. The user picks an area by
administrative boundary (city/district) or a drawn rectangle. No planet
download. A single city in street detail is roughly in the tens-to-low-hundreds
of MB range.

### Notes & photos pinned to places
Pin a note or photo to a position (or to a find), with a date. This is the step
from heatmap to *life map* — the map gains a memory layer instead of being mere
statistics. Photos stay local. Emotionally, this is what lifts the app beyond
"nice tracker."

### Export — and its often-forgotten twin, Import
- **Export** (mandatory for OSS + data ownership): walked segments as GeoJSON
  (with a `count` property, visualizable anywhere), raw tracks as GPX, and a full
  backup as a ZIP including photos and notes. Git-friendly.
- **Import** is the stronger move: anyone with years of GPX archives (Strava,
  Komoot, Garmin) reads in their history and sees the map fill *instantly* — a
  real wow-moment at onboarding instead of starting from zero.

None of these features break the offline/privacy model. Everything stays local.

---

## 5. Data ownership

No account, no login. Your data lives as local files (SQLite / GeoJSON), always
exportable. The app never phones home. Location data is the most sensitive thing
an app can know about you — where you live, when you're away, your habits. A
walking app that *never* sends that anywhere is the exact opposite of the
incumbents, and Wanderlust's strongest distinguishing trait. See
[ADR-0004](adr/0004-local-first-no-cloud.md).
