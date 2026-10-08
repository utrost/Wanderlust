# Recording evidence build

During a recording, an independent scheduled worker saves a heartbeat every 30 seconds into the walk metadata, without requiring GPS fixes. It also captures start/resume/destruction, screen and app visibility changes, GPS request/retry events, and recording failures. Each event includes wall time, elapsed realtime, uptime, process ID, the last recording-worker tick and location callback, screen/idle/power-save state, battery optimization exemption and wake-lock state. This is diagnostic instrumentation, not a confirmed fix for the Honor screen-off gaps.

The latest 1,024 events per recording are retained. Diagnostics remain on the device and travel in the normal `.wanderlust` backup; GPX does not include the evidence log. No additional location samples or network uploads are introduced. Extra periodic database writes may modestly affect battery consumption and timing.

Interpretation: continued heartbeats with a stale worker tick indicate a recording-worker stall; advancing ticks without callbacks indicate missing location delivery. Gaps in all evidence with an unchanged process ID suggest process suspension, although this alone cannot prove an OEM cause. A new process ID or sticky-start event indicates service recreation. Elapsed realtime versus uptime helps identify device sleep. Missing evidence can also result from storage failure; logcat records diagnostic-write errors when available.

For a field test, install over the previous APK, start a recording, lock the screen for at least ten minutes while moving, reopen once, then stop and export a full backup. Keep the same power settings as the failing test so the comparison is meaningful.

## Android service-state audit

Schema 2 adds Android's process importance, own-service foreground/started state and service PID, foreground service type, background restriction status, location power-save mode, permission/provider state and APK build number. A main-thread heartbeat is recorded alongside the recording-worker and GPS-callback timestamps. Diagnostic API failures are reported per group and do not abort the evidence event.

On Android 13+, `WakeLock.setStateListener` records framework enabled/disabled callbacks independently of `isHeld()`. Until a callback arrives, enabled state is unknown (JSON null); older Android versions also report unknown. Callback delivery can itself be delayed while the process is suspended, so event timestamps are receipt times, not proof of when the system disabled a lock. Power/service fields are sampled when the event is written; `writeElapsed` distinguishes that from enqueue time.

The lifecycle audit found distinct notification IDs and wake locks for the Geolocator preview and native recorder. Hiding the UI cancels preview/polling, without calling native Stop; native lock release occurs during recording teardown. No confirmed explanation for Honor's suspension has yet been found. This update adds targeted evidence rather than speculative retries or extra permissions.
