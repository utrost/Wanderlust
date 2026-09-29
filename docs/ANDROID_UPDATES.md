# Android test APK updates

Test APK releases now use one persistent, private test signing key and build
number `1000 + github.run_number` from the **Test APK** workflow. New workflow
runs increase the version; retrying the same run keeps its version. Keep that
workflow's run counter when changing the build pipeline. Android rejects a
downgrade to an older build.

The workflow requires the `WANDERLUST_TEST_KEYSTORE` Actions secret (base64 JKS,
the conventional Android debug alias/password). The private key must never be
committed. A protected local backup lives in the ignored `.local/signing/`
directory. Back it up securely before deleting this checkout. GitHub does not
allow reading a secret back after upload. These are still debug APKs, not a
production signing/distribution setup.

The public certificate SHA-256 is pinned in
`tools/android/test-signing.sha256`. `tools/install_test_signing.py` refuses
missing credentials and certificates that differ from the pin. There is no
fallback to a random key. The credential is installed in the runner's temporary
directory, separate from Gradle's default debug keystores. After compilation,
`tools/sign_test_apk.py` explicitly signs the finished APK and uses
`tools/verify_android_release.py` to verify its signature, pinned certificate,
application ID and version code before replacing the build output. The runner's
key is removed in an always-run cleanup step.

## One-time transition

Earlier test releases used disposable runner keys. Their private keys cannot
be recovered from the APK. Moving from those builds requires one final backup,
uninstall, install and restore. Backups contain walks, not maps or settings;
download the maps again and choose settings after that transition.

Afterwards, download a newer APK and install it over Wanderlust. Do not uninstall:
Android retains the database, saved walks, maps, selection and preferences.
Stop and save any active walk before installing an update.

## Provisioning status

The persistent test key is provisioned in the repository Actions secret. Its
public certificate matches the committed pin. A private local backup remains
in the ignored signing directory; neither the key nor its base64 encoding is
part of the repository.

## Local upgrade validation

On Android API 35, builds 990 and 991 signed with the prepared key passed APK
certificate/application-ID/version checks. Installing 991 over 990 succeeded.
Every database table remained identical after reopening: walks and fixes,
downloaded map bytes, selection, coverage and a non-default preference. See
[screen-off evaluation](SCREEN_OFF_RECORDING.md#evaluation--2026-09-29).
