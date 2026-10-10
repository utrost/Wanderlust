# Google Play beta submission

Prepared 10 October 2026. This packet is not a submitted or approved release.

## Owner decisions

- Owner confirms a Google Play developer account exists.
- Requested track: open testing, so anyone with the testing link can join, if eligible.
- App has not been created in Play Console; no Play signing configuration exists yet.
- Public support and privacy email: info@simiono.com.

## Release identity and track

- App: Wanderlust; Android package: `com.simiono.wanderlust`; version: 0.1.0.
- Build an optimised AAB through the Store candidate workflow. Its version code is
  100000 plus that workflow's run number. Record the exact code and commit at upload.
- Use Play App Signing and a separate private upload key for a new Play application.
  Check an existing app's signing configuration before generating or registering a key.
  Do not use the development/test signing key for the Play release.
- Open testing fits a wider opt-in beta if the developer account is eligible.
  New personal accounts created after 13 November 2023 first need a closed test
  with at least 12 testers continuously opted in for 14 days, followed by an
  application for production access; open testing is unlocked with that access.
- Choose countries, intended audience and free/paid status in Console with the owner.
  Do not treat an inferred audience or questionnaire answer as an owner declaration.

## Material ready in the repository

- Listing draft: `LISTING.txt` in this directory.
- Artwork: `fastlane/metadata/android/en-US/images/` (icon, feature graphic,
  two synthetic phone screenshots). Recapture the final candidate before upload;
  older captures may show controls that have changed.
- Approved field screenshot: `docs/images/wanderlust-bremen-map.jpg`, used in
  documentation. It predates the compass and remains an unchanged source image.
- Privacy text: `app/assets/legal/privacy.txt` and `docs/privacy.html`.
  Both now disclose the map-location precision and list info@simiono.com.
  They still require public hosting. A private GitHub URL is not a public policy.

## Data Safety review

No accounts, ads, analytics or developer route-upload endpoint were found in the
reviewed implementation. Routes, notes, photos and recording diagnostics are
stored locally. On-device-only processing is not off-device collection under
Google's definitions. User-requested exports may go to the user's chosen document
provider; review the user-initiated transfer exception rather than declaring an
app-operated cloud backup service.

Map downloads send geographic bounds to `https://overpass-api.de/api/interpreter`.
The service also receives an IP address and app user agent. Downloads may be
automatic during a user-started recording, and can be disabled in Settings.
`NearbyArea.around` rounds each bounding-box edge to four decimal places; the
centre can still reveal a precise location. The policy now explains this precision. Prepare a precise
location disclosure for map functionality unless the implementation changes.
Do not claim ephemeral processing or a service-provider sharing exemption without
checking the operator's actual processing/retention and the applicable definitions.
The final form must cover every distributed app version and any additional SDKs.

## Foreground location service declaration draft

Feature: User-started journey recording.

The user taps Start recording while the app is visible. Wanderlust records the
route so it remains available when the phone is locked or another app is open.
A visible recording notification accompanies the location foreground service.
The user can stop recording in the app or from its notification. Deferring or
interrupting the service would lose sections of the requested route. Recording
is not started automatically at boot.

Manifest: FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION, fine/coarse
location and notification permissions. No ACCESS_BACKGROUND_LOCATION is declared.
Absence of that permission does not by itself exempt the behaviour from review.

Reviewer video to capture from the final signed candidate:

1. Open the app and show the recording explanation and runtime location request.
2. Start recording; show the persistent recording notification and Stop action.
3. Lock/unlock or switch apps, then return and show that the route continued.
4. Stop recording and open the saved route in history.

Provide a reviewer-accessible video URL in the declaration, with synthetic data.
App access: no login or paid access is required. Internet is needed to download
the first map; saved maps and recording then work offline.

## Outstanding before Send for review

- Verified account, existing app record/signing status and testing-track eligibility.
- Public support email and publicly hosted, corrected privacy policy.
- Upload key provisioned securely and signed AAB verified; never commit secrets.
- Final screenshots and foreground-service demonstration video.
- Owner-completed Data Safety, audience/content rating, ads and other Console forms.
- Tester list/group for closed testing, or eligible open-test countries and rollout.
- Play bundle validation and pre-launch report, including native/16 KB compatibility.
- Existing GitHub testers: export a full backup before switching signing channels.
  A Play-signed install will normally require uninstalling the differently signed
  test build, then restoring that backup. Do not promise an in-place update.

## Official references

- [Testing eligibility](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Testing tracks](https://support.google.com/googleplay/android-developer/answer/9845334)
- [Data Safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Foreground services](https://support.google.com/googleplay/android-developer/answer/16559646)
- [Location review](https://support.google.com/googleplay/android-developer/answer/9799150)
