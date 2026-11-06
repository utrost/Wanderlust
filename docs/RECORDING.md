# Recording and matching

Tap **Start recording** to record walking, cycling or other journeys on one map.
Recording and matching adapt to movement. Optional activity labels in review
organise history; they do not determine which movement is matched. No GPX file
is needed: export is an explicit action in history. Labels can be changed
without changing the raw GPS trace.

Fixes are journaled to local SQLite with timestamps and horizontal accuracy.
Starts cannot overlap, stop waits for queued writes, and distance is accumulated
incrementally. Display distance remains an estimate, not a survey measurement.
The Android foreground service can continue while the app UI is closed, and
Android may restart its sticky service after process termination. Recoverable
recordings can be continued from the app. Committed fixes survive process
termination; pending writes may be lost.

If writing fails, recording stops and the in-memory trace remains available for
**Retry saving walk**. Another activity cannot start until saving succeeds.
Retries reuse original identities to avoid duplicate points. Uncommitted fixes
cannot survive process death while storage remains unavailable.

Walk history supports GPX import/export and streamed `.wanderlust` backups with
merge restore. See [formats and limits](IMPORT_EXPORT.md). Android screen-off
recording uses a user-started foreground service; real-phone battery and longer
activity validation remain open. See [screen-off recording](SCREEN_OFF_RECORDING.md).

## Location and sampling

The blue dot shows the latest fix with its reported horizontal-accuracy circle.
Opening or returning to the map recenters on a fresh fix when permission is
already granted. Panning while a location request is pending preserves the user's
chosen view. The location button recenters on demand; **Show map area** fits the
selected map. During recording, fixes update the dot without continually pulling
the map away from a manually chosen view.

Idle acquisition uses a bounded foreground warm-up stream: up to 20 seconds,
ending early after two distinct fresh fixes reporting accuracy within 15 metres.
It is cancelled when the app hides or recording starts. Preview fixes are not
added to an activity. Warm-up cannot guarantee satellite reception or accuracy.

Android automatic sampling requests frequent updates during acquisition and
turns (1 second), faster travel (2 seconds), ordinary movement (3 seconds), and
stationary periods (15 seconds). Disable automatic sampling in Settings to choose
**2, 5, 10 or 20 seconds** for the next recording. These are requests to Android,
not guaranteed arrival intervals.

Optional GPS details show coordinates, reported accuracy and fix age. Fixes older
than 30 seconds appear grey. A missing first fix shows a locating state. Outside
saved maps, recording can continue; see [nearby map downloads](NEARBY_MAPS.md).

## Matching and gaps

The matcher uses nearby candidates and a sequence of observations rather than
independent nearest-street choices. Accuracy, travel direction, along-street
progress and network connectivity contribute to the result. New evidence can
correct provisional live coverage. Networks use short sections targeting 15 metres
(typically 10–20 metres), so crossing a junction need not colour an entire street.

Matching infers movement constraints from the GPS sequence rather than the
activity label, with an absolute 70 metres/second envelope. Normal continuous
matching has a 30-second time-gap limit. Moderately inaccurate
fixes may support a street when sustained movement provides enough evidence;
recording retains rejected fixes too. Reliable unmatched movement can appear as
a dashed GPS trail. This preserves off-network evidence without claiming it
belongs to a nearby street.

**Fill small gaps** controls short inferred connections. Longer outages use a
separate route-estimation flow bounded by time, distance and detour limits
(up to five minutes and 600 metres). Automatic outage filling is off by default;
explicitly confirmed repairs are retained. An inferred route is an estimate, and
insufficient or conflicting evidence can still leave gaps. Neither setting is a
guarantee that every real journey is recovered.

See [matching evidence](MATCHING_EVIDENCE.md) for the detailed rules, regression
cases and known limitations. Downloads include street, cycle and useful railway
geometry. These are recording maps, not navigation or a statement of legal access.
See [automatic journeys](AUTOMATIC_JOURNEYS.md).

## Storage boundary

`AppDatabase` in `app/lib/storage/app_database.dart` owns the current version-3
schema for the `com.simiono.wanderlust` fresh-install lineage. `SqliteWalkStore`
is a facade over focused repositories, including the recording journal, maps,
preferences and derived coverage. Earlier versions within this lineage migrate in place; experimental predecessor
databases are not migrated into it.

Writes are serialized and foreign keys are enabled. History loads summaries;
full traces are loaded when needed. Activity mode and optional reception
diagnostics live in trace metadata. Derived coverage fingerprints allow matching
to be recalculated without replacing the original recorded points.

## Local diagnostics

The satellite action in saved-activity review shows optional GPS reception
statistics: reported accuracy, delivered intervals, fix age, time to first fresh
fix and stream restarts. Bounded summaries are checkpointed every 30 fixes and
on stop; diagnostics failure does not prevent recording. These summaries contain
no coordinates, remain local and are included in full backups, but not GPX.
A copy action lets the user choose to share them. Reported accuracy is the
receiver's estimate, not independently measured ground truth.

Settings also provides the native matcher diagnostic. A packaged APK must
successfully run its native smoke test; a graceful error alone is not evidence
that the native library works.

## Verification

From the repository root, run `cargo test --workspace`,
`cargo clippy --all-targets --all-features -- -D warnings`, and `cargo fmt --check`.
From `app/`, run `flutter analyze` and `flutter test`.

Checks cover recording failures/retry/recovery, mixed-activity journeys and
history labels, warm-up cancellation, sampling preferences, diagnostic
persistence, malformed GPX, and matching around gaps, junctions and parallel
streets. Field testing remains necessary for device reception and battery use.
