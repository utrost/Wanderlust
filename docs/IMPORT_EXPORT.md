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

Full backups use the `.wanderlust` version-4 archive: length-delimited records,
individual SHA-256 checksums and a final record count. Checksums detect corruption;
they do not authenticate or encrypt a file. JSON/gzip backup formats 1–3 are
retired and rejected. The single-walk JSON record inside version 4 remains an
internal codec, not a separately supported backup import format.

GPX input is limited to **32 MiB / 100,000 points**. Full archives are limited to
**2 GiB**, with **32 MiB per record**, **8 MiB per photo**, **100,000 walks**,
**10,000 memories**, and **eight maps of 16 MiB each**. Walk and photo data are
staged and committed one item at a time; no combined 80 MiB photo ceiling remains.

Restore offers optional offline maps and an unchecked **Replace my settings**
choice. Existing walks, memories, maps and map selection take precedence. On a
fresh installation the backed-up selected map becomes active. Selected content
commits in one transaction, including settings; an error rolls everything back.
Export and restore show progress and allow cancellation before commit. Private
staging files are removed after success, cancellation or failure.

## Storage and verification

`com.simiono.wanderlust` starts a fresh schema lineage at version 1, created
straight from the current schema. Old experimental database migrations are not
shipped. Database identity checks reject an unrelated file without deleting it.
The point journal's separate timestamp column preserves sub-millisecond precision.
History reads use summaries and cached fingerprints; full traces load on demand.

Automated checks cover GPX round trips, missing timestamps and segment breaks,
bounded input, repeated imports, complete archive round trips, stable identities,
transaction rollback, fresh schema/reopening, cancellation, cleanup and rejection
of retired formats. Native FFI tests verify that restored walks produce the same
street coverage.

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
