# Recording evidence build

During a recording, an independent scheduled worker saves a heartbeat every 30 seconds into the walk metadata, without requiring GPS fixes. It also captures start/resume/destruction, screen and app visibility changes, GPS request/retry events, and recording failures. Each event includes wall time, elapsed realtime, uptime, process ID, the last recording-worker tick and location callback, screen/idle/power-save state, battery optimization exemption and wake-lock state. This is diagnostic instrumentation, not a confirmed fix for the Honor screen-off gaps.

The latest 1,024 events per recording are retained. Diagnostics remain on the device and travel in the normal `.wanderlust` backup; GPX does not include the evidence log. No additional location samples or network uploads are introduced. Extra periodic database writes may modestly affect battery consumption and timing.

Interpretation: continued heartbeats with a stale worker tick indicate a recording-worker stall; advancing ticks without callbacks indicate missing location delivery. Gaps in all evidence with an unchanged process ID suggest process suspension, although this alone cannot prove an OEM cause. A new process ID or sticky-start event indicates service recreation. Elapsed realtime versus uptime helps identify device sleep. Missing evidence can also result from storage failure; logcat records diagnostic-write errors when available.

For a field test, install over the previous APK, start a recording, lock the screen for at least ten minutes while moving, reopen once, then stop and export a full backup. Keep the same power settings as the failing test so the comparison is meaningful.
