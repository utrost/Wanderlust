# Screen-off walking on Android

Tap **Start walk** while Wanderlust is visible, then put the phone away. Android's
native `RecordingService` owns GPS, the recovery watchdog, notification and
SQLite writes. Flutter is a reader of that journal; hiding or disposing its
screen does not stop capture. Maps are optional for recording.

Each valid ordered fix from the session is committed atomically with its sequence and diagnostics
before it appears in the interface. Late-delivered fixes are retained, but only
a fresh fix clears the stalled-GPS warning. Existing walk IDs, raw points, GPX and backup
formats remain compatible. A small `native_recording` table holds durable session
state. Legacy interruption recovery excludes its active session. GPS callbacks,
commands and watchdog work share one native worker; SQLite writes are off the
Android main thread. Flutter reads unseen fixes in pages of at most 500, only
while visible, and never duplicates the native writes. Live matching and nearby
map download checks catch up on return; native recording does not need map data.

## Sampling and rest stops

Automatic sampling requests one-second updates for the first 20 seconds (up to
45 seconds while acquiring a fix), then three seconds walking or two cycling.
Turns temporarily request one-second updates. After at least a minute without
clear movement, the request interval becomes 15 seconds. A significant-motion
sensor, where available, wakes normal sampling sooner; GPS movement also exits
rest mode. Stops remain part of the same walk. Uncertain fixes, implausible jumps,
outages and trustworthy zero-speed drift do not inflate display distance. Raw
accepted positions are still retained for future matching improvements.

Manual 2/5/10/20-second settings remain available and persist across service
restarts. Provider delivery is advisory, not guaranteed. The service holds one
partial CPU wake lock only while recording, never a screen or Wi-Fi lock.
Stationary cadence and turn handling are initial defaults awaiting the Honor
field test; no battery saving percentage is claimed.

## Notification and recovery

The quiet recording notification shows distance, an elapsed-time chronometer and
**Stop**. Stop commits the end of the walk without opening Flutter, then releases
GPS, its wake lock and foreground notification. Old notification actions are
checked against the current walk ID and cannot stop a newer session.

The native watchdog checks every five seconds. After 45 seconds without a fresh
fix it shows reconnecting status; it renews native GPS requests at most once per
minute while preserving the recording service. After two minutes it posts one
attention notification per walk. Fresh fixes clear that notification. Storage
failure pauses capture while retaining the last durable journal and offers
continuation when the app reopens.

The service requests Android sticky restart. If Android restarts it, it resumes
the same journal with a segment break at the next fix. If it does not (including
force-stop or reboot), reopening offers **Continue your walk** and **Finish this
walk**. Finishing an interrupted session uses its last saved fix as its end time,
not the reopening time. No boot receiver, always-on tracking or background
location permission is introduced. Android and manufacturer policies can still
stop recording; successful emulator tests do not establish Honor reliability.

Android 13+ asks once for notification permission at first Start. Refusing it
leaves recording available but removes drawer controls and alerts; reopen the
app to Stop. Location permission and enabled location services remain required.

## Validation and field checks

Native tests cover atomic journal rollback, reconnect/paging, session identity,
sticky restart without Flutter, notification Stop, late callbacks, one-time
stalled-GPS alerts, adaptive/manual sampling and rest-stop distance. Flutter tests
cover reconnecting the same session, continuation, notification Stop, read/save
failures and legacy database recovery. CI runs both native and Flutter suites.

On the Honor Magic V6, try a five-minute walk, a one-hour pocket walk and a longer
outing with a rest stop. Include screen lock, another app, reopening during the
walk and Stop from the notification. Record battery before/after and export the
walk if any section is missing. Real-device acceptance and battery measurements
remain the user's next step.

Platform references: [Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location)
and [foreground-service restart restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).

## Native recorder emulator smoke test — 7 October 2026

On an isolated API 35 emulator, a real installed APK recorded with Wi-Fi/mobile
data off and the display asleep. Force-stop left 32 committed points in the
original journal; reopening offered Continue/Finish. Continuing retained that
walk ID and added a segment boundary at point 32. The notification displayed a
chronometer, distance and Stop. Stop from the drawer saved all 67 points as one
completed walk, removed the recording service and left zero held wake locks.
SQLite integrity checks passed before and after recovery.

The smoke test exposed zero-speed readings accompanying clear coordinate
movement; the distance policy was corrected and a regression test added. The
corrected resumed leg counted 24.09 metres for a 24-metre injected movement.
These are functional tests with public synthetic coordinates, not a measurement
of Honor background reliability, GPS quality or battery consumption.

## Earlier implementation and field evidence

The entries below describe previous builds, superseded by the native recorder
above; their field observations are retained for comparison.

## Evaluation — 2026-09-29

