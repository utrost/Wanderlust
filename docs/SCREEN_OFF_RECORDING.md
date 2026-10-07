# Screen-off walking on Android

Start a walk while Wanderlust is visible. The existing Geolocator stream now
uses an Android location foreground service, a quiet **Walk in progress**
notification and a partial CPU wake lock. Lock the screen or switch apps; GPS
fixes continue to be committed individually to the SQLite recording journal.
Tap the notification to return, then Stop to save. Starting while hidden is
guarded; no boot receiver, background auto-start or always-on tracking is added.

Android 13+ asks once for notification permission when starting the first walk.
Refusing notifications does not prevent recording, but the return shortcut is
absent from the notification drawer; use the app icon. Android's active-apps
controls still show the foreground service. Location permission and enabled
location services remain required. Center on me does not request notifications
or start a recording service.

## Work and battery budget

- High-accuracy location requests use a five-second desired interval and a
  five-metre distance filter by default. Settings → GPS interval offers 2, 5, 10
  and 20 seconds for the next walk (2 s uses a two-metre movement filter). Actual
  delivery depends on the location provider.
- No Wi-Fi lock, route upload, screen wake lock or constant notification update.
  Automatic nearby map downloads may use the network during a started walk,
  including while hidden, unless disabled in Settings.
- Display clocks and live map matching pause while hidden. On return, matching
  catches up with every unseen fix, retaining overlap for consecutive evidence.
- Stop cancels the stream and releases the foreground notification and partial
  wake lock. GPS or storage errors follow the existing interrupted-save path.

This is a conservative first policy, not adaptive sampling. A partial wake lock
costs power; emulator results cannot establish a real phone battery budget.
Initial field acceptance target: a one-hour screen-off walk with no unexplained
moving gaps over 30 seconds and at most five percentage points of battery use,
measured against the same phone's idle baseline. Record device, duration, battery
before/after, GPS conditions and other active apps. Revise the target with data.

## Limits and recovery

This service is tied to the app's Flutter engine. Screen-off and switching apps
are supported; force-stop, task removal, reboot or OS process termination may
end recording. There is no promise of uninterrupted collection after process
death. On relaunch, committed fixes are recovered as an **interrupted** walk;
GPS never silently restarts. Already committed readings remain exportable and
can produce coverage. Pending uncommitted writes can be lost.

Manufacturers can impose additional battery restrictions. Field testing on the
actual phone remains required; no blanket battery-optimization exemption is
requested in this slice.

## Repeatable acceptance checks

1. Start with precise while-in-use location permission; check the notification.
2. Lock the screen and walk for at least 15 minutes. Return and verify the trace
   includes the hidden portion and live colour catches up before Stop.
3. Switch to another app for several minutes; repeat the continuity check.
4. Stop; verify the walk is saved and the notification disappears.
5. Start another walk, then force-stop. Reopen: committed points must be retained
   in an interrupted walk, without a new GPS service starting automatically.
6. Repeat with notification permission refused and with location disabled.
7. Measure the one-hour battery/trace acceptance target above on the real phone.

The unit suite checks hidden journaling, suspended display ticks, stream cleanup,
start/permission races, and coverage catch-up beyond 80 fixes. SQLite recovery
tests reopen the real database.

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
