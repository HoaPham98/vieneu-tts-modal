# android-emulator-ci Specification

## Purpose
Cung cấp quy trình tự động hóa CI độc lập và kiểm thử tích hợp trên thiết bị Android ảo (Android Emulator) cho ứng dụng Flutter Example, đảm bảo toàn bộ vòng đời tải model, khởi tạo engine offline, tổng hợp WAV, và streaming âm thanh hoạt động hoàn hảo trước khi xuất bản bản Release APK.

## Requirements

### Requirement: Deactivated Monolithic CI Triggers
The previous monolithic CI workflow (`.github/workflows/vieneu-tts-lib.yml`) SHALL NOT be triggered automatically on push or pull requests, and SHALL only run on explicit manual invocation via `workflow_dispatch`.

#### Scenario: Push commit does not trigger legacy workflow
- **WHEN** changes are pushed to `main` affecting `packages/vieneu_tts/**`
- **THEN** only the dedicated Android Example App workflow triggers, leaving the legacy workflow idle.

### Requirement: Dual-Architecture Android NDK Compilation
The dedicated CI workflow SHALL compile the native Rust bridge library (`rust_lib_vieneu_tts`) and dependencies into shared libraries (`.so`) for both `arm64-v8a` (for physical Android devices) and `x86_64` (for CI Android Emulator).

#### Scenario: Compiling shared libraries for both ABIs
- **WHEN** the native build job runs
- **THEN** `cargo ndk` builds release artifacts producing `librust_lib_vieneu_tts.so` and `libsea_g2p_rs-*.so` under both `jniLibs/arm64-v8a/` and `jniLibs/x86_64/`.

### Requirement: Hardware-Accelerated Android Emulator Runner
The dedicated CI workflow SHALL initialize a hardware-accelerated (KVM) Android Virtual Device (AVD) running Android 11 (API 30) with Google APIs architecture `x86_64` on the Ubuntu runner.

#### Scenario: Emulator boot and readiness
- **WHEN** the test job executes on Ubuntu runner
- **THEN** KVM permissions are configured, AVD is booted headless, and ADB connects successfully to the running emulator.

### Requirement: On-Device UI Model & Dictionary Download
The integration test suite SHALL drive the Flutter Example UI on the Android emulator to initiate on-demand download of `vieneu-v3-turbo-q8_0.gguf` (~188 MB) and `sea_g2p.bin` (~13 MB) over the emulator's network interface and verify persistence in the application's document directory.

#### Scenario: UI download execution in emulator
- **WHEN** the test finds and taps the download button on the device screen
- **THEN** progress updates from 0% to 100%, files are persisted to app storage, and status confirms resources are ready.

### Requirement: On-Device Engine Initialization & Speech Synthesis
The integration test suite SHALL verify that the in-process TTS engine initializes in Android ART runtime and successfully synthesizes text into a valid WAV audio file.

#### Scenario: Synthesize speech to WAV on Android
- **WHEN** the test enters Vietnamese text, selects a voice preset, and taps the "Đọc (WAV)" button
- **THEN** the native engine generates audio without throwing exceptions, latency is displayed, and audio data exceeds standard 44-byte WAV header.

### Requirement: On-Device Real-Time Audio Chunk Streaming
The integration test suite SHALL verify that real-time streaming produces sequential PCM audio chunks via Dart `Stream<Uint8List>`.

#### Scenario: Stream speech chunks on Android
- **WHEN** the test taps the "Stream thời gian thực" button
- **THEN** multiple sequential audio chunks are emitted, first-chunk latency is captured, and the streaming task completes cleanly.

### Requirement: Release APK Packaging & Artifact Upload
The CI workflow SHALL compile a release Android APK targeting `arm64-v8a`, verify that native `.so` files are properly bundled inside the APK package, and upload the APK as an accessible artifact named `vieneu-tts-example-apk`.

#### Scenario: Build and upload release APK
- **WHEN** integration tests pass successfully
- **THEN** release APK is built, verified for embedded native libraries, and uploaded to GitHub Actions artifacts with 14-day retention.

### Requirement: Toolchain-Purged Consumer Verification
The CI workflow SHALL execute Android and Dart verification jobs in an environment with Rust, Cargo, and Android NDK purged, proving consumer applications build and run using prebuilt binaries without local native compilers.

#### Scenario: Building consumer app in purged environment
- **WHEN** consumer test job runs after removing Rust and NDK toolchains
- **THEN** `flutter build apk` succeeds and inspects that both `librust_lib_vieneu_tts.so` and `libc++_shared.so` are bundled in the resulting APK.
