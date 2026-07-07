# Wanderlust — User Guide

> **Note:** Wanderlust is pre-alpha and not yet buildable. This guide describes
> the intended experience so contributors and early readers share one picture of
> the app. It will become the real user manual as features land.

For the reasoning behind these choices, see the [Design Spec](DESIGN.md).

---

## The idea in one minute

You walk. Wanderlust quietly records where you went and paints those streets onto
a map of your city. Walk a street once and it glows faintly. Walk it again and
again and it grows brighter and thicker. Over time the map fills in — a portrait
of everywhere your feet have taken you.

There is no goal handed to you, no pace to beat, no streak to keep. The only
thing that grows is your own map.

---

## Getting started

### 1. Pick your area
On first run you choose a **home area** — the place you want to fill in. You can
pick it by:

- an **administrative boundary** (your city or district), or
- a **rectangle you draw** on the map.

Wanderlust downloads a compact offline map for just that area (roughly tens to a
low-hundreds of MB for a city in street detail). No planet download, no tile
server, and it works with no signal afterward.

### 2. (Optional) Import your history
If you already have years of walks in **Strava, Komoot, or Garmin**, export them
as GPX and import them here. Your map fills in *instantly* — you start with the
territory you've already covered instead of a blank slate.

### 3. Walk
Start a walk and put your phone away. Wanderlust records in the background and
snaps your route onto the real streets you plausibly walked, adding to each
street's count.

---

## What you'll see

- **A filling map.** Streets you've walked are lit. The more often you've walked
  one, the brighter and wider it is.
- **First-time sparkle.** The first time you ever set foot on a street, it briefly
  shimmers — a small nudge toward the alleys you'd normally skip.
- **Claimed areas.** Fully walk a neighborhood or district and it earns a subtle
  seal, like a passport stamp. There's no time limit — the map waits.
- **Your completeness.** A percentage for *your* chosen area only. It's never
  compared to anyone else; the only benchmark is your past self.

---

## Collecting & remembering

### Finds
As you explore, you can collect small treasures the map knows about — fountains,
viewpoints, benches, monuments, old trees. They become a personal cabinet of
curiosities of your surroundings.

### Notes & photos
Pin a note or a photo to a spot (or to a find), with a date. This turns the
heatmap into a **life map** — a memory layer over the streets. Photos and notes
stay on your device.

---

## Exploration suggestions *(planned / optional)*

If you want a nudge, Wanderlust can suggest a **loop from where you are** that
grazes as much unwalked ground as possible and brings you home. It's a
suggestion to glance at — never a turn-by-turn command. You're free to ignore it
and wander.

---

## Your data is yours

- **No account, no login.** Nothing to sign up for.
- **Nothing leaves your phone.** No ads, no analytics, no telemetry. Your
  location history stays local.
- **Always exportable:**
  - **GeoJSON** — walked segments with a walk `count`, viewable in any GIS tool.
  - **GPX** — your raw tracks, for other apps or archives.
  - **Full backup (ZIP)** — everything, including photos and notes. Git-friendly,
    so you can back it up to your own server or repo.

If you ever want to leave, you take everything with you. That's the point.

---

## Multiple maps (the "passport")

Your home area is your main collection, but you can add **travel areas**: a city
you visit becomes its own little map with its own completeness percentage — a
stamp in your passport. Each area is a separate offline map, loaded on demand.
