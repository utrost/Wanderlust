# Street coverage presentation

The overview map consolidates equivalent parallel road coverage when its visible
span is at least 600 metres. It uses a stable OSM way identity to choose one road
geometry, preferring roads over explicitly tagged roadside sidewalks or cycleways.
The candidates must share a name or way identity, level and bridge/tunnel state,
run parallel, overlap longitudinally, and lie within 18 metres. Road-to-road
consolidation also requires the same highway class. Ordinary footpaths, service
roads, unrelated names and maps without way identities retain their geometry.
Zooming in shows the original matched sections.

Projection clips each highlighted piece to its covered interval, including where
15-metre coverage subdivisions do not line up across carriageways. Uncovered
continuations are never extended. The operation is display-only: saved GPS,
coverage IDs, visit counts and exported recordings are unchanged. Overlapping
highlights retain the strongest existing heat colour rather than summing counts.
A spatial grid and cached geometry avoid scanning the whole map on each GPS fix.

The native matcher applies a small cost to lateral switches between parallel
streets, without penalising straight subdivisions or actual turns. Turning onto
a different street also needs sustained departure from the previous street:
movement beyond the accuracy-dependent 6–15 metre threshold and at least four
metres beyond the initial departure. This reduces short false branch highlights;
very short or uncertain turns may take longer to confirm. Original GPS remains
available where street evidence is insufficient.

Matching revision `street-corridor-v11` invalidates previous matching results so
saved walks are reprocessed automatically. No map refresh is needed when the
existing map already contains OSM way identities. Missing metadata is never
inferred from proximity alone.

Validation includes synthetic junction noise checked at every live prefix,
real turns through the same refined junction, existing short-crossing and
out-and-back regressions, parallel roads, clipped subdivisions, separate paths,
level separation and metadata preservation during map refinement. Private backup
replays are useful smoke checks, not independently labelled ground truth.
