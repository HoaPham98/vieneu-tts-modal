# Tasks

## 1. Align `flutter_rust_bridge` 2.13.0 Dependencies & Bindings

- [x] 1.1 Update `flutter_rust_bridge` version to `=2.13.0` in `packages/vieneu_tts/rust/Cargo.toml` and `^2.13.0` (or `2.13.0`) in `packages/flutter_vieneu_tts/example/pubspec.yaml`, and verify `flutter pub get` succeeds in both packages.
- [x] 1.2 Regenerate Rust-to-Dart bindings using `flutter_rust_bridge_codegen generate` (v2.13.0) in `packages/vieneu_tts` and verify `packages/vieneu_tts/lib/src/rust/frb_generated.dart` reports `codegenVersion => '2.13.0'` and passes `dart analyze`.

## 2. Implement Hybrid Build Mode & Dynamic Version in `hook/build.dart`

- [x] 2.1 Replace the hardcoded `packageVersion` constant in `packages/vieneu_tts/hook/build.dart` with dynamic version resolution from `packages/vieneu_tts/pubspec.yaml`, and verify via unit test that the resolved version matches `pubspec.yaml`.
- [x] 2.2 Implement `_shouldBuildFromSource(BuildInput input)` in `packages/vieneu_tts/hook/build.dart` supporting `VIENEU_TTS_BUILD_MODE=source|prebuilt`, prebuilt override env vars (`VIENEU_TTS_LOCAL_LIB`, `VIENEU_TTS_BINARY_URL`, `VIENEU_TTS_LOCAL_ARCHIVE`), Pub cache detection (`.pub-cache` / `Pub\Cache`), `rust/Cargo.toml` presence, and `rustup` availability.
- [x] 2.3 Implement the `source` build path in `packages/vieneu_tts/hook/build.dart` using `FlutterRustBridgeNativeAssetsBuilder(assetName: 'rust_lib_vieneu_tts', cratePath: 'rust')` with `~/.cargo/bin` injected into `PATH` and automatic Android NDK `libc++_shared.so` lookup and `CodeAsset` registration when `targetOS == OS.android`.
- [x] 2.4 Add unit tests in `packages/vieneu_tts/test/build_hook_test.dart` covering dynamic version parsing from `pubspec.yaml`, `_shouldBuildFromSource` mode selection logic (`source`, `prebuilt`, Pub cache path, override env vars), and document `VIENEU_TTS_BUILD_MODE` in `packages/vieneu_tts/README.md`, verifying `dart test test/build_hook_test.dart` passes.

## 3. Enhance CI Workflows for Version Parity & Dual-Mode Testing

- [x] 3.1 Update `.github/workflows/vieneu-tts-native-release.yml` to add a version parity check (verifying git tag / dispatch version matches `packages/vieneu_tts/pubspec.yaml` and `packages/vieneu_tts/rust/Cargo.toml`) and upgrade toolchains to `flutter_rust_bridge_codegen` `v2.13.0`, Rust `1.93.1`, and Android NDK `r28`, verifying workflow YAML syntax is valid.
- [x] 3.2 Update `.github/workflows/vieneu-tts-lib.yml` and `.github/workflows/example-app-android.yml` to use `flutter_rust_bridge_codegen` `v2.13.0`, Rust `1.93.1`, and Android NDK `r28`, fix example paths to `packages/flutter_vieneu_tts/example`, and include explicit CI jobs testing both `VIENEU_TTS_BUILD_MODE=source` and `VIENEU_TTS_BUILD_MODE=prebuilt`, verifying workflow YAML structure and job dependencies.

## 4. Standardize Flutter Example App Template (Android & Windows)

- [x] 4.1 Remove legacy hand-crafted Android files in `packages/flutter_vieneu_tts/example/android` and re-scaffold platform directories using `flutter create --platforms=android,windows --org com.vieneu.tts --project-name vieneu_tts_example .` while preserving `lib/`, `test/`, `integration_test/`, and `pubspec.yaml`.
- [x] 4.2 Configure `android/app/src/main/AndroidManifest.xml` with `INTERNET` permission, align `applicationId` (`com.vieneu.tts.example`) with `.github/scripts/run_emulator_test.sh`, and verify `flutter analyze` and build/run on Android emulator (`emulator-5554`) succeed.
