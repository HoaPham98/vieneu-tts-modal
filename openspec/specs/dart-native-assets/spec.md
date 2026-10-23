# dart-native-assets Specification

## Purpose

Enables pure Dart and Flutter applications to execute on-device VieNeu-TTS synthesis via Dart Native Assets build hooks, dynamically resolving and packaging prebuilt native binaries without requiring host Rust or NDK toolchains.

## Requirements

### Requirement: Native Assets Hook Execution
The `vieneu_tts` package SHALL provide a build hook at `hook/build.dart` conforming to the Dart Native Assets specification that is automatically executed during Dart and Flutter builds.

#### Scenario: Build hook runs during application build
- **WHEN** consumer runs `dart run`, `dart build`, `flutter run`, or `flutter build`
- **THEN** `hook/build.dart` executes and receives target OS and architecture information.

### Requirement: Prebuilt Artifact Resolution and Caching
The build hook SHALL resolve, download, verify via SHA-256, and cache platform-specific prebuilt binaries matching the package version from GitHub Releases.

#### Scenario: Downloading prebuilt binary on cache miss
- **WHEN** consumer machine does not have the prebuilt binary for the requested target in `.dart_tool/`
- **THEN** the hook downloads the corresponding archive from GitHub Releases, verifies its SHA-256 checksum, and extracts it to the local cache directory.

#### Scenario: Reusing cached prebuilt binary
- **WHEN** the prebuilt binary already exists in `.dart_tool/` with valid integrity
- **THEN** the hook skips downloading and uses the cached binary immediately.

### Requirement: CodeAsset Registration
The build hook SHALL register the native shared library as a `CodeAsset` with dynamic bundling mode for the current target platform.

#### Scenario: Android target registers native libraries
- **WHEN** target platform is Android
- **THEN** the hook registers both `librust_lib_vieneu_tts.so` and `libc++_shared.so` as bundled code assets.

#### Scenario: Linux or iOS target registers native library
- **WHEN** target platform is Linux or iOS
- **THEN** the hook registers the platform-appropriate binary (`librust_lib_vieneu_tts.so` or framework/dylib) as a bundled code asset.

### Requirement: Local Build Override
The build hook SHALL allow developers to override binary download by providing an explicit local binary path via an environment variable.

#### Scenario: Local binary path provided
- **WHEN** `VIENEU_TTS_LOCAL_LIB` points to an existing shared library file
- **THEN** the build hook registers that file as the code asset and bypasses network downloads.

### Requirement: Hybrid Build Mode Detection
The build hook SHALL automatically select between local source compilation mode (`source`) and prebuilt binary resolution mode (`prebuilt`) based on environment overrides, package location, and host toolchain availability.

#### Scenario: Explicit build mode override via environment variable
- **WHEN** `VIENEU_TTS_BUILD_MODE` is set to `source` or `prebuilt`
- **THEN** the build hook executes the requested mode regardless of package location.

#### Scenario: Automatic source mode in local repository development
- **WHEN** `VIENEU_TTS_BUILD_MODE` is unset, no prebuilt override variables (`VIENEU_TTS_LOCAL_LIB`, `VIENEU_TTS_BINARY_URL`, `VIENEU_TTS_LOCAL_ARCHIVE`) are set, `packageRoot` is outside the Pub cache, `rust/Cargo.toml` exists, and `rustup` is available on the host
- **THEN** the build hook selects `source` mode and compiles the native library directly from the local Rust crate.

#### Scenario: Automatic prebuilt mode for package consumers
- **WHEN** `packageRoot` resides inside `.pub-cache` or `Pub\Cache`, or `rustup` is unavailable on the host, or a prebuilt override variable is set
- **THEN** the build hook selects `prebuilt` mode and resolves precompiled native binaries without invoking Cargo.

### Requirement: Local Source Compilation Mode
When operating in `source` mode, the build hook SHALL compile the local Rust crate using the Native Assets Rust builder, track Rust source dependencies for incremental rebuilds, and bundle `libc++_shared.so` from the Android NDK when targeting Android.

#### Scenario: Compiling from source on desktop or mobile target
- **WHEN** the build hook runs in `source` mode
- **THEN** it compiles the `rust/` crate for the target architecture, registers the resulting library as the `rust_lib_vieneu_tts` `CodeAsset`, and records Rust source files in `output.dependencies`.

#### Scenario: Bundling Android C++ runtime in source mode
- **WHEN** the build hook runs in `source` mode for an Android target
- **THEN** it locates `libc++_shared.so` for the target ABI from the configured Android NDK sysroot and registers it as an additional bundled `CodeAsset`.

### Requirement: Dynamic Package Version Resolution
The build hook SHALL dynamically read the package version from `pubspec.yaml` at `packageRoot` instead of relying on a hardcoded version string when resolving prebuilt cache paths and release download URLs.

#### Scenario: Resolving prebuilt archive URL from pubspec version
- **WHEN** the build hook runs in `prebuilt` mode for a package with `version: X.Y.Z` in `pubspec.yaml`
- **THEN** it resolves the cache directory and GitHub Release archive URL using `vX.Y.Z`.
