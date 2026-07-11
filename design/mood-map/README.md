# Wanderlust — Mood &amp; Map

A faithful, dependency-free implementation of the **Wanderlust Mood &amp; Map**
visual-direction canvas, exported from [Claude Design](https://claude.ai/design)
as a handoff bundle and re-created here as a plain, runnable web page.

Open `index.html` in any browser — no build step, no server, no dependencies.

## What it shows

The v1 visual direction for Wanderlust — a warm, single-hue "ink on paper" map
that fills in as you walk. Sections:

- **Foundations** — the logarithmic walk-count colour ramp (light, dark, and a
  desaturated colour-vision check), quiet basemap tones, and type.
- **The filling map** — the signature moment: the same Kreuzberg street network
  at three points in a walking life (first week → a few months → two years), in
  both light and dark.
- **Uncharted** — an exploration of the "fog of war" idea, reframed on-brand: a
  soft cartographer's mist over unwalked ground (streets stay faintly legible,
  so it still invites) that clears into full ink as you walk. Shown at the same
  three life stages, light and dark, as an optional third view — not the default.
  Design rationale: [ADR-0007](../../docs/adr/0007-fog-of-war-optional-reveal-lens.md).
- **Notes &amp; photos** — the memory layer: browsing, opening, and pinning notes.
- **Choosing a home area** — first-run onboarding: search, confirm a boundary,
  download offline, or draw your own area.
- **Inviting a walk you haven't taken** — three quiet nudges toward a nearby,
  never-walked street (notification, in-context map hint, browsable list), using
  a dashed amber "known but unwalked" thread.

## Structure

| File | Role |
| --- | --- |
| `index.html` | Page shell — fonts, background, sparkle keyframes, mounts the canvas. |
| `map-data.js` | Heat-ramp functions (`rampWidth` / `rampColor` / `rampGlow`) and the seeded 264-segment street network, each segment carrying week/month/year walk counts. Ported verbatim from the design bundle. |
| `android-frame.js` | `androidFrame(opts, innerHTML)` — a Material-3 device bezel (status bar + gesture nav) that wraps each screen. |
| `app.js` | Builds the canvas: replaces the design tool's `<x-dc>` template directives (`sc-for`, `sc-if`, `x-import`) with plain DOM assembly. |

## Provenance

Source: Claude Design project *"Wanderlust visual design brief"*, primary file
`Wanderlust Mood & Map.dc.html`. The colours (OKLCH), geometry, and copy are
reproduced from that source; the proprietary runtime (`support.js`, `.dc.html`
directives, the React `android-frame.jsx`) is replaced with vanilla equivalents
so the page runs anywhere.
