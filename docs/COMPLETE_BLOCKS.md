# Complete blocks

Enable **Settings → Complete blocks** to colour completed street blocks on the
existing map. The feature defaults to off. Walking, cycling and other recorded
travel all contribute, including journeys recorded before enabling it.

Tap the completion chip for an explanation, or tap inside a block to see its
percentage and remaining perimeter distance. Dismiss the details to follow the
highlighted remaining streets; tap empty space to clear the selection. Memories
keep priority when their markers overlap a block. The count is across downloaded
maps, independently of the currently selected map or viewport.

## Completion and evidence

A block completes when at least 95% of its perimeter has supporting coverage and
no continuous missing interval is longer than 20 metres. Intervals wrap around
the polygon. The tolerance does not modify street coverage or GPS records.

Only GPS-supported matched sections and explicitly confirmed gap repairs count.
Automatic route estimates do not count. Equivalent parallel sidewalks and
carriageways can supply overlapping portions of the same street boundary using
the existing street display projection rules. Travel is unioned by length, never
summed twice. Internal paths are not required. Colour indicates perimeter
completion, not exploration of the interior.

Live detail percentages are provisional; light-red fills and the count use saved
journeys. Saving from the recording panel produces one combined recording-health
and completion message when new blocks were completed. History loading, imports,
map refreshes and enabling the feature do not replay celebrations. Deleting a
journey, removing a map or changing map geometry can reduce the count.

## Geometry, lifecycle and performance

The block worker uses OSM node identities from all downloaded maps, deduplicating
sections shared by overlapping maps. Public ground-level residential,
living-street, unclassified, primary, secondary, tertiary and pedestrian streets
form boundaries. Ground-level paths and service roads can close otherwise open
street perimeters. Public and local-access (`access=destination`) connectors are
eligible; private, prohibited and customer-only access remains excluded. This is
perimeter recognition, not a navigation recommendation or an access permission.
Paths inside already recognised street blocks are ignored. Path-only loops,
sidewalks, crossings, railways and motorway infrastructure do not define challenges.
Completed blocks use a muted light-red fill to distinguish them from parks.

The worker peels dead ends and traverses ordered directed edges to identify
bounded faces. It omits self-crossing or ambiguous geometry, crossings without
shared topology, nested containing faces requiring holes, polygons below 1,000
square metres, and polygons whose twice-area/perimeter is below 10 metres.
Boundaries require a 30 metre buffer inside the union of downloaded map bounds.
This is intentionally conservative: some real-world blocks are not eligible.

Topology runs in a background isolate and has a bounded in-memory cache keyed by
source network contents for the current algorithm revision. Section-to-block
indexes limit progress updates. Projected polygon paths and small fill batches
are cached; pan frames only query visible batches. No topology is computed during
gestures. A short fill fade honours reduced-motion preferences. Fog still uses
GPS discovery and may cover unexplored interiors.

All block data is derived. The preference is backed up; geometry and awards are
rebuilt from maps and recordings. Older v4 backups without the optional layer
preferences remain readable, with those options disabled. Missing topology
metadata asks for an offline-map refresh; it does not initiate a download.
Failures leave recording usable and expose Retry in the block details.

## Validation

Run `flutter test test/blocks_test.dart test/block_controller_test.dart
 test/block_render_test.dart test/map_render_benchmark_test.dart` from `app`,
plus the full Flutter suite and `flutter analyze` before release. Tests cover
geometry, evidence intervals, thresholds, lifecycle changes, backup compatibility,
map interaction and rendering. The synthetic pan benchmark compares 20,000 street
sections with and without 9,801 completed blocks, using median warmed timings and
a 20% overhead limit. These are CPU drawing-command timings, not phone frame rates.

Device checks: enable the feature, inspect known Bremen blocks, tap incomplete
blocks and memories, pan/zoom a large map with both exploration layers, save a
journey, restart, and confirm the count persists through derived-data rebuilding.
