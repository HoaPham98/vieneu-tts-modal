# Spec Delta

## ADDED Requirements

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
