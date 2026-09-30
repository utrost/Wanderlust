# Walking memories: UX, UI and workflows

## Intent

Notice something, save it, keep walking. Memories are private, offline annotations;
they never change heatmap counts, scores or matching. No account, feed or upload.

## Main map

A compact row above the walk control offers **Add memory** and **Memories**.
Recording continues while the editor or camera is open. Saved located memories
appear as small, tappable bookmark/photo markers with a 44 dp touch target.
Settings → Show memory markers hides them on both maps without deleting anything.
The library remains accessible without a downloaded map and during recording.

## Add / edit

The editor has a plain multiline “What caught your attention?” field, an optional
photo preview, Take photo / Choose photo controls, a location status and Save.
One photo per memory keeps capture short; Replace and Remove are available.
A note, a photo, or both is sufficient. Empty entries cannot be published.

The initial pin uses the current fix only if it is at most one minute old and
accurate within 50 metres. The editor freezes that location: walking further or
spending time taking a picture must not move the memory. Without a suitable fix,
show “No location attached”; offer an explicit Use current location action or
save without a pin. Never silently use a stale fix or infer a photo's location.
Location is optional and may be removed. No GPS permission request just to type.

Saving returns to the previous screen. Back keeps a private draft (including
edits to an existing memory), surfaced in the library as “Draft · Continue”.
Drafts are saved on leaving and before invoking the camera/picker. Deleting an
entry or draft requires an explicit confirmation. Storage and picker failures
keep the editor open with a retryable message. While a write is pending, prevent
duplicate saves and navigation that could discard it.

## Browse / review

The library lists newest entries first with note preview, photo icon, local date,
location state and draft state. Tap to open/edit, pinch the photo for a closer
look. Saved-walk review exposes only memories linked to that walk, both through
markers and a Memories button. Unlocated entries remain in the list. Main-map
markers show all saved located memories, independent of active map selection.

## Recovery and persistence

Use stable random memory identities and stable walk identities. Notes and photo
bytes are stored in app-private SQLite; photos are split into small rows to avoid
Android CursorWindow's per-row limit. Photo picker results are copied into this
store, never left dependent on cache paths. A pending-photo draft is persisted
before launching the platform picker. Startup recovers image_picker's lost result
into that draft; cancellation retains the note. Existing memory edits use a
separate draft so the published entry stays unchanged until Save.

Photo input is limited to 8 MiB and 32 megapixels; the picker requests a 1600 px
copy. Notes are limited to 4,000 characters. No change to the original gallery
photo. This first version supports one photo per memory; albums, tags, search,
manual map placement and individual sharing are later slices.

## Backup / restore

Create backup includes saved walks, memories, drafts and photo bytes, with an
integrity checksum. Restore supports earlier walk-only backups. Validate the
entire file before writes and merge walks and memories in one transaction;
existing memory identities win on conflict (never overwrite newer local edits).
The new bundle has a 128 MiB limit (at most 80 MiB of photo bytes before base64 encoding) and retains the existing walk limits. Oversize
exports fail explicitly rather than omitting photos. GPX remains a walk-only
export; the UI says that memories require the full backup. Backups may contain
photo metadata as well as notes and locations. Finish recording before backing up
or restoring so walk associations remain consistent.

## Acceptance checks

- Note-only, photo-only and combined entries; cancel picker; denied camera/GPS.
- No fix / stale fix / fresh fix; pin remains fixed during capture.
- Save, edit, remove photo, delete, draft continuation and process restart.
- Marker visibility preference and geographic placement under pan/zoom.
- Saved-walk association survives restart and restore with different row IDs.
- Large photo chunk round-trip; failed writes do not leave partial memories.
- Old backup compatibility, full photo round-trip, idempotent restore,
  corrupt backup rejection and rollback on a walk conflict.
- Heatmap and recording regression tests remain green.

Implementation uses Flutter's image_picker and its documented Android
[lost-data recovery](https://pub.dev/packages/image_picker).
