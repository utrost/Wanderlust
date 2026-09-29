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

# Idempotent permissions, notification icon, and notification permission bridge.
python3 "$ROOT/tools/configure_android.py" android

# Cross-compile geo-ffi (libwanderlust_geo.so) into jniLibs for the shipped ABIs.
cargo ndk -t arm64-v8a -t x86_64 \
  -o android/app/src/main/jniLibs \
  build --release -p geo-ffi

python3 "$ROOT/tools/generate_licenses.py"

echo "Android prepared: permissions injected, geo-core .so in jniLibs."
