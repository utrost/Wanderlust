# Automatic journeys

## Product contract

One Start recording button, one shared map of places visited, and one recording
that can contain walking, cycling and vehicle travel. Start and Stop remain
explicit: this does not introduce always-on location tracking. Optional activity
labels describe history; they never decide whether reliable movement is visible.

Raw observations remain the source of truth. Matching is a derived, repeatable
presentation step. Confident sections follow the mapped street geometry. Reliable
unmatched movement appears in the same brown route. Outages, bad fixes and
isolated jumps remain breaks; the app never paints an invented straight line
across an actual recording outage by default. The older automatic-outage-fill
preference is reset on migration; explicit user-confirmed repairs remain saved.
Review and overview use the same fallback.

## Movement handling

Infer a local movement envelope from consecutive timestamped GPS positions,
not a single speed sample or a single label for the whole recording. Reject
isolated out-and-back spikes and discontinuities before estimating speed. Use
nearby sustained movement to choose walking, faster travel, or vehicle matching
constraints. These are internal matching hints, not claims that a trip was a car,
tram or bicycle. Keep the existing motion sensor and foreground recording
service; no activity-recognition dependency or extra permission is needed.

Display distance and sampling must also accept changes of movement. Fast travel
gets more frequent fixes; stationary recording retains the existing low-power
policy. Historic labels and imported GPX remain readable, but the app explicitly
requests automatic matching for both new and old recordings. A matching-revision
change reprocesses saved journeys without rewriting their original GPS.

## Offline maps

New map downloads include road, cycle and useful railway geometry. They remain
recording maps, not legal routing instructions. Preserve OSM node topology,
bridges and levels. Rail and road ambiguity falls back to recorded geometry.
Existing maps continue working, including the GPS fallback; refreshing them adds
the broader geometry. No automatic network request or map deletion is required.

## Validation and limits

Test mixed-speed journeys, fast legacy-labelled walks, abrupt mode changes,
stationary noise, isolated jumps, out-and-back movement, outages and track breaks.
Check retained raw fallback in both screens, backup/GPX compatibility, native
sampling/distance, and road/rail import parity. Replay the private field backups
without committing them. Automated checks cannot establish ground truth for an
ambiguous parallel road or identify car versus tram reliably.

The automatic matcher has an absolute 70 m/s envelope and breaks at intervals
longer than 30 seconds. This targets ordinary ground travel; it is not a flight
recorder. It checks local movement and uses a longer displacement baseline for
mode hints, so position noise does not turn a walk into vehicle travel. Native
Android sampling adapts online; completed routes can use later evidence when
rematching. No-map review uses the same reliable-pair rules for its brown route.

## Continuous street display

Confirmed pair-level sequence evidence survives automatic movement composition.
A nearest-edge proximity check must not redraw raw GPS beside a street already
supported by a coherent sequence. Short unique connections retain the same pair
evidence only after the existing time, accuracy, detour and trace-proximity
checks pass. Unresolved and off-network pairs remain visible.

At the start of a run, later fixes can establish direction when there is not yet
a usable backward baseline. This never overrides contradictory backward evidence
or crosses a discontinuity. Matching revision v13 reprocesses existing recordings
as well as new journeys; original GPS remains unchanged.
