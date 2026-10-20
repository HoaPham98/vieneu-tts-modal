# Tasks: VieNeu-TTS Dart Library with Flutter Rust Bridge & audio.cpp

## 1. Path Filtering & Workflow Isolation

- [x] 1.1 Update `.github/workflows/deploy-modal.yml` with explicit `paths:` filters (`modal_app.py`, `requirements.txt`, `preset_voices/**`, `.github/workflows/deploy-modal.yml`) to prevent unnecessary Modal deploys
- [x] 1.2 Verify and adjust `.github/workflows/docker-build.yml` paths to guarantee complete isolation from `packages/**` changes

## 2. Package Scaffolding & Rust Bridge Core

- [x] 2.1 Scaffold `packages/vieneu_tts/` Dart library structure (`pubspec.yaml`, `analysis_options.yaml`, `README.md`, `lib/vieneu_tts.dart`)
- [x] 2.2 Scaffold Rust bridge crate (`packages/vieneu_tts/rust/Cargo.toml`) with dependencies `flutter_rust_bridge`, `audio-cpp` (`model-vieneu-v3-turbo`), and `sea-g2p-rs`
- [x] 2.3 Implement embedded voice catalog (`packages/vieneu_tts/rust/src/embedded_voices.rs`) embedding `ref_codes.txt` and `speaker.emb.txt` for 25 presets from `preset_voices/`
- [x] 2.4 Implement Rust bridge API (`packages/vieneu_tts/rust/src/api.rs`) handling in-process engine initialization, natural text phonemization via SEA-G2P, full WAV synthesis, and chunked streaming

## 3. Dart Public API & Mobile Packaging

- [x] 3.1 Implement public Dart API `VieneuTts` (`lib/vieneu_tts.dart`) supporting `downloadModel`, `init`, `synthesize`, `stream`, and `availableVoices`
- [x] 3.2 Configure Android Gradle build script (`packages/vieneu_tts/android/build.gradle`) with NDK cross-compilation support for `arm64-v8a` and `x86_64`
- [x] 3.3 Configure iOS CocoaPods Podspec (`packages/vieneu_tts/ios/vieneu_tts.podspec`) for Apple Silicon and iOS arm64 linking

## 4. GitHub Actions CI & Remote Verification

- [x] 4.1 Create `.github/workflows/vieneu-tts-lib.yml` with `workflow_dispatch`, path filtering on `packages/vieneu_tts/**`, matrix jobs for codegen validation, Android NDK build, and iOS build
- [x] 4.2 Add automated E2E test job in CI that downloads `vieneu-v3-turbo-q8_0.gguf`, synthesizes sample Vietnamese audio, and verifies output WAV integrity
- [x] 4.3 Trigger the CI workflow using GitHub CLI (`gh workflow run vieneu-tts-lib.yml`), monitor execution with `gh run watch`, and verify logs using `gh run view`

## 5. Android Example Application & CI APK Artifact

- [ ] 5.1 Scaffold Flutter example app (`packages/vieneu_tts/example/`) with `path_provider` and `audioplayers` dependencies
- [ ] 5.2 Build example app UI for downloading model/dict, offline engine initialization, voice selection, and speech synthesis/playback
- [ ] 5.3 Add `Build Android Release APK` job to `.github/workflows/vieneu-tts-lib.yml` to compile release APK and upload `vieneu-tts-android-apk` artifact
- [ ] 5.4 Trigger CI workflow, monitor execution, and verify APK artifact download via `gh run download`

## Workflow follow-up

- Verify all GitHub Actions pass with green status across all jobs.
- Validate that pushing commits touching only `packages/vieneu_tts/` does NOT trigger `deploy-modal.yml` or `docker-build.yml`.
- Verify the generated `app-release.apk` artifact can be downloaded and inspected.
