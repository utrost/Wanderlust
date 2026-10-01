# GPX import, export, and backup/restore

Implemented in the **Walk history** screen. Finish recording (and any pending save
retry) before opening the library. The Android system document picker handles
opening and saving files; the app does not request broad storage access.

## Using the library

- **Import GPX**: choose a UTF-8 GPX track file. One file becomes one saved walk,
  including all of its track segments. Import commits the walk before updating
  downloaded street coverage. Walks outside saved maps are retained even when
  they paint no streets. Download/select the corresponding nearby map to match
  these saved walks later; see [nearby maps](NEARBY_MAPS.md).
- **Export GPX**: use the download button beside a walk and choose a destination.
  GPX includes coordinates, elevation, available timestamps, track breaks, and
  Wanderlust's horizontal-accuracy extension. It is an interchange format, not
  a lossless copy of arbitrary third-party names, waypoints, or extensions.
- **Create backup**: save `wanderlust-backup.wanderlust` on Android. This retains saved walks,
  complete GPS measurements, segment breaks, stable identities, memories/photos,
  settings and downloaded maps. Derived coverage is rebuilt after restore.
- **Restore backup**: choose a Wanderlust backup. Restore merges missing walk
  identities in a single transaction; it never clears the existing library.
  Repeated restores are idempotent. A conflicting identity rejects the entire
  merge, preserving the previous library and coverage.

Canceling either picker makes no change. A failed file save leaves the original
walks available for another attempt. Backups are not encrypted;
GPX is plain text. Both contain location history; the destination is chosen by the user, including any storage
providers they have installed. Wanderlust itself does not upload these files.

## Validation and duplicate handling

GPX 1.0/1.1 namespaces, prefixed XML, and unnamespaced track files are accepted.
Coordinates must be finite and in range. Supplied timestamps must be valid and
include a timezone. Missing timestamps remain missing on export and matching;
no speed or time is invented. Non-monotonic timestamps and gaps are retained so
the native matcher's continuity rules still apply. Empty tracks, route-only or
waypoint-only files, malformed XML, and document type declarations are rejected.

GPX duplicate detection hashes ordered coordinates, UTC timestamps (or missing
markers), and segment boundaries. Renaming a file or changing XML formatting does
not add another walk. Reimporting an exported recording also skips that trace.
Different sampling, timestamps, or segmentation are treated as distinct tracks;
this is not fuzzy GPS similarity detection.

Backups use persistent walk identities, independent of local SQLite IDs. This
preserves distinct recorded sessions even if their traces are identical. Backup
restore deduplication is by identity, while GPX import deduplication is by trace;
restoring a recording after separately importing its GPX export can therefore
retain both identities. Use backups to move a library between installations.

The version-1 JSON envelope carries a SHA-256 checksum of its payload string to
detect corruption, not authenticate or encrypt the file. Unknown versions,
malformed measurements, duplicate identities, invalid segment indices, and
checksum mismatches are rejected before storage writes.

Files are limited to **32 MiB**, GPX imports to **100,000 points**, and backups to
**10,000 walks / 100,000 total points**. Backup creation validates the same limits
so it never emits an unsupported backup. These are initial resource bounds, not
a lifetime-library storage target. File reading is bounded and parsing/encoding
runs in worker isolates. SQLite library reads still load all points; paging and
streaming archives remain future work.

## Storage and verification

Schema version 3 adds stable identities and per-walk trace metadata. Versions 1
and 2 migrate in place. The point journal's separate timestamp column is used on
read to preserve sub-millisecond precision omitted by `Position.toJson()`.

Automated checks cover GPX round trips, missing times and segment breaks,
malformed/oversize input, renamed and repeated imports, migration, full backup
round trips, local ID remapping, repeated restore, identity-conflict rollback,
active recording safety, and file-dialog cancellation/save failures. The real
Rust/SQLite test imports a Bremen fixture, backs it up, restores it into a fresh
database, and checks identical persisted coverage. Separate singleton GPX segments
produce no coverage, confirming that transfer does not invent connections.

Local validation: **42 Flutter tests passed**, including native integration;
`flutter analyze` is clean. The debug APK also built successfully and passed
architecture/asset and APK-signature checks. It contains no broad storage
permissions. Native picker interaction still requires the phone.

Local APK: `app/build/app/outputs/flutter-apk/app-debug.apk`

SHA-256: `12b59931cc0da8844ff7621bce41f96b3869285365f41d16503347aa12c752e8`.

## Phone acceptance checks

1. Open **Walk history → Import GPX** and select
   `data/bremen/evaluation/schlachte.synthetic.gpx` copied to the phone. Confirm
   one walk appears and Bremen streets fill. Import it again: zero added.
2. Export the walk as GPX. Open the saved file in the phone's file manager,
   then import it again: zero added. Cancel open/save dialogs and confirm the
   library remains usable.
3. Create a backup and restore it immediately: zero added, unchanged counts.
   Restore the backup on a fresh test installation and compare the walk and
   coverage. Keep the backup outside app-private storage before clearing data.
4. Import invalid GPX or a damaged backup: an error should leave the library
   unchanged. Check the Android file provider's denied-access/save-failure flow.
5. Confirm the library controls are unavailable during recording or a pending
   save retry; stop the walk and check that its GPX exports correctly.

Implementation references: [file picker API](https://pub.dev/packages/file_picker)
and [Dart XML parser](https://pub.dev/packages/xml).

## Complete compressed backups (version 3)

Create backup now writes `wanderlust-backup.json.gz`: walks, memories/drafts and
photos, settings, and all downloaded street maps. A SHA-256 checksum covers the
JSON payload. Gzip reduces file size; decompression enforces the same 128 MiB
expanded-data limit before JSON parsing. Photos retain their 80 MiB combined
limit. Streaming larger collections is future work, not silently omitted data.

Restore accepts gzip version 3 and older uncompressed version 1/2 files. Its
preview offers optional offline maps and an unchecked **Replace my settings**
option. Existing walks/memories/maps and selected map take precedence. On a new
installation the backed-up selected map becomes active. Walks, memories, maps and
selected settings commit in one transaction. If merged maps exceed eight, the
restore fails without partial changes; retry without maps or remove an unused
map first. Coverage is recomputed from restored raw walks.

Android API 35 emulator validation: saved a compressed backup through the system
document picker, cleared only the isolated test app's data, restored through the
picker with settings selected, and verified the offline map, selection, settings
and all three test memories in SQLite. A manually placed pin retained its
coordinates and null GPS accuracy. Actual-phone provider testing remains open.

## Streaming Android backups (version 4)

Android now creates `wanderlust-backup.wanderlust`. Walks and photos are separate
checksummed records rather than one large JSON/base64 payload. The previous
80 MiB combined-photo limit no longer applies to new archives. Individual photos
remain limited to 8 MiB and the entire archive to 2 GiB. Backups are not encrypted.

Export and restore show progress and allow cancellation before the restore
transaction begins. The Android document picker streams bytes from/to private
cache files. Restore validates all records and photos before committing; a late
failure rolls back the entire merge. Full walks and photos are loaded one at a
time during the commit. Leave enough free space for the archive and staging.
Older JSON/gzip backups still restore with their original limits. Older app
versions cannot read version-4 archives; keep an older backup if downgrading.

The compressed version-3 workflow above describes the previous release and the
legacy codec; it is no longer Android's default export format.
