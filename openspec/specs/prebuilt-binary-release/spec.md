# prebuilt-binary-release Specification

## Purpose

Automates cross-compilation, bundling of required runtime libraries (including `libc++_shared.so` for Android), archive creation, checksum generation, and release publishing to GitHub Releases across supported platforms.

## Requirements

### Requirement: Matrix Release Cross-Compilation
The CI pipeline SHALL compile the native Rust crate into shared or static libraries for Linux (`x86_64`), Android (`arm64-v8a`, `x86_64`), and iOS (`arm64`, `simulator`).

#### Scenario: Building native release artifacts
- **WHEN** a release workflow is triggered by version tag or manual dispatch
- **THEN** compilation jobs produce optimized native binary artifacts for all targeted architectures.

### Requirement: Android Runtime Library Bundling
For Android targets, the release packager SHALL bundle `libc++_shared.so` alongside `librust_lib_vieneu_tts.so` within the release archive.

#### Scenario: Packaging Android prebuilt archive
- **WHEN** packaging Android `arm64-v8a` or `x86_64` targets
- **THEN** the archive contains both `librust_lib_vieneu_tts.so` and `libc++_shared.so`.

### Requirement: Release Asset Publishing with Checksums
The release pipeline SHALL generate SHA-256 checksums for each platform archive and upload all archives and checksum manifests to GitHub Releases.

#### Scenario: Uploading release assets
- **WHEN** all matrix compilation jobs finish successfully
- **THEN** archives named `vieneu_tts-<target>-v<version>.tar.gz` and a checksum manifest are uploaded to the matching GitHub Release tag.

### Requirement: Release Version and Tag Parity Verification
The release CI workflow SHALL verify that the target release version (from a `v*` git tag or `workflow_dispatch` input) matches the `version` field in `packages/vieneu_tts/pubspec.yaml` and `packages/vieneu_tts/rust/Cargo.toml` before building or publishing prebuilt artifacts.

#### Scenario: Release tag matches package manifests
- **WHEN** the release workflow is triggered for version `X.Y.Z` and both `pubspec.yaml` and `Cargo.toml` declare version `X.Y.Z`
- **THEN** the version verification check passes and the matrix compilation jobs proceed.

#### Scenario: Release tag mismatches package manifests
- **WHEN** the release workflow is triggered with a tag or input version that differs from `pubspec.yaml` or `Cargo.toml`
- **THEN** the workflow fails immediately with a clear version mismatch error before compiling or uploading release assets.

### Requirement: Dual-Mode CI Build Hook Verification
The CI pipeline SHALL verify that `vieneu_tts` builds and passes tests in both `source` mode (`VIENEU_TTS_BUILD_MODE=source`) and `prebuilt` consumer mode (`VIENEU_TTS_BUILD_MODE=prebuilt`).

#### Scenario: CI verifies source build mode
- **WHEN** the source-mode CI job runs with Rust and CMake/NDK toolchains installed and `VIENEU_TTS_BUILD_MODE=source`
- **THEN** `hook/build.dart` compiles the Rust crate from source and passes package verification tests.

#### Scenario: CI verifies prebuilt build mode in zero-Rust environment
- **WHEN** the prebuilt-mode CI job runs with `VIENEU_TTS_BUILD_MODE=prebuilt` (or in a toolchain-purged environment with prebuilt archives served)
- **THEN** `hook/build.dart` resolves the prebuilt archive, verifies SHA-256 integrity, and bundles the native assets without invoking Rust or NDK compilers.
