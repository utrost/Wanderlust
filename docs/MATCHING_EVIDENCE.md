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

## GPS intervals

**Settings → GPS interval** offers 2, 5, 10 and 20 seconds (default 5).
Two seconds requests a two-metre movement
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

## Optional short-gap interpolation

Settings → **Fill small gaps** defaults off. It applies immediately to live
coverage and recalculates saved walks. Turning it off recalculates again, removing
only the additional estimates; raw GPS readings remain unchanged. The cache key
includes the policy. Existing limited fill between consecutive confirmed fixes
remains available with the option off.

The new pass bridges an unconfirmed run between two motion-confirmed street
anchors in the same walk and GPX segment. It requires:

- Reliable readings throughout, increasing timestamps and no adjacent speed
  above 3 m/s. Untimed imports and bad-accuracy readings cannot support this fill.
- At most 30 seconds between anchors and a complete projected route of at most
  75 m, also bounded by elapsed time × 3 m/s and 1.8 × straight-line separation.
  The route includes the partial lengths of both anchor streets.
- Connected map topology and only one route within that budget. A second plausible
  route causes rejection, rather than arbitrarily choosing a shortest path.
- Intermediate route vertices within 20 m of the trace, and readings within
  20 m of the selected route including anchor streets.

No extrapolation beyond the last confirmed street, merging unrelated walks, or
bridging separate GPX segments. A subsequent confirmed street is needed before a
live gap fills. Long outages, ambiguous routes and substantial noise stay dark.

Regression tests exercise the missing connector, delayed live confirmation,
side streets, alternate routes, off-route excursions, bad accuracy, untimed
imports, backwards timestamps, outages, disconnected topology and full route
cost. Existing junction/jitter/turn tests also run with interpolation enabled.
Native Flutter/SQLite tests verify saved/live on→off recalculation, idempotence,
and unchanged raw walks. Settings tests cover persistence and failed writes.

All 18 synthetic Bremen scenarios with the option enabled had zero false-positive
edges. Clean expected-length recall (off → on):

| Sampling | Market to wall | Schlachte | Ostertor |
| --- | --- | --- | --- |
| 3 m | 83.5 → 84.8% | 93.0 → 100% | 90.8 → 97.4% |
| 5 m | 91.2 → 96.7% | 91.4 → 95.3% | 92.2 → 97.4% |

At 2 m simulated noise, 5 m sampling improves from 75.5–87.5% to 83.5–91.8%.
At 6 m noise the safeguards add no coverage. These are synthetic traces, not a
claim that every gap in the phone screenshot will fill. Reproduce with
`python3 tools/evaluate_matching.py --fill-small-gaps --check`, and repeat with
`--step-m 5`. CI evaluates both policies.

### User-confirmed longer gaps

Walk history → Review walk → Review GPS gaps offers explicit review of gaps between reliable (≤25 m) timed fixes lasting over 30 seconds and at most five minutes. Poor fixes may be skipped, but GPX segment boundaries, missing timestamps and reversed time break inference. Routing uses saved OSM node topology, never coordinate-only crossings. Routes are bounded by 600 m, elapsed time at 2.2 m/s, and 1.8× straight distance plus 30 m; endpoints must have a graph node within 25 m. Up to three candidate routes are shown in purple. Alternative searches and per-route visited nodes are bounded; the list is not exhaustive or a claim of certainty.

“I walked this” explicitly adds the selected section IDs once per walk to heatmap membership. Undo removes all user confirmations for that walk. Raw GPS and GPX exports stay unchanged. Confirmed IDs live in walk metadata, round-trip through full backups, participate in coverage cache identity, and only contribute to downloaded maps containing those IDs. Changing to another section-ID scheme would require reviewing confirmations again.

### Automatic GPS gap filling (default)

Settings → Fill GPS gaps automatically is enabled for new and existing installations. The coverage pipeline uses the same bounded route candidates as manual review and selects the shortest plausible candidate, including when alternatives exist. This is an estimate, not proof of the path taken. Explicitly confirmed candidate routes take precedence. Applies to live previews and reprocessed saved walks; coverage cache keys include the policy. Switching it off removes automatic estimates while preserving explicit confirmations and original GPS. Settings and recorded data are retained in backups, so estimates rebuild after restore. Ordinary short matching-gap interpolation remains independently configurable. No route is invented where the graph is disconnected or the existing distance/time limits reject it.

Field replay (4 October): the supplied three-walk backup produces four eligible gaps in the newest walk (42 candidate sections before overlap with direct matching), and two in the earlier Goetheplatz walk (25 candidate sections). The intermediate walk has no eligible gaps. This verifies routing availability, not ground-truth route choice. Private recordings remain outside the repository.

### Sequence evidence and final display resolution

The sequence model scores up to eight nearby street candidates and an unresolved
state per fix. Forward/backward inference considers GPS accuracy, movement
heading and projected distance through the connected street graph. Later clear
fixes can resolve earlier ambiguous choices. Disconnected crossings cannot act
as junctions; artificial 15 m sections retain parent-street continuity. A relative
cost margin rejects unresolved alternatives, while clear local evidence can
anchor a sequence. These costs are not calibrated probabilities.

Continuous runs stop at GPX boundaries, reversed/missing time transitions,
intervals over 30 seconds, implausible speed or accuracy worse than 50 m.
Moderately poorer accuracy requires more sustained along-street progress before
credit. Existing short-connector safeguards and bounded longer-outage routing
remain separate stages. Raw GPS is never changed.

