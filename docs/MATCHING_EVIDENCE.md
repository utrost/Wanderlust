# Junction matching and configurable GPS

Phone feedback showed a perpendicular street coloured during a straight walk.
The screenshot cannot identify the exact GPS cause without its exported trace.
However, a synthetic junction reproduces a weakness in the old matcher: two
consecutive noisy fixes nearest the branch immediately colour its entire section.
Repeated stationary jitter also produced coverage.

## Matching changes

The GPX/native matching path now requires:

- Consecutive, continuous support on the same street, as before.
- A projected along-street span of 20% of the section length, bounded to 2–4 m.
  Endpoint-clamped projections prevent crossing past a spur from counting as
  walking up it. Extra samples at essentially the same spot are insufficient.
- A compatible travel direction (within 45° of the local street tangent, either
  walking direction). Direction uses a 4–12 m baseline, depending on section
  length, rather than the often-noisy bearing between adjacent GPS samples.
  Backward-only context keeps the decision causal for live colouring. Context
  stops at time discontinuities, >30-second sample gaps, large timed GPS jumps,
  poor accuracy and a 60-second total horizon (60 samples for untimed imports).
- Fixes with recorded horizontal accuracy worse than 25 m are excluded from
  matching, but remain in the saved raw walk. Only the namespaced Wanderlust
  accuracy extension is read; GPX hdop is not interpreted as metres.

Direct confirmation retains the 3 m/s continuity limit. Existing strict rules
for graph fill, ambiguous parallel streets, outages and GPX segment boundaries
remain. This is still a conservative nearest-street matcher, not a guarantee
against every false snap. Gradual drift, long sections coloured from partial
travel, parallel paths and noisy coverage gaps remain field-evaluation topics.
The older positions-only spike API is unchanged; the app uses the GPX path.

The cache revision is now `motion-evidence-osm-v4`. Saved walks are rematched
automatically on synchronization. Previous derived colours can disappear, but
raw walks, maps and settings are preserved. A real native/SQLite integration
test seeds an old-revision phantom membership and verifies that it is removed
without changing the raw fixes.

## Detailed GPS

**Settings → Detailed GPS** requests a two-second interval and two-metre movement
filter. Off uses the existing five-second/five-metre policy. The preference is
stored locally, defaults off for existing installations, and is read when the
next walk starts. Changing it during a walk does not interrupt the active stream.

These are Android provider requests, not guaranteed delivery rates. Higher
sampling uses more battery and does not make poor GPS accurate; motion evidence
must still pass before a section colours. Screen-off recording uses the same
selected policy and existing foreground-service cleanup.

## Evaluation

31 Rust tests (including doc tests), 88 Flutter tests with native matching, clean
analysis/clippy/format checks and 15 Python tooling tests passed locally. Two
optional Flutter live-download evaluations were skipped.

An Android API 35 emulator check verified the actual location-provider request:
2 seconds with Detailed GPS, still 2 seconds after turning the setting off during
the active walk, and 5 seconds on the next walk. Both walks stopped normally.
This verifies configuration and stream continuity, not real-world GPS accuracy.

The new junction regression fails on the previous matcher and passes on the new
one at every live prefix, including a denser sample sequence. Stationary jitter
stays dark; a genuine turn and doubling back still count. Poor-accuracy rejection
and accuracy parsing have independent tests. Tests also cover preference
persistence, unrelated-setting preservation and failed-write rollback.

All 18 synthetic Bremen evaluations reported zero false-positive edges. These
are independent OSM routes with simulated noise, not the user's recorded walk.
Retained expected street length across the three routes:

| Sampling distance | Clean | 2 m simulated noise | 6 m simulated noise |
| --- | --- | --- | --- |
| 3 m | 83.5–93.0% | 75.1–85.3% | 22.6–28.8% |
| 5 m | 91.2–92.2% | 75.5–87.5% | 50.9–59.2% |

The drop with stronger noise is material: stricter confirmation trades gaps for
fewer incorrect colours. Dense noisy samples can violate the speed guard more
often, so more GPS samples alone are not a matching-quality guarantee. The
original exported GPX and additional real walks are still needed for field
validation and further tuning.

Reproduce with `cargo test --workspace`, a release host geo-ffi build, and
`python3 tools/evaluate_matching.py --check` (repeat with `--step-m 5`).
