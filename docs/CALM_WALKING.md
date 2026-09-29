# Calm walking, live coverage and map scenery

The walking screen hides elapsed time, GPS sample count, and technical GPS
readings by default. Settings lets the user enable each separately. Preferences
stay on the phone (SQLite schema v5); existing walks and maps are retained during
migration. Distance, a quiet recording indicator, Stop, and useful location/map
warnings remain visible. The former “pts” were raw GPS samples, never a score.

“Street sections explored” replaces “street segments walked”. A section is a
piece of the pedestrian graph split at junctions, map limits, and approximately
60 metres along longer ways when an existing OSM node is available. It is not a
whole named street or a goal. The Settings screen explains the distinction.

## Live colour

New GPS observations schedule a coalesced background match, normally within two
seconds plus processing time. Repeated clock ticks do not schedule extra work.
The most recent 80 observations use the same conservative native matcher as
saved walks; confirmed preview sections accumulate for the current walk. The
preview is provisional, stays in memory, and contributes at most one additional
visit per section even where downloaded maps overlap. Ambiguous GPS observations
may delay colouring. Saving matches the full recorded trace and replaces the
preview with persisted counts without counting it twice. Temporary preview
failures do not interrupt recording. This does not add background recording.

## Parks and water

New nearby downloads include parks, gardens, green areas, woods, water areas and
river/stream/canal lines. Offline maps offers **Refresh map with parks and water**
for older downloads; it uses that saved area's bounds, requires internet and does
not require a GPS fix. Refresh sends the saved area to the same Overpass service.
The bundled legacy Bremen map remains usable; download a nearby area for scenery.

Decorative geometry lives in `wanderlust_scenery`, separately from street graph
features. Multipolygon pieces join by OSM node identity, island holes remain
holes, and incomplete rings are omitted rather than closed across missing data.
The painter clips scenery to each downloaded area and paints it underneath the
streets. No park, lake or river contributes to walked counts or graph connections.
Old map files without scenery still work. Streets keep their existing identities
when only scenery changes. Stroke widths are limited at high zoom for legibility.

## Validation

77 tests passed locally with native matching and the optional scenery evaluation;
analysis is clean. Tests cover calm defaults and settings migration/persistence,
failed preference saves, live matching before save, coalesced updates, late results
from a previous walk, failure recovery, save idempotency, geometry identity,
multipolygon joining and holes, actual rendered pixels, and refreshing without GPS.

The public Bremen-Vegesack example response was 2,635,954 bytes. It normalized to
5,234 street sections and 448 scenery features (1,795,248 bytes), accepted by the
native matcher. This is public test data, not the user's recorded route.

Android API 35 emulator validation with the real Vegesack map: a simulated walk
showed one explored section while recording was active, then retained exactly
one after Stop/save. The default panel showed distance and Stop without elapsed
time or sample count. All optional details fit on the 360 logical-pixel-wide
screen, and all three preferences survived a process restart. Parks and the river
were visually inspected in the actual offline Android view.
