# Design: VieNeu-TTS Dart Library with Flutter Rust Bridge & audio.cpp

## Context

See [proposal.md](proposal.md) for motivation and problem background.

The current repository contains a Python FastAPI server running `audio.cpp` in a dual-process container or Modal serverless function. To bring this capability directly to edge devices (Android and iOS) without requiring backend infrastructure, we are introducing a pure Dart API library wrapped around Rust and C++ through Flutter Rust Bridge (FRB v2).

A strict project constraint is: **no Rust or Flutter toolchains are installed on the local development machine**. All builds, code generation, linting, and tests must be executed remotely on GitHub Actions runners, with triggers and log inspection managed via the GitHub CLI (`gh`).

## Goals / Non-Goals

**Goals:**
- Provide a clean, idiomatic Dart API (`VieneuTts`) for in-process, offline speech synthesis and streaming.
- Target mobile platforms primarily (Android `arm64-v8a`, `x86_64` and iOS `arm64`).
- Support on-demand model download (Option A) to store the 188 MB GGUF model in local device storage.
- Embed all 25 voice presets directly in the native binary so no extra voice asset downloads are required.
- Isolate existing workflows (`deploy-modal.yml`, `docker-build.yml`) using path filtering so changes to the Dart package never trigger server deployments or container builds.
- Provide a fully automated GitHub Actions CI pipeline with `workflow_dispatch` and path triggers.

**Non-Goals:**
- Audio playback UI or audio device output management (developers use their preferred audio player plugin such as `audioplayers` or `just_audio`).
- Server-side Python changes or modifying existing Modal/Docker APIs.

## Decisions

### 1. Flutter Rust Bridge (FRB v2) as the FFI Layer
- **Decision**: Use `flutter_rust_bridge` version 2 to bridge Dart and Rust.
- **Rationale**: FRB v2 provides zero-copy binary transfer, native Dart `Stream` support via `StreamSink`, robust memory management, and automatic packaging scripts for Android Gradle and iOS CocoaPods.
- **Alternatives Considered**: Raw `dart:ffi` with manual C ABI. Rejected due to high maintenance burden, complex string and array marshaling, and manual threading/stream synchronization.

### 2. Rust Engine Architecture (`audio-cpp` + `sea-g2p-rs`)
- **Decision**: Combine `audio-cpp` (configured with `model-vieneu-v3-turbo`) and `sea-g2p-rs` (with `default-features = false`, dropping PyO3) in the Rust bridge crate.
- **Rationale**:
  - `sea-g2p-rs` handles Vietnamese text normalization, numbers, abbreviations, and emotion tags directly in Rust to produce IPA phonemes in ~1ms.
  - `audio-cpp` handles GGUF model memory-mapping and 48 kHz MOSS neural codec decoding.
  - Doing G2P and inference together inside Rust keeps the Dart API simple: callers pass natural Vietnamese strings without needing separate G2P preprocessing.

### 3. Voice Presets Embedding
- **Decision**: Embed the text representations of the 25 voice presets (`ref_codes.txt` and `speaker.emb.txt`) directly in the Rust binary using `include_str!`.
- **Rationale**: The 25 presets total less than 1 MB of text data. Embedding them eliminates the need for downloading 25 separate voice files or managing asset bundles in client apps. Users only need to download the base `model.gguf` (188 MB).
- **Alternatives Considered**: Bundling voice files in Flutter `assets/` or downloading on demand. Downloading on demand creates network failure points and asset bundling complicates pure Dart package distribution.

### 4. CI Workflow Architecture & Path Filtering
- **Decision**:
  - Update `.github/workflows/deploy-modal.yml` to trigger only on `modal_app.py`, `requirements.txt`, `preset_voices/**`, and `.github/workflows/deploy-modal.yml`.
  - Update `.github/workflows/docker-build.yml` paths similarly.
  - Create `.github/workflows/vieneu-tts-lib.yml` with paths restricted to `packages/vieneu_tts/**` and `.github/workflows/vieneu-tts-lib.yml`.
  - Add `workflow_dispatch` to `.github/workflows/vieneu-tts-lib.yml` with parameters for `target` (`android`, `ios`, `desktop`, `all`) and `run_e2e_test` (boolean to trigger model download and inference verification).
- **Rationale**: Completely isolates CI runs and ensures no accidental deployments.

### 5. Flutter Example App & CI APK Packaging
- **Decision**: Provide a standalone Flutter example application in `packages/vieneu_tts/example/` and add an automated APK packaging job to CI.
- **Rationale**:
  - Users need a reference mobile app proving full on-device functionality: on-demand download of `model.gguf` (188 MB) and `sea_g2p.bin` (60 MB) into app sandbox (`path_provider`), offline engine initialization, voice preset selection (25 voices), text input, and audio playback (`audioplayers`).
  - In `.github/workflows/vieneu-tts-lib.yml`, a dedicated `Build Android Release APK` job builds the Flutter APK with compiled Rust JNI libs (`arm64-v8a`) and publishes the `.apk` as an artifact (`vieneu-tts-android-apk`), allowing immediate installation and manual testing on real Android hardware without local compilation.

## Architecture & Data Flow

```
+--------------------------------------------------------------------------+
|                         Dart API (VieneuTts)                             |
|                                                                          |
|   synthesize(text, voice)               stream(text, voice)              |
+--------------------------+-----------------------+-----------------------+
                           |                       |
                           | FRB v2 Calls          | StreamSink<Uint8List>
                           v                       v
+--------------------------------------------------------------------------+
|                     Rust Bridge (libvieneu_tts)                          |
|                                                                          |
|   1. sea-g2p-rs: Natural Text -> IPA Phonemes                            |
|   2. embedded_voices: Voice ID -> (ref_codes, speaker_embedding)         |
|   3. audio-cpp: Model Session (offline mode)                             |
|      - Run inference on CPU threads (2-4 threads)                        |
|      - Decode 48 kHz stereo audio frames                                 |
|      - Emit chunk bytes / WAV header                                     |
+--------------------------------------------------------------------------+
```

## Risks / Trade-offs

- **[Risk] CMake / NDK build time on GitHub Actions** → Mitigation: Use GitHub Actions caching (`actions/cache` / `Swatinem/rust-cache`) for `target/` and CMake build directories to keep incremental builds under 2 minutes.
- **[Risk] Android NDK compatibility across multiple ABIs** → Mitigation: Target `arm64-v8a` as primary, with `x86_64` for emulators; configure `cargo-ndk` standard CMake toolchain flags in the workflow.
- **[Risk] Large model download failure on mobile devices** → Mitigation: Implement chunked HTTP streaming with resume and progress callbacks in `downloadModel`.

## Migration Plan

1. Path filters in existing workflows take effect immediately upon merge without affecting production deployments.
2. The Dart library is placed in `packages/vieneu_tts/`, leaving root-level files untouched.
