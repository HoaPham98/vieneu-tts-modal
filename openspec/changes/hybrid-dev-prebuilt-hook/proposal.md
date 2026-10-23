# Proposal

## Why

Currently, `packages/vieneu_tts/hook/build.dart` only downloads prebuilt native binaries (or requires a manual `VIENEU_TTS_LOCAL_LIB` file path override) and hardcodes `packageVersion = '0.1.0'`. When developing locally in the repository with Rust and Android NDK installed, developers want `flutter run` / `dart test` to automatically compile the local Rust source code via `flutter_rust_bridge_hooks` (`FlutterRustBridgeNativeAssetsBuilder`), while end-user consumers installing the released package (from `pub.dev` or `git`) automatically download precompiled binaries matching the version in `pubspec.yaml`—backed by a CI pipeline that validates version/tag parity and tests both `source` and `prebuilt` build modes.

## What Changes

- **Hybrid Dev (Source) vs Release (Prebuilt) Mode in `hook/build.dart`**:
  - Automatically detect whether the package is running in **Local Development Mode** or **Consumer Release Mode**:
    - Explicit override via `VIENEU_TTS_BUILD_MODE=source|prebuilt` (plus honoring `VIENEU_TTS_LOCAL_LIB`, `VIENEU_TTS_BINARY_URL`, and `VIENEU_TTS_LOCAL_ARCHIVE` as prebuilt overrides).
    - In default (`auto`) mode: build directly from Rust source when `input.packageRoot` is outside `.pub-cache` / `Pub\Cache`, `rust/Cargo.toml` exists, and `rustup` is available on the host machine; otherwise resolve and download prebuilt binaries.
  - In **Source Mode**, invoke `FlutterRustBridgeNativeAssetsBuilder` (`flutter_rust_bridge_hooks`) to compile `rust/` with Cargo/Rustup and track `.rs` source dependencies, and on Android targets automatically locate and register `libc++_shared.so` from the configured Android NDK sysroot (`input.config.code.cCompiler`).
- **Dynamic Version Resolution from `pubspec.yaml`**:
  - Remove the hardcoded `packageVersion` constant in `hook/build.dart` and dynamically parse the `version:` field from `packages/vieneu_tts/pubspec.yaml` at build-hook runtime so prebuilt cache paths and download URLs always match the package version.
- **Synchronize `flutter_rust_bridge` 2.13.0 & Toolchain Versions**:
  - Align `packages/vieneu_tts/rust/Cargo.toml` and `packages/flutter_vieneu_tts/example/pubspec.yaml` to `flutter_rust_bridge` `2.13.0` (matching `packages/vieneu_tts/pubspec.yaml` and `flutter_rust_bridge_hooks: 2.13.0`) and regenerate bindings with `flutter_rust_bridge_codegen` `2.13.0`.
- **CI Release Version Verification & Dual-Mode Testing**:
  - Update `.github/workflows/vieneu-tts-native-release.yml`, `.github/workflows/example-app-android.yml`, and `.github/workflows/vieneu-tts-lib.yml` to use `flutter_rust_bridge_codegen` `v2.13.0`, Rust toolchain `1.93.1` (from `rust-toolchain.toml`), and Android NDK `r28` (`28.2.13676358`).
  - Add a version-tag parity verification step in the release workflow ensuring the git tag / dispatch version matches `packages/vieneu_tts/pubspec.yaml` and `packages/vieneu_tts/rust/Cargo.toml`.
  - Add CI verification jobs that explicitly test both `VIENEU_TTS_BUILD_MODE=source` (compiling via `FlutterRustBridgeNativeAssetsBuilder`) and `VIENEU_TTS_BUILD_MODE=prebuilt` (consumer zero-Rust mode).
- **Standardize Flutter Example Platform Scaffolding (`android` & `windows`)**:
  - Re-scaffold `packages/flutter_vieneu_tts/example` using `flutter create --platforms=android,windows --org com.vieneu.tts .` so the example app conforms to the official Flutter SDK template (Kotlin DSL `.gradle.kts`, AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, dynamic `flutter.compileSdkVersion`/`flutter.ndkVersion`, and Windows C++ desktop runner) while preserving `lib/main.dart`, `pubspec.yaml`, `test/`, and `integration_test/`.
  - Add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml` and keep `applicationId` aligned with `.github/scripts/run_emulator_test.sh`.

## Capabilities

### New Capabilities
<!-- None: all requirements extend existing capabilities. -->

### Modified Capabilities
- `dart-native-assets`: Add requirements for automatic hybrid `source` vs `prebuilt` mode detection, `FlutterRustBridgeNativeAssetsBuilder` compilation with Android NDK `libc++_shared.so` bundling in source mode, and dynamic package version resolution from `pubspec.yaml`.
- `prebuilt-binary-release`: Add requirements for version/tag synchronization checks against `pubspec.yaml` and `Cargo.toml`, toolchain alignment (FRB `2.13.0`, Rust `1.93.1`, NDK `r28`), and CI verification of both `source` and `prebuilt` hook modes.

## Impact

- **Affected Code**:
  - `packages/vieneu_tts/hook/build.dart`
  - `packages/vieneu_tts/pubspec.yaml`
  - `packages/vieneu_tts/rust/Cargo.toml`
  - `packages/vieneu_tts/lib/src/rust/**` and `packages/vieneu_tts/rust/src/frb_generated.*`
  - `packages/flutter_vieneu_tts/example/pubspec.yaml`
  - `packages/flutter_vieneu_tts/example/android/**`
  - `packages/flutter_vieneu_tts/example/windows/**`
- **Affected CI Workflows**:
  - `.github/workflows/vieneu-tts-native-release.yml`
  - `.github/workflows/example-app-android.yml`
  - `.github/workflows/vieneu-tts-lib.yml`
