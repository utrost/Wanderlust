# Screen-off recording setup

Before the first recording, Wanderlust checks Android's battery-optimization
exemption. If it is off and this phone has not seen the explanation, the app shows
**Keep recording when your screen is off**. **Allow reliable recording** opens the
Android system dialog; **Not now** continues to recording. Dismissing the app's
explanation with Back cancels that start attempt. Repeated taps do not start
multiple dialogs or recordings.

The app reads the actual PowerManager exemption after the system dialog returns
and when its setup screen resumes. Android's activity result code is not treated
as proof of permission. Denial, a missing dialog, or unavailable status never makes
battery exemption a prerequisite for recording. A granted exemption bypasses the
first-recording prompt. A declined explanation is not repeatedly shown.

**Settings → Screen-off recording** reopens the setup at any time, including after
a refusal. The explanation preference is stored in Android's device-local shared
preferences, excluded from both Android backup/device transfer and Wanderlust's
own backups. Restoring journeys onto another phone does not imply permission on
that phone.

Honor and Huawei users see additional App launch guidance. The shortcut tries
known vendor launch screens, then Android app details when unavailable or blocked.
Wanderlust cannot verify or change the vendor's switches and does not report them
as enabled. On a model using the fallback, use the phone's Settings search for
App launch, find Wanderlust, disable Manage automatically, and allow Run in
background; retain Auto-launch and Secondary launch if offered.

## Android permission and Play review

`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` enables the user-initiated
`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog for this package. It is not
background-location permission and does not start recording, grant GPS permission,
or bypass notification permission. No new background service is introduced.

The reason for requesting the exemption is the app's core function: preserving a
user-started GPS journey when the screen is off. Existing recording diagnostics and
field reports show interruptions under phone power management. The native location
foreground service remains the recording mechanism. The explanation acknowledges
battery impact and leaves the choice with the user.

Android limits direct exemption requests to appropriate core-function cases;
Google Play acceptance remains subject to review. The exemption is not a guarantee
against manufacturer restrictions, force-stop, or poor GPS reception.

References:
- https://developer.android.com/training/monitoring-device-state/doze-standby
- https://www.honor.com/uk/support/content/en-us00428704/

## Validation

Flutter tests cover first-start integration, double taps, grant/refusal, missing
platform support, manual reopening, resume rechecks, Honor guidance and large text.
Robolectric tests check package-scoped requests, actual PowerManager state,
recreation of the device-local preference, denial, pending-request cleanup,
unavailable intents and OEM fallback. Overlay tests verify the manifest permission
and continued absence of `ACCESS_BACKGROUND_LOCATION`.

On a phone: start a recording without exemption, grant or decline the system
prompt, return to the map and record with the screen off. Reopen Settings to verify
the reported Android status; on Honor, check the separate launch controls too.
