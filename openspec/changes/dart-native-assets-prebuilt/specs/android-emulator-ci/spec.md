# Spec Delta

## ADDED Requirements

### Requirement: Toolchain-Purged Consumer Verification
The CI workflow SHALL execute Android and Dart verification jobs in an environment with Rust, Cargo, and Android NDK purged, proving consumer applications build and run using prebuilt binaries without local native compilers.

#### Scenario: Building consumer app in purged environment
- **WHEN** consumer test job runs after removing Rust and NDK toolchains
- **THEN** `flutter build apk` succeeds and inspects that both `librust_lib_vieneu_tts.so` and `libc++_shared.so` are bundled in the resulting APK.
