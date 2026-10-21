# Tasks

## 1. Monorepo Reorganization & Git Tracking

- [x] 1.1 Remove `lib/src/rust/` and `rust/src/frb_generated.*` from `.gitignore` and verify `git status` tracks Dart binding files
- [x] 1.2 Convert `packages/vieneu_tts` to a pure Dart package by updating `pubspec.yaml` (minimum SDK `^3.5.0`, remove Flutter SDK dependency) and verify `dart pub get` succeeds
- [x] 1.3 Scaffold `packages/flutter_vieneu_tts` as the Flutter wrapper package depending on `vieneu_tts` and verify `flutter pub get` resolves cleanly
- [x] 1.4 Move the Flutter example application to `packages/flutter_vieneu_tts/example` and update its dependencies to point to `flutter_vieneu_tts`

## 2. Dart Native Assets Implementation (`hook/build.dart`)

- [x] 2.1 Add `native_assets_cli` and `hooks` dependencies to `packages/vieneu_tts/pubspec.yaml` and verify dependency resolution
- [x] 2.2 Implement `packages/vieneu_tts/hook/build.dart` with target platform resolution (Linux x64, Android arm64/x64, iOS arm64) and local cache lookup in `.dart_tool/vieneu_tts/cache/`
- [x] 2.3 Implement download, SHA-256 integrity verification, and archive extraction logic within `hook/build.dart`
- [x] 2.4 Register dynamic `CodeAsset` in `build.dart` (including both `librust_lib_vieneu_tts.so` and `libc++_shared.so` for Android targets)
- [x] 2.5 Add `VIENEU_TTS_LOCAL_LIB` and `VIENEU_TTS_BINARY_URL` environment overrides for development and test workflows

## 3. Flutter Wrapper API & Example App

- [x] 3.1 Implement `VieneuTtsFlutter` in `packages/flutter_vieneu_tts` with automatic sandbox directory resolution via `path_provider` and verify unit tests pass
- [x] 3.2 Implement reactive `downloadProgress` notifiers and model availability checks in `flutter_vieneu_tts`
- [x] 3.3 Update `packages/flutter_vieneu_tts/example/lib/main.dart` to use `VieneuTtsFlutter` and verify `flutter analyze` passes with zero errors

## 4. CI Matrix Release & Toolchain-Purged Verification Pipelines

- [x] 4.1 Create `.github/workflows/vieneu-tts-native-release.yml` to compile native libraries for Linux x64, Android arm64/x64 (bundling `libc++_shared.so`), and iOS, creating `.tar.gz` release archives with checksums
- [x] 4.2 Create a toolchain-purged test job in `.github/workflows/example-app-android.yml` that removes `cargo`, `rustc`, and `$ANDROID_HOME/ndk`
- [ ] 4.3 Verify in CI that a clean consumer app builds release APK and bundles both `librust_lib_vieneu_tts.so` and `libc++_shared.so` without compiling from source
- [ ] 4.4 Run on-device Android emulator integration test verifying speech synthesis with prebuilt native assets
