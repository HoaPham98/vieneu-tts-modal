# Spec Delta

## Purpose

Automates cross-compilation, bundling of required runtime libraries (including `libc++_shared.so` for Android), archive creation, checksum generation, and release publishing to GitHub Releases across supported platforms.

## ADDED Requirements

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
