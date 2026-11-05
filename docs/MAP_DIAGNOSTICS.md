# Map diagnostic reports

If a map download, refresh or opening fails, choose **Details → Copy report**
or **Save report** on the Offline maps screen. Recent reports are also available
from **Recent map reports** on that screen. Retry once before exporting so the
report includes the current failure. A full backup is not required.

Reports distinguish downloading, converting, validating, saving, listing and
opening maps. They include elapsed times, response status and byte counts where
available, error categories/codes and application code locations, the app build,
Android version, phone model and available space on the app's storage volume.
An insufficient-space message appears only when the error explicitly reports it.
A map already saved remains available when activation fails.

Reports remain local until the user copies or exports them. They exclude GPS
coordinates, map names, downloaded map contents, recordings, query bodies and
SQL arguments. SQLite errors use structured accessors instead of serializing
queries and parameters. Unexpected error text is reduced to diagnostic categories
rather than exporting arbitrary exception payloads. Stack traces retain only Dart
and Wanderlust source locations.

The last 20 operations are retained, up to 256 KiB in a separate private JSON file.
Writes replace that file atomically; errors in diagnostic persistence leave an
in-memory report and do not fail the map operation. No database migration, extra
permission prompt, telemetry upload or periodic background work is introduced.
This is diagnostic instrumentation, not a confirmed fix for the reported beta
failure. The exported report will determine the next corrective change.