Live previews recompute the full sequence on the worker, replacing provisional
coverage instead of accumulating earlier guesses. Hidden previews remain paused.
GPX round-trips preserve unknown accuracy instead of inventing a zero-error fix.

Validation includes parallel ambiguity resolved by later evidence, sustained
poor-accuracy movement versus jitter, 2/5/10/20-second sampling and disconnected
crossings, plus all earlier turn/branch/gap regressions. All four synthetic Bremen
evaluation configurations pass with zero false street credits. Private field
replays show both additional matches and more conservative choices; section
counts alone do not establish correctness. A 694-fix replay took approximately
40 ms for native matching on the development host, excluding graph loading and
Flutter work. Phone performance still needs field testing.

After native matching, automatic gap routing and explicit confirmations, a final display pass removes redundant fallback GPS pairs only when the nearest street at both endpoints and the midpoint is already covered. It uses the same 25 m corridor as snapping. A closer unpainted parallel street, missing intermediate section or off-network trace remains visible. This pass never adds heatmap credit; the raw GPS is unchanged and remains available in review. A 50 m spatial index bounds nearby geometry searches. Cache revision `sequence-model-v8` rebuilds saved results.

### Walking and cycling profiles

Each recording now carries an explicit Walk/Cycle type, selected before starting
and remembered in preferences. Existing recordings default to Walk. History →
Review → Cycle changes the type and recomputes coverage without changing raw fixes,
identity, favourites or explicit confirmations. Both activities contribute once
per activity per section to the same heatmap. Changing type replaces membership;
it does not add another traversal. GPX exports use a namespaced root extension,
and full backups retain the type. Missing or unknown type defaults to walking.

Walking retains its 3 m/s continuity ceiling. Cycling uses 15 m/s (54 km/h) as
an outlier ceiling, not a target speed. The native sequence, raw fallback and
short-connector checks use that ceiling; short inferred runs are capped at 150 m
instead of 75 m. Time continuity remains 30 seconds. Long-outage candidates use
8 m/s instead of 2.2 m/s, retaining the five-minute/600 m/route-detour bounds.
Displayed distance uses the selected profile too. Accuracy, topology, ambiguity
and trace-corridor safeguards remain in force.

The profiles match against existing downloaded geometry. Downloads still use the
pedestrian network policy: some cycle-only routes can be absent, and membership
is not a cycling access or navigation recommendation. Missing map geometry stays
as raw GPS evidence where reliable. A cycling-specific map download policy is a
separate enhancement.

The supplied 4 October ride (88 fixes) produces 100 matched sections on the
Viertel map under cycling versus 11 under walking. This is recovery evidence,
not proof of every inferred section. Synthetic tests cover 2/5/10/20-second rides,
implausible jumps, outages, off-network fallback and per-call profile isolation.
Storage/controller tests cover mode recovery, backup/GPX round-trips, live mode
capture, changed fingerprints and idempotent replacement of heatmap membership.

### Street corridors and visible estimates — 7 October 2026

Revision `street-corridor-v10` rebuilds saved coverage from unchanged GPS traces.
It adds four improvements:

1. The native loader retains OSM way identity, names, road type, access and
   bridge/tunnel/layer information. Closely parallel carriageways or explicitly
   identified roadside paths can support the same street identity. Grouping
   requires compatible geometry, identity, type and level; a shared name alone
   is insufficient. One coherent representative route receives credit, rather
   than painting both carriageways. This is street evidence, not lane certainty.
2. Viterbi backtracking selects one connected sequence. Connected, aligned pieces
   of the same street support each other across short subdivisions, with a
   bounded 60 m connection search. Each credited piece still needs projected
   movement and compatible direction, so endpoint jitter cannot extend a walk.
   Supported pairs no longer produce duplicate fallback trails just because a
   side-street endpoint is closer than the matched route.
3. Walking/cycling use explicit access and path-type evidence as soft candidate
   preferences. Shared paths remain valid; uncertain tags do not overwrite clear
   GPS evidence. New downloads retain `bicycle` and `footway` tags through coverage
   subdivision. Existing maps use the information they already contain; refresh
   maps to obtain the added tags. The conservative download inclusion policy is
   unchanged, so missing cycle-only geometry still cannot be matched.
4. Main-map heat counts now use supported or manually confirmed visits only.
   Native short-gap inference and automatic outage estimates appear as purple
   dashes, separately from grey-green unmatched GPS trails. Direct evidence wins
   over estimates across overlapping maps and activities. Estimated memberships
   remain derived data, rebuilt on restart; backups and GPS samples are unchanged.

Time/accuracy/speed boundaries remain in force. Street grouping does not create
routing links, bridge long recording outages, or merge different map levels.
Regression cases cover parallel carriageways, unrelated roads, roadside cycle
paths, access preference, sparse section sampling, endpoint jitter and outages.
The four synthetic Bremen evaluation configurations retain zero false-positive
edges, with clean-route length recall between 98% and 100% on the development
host. These checks are not a claim of that accuracy on arbitrary GPS recordings.

A private replay of the reported area reduced native unmatched samples from
21 to 3 of 35 nearby fixes against the larger downloaded map. The route and
backup are not committed. Some ambiguity remains; road credit and recovered
section counts do not prove the exact carriageway travelled.
