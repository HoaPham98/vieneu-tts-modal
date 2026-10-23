# Tasks

## 1. Rust Audio Processing & Synthesis Options

- [x] 1.1 Implement voice identifier and display name resolution in `rust/src/embedded_voices.rs` supporting case-insensitive IDs and friendly titles (`'Mai Anh'` -> `'mai_anh'`), verified with cargo unit tests in `rust/src/embedded_voices.rs`.
- [x] 1.2 Implement channel downmixing (stereo-to-mono averaging, mono-to-stereo duplication) and resampling algorithms (fast-path 2:1 decimation with 2-point moving average for 48k -> 24k, linear interpolation for 16k and 8k) in `rust/src/api.rs`, verified with cargo unit tests.
- [x] 1.3 Implement `SynthesisOptions` struct and audio formatting for raw `s16le` PCM and 44-byte WAV container bytes in `rust/src/api.rs`, verified with hound and byte-buffer test assertions.
- [x] 1.4 Wire `SynthesisOptions` and sampling parameter propagation (`speaking_rate`, `temperature`, `top_k`, `top_p`, `repetition_penalty`, `text_chunk_size`, `text_chunk_min_size`, `seed`) into `synthesize_speech` and `stream_speech` in `rust/src/api.rs`.

## 2. Flutter Rust Bridge Codegen

- [x] 2.1 Run `flutter_rust_bridge_codegen generate` from `packages/vieneu_tts` to update the Dart-Rust bindings in `lib/src/rust/` and verify generated code compiles cleanly.

## 3. Dart High-Level API & Configuration

- [x] 3.1 Define `AudioFormat` enum (`pcm`, `wav`) and `TtsSynthesisOptions` class in `lib/vieneu_tts.dart` with all optional fields and default values matching Remote API specifications.
- [x] 3.2 Update `VieneuTts.synthesize` and `VieneuTts.stream` in `lib/vieneu_tts.dart` to accept `TtsSynthesisOptions` and optional named parameters with backward-compatible defaults (`wav` container for `synthesize`, raw `pcm` chunks for `stream`).
- [x] 3.3 Add voice catalog name resolution helper in Dart to match user-provided names against both `VoicePreset.id` and `VoicePreset.name`.

## 4. Testing & Verification

- [x] 4.1 Add unit tests in `packages/vieneu_tts/test/` validating `AudioFormat` and `TtsSynthesisOptions` configuration, default parameters, and voice name resolution.
- [x] 4.2 Add test cases validating PCM vs WAV output expectations, checking that raw PCM chunks contain no 44-byte WAV header and WAV outputs contain valid RIFF headers matching target sample rates and channel counts.
- [x] 4.3 Run `dart test` in `packages/vieneu_tts` to verify that all existing and new tests pass with zero regressions.
