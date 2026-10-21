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
