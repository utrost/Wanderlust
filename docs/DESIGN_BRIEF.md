# Wanderlust — Visual & UX Design Brief

A briefing for the designer. This document says what to design and the
constraints it must respect; it does **not** dictate final visual solutions —
those are your craft. Where it proposes a direction (e.g. a colour intent), treat
it as a starting hypothesis to pressure-test, not a spec.

**Read first for context:** [DESIGN.md](DESIGN.md) (the product's soul) and
[USER_GUIDE.md](USER_GUIDE.md) (the flows in plain language). This brief assumes
both.

---

## 1. In one line

Wanderlust colours in the real streets you've walked. The filling map is the
whole reward. **Design a keepsake, not a dashboard.**

---

## 2. Who it's for

- People who walk to *wander*, not to train — the flâneur, the curious local, the
  newly-arrived resident learning a city on foot.
- Not athletes. Anyone who opens this expecting pace/calories should feel, within
  seconds, that they're somewhere gentler.
- Age and tech-comfort range widely; it must feel calm and legible to a
  non-technical person, and never nag.

## 3. The feeling to hit

If a user had to describe the app in three words, we want: **quiet, personal,
alive.**

- **Quiet** — restrained, generous whitespace, nothing shouting for attention. No
  badges-in-your-face, no red notification dots, no urgency.
- **Personal** — this is *my* map, *my* memory. Warm, not clinical. It should feel
  closer to a well-made notebook or an atlas you'd keep for years than to a
  fitness app.
- **Alive** — the map *grows*. Motion is meaningful and earned (a street lighting
  up), never decorative fidget.

**Anti-references:** Strava, Nike Run Club, any leaderboard/streak/ring UI. If it
looks like it wants to make you compete or feel guilty, it's wrong.
**Adjacent references (mood, not copying):** a beautiful transit map, an
illuminated manuscript, a naturalist's specimen cabinet, passport stamps.

## 4. Design principles (decision rules)

Use these to break ties:

1. **The map is the hero.** Chrome recedes; the street network and its colour own
   the screen. When in doubt, remove UI.
2. **Reward, never pressure.** Celebrate progress; never manufacture a deficit
   ("you haven't walked in 3 days" is banned).
3. **Earned motion.** Animation marks a real event (first-time sparkle, an area
   getting claimed). Nothing loops or pulses just to look busy.
4. **Honest to the individual.** No comparison to others, ever, anywhere in the
   UI. The only reference point is the user's own past.
5. **Calm defaults, quiet depth.** Simple on the surface; power (import, export,
   multiple areas) tucked away, discoverable, never in the face of a first-timer.

---

## 5. The signature moment (design this first)

**The filling map** is the product. Get this right and the rest follows.

- A street's **walk count drives its colour intensity and stroke width** — faint &
  thin at 1×, saturated & broad at ~20× (see the ramp brief in §6). The aggregate
  should read, in the words of the vision, like *"a growing nervous system of your
  city."*
- It must look beautiful at every stage: **an almost-empty map on day one must
  feel inviting, not depressing**, and a richly-filled map after two years must
  feel like a treasured object. Design both extremes explicitly.
- The basemap (streets, water, parks) is a quiet substrate; the *walked* overlay
  is what carries colour and life. Design the two as figure/ground.

Deliverable for this moment: mocks at **three fill levels** — first week, a few
months, multi-year — in both light and dark.

---

## 6. Visual language

Propose a cohesive system; below are the intents and hard constraints.

### Colour
- **Signature: the walk-count heat ramp.** This is the brand. Intent: a warm,
  inviting progression that feels like *ink soaking in* / *warmth accumulating* —
  not a clinical blue→red data-viz gradient, not a traffic-light scale. It should
  be pleasant across the *whole* range (a 1× street shouldn't look like an error
  state). Must remain legible over both light and dark basemaps.
- **Sequential, single-hue-family preferred** so the map reads as one growing
  organism rather than a rainbow. Perceptually smooth steps (equal visual jumps
  between counts).
- **Constraint:** distinguishable for the most common colour-vision deficiencies —
  intensity/width must carry meaning even if hue is hard to separate. (This is why
  count also drives *width*, not colour alone — lean on that.)
- Restrained UI accent palette beyond the ramp; the map supplies the colour, the
  chrome stays neutral.

### Typography
- Legible, humane, a little characterful — this is a keepsake. Avoid a sterile
  "sport-tech" typeface. One family, a few weights.
- Numbers (completeness %, counts, dates) appear often — make sure figures are
  clean and calm, never scoreboard-like.

### Iconography & the "collectibles"
- **Finds** (fountains, viewpoints, benches, monuments, old trees) are a *cabinet
  of curiosities* — design their markers and the collection view to feel like
  pressed flowers / specimen cards, not map pins from a delivery app.
- **The "claimed" seal** for a fully-walked area: a small, tasteful mark — think
  wax seal / passport stamp — that rewards without gamifying loudly.

### Motion
- **First-time sparkle:** the brief shimmer when a never-walked street is touched
  for the first time. Subtle, gone in a moment, delightful — the one nudge toward
  unexplored alleys. Design its timing and restraint carefully; overdone, it
  cheapens everything.
- **Area claimed:** a quiet, satisfying moment when a neighbourhood/district
  completes. Celebratory but soft.
- Everything else: minimal, functional transitions.

### Light & dark
- Both are first-class. The map likely looks stunning in dark (glowing streets on
  a dark field) — but light must be equally considered, not an afterthought.

---

## 7. Screen inventory (what to design)

Priority order. Flows are described in [USER_GUIDE.md](USER_GUIDE.md).

**P0 — core loop**
1. **The map (home/idle)** — the filling map at rest; how counts, "your
   completeness %", and light chrome coexist. The product's front door.
2. **Recording a walk** — the minimal, glanceable state while walking (phone
   likely pocketed); starting/stopping a walk. Battery-honest, calm.
3. **First-run / onboarding** — pick a **home area** (admin boundary *or* drawn
   rectangle), then the optional **GPX import** step (the "watch it fill
   instantly" wow-moment — make this land).

**P1 — the life map**
4. **First-time sparkle** & **area-claimed** moments (motion specs + states).
5. **Nested completeness** — how street → neighbourhood → district → city
   progress is shown without turning into a checklist/score.
6. **Finds** — collecting a find, and the **collection/cabinet** view.
7. **Notes & photos** — pinning a note/photo to a place or a find; browsing the
   memory layer.

**P2 — depth**
8. **Areas / the "passport"** — managing home + travel areas, each with its own
   map and %.
9. **Export / backup** — GeoJSON / GPX / ZIP; present data-ownership as a feature
   users feel proud of, not a settings-page afterthought.
10. **Settings** — deliberately sparse (no account exists to manage).

---

## 8. Hard constraints (non-negotiable)

- **No competitive/social UI.** No leaderboards, no comparisons, no follower
  counts — not even a placeholder. (See
  [DESIGN.md §Non-goals](DESIGN.md#non-goals-deliberately-excluded).)
- **No guilt mechanics.** No streaks, no "don't break the chain", no dormant-user
  nudges.
- **No account/login screens.** There is no account. Don't design one.
- **Offline-first & privacy-first must be *felt*.** Nothing in the UI should imply
  data leaves the device; where relevant, quietly reassure ("stays on your
  phone").
- **Android first** (iOS later) — design to Android conventions first, but keep
  the system portable; avoid anything that can't cross to iOS cleanly.
- **Accessibility:** meet WCAG AA contrast for chrome; ensure the map's meaning
  survives colour-vision deficiency (see §6); support large text sizes.

---

## 9. Deliverables

Suggested, adjust with the team:

1. **Mood / direction** — 1–2 concepts establishing tone, colour intent
   (especially the heat ramp), and type.
2. **The filling map** at three fill levels × light/dark (the §5 hero).
3. **P0 flows** as connected screens (onboarding incl. GPX import, recording,
   idle map).
4. **A component/style foundation** — colour system incl. the count ramp, type
   scale, iconography language, the find markers, the claimed seal, motion specs
   for sparkle & claim.
5. **P1 screens** once P0 direction is signed off.

Source files in a shared, inspectable format (e.g. Figma). Tokens (colour ramp
stops, type scale, spacing) documented so engineering can wire them to the
data-driven map styling.

---

## 10. What success looks like

A first-time user, on a nearly-empty map, feels *invited to go for a walk* — and a
two-year user opens the app just to **look at their map**, the way you'd open a
photo album. If both are true, the design has done its job.
