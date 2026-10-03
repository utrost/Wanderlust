# Recording and matching

Walk recording journals each GPS fix to local SQLite before a walk
is finalized. It retains timestamps and horizontal accuracy, prevents overlapping
starts, freezes elapsed time on stop, and handles location stream errors and
completion. Distance is accumulated incrementally; it is still a raw GPS-distance
estimate and can include drift.

The **Saved walks** button opens the library for completed and interrupted walks.
It supports GPX import, per-walk GPX file export, and full streamed `.wanderlust` backup
and merge restore. See [import/export](IMPORT_EXPORT.md) for formats, limits,
duplicate handling, and phone acceptance checks.

On relaunch, unfinished sessions become `interrupted`; their end time is the last
committed fix (or start time if there were no fixes). Recovery never resumes GPS
automatically. Committed points survive a process kill; fixes still awaiting a
commit can be lost. User-started Android screen-off recording is implemented;
see [behaviour, limits and battery acceptance](SCREEN_OFF_RECORDING.md).

If writing fails, recording stops and the in-memory trace remains available for
**Retry saving walk**. Another walk cannot start until this save succeeds. Retry
uses the original walk and point keys so partially saved traces aren't duplicated.
Uncommitted fixes cannot survive process death while storage remains unavailable.

## Location on the map

The blue dot shows the latest GPS fix, with a translucent horizontal-accuracy
circle. Starting a walk centers the first fix automatically. **Center on me**
recenters on the recording's latest fix, or requests a one-off location while
idle without creating a walk. Panning remains manual after centering; subsequent
fixes move the dot without pulling the map away from where you are looking.
**Show map area** returns to the full selected street view.

Optional GPS details show coordinates, accuracy, and the age of the fix. The HUD
explicitly reports waiting for GPS and locations outside all saved maps. Fixes older than 30 seconds use a gray marker and a last-fix label;
recording uses a 5 m distance filter, so an aging fix can also mean you have not
moved. Coverage uses all saved networks. If your position is outside them,
use **Download a map here** to save nearby streets; see [nearby maps](NEARBY_MAPS.md). Stopping retains the last marker; idle centering can
refresh it. The bundled geo-core diagnostic is available in Settings.

Phone follow-up: check initial positioning, accuracy-circle size, pan then
recenter, area reset, and disabled GPS. Initial installation, permission prompt,
and receiving a recording fix were confirmed by the tester on 2026-09-26; outdoor
recording and saved coverage have since been confirmed by the tester. Broader
trace-quality and screen-off battery testing remain open.

## Storage boundary

`app/lib/recording/walk_store.dart` owns database schema version 5 in
`wanderlust.db`: `recorded_walk` and `recorded_point`. SQLite plugin access is lazy
so an unavailable database reports a recording error instead of crashing startup.
Writes are serialized and stop waits for queued fixes. Foreign keys are enabled.

The journal is separate from the older area/segment schema sketch in
`geo-core/src/schema.rs`. Version 2 adds durable per-walk edge membership and
network-scoped counts; see [Bremen coverage](BREMEN_SLICE.md). The current
saved-walk list loads all recorded points; imports have explicit resource limits.
Version 3 adds stable backup identities and segment/missing-time metadata. Older database versions migrate in place. Version 4 adds offline maps and
persisted area selection. Version 5 adds local display preferences. Paging remains needed for large libraries.

## Conservative GPX matching

- XML parsing supports namespaced and self-closing points and validates finite,
  in-range coordinates and RFC3339 timestamps. Malformed/empty GPX is an error.
- Each GPX track segment is independent. Missing times, non-increasing times,
  gaps over 30 seconds, or displacement above 3 metres/second prohibit fill
  between those fixes. Direct observations require consecutive unambiguous
  support, along-street movement and a compatible travel direction. Fixes with
  known horizontal accuracy worse than 25 m remain recorded but do not confirm
  streets. See [matching evidence and evaluation](MATCHING_EVIDENCE.md).
- Inferred path length is also capped by elapsed time at 3 metres/second, in
  addition to the existing detour and absolute-distance limits.
- Off-network fixes break continuity instead of being dropped and bridged over.
- When the nearest two streets differ by at most 3 metres in snap distance,
  that fix is left unmatched. This reduces junction/parallel-path false positives
  at the cost of leaving more gaps; it is not a guarantee against all bad snaps.
- Untimed GPX can still paint repeatedly observed streets, but receives no inferred
  fill. The lower-level positions-only Rust API retains distance-based fill.

These initial thresholds need validation on real walking traces. The Bremen pipeline now splits at junctions and bounds chain length where
OSM nodes permit it; nearest-street matching remains a linear scan. Measured GPS
accuracy is preserved, and the matcher reads Wanderlust's accuracy extension.

## Tester diagnostics

The startup status chip distinguishes sample asset loading, native library/ABI
loading, street-network rejection, and matching failure. Tap a failed chip for
its underlying local error. Invalid GPX returns an `error` JSON object over the
C ABI, which the Dart binding reports as a format error. Nothing is transmitted.

A packaged APK must successfully match the sample to pass the native smoke test;
a graceful error message is useful diagnosis, not evidence that native code works.

## Verification

Run `cargo test --workspace`, `cargo clippy --all-targets --all-features -- -D warnings`,
and `cargo fmt --check` from the repository root. Run `flutter analyze` and
`flutter test` from `app/`.

Tests cover recorder starts/stops and failures, save retry, interruption recovery
against a real temporary SQLite database, diagnostic stages and cleanup, malformed
GPX over the C ABI, and gaps/noisy junctions/parallel streets in the matcher.

Implementation references: [sqflite transactions](https://pub.dev/packages/sqflite),
[roxmltree XML parsing](https://docs.rs/roxmltree/0.21.1/roxmltree/struct.Document.html),
and [Chrono timestamp parsing](https://docs.rs/chrono/latest/chrono/struct.DateTime.html#method.parse_from_rfc3339).
