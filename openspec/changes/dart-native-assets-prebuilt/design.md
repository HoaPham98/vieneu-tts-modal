# Design: Dart Native Assets & Prebuilt Monorepo Architecture

## Context

See [proposal.md](proposal.md) for background and motivation.

Currently, `packages/vieneu_tts` contains both the core Dart synthesis API and a monolithic Flutter plugin structure with Android-specific Gradle configuration. Rust compilation has been tested on Android emulator via GitHub Actions, but third-party developers cannot consume the package without installing Rust, Cargo, and Android NDK because native binaries and bridge bindings are not pre-packaged or tracked.

This design introduces a modern Dart Native Assets architecture (`hook/build.dart`) with prebuilt binary artifact distribution via GitHub Releases, structured as a clean monorepo.

## Goals / Non-Goals

**Goals:**
- Enable third-party Flutter and pure Dart apps to install and use `vieneu_tts` without installing Rust, Cargo, CMake, or Android NDK.
- Decouple the core library into a pure Dart package (`packages/vieneu_tts`) and a Flutter wrapper (`packages/flutter_vieneu_tts`).
- Implement `hook/build.dart` to automatically resolve, download, verify (SHA-256), cache, and link platform-specific native binaries.
- Bundle `libc++_shared.so` alongside `librust_lib_vieneu_tts.so` for Android targets to ensure zero C++ runtime linking failures.
- Track generated bridge bindings (`lib/src/rust/` and `rust/src/frb_generated.*`) in Git to eliminate downstream codegen requirements.
- Establish a hermetic CI consumer test verifying clean builds and on-device execution with Rust and NDK toolchains purged.

**Non-Goals:**
- Windows or macOS native assets support in phase 1 (initial support targets Linux x64, Android arm64/x64, and iOS).
- Re-architecting internal C++ neural codec or G2P phonemizer logic.

## Decisions

### 1. Monorepo Package Decoupling
- **Decision**: Split the codebase into two distinct packages under `packages/`:
  - `packages/vieneu_tts`: Pure Dart library with `dart:io` and `dart:ffi`. Has no Flutter SDK dependency. Contains `hook/build.dart`, the Rust crate source, and public Dart synthesis/streaming APIs.
  - `packages/flutter_vieneu_tts`: Flutter package depending on `vieneu_tts`. Provides Flutter-specific integrations (e.g. `path_provider` sandbox resolution, download progress notifiers) and houses `example/`.
- **Rationale**: Pure Dart developers (CLI, server/backend) can use `vieneu_tts` without pulling the Flutter SDK, while Flutter developers enjoy seamless lifecycle and UI helpers.
- **Alternatives Considered**: Monolithic hybrid package. Rejected because keeping Flutter dependencies in the core package breaks standalone Dart VM execution.

### 2. Dart Native Assets (`hook/build.dart`) as the FFI Standard
- **Decision**: Adopt Dart's standard Native Assets build hook mechanism (`hook/build.dart`) instead of Cargokit or manual Gradle `jniLibs` scripts.
- **Rationale**: Native Assets is Dart's first-class native compilation and bundling mechanism. It dynamically receives target OS/architecture from the Dart/Flutter compiler and registers prebuilt libraries using `CodeAsset`.
- **Alternatives Considered**: Retaining Cargokit. Rejected because Cargokit requires local Cargo and NDK toolchains on developer machines.

### 3. Prebuilt Artifact Distribution via GitHub Releases
- **Decision**: Publish platform-specific prebuilt archives (`.tar.gz`) directly to GitHub Releases upon tagged releases, accompanied by a `checksums.json` manifest.
- **Rationale**: Keeps the pub.dev package under the 100 MB upload limit. Developers only download the exact binary needed for their active build target, and binaries are cached permanently in `.dart_tool/vieneu_tts/cache/`.
- **Alternatives Considered**: Bundling all prebuilt binaries directly into the package. Rejected because bundling multi-platform binaries exceeds package size limits and burdens users with binaries for platforms they don't target.

### 4. Tracking Generated Bridge Bindings in Git
- **Decision**: Remove `lib/src/rust/` and `rust/src/frb_generated.*` from `.gitignore` and commit them into version control.
- **Rationale**: Downstream Dart consumers do not have `flutter_rust_bridge_codegen`. Tracking generated Dart bindings ensures pure Dart apps can compile immediately upon `pub get`.
- **Alternatives Considered**: Running codegen on consumer machines. Impossible without installing the Rust toolchain and codegen binary.

### 5. Bundling `libc++_shared.so` for Android Targets
- **Decision**: For Android targets (`arm64-v8a` and `x86_64`), package `libc++_shared.so` from the Android NDK alongside `librust_lib_vieneu_tts.so` in the release tarball, and register both as `CodeAsset` in `hook/build.dart`.
- **Rationale**: `audio.cpp` C++ compilation links against the C++ standard library. Android requires `libc++_shared.so` at runtime; omitting it causes `UnsatisfiedLinkError` on devices.

### 6. Hermetic Toolchain-Purged CI Verification Strategy
- **Decision**: Validate consumer isolation in CI by explicitly removing `cargo`, `rustc`, and `$ANDROID_HOME/ndk` before building and testing a new consumer app.
- **Rationale**: Standard GitHub Actions runners have pre-installed Rust and NDK toolchains. Purging them ensures that tests fail immediately if any step accidentally falls back to compiling from source.

## Architecture & Data Flow

```
+-----------------------------------------------------------------------------------------+
|                                CI Matrix Release Pipeline                               |
|                                                                                         |
|  cargo ndk / cargo build -> [Linux x64, Android arm64, Android x64, iOS arm64]          |
|  Bundle with libc++_shared.so (Android) -> Tarball (.tar.gz) + SHA-256                   |
|  -> Upload to GitHub Releases (v${version})                                             |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v (HTTP Fetch)
+-----------------------------------------------------------------------------------------+
|                           Consumer Build (hook/build.dart)                              |
|                                                                                         |
|  1. Detect Target: (OS, Architecture)                                                   |
|  2. Check Cache: `.dart_tool/vieneu_tts/cache/v${version}/${target}/`                   |
|  3. If missing: Download tarball, verify SHA-256 checksum, extract to cache             |
|  4. Register CodeAsset:                                                                 |
|     - Android: librust_lib_vieneu_tts.so + libc++_shared.so                             |
|     - Linux/iOS: librust_lib_vieneu_tts.so / dylib                                      |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
|                                   Application Runtime                                   |
|                                                                                         |
|  Dart/Flutter bundles native libs into APK / executable                                 |
|  FRB loads via @ffi.DefaultAsset -> In-process synthesis & streaming                    |
+-----------------------------------------------------------------------------------------+
```

## Risks / Trade-offs

- **[Risk] Network failure on initial build** → Mitigation: Cache binaries permanently in `.dart_tool/`; support `VIENEU_TTS_LOCAL_LIB` for offline or custom builds.
- **[Risk] Version mismatch between Dart bindings and native binary** → Mitigation: Strict URL binding matching `pubspec.yaml` package version and SHA-256 integrity verification.
- **[Risk] Android ABI mismatch in hybrid emulators** → Mitigation: Provide both `arm64-v8a` and `x86_64` prebuilts.