87 Flutter tests passed with the native Rust matcher enabled; two optional
live-data evaluations were skipped. Analysis was clean. All 14 Python tooling
tests passed, including rejection of missing/wrong signing credentials and
unexpected APK certificates/build numbers.

On an Android API 35 emulator, using injected positions on a public Vegesack
street (not the tester's trace):

- Six additional fixes committed during 36 seconds with the display asleep.
  Returning showed one coloured street section before stopping.
- Stop saved all seven fixes, removed foreground status and released the active
  Geolocator wake lock (checked in the current lock list, not historical events).
- A second screen-off walk committed three fixes before force-stop. Reopening
  recovered all three as interrupted, without restarting GPS or a wake lock.
- With notification permission revoked, recording still committed three fixes
  while the launcher was visible; Stop again released the service and lock.
- With device location disabled, Start created neither a walk nor a foreground
  service. Location was re-enabled after the check.
- Two APKs signed with the same prepared key (builds 990 → 991) upgraded using
  Android's normal replace-install path. Every SQLite table's contents remained
  identical: two walks, ten fixes, the 1.79 MB downloaded map, selected map,
  coverage and a non-default display preference.

Both APK certificates/version codes and packaged ARM64/x86-64 native libraries
were verified. These short emulator probes establish functional behaviour, not
real-device power consumption or resilience to a manufacturer's battery policy.

Platform references: [Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location)
and [foreground-service start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).

### Stalled GPS recovery

During a user-started walk, a separate watchdog checks for fresh location events
every 10 seconds, including while the map is hidden. After 45 seconds without a
fresh fix the recording pill shows a GPS-off icon with an explanatory tooltip.
After 60 seconds it renews the native Android location request, at most once a
minute, retaining the existing event subscription, foreground service,
notification and wake lock. Other location sources cancel and reopen their
stream. Failed native recovery leaves the subscription intact for another retry;
only a fresh fix clears the stale warning. Stop/dispose cancels retries; raw
fixes are never synthesized. The OS may suspend execution, and recovery cannot
guarantee satellite reception. Resuming the app checks immediately. The
elapsed-time display remains optional.

### Screen-off recovery correction — 7 October 2026

Honor Magic V6 field recordings still contained multi-minute GPS delivery gaps
after enabling background running and excluding the app from battery
optimization. Those settings alone did not resolve the issue.

Code review found that the previous watchdog cancelled the event subscription,
which removed foreground status and released the CPU wake lock, then attempted
to promote the service again while hidden. Android restricts starting location
foreground services from the background. Recovery now replaces only the native
location request, retaining the session's original options and event sink.
Late callbacks from removed requests are ignored, and recovery cannot start a
stopped recording. Initial recording promotes the service before requesting GPS.

The provider diagnostic also used the wrong method-channel name; it now calls
the Android plugin's actual channel. This restores the existing provider field
for subsequent backups. These fixes address demonstrated code defects; their
effect on the Honor gaps still requires a new screen-off field recording.

Validation: 19 focused Flutter recording/recovery tests and five native Android
unit tests passed; the ARM64 debug APK built successfully. Native recovery tests
also run in CI. No physical device was connected for screen-off validation.

## GPS acquisition and local diagnostics — 4 October 2026

Automatic sampling requests five-second fixes when walking and two-second fixes
when cycling. Settings offers manual 2/5/10/20-second intervals. Existing non-default
interval choices remain manual; old five-second defaults adopt automatic mode.
The interval is captured when recording starts and retained through watchdog
restarts. Requests are not delivery guarantees: the existing distance filter is
2 m for two-second sampling and 5 m otherwise, so stationary periods can be quiet.

Opening/reopening the map with permission already granted starts a foreground-only
warm-up for at most 20 seconds. Two distinct fresh readings with reported accuracy
at most 15 m finish it early. Hidden/disposed screens cancel it; starting a recording
awaits cancellation and opens the recording stream with its own settings. Warm-up
fixes update the position marker but are never added to an activity. Recording is
not gated on reaching a particular accuracy; a small locating icon is shown until
a fresh fix arrives. No permission prompt is triggered by automatic warm-up.

Each activity stores bounded acquisition statistics: requested interval, received
fixes, average/worst reported accuracy, delivery and GPS timestamp intervals,
fix age, time to first fresh fix, invalid/stale/future counts and watchdog restarts.
The Android bridge supplies the last provider reported within this app; this is
not per-fix provider attribution. Permission accuracy is sampled with diagnostics.
Snapshots are saved every 30 fixes and when stopping, so recovery after force-stop
may have only partial statistics. Missing platform metadata is allowed, and metric
storage failure cannot fail raw recording. No new network request is involved.

Review → satellite icon shows diagnostics and offers explicit clipboard copying.
Full backups include them; GPX does not. Metrics never affect the raw trace identity,
matching fingerprint or heatmap. These figures distinguish sparse sampling from
late delivery but cannot measure true positional error without ground truth.
