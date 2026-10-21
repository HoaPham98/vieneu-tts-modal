# Proposal

## Why

Currently, `vieneu_tts` is configured as a monolithic Flutter Android plugin relying on manual JNI staging and requiring a full Rust/Cargo/NDK toolchain on the developer's machine to build or link native code. To enable broad adoption across the Dart and Flutter ecosystem, third-party applications must be able to add the library and run speech synthesis out-of-the-box without installing Rust, Cargo, Android NDK, or C++ compilers. Transitioning to Dart Native Assets (`hook/build.dart`) with automated GitHub Releases prebuilt binary distribution and splitting into a pure Dart core with a Flutter wrapper package solves this barrier.

## What Changes

- **Monorepo Structure**: Separate into a pure Dart package (`packages/vieneu_tts`) and a Flutter wrapper package (`packages/flutter_vieneu_tts`).
- **Dart Native Assets Integration**: Replace legacy Gradle/cargokit build mechanics with Dart Native Assets (`hook/build.dart`), using `CodeAsset` to link `librust_lib_vieneu_tts` and `libc++_shared.so`.
- **Prebuilt Binary Artifacts**: Automatically download, checksum-verify, cache, and link platform-specific prebuilt binaries from GitHub Releases on Android (`arm64-v8a`, `x86_64`), iOS (`arm64`, `simulator`), and Linux (`x86_64`).
- **Tracked Bridge Bindings**: Remove `lib/src/rust/` from `.gitignore` and commit generated Dart FFI bindings into version control so consumers have complete Dart code without needing `flutter_rust_bridge_codegen`.
- **Zero-Toolchain CI Verification**: Establish a hermetic consumer verification test pipeline in GitHub Actions that purges all Rust and NDK toolchains and proves clean third-party app builds and on-device execution.

## Capabilities

### New Capabilities
- `dart-native-assets`: Defines build hook resolution (`hook/build.dart`), binary caching in `.dart_tool`, SHA-256 checksum verification, and dynamic `CodeAsset` registration for Linux, Android, and iOS.
- `flutter-wrapper-api`: Defines the `flutter_vieneu_tts` wrapper package that auto-resolves app sandbox directories using `path_provider`, exposes UI download progress notifiers, and hosts the Flutter example application.
- `prebuilt-binary-release`: Defines the CI release matrix, binary bundling (including `libc++_shared.so` for Android), archive creation (`.tar.gz`), and publishing to GitHub Releases.

### Modified Capabilities
- `android-emulator-ci`: Update the on-device emulator test pipeline to verify APK integrity and runtime synthesis in a zero-Rust, zero-NDK consumer environment.

## Impact

- **Consumer Apps**: Can add `vieneu_tts` (Dart) or `flutter_vieneu_tts` (Flutter) without having Rust or NDK installed.
- **Repository Structure**: `packages/vieneu_tts` becomes a pure Dart library (Flutter SDK dependency removed); `packages/flutter_vieneu_tts` hosts Flutter-specific conveniences and the example app.
- **Git Tracking**: `packages/vieneu_tts/lib/src/rust/` is tracked in git; native `.so`/`.dylib` remain gitignored and are fetched dynamically.
- **CI/CD**: Introduces a native matrix release workflow and a toolchain-purged consumer verification test.
