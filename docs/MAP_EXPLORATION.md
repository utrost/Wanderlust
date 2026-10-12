# Map performance and exploration

The map indexes street and scenery bounds once per map/viewport size. During
panning it queries visible geometry instead of scanning every street. Label text
measurements are cached with a bounded, explicitly disposed LRU. Explored streets
remain visible when subpixel unvisited detail is omitted at overview zoom.

## Optional fog of war

Enable **Settings → Fog of war** to gently mute unexplored terrain. It is off by
default. The normal map remains available by switching it off, and journey review
continues to show the full map.

Saved and ongoing journeys reveal approximately 60 metres around recorded fixes.
This works independently of street matching and the currently selected offline
map. Browsing the map does not reveal anything. Missing GPS stretches are not
filled in; fixes reporting worse than 50 metres accuracy are excluded.

Discovery is derived from saved GPS records, including imported/restored journeys.
Backups already contain these records and now include the display preference.
Deleting a journey removes terrain revealed only by that journey. Live recording
adds only newly received fixes; saved journey calculations run in an isolate and
are cached. The renderer merges revealed grid cells into indexed horizontal strips
and draws a translucent veil without an offscreen blur layer.

## Validation

`flutter test test/map_render_benchmark_test.dart` exercises a synthetic roughly
10 × 10 km map containing 20,000 street sections and 25 warmed-up pan frames.
A controlled comparison on 2026-10-12 measured 545 ms with the previous renderer
and 36 ms with the indexed renderer. These are CPU drawing-command timings in the
Flutter test environment, not phone frame rates or an end-to-end speed guarantee.
Cold map loading and device GPU performance require separate device testing.

Tests cover spatial queries against brute force, features crossing the viewport,
fog pixels, historical discovery, journey deletion, GPS gaps, default preferences,
and preference restoration through a complete backup.

For the device beta, pan and zoom the same 10 km map with fog disabled and enabled,
then record a short journey with the screen off. Confirm the route and discovery
appear on return, and that switching fog off immediately restores the full map.
