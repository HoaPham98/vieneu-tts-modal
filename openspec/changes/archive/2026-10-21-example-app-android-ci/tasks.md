# Implementation Tasks

## 1. CI Workflow Management
- [x] 1.1 Update `.github/workflows/vieneu-tts-lib.yml` to remove `push` and `pull_request` triggers, keeping only `workflow_dispatch`
- [x] 1.2 Create `.github/workflows/example-app-android.yml` scaffold with `push` paths filter on `packages/vieneu_tts/**` and `workflow_dispatch`

## 2. Dual-Architecture NDK Compilation
- [x] 2.1 In `.github/workflows/example-app-android.yml`, configure job `build-native` to install Rust targets `aarch64-linux-android` and `x86_64-linux-android`
- [x] 2.2 Configure `cargo ndk` to compile both `arm64-v8a` and `x86_64` into `jniLibs/` and upload as an artifact

## 3. On-Device Integration Test Suite
- [x] 3.1 Update `packages/vieneu_tts/example/integration_test/app_test.dart` to test on-demand download via UI tap and progress completion
- [x] 3.2 Add test step verifying in-process engine initialization without runtime error
- [x] 3.3 Add test step driving "Đọc (WAV)" button and asserting generated WAV file validity
- [x] 3.4 Add test step driving "Stream thời gian thực" button and asserting PCM chunks stream

## 4. Android Emulator CI Job & Release APK Packaging
- [x] 4.1 In `.github/workflows/example-app-android.yml`, configure job `test-and-package` with KVM acceleration and `reactivecircus/android-emulator-runner@v2` (API 30, x86_64)
- [x] 4.2 Run `flutter test integration_test/app_test.dart` inside the running emulator
- [x] 4.3 Stage `arm64-v8a` libraries and build release APK (`flutter build apk --release --target-platform android-arm64`)
- [x] 4.4 Verify embedded `.so` libraries and upload release APK artifact `vieneu-tts-example-apk`

## 5. Execution & Verification
- [x] 5.1 Push changes to GitHub repository to trigger the dedicated workflow
- [x] 5.2 Monitor workflow execution via `gh run watch` until complete
- [x] 5.3 Verify integration test passes on Android Emulator and download release APK artifact
