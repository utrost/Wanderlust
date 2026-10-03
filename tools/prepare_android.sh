#!/usr/bin/env bash
# Prepare the app's Android build: generate the (git-ignored) platform folder,
# inject the location permissions the walk recorder needs, and cross-compile the
# Rust geo-core into jniLibs so the FFI works on device.
#
# Prerequisites: Flutter, the Rust android targets, cargo-ndk, and ANDROID_NDK_HOME
# set (CI installs these; locally: `rustup target add aarch64-linux-android
# x86_64-linux-android && cargo install cargo-ndk`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/toolchain.env"
actual_flutter=$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')
if [[ "$actual_flutter" != "$FLUTTER_VERSION" ]]; then
  echo "Expected Flutter $FLUTTER_VERSION; got $actual_flutter" >&2
  exit 1
fi
actual_rust=$(rustc --version | cut -d ' ' -f 2)
if [[ "$actual_rust" != "$RUST_VERSION" ]]; then
  echo "Expected Rust $RUST_VERSION; got $actual_rust" >&2
  exit 1
fi
actual_ndk=$(sed -n 's/^Pkg.Revision *= *//p' "$ANDROID_NDK_HOME/source.properties")
if [[ "$actual_ndk" != "$NDK_VERSION" ]]; then
  echo "ANDROID_NDK_HOME must point to NDK $NDK_VERSION" >&2
  exit 1
fi
cd "$ROOT/app"

# Flutter create writes a template lockfile even with --no-pub. Preserve the
# reviewed dependency resolution across scaffold generation, including failures.
lock_copy=$(mktemp)
cp pubspec.lock "$lock_copy"
trap 'cp "$lock_copy" "$ROOT/app/pubspec.lock"; rm -f "$lock_copy"' EXIT
flutter create --no-pub --org com.simiono --project-name wanderlust --platforms=android .
cp "$lock_copy" pubspec.lock
rm -f "$lock_copy"
trap - EXIT
flutter pub get --enforce-lockfile

# Idempotent permissions, notification icon, and notification permission bridge.
python3 "$ROOT/tools/configure_android.py" android

# Cross-compile geo-ffi (libwanderlust_geo.so) into jniLibs for the shipped ABIs.
cargo ndk -t arm64-v8a -t x86_64 \
  -o android/app/src/main/jniLibs \
  build --release --locked -p geo-ffi

python3 "$ROOT/tools/generate_licenses.py"

echo "Android prepared: permissions injected, geo-core .so in jniLibs."
