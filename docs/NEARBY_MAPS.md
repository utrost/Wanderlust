# Downloadable nearby street maps

**Offline maps → Download nearby map** saves a square centered on the current/last
GPS fix. Choose **1–25 km per side**, in 1 km steps; the default is 4 × 4 km.
The picker displays dimensions and total area (25 × 25 km = 625 km²) and remembers
the choice. New map names include dimensions. Refreshing an existing map keeps
its original bounds. The map screen also offers **Download a map here**
when that fix is outside all saved maps. Within roughly 500 metres of the outer
edge, a fresh GPS fix shows an edge warning and **Download more streets**.
Internal seams covered by another saved map do not trigger a warning. Tap the area name to choose between
previously downloaded maps. **Show map area**
returns to the extent of the selected map; **Center on me** still centers GPS.
All downloaded maps render together using the same camera;
crossing into a saved neighbouring area needs no selection or internet. The
selected map controls the initial view, not which streets can be displayed.
Downloads remain manual. Outside saved areas, recording continues and coverage
can be recovered after saving the walk and downloading the missing streets.

Downloads include **street geometry** for matching plus decorative parks and
water. Refresh older downloaded maps to add this scenery. Terrain, buildings
and satellite imagery remain out of scope. See [calm walking](CALM_WALKING.md). This resolves coverage outside Bremen center
without introducing a separate map whose streets cannot receive walk coverage.

## Data and offline behavior

- The first map is downloaded explicitly. During started walks, automatic
  2 × 2 km extensions are enabled by default within 500 m of the exposed boundary
  of all saved maps (or outside them). Settings can disable this. Requests use
  the available connection, including mobile data; they do not run on app startup.
- A rounded bounding box goes to `https://overpass-api.de/api/interpreter`.
  Recorded walks and the precise GPS fix are not sent. The screen explains this
  before the download button. OSM attribution and ODbL information remain visible.
- The downloaded OSM XML is normalized on a worker isolate with the same access
  policy, junction rules, and 52-bit OSM way/node-chain edge IDs as the Python
  builder. Distinct OSM nodes are never connected just because they are nearby.
- Complete, validated GeoJSON is stored in SQLite. The selected map survives app
  restart; opening a downloaded map needs no internet. Interrupted, cancelled,
  malformed, and failed downloads leave existing maps and raw walks intact.
- Saved walks are processed against every saved network. Coverage remains
  scoped to each map version in storage. Display counts use distinct walk IDs
  per street across all loaded maps, so overlaps never count a walk twice. A queued match always finishes against its
  original network before another network can become active.
- Walk recording may continue while downloading. The active walk shows provisional live colour;
  saved coverage is confirmed when the walk is saved. Downloads use the GPS fix displayed when
  the map picker was opened, not a moving request boundary.
- Up to eight downloaded maps can be kept, each at most 16 MiB. Remove unused
  downloads in the picker. Removing the selected download selects another saved map,
  or returns to setup when none remain; raw walks and derived coverage records are retained.
- Complete compressed backups include downloaded maps and settings alongside
  raw walks and memories. Restore can include those maps without a download.
  Older walk-only backups still need the desired areas downloaded again.

Schema v4 adds `offline_area` and `offline_selection`. The foreign key prevents
selection of missing maps and clears selection when the selected cache is removed.
The Bremen asset remains a development/test fixture; it is not automatically
selected, shown in the map picker, or included in displayed coverage.

