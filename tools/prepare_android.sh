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
cd "$ROOT/app"

flutter create --org com.wanderlust --project-name wanderlust --platforms=android .

# Location permissions (idempotent — flutter create won't have added them).
MANIFEST="android/app/src/main/AndroidManifest.xml"
if ! grep -q "ACCESS_FINE_LOCATION" "$MANIFEST"; then
  perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"\/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"\/>/' "$MANIFEST"
fi

# Cross-compile geo-ffi (libwanderlust_geo.so) into jniLibs for the shipped ABIs.
cargo ndk -t arm64-v8a -t x86_64 \
  -o android/app/src/main/jniLibs \
  build --release -p geo-ffi

echo "Android prepared: permissions injected, geo-core .so in jniLibs."