Downloads have a 15-second connection timeout and 75-second total timeout, a
bounded response size, and a Cancel control. No background retries or bulk
requests are made. The current small personal-testing use relies on a public
Overpass instance, whose availability is not guaranteed. Public rollout needs a
hosted extraction service or prepared region packages; see the provider's
[resource-sharing guidance](https://dev.overpass-api.de/overpass-doc/en/preface/commons.html).
Polar regions and date-line-crossing downloads are not supported in this slice.

## Evaluation and phone checks

Boundary update validation: **67 tests passed**, with the optional live endpoint
evaluation skipped. Includes a real Rust walk spanning two overlapping maps,
union boundaries (overlap, touching edges, gaps and corners), stale GPS warnings,
camera continuity and distinct-walk aggregation.

Original download validation: **61 tests passed**, including native downloaded-map coverage
and the optional live-data evaluation. `flutter analyze` is clean.

A live download for a **public Bremen-Vegesack example area** (bbox
`8.58,53.15,8.64,53.186`, not the tester's location) returned 1,788,846 bytes of OSM
XML. Mobile normalization produced **5,234 edges / 1,544,436 bytes** of GeoJSON,
accepted by the actual Rust matcher. This checks the network path and graph
contract; it is not a field evaluation of GPS accuracy in Vegesack.

The mobile builder reproduces all **7,930 edge IDs and geometries** of the bundled
Bremen network from its original OSM snapshot. Automated tests also cover invalid
responses, access restrictions, real local HTTP request/response handling, a busy
server, offline persistence after restart, schema migration, serialized area
switches, preserved old counts, UI cancellation, and failed selection/downloads.

On the phone:

1. Tap **Center on me** and verify the fix/coordinates. If outside the current
   map, tap **Download a map here**.
2. Tap **Download nearby map** with internet enabled. Confirm local streets appear
   and the selected-area title changes.
3. Turn on airplane mode, restart Wanderlust, and confirm the downloaded streets
   still appear. Map selection itself must not require a connection.
4. Record and save a short walk, or restore/import an existing nearby trace.
   Check that its coverage appears in the selected area.
5. Switch between downloaded maps. Verify existing counts survive and are not
   added twice. Cancel a download and test a disconnected download: saved maps
   must remain available.

## Android large-map loading fix

Android's SQLite cursor window can reject a multi-megabyte result row even when
SQLite successfully stored it. The previous `SELECT geojson` read could therefore
save a download but fail to activate it, or fail to reopen it after restart.
All cached-map reads now use `length` plus 128K-character `substr` chunks in one
transaction, including the active-map startup path. Each row is at most 512 KiB
of UTF-8 text. Existing stored maps need no migration or redownload for this fix.
SQLite character offsets are used, preserving non-BMP Unicode across chunks.

Validation: 68 Flutter tests passed (optional live endpoint test skipped), clean
analysis, and a verified Android APK. On an Android API 35 emulator, the previous
APK failed to open a 2.5 MB saved map; the fixed APK opened the identical database,
selected the saved map and displayed both offline maps without a storage error.
`tools/android/MapCursorProbe.java` independently reproduces the old
`SQLiteBlobTooBigException` and verifies the chunked query with a large Unicode
value. Compile against android.jar, convert with d8, push classes.dex, and run
with `CLASSPATH=<device dex path> app_process /system/bin MapCursorProbe` on a test
device. This probe uses an in-memory database and does not change app data.

## Download size limits

The size selector changes the requested footprint; it does not guarantee that
every 25 km square will fit. Downloads retain the existing bounded request,
timeout, 16 MiB response/cache limits, and normalization limits. A large dense
city area may need a smaller selection. Failed or cancelled downloads preserve
existing maps and selection. Date-line-crossing footprints are rejected before
network access. The selector makes the large-area caveat visible from 10 km up.

## First launch and no-map state

A fresh installation opens a welcome screen, not Bremen. Choose **Set up my map**,
then **Find my location**. Permission and a one-off GPS fix are requested only on
that tap. Choose a square size (4 km per side by default) and explicitly tap
**Download nearby map**. The surrounding-area disclosure appears before download.
Only a fully saved and successfully selected map opens the walking screen.
Location failures, denied permission and failed/cancelled downloads leave setup
retryable. Refresh my location is also available for later downloads.

No onboarding-completed flag is needed: the downloaded-map catalogue determines
whether setup is necessary. Existing selected downloads open normally; if selection
is missing, an available download is used. No existing walks, map files or derived
coverage are deleted by this change. Users who previously relied only on the
bundled map get setup and can download their area; their walks remain accessible.

Saved walks, import and Settings remain accessible before setup. Review without
maps shows the raw GPS trace on an empty background. Removing all maps during a
walk keeps Stop and save-retry controls available. Deleting a map never deletes
raw recordings. Download the area again to recalculate its coverage.
