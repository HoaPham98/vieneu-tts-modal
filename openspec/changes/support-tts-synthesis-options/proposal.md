# Proposal

## Why

Currently, the `vieneu_tts` package (`packages/vieneu_tts`) exposes limited synthesis parameters in both Dart and Rust bridge layers (`synthesize_speech(text, voice, speed)`), outputting fixed 48 kHz stereo WAV bytes. In contrast, the Remote API (`POST /v1/audio/speech`) and realistic on-device mobile/desktop use cases require flexible audio sampling rates (e.g. 24 kHz, 16 kHz, 8 kHz), channel downmixing (Mono vs Stereo), raw PCM (`s16le`) output for low-latency streaming and audio player pipelines, flexible voice name resolution (matching display names like 'Mai Anh' to 'mai_anh'), and sampling controls (`temperature`, `top_k`, `top_p`, `repetition_penalty`, `text_chunk_size`, `seed`).

Upgrading `vieneu_tts` to support these parameters aligns on-device synthesis 1:1 with the Remote API capabilities while drastically reducing memory bandwidth, payload size, and playback latency.

## What Changes

- **Add `TtsSynthesisOptions` & `AudioFormat` in Dart**:
  - Provide a configuration class `TtsSynthesisOptions` (and corresponding optional named parameters on `VieneuTts.synthesize` and `VieneuTts.stream`) supporting `voice`, `speed`, `sampleRate`, `channels`, `responseFormat`, `temperature`, `topK`, `topP`, `repetitionPenalty`, `maxChars`, `minChars`, and `seed`.
  - Maintain full backward compatibility: default calls without extra options synthesize 24 kHz Mono WAV audio (or 48 kHz if configured), while `VieneuTts.stream()` defaults to raw PCM (`s16le`) chunks at 24 kHz Mono for direct streaming playback without WAV headers.
  - Case-insensitive voice name and alias mapping supporting both IDs (`minh_quan_pro`, `mai_anh`) and display names (`Minh Quân Pro`, `Mai Anh`).
- **Rust Native Bridge Options & Audio Processing (`rust/src/api.rs`)**:
  - Introduce `SynthesisOptions` struct in Rust with full parameter support.
  - Implement channel downmix: downmix 2-channel stereo audio to 1-channel mono by averaging frame channels.
  - Implement resampler: high-performance fast-path 2:1 decimation with anti-aliasing/2-point averaging for 48 kHz -> 24 kHz downsampling, and linear interpolation for 16 kHz and 8 kHz target rates.
  - Audio encoding: output raw little-endian signed 16-bit PCM bytes (`s16le`) when format is `'pcm'`, or valid 44-byte RIFF/WAVE header formatted data when format is `'wav'`.
  - Pass inference options (`speaking_rate`, `temperature`, `top_k`, `top_p`, `repetition_penalty`, `text_chunk_size`, `text_chunk_min_size`, `seed`) into `Request::tts()` for `audio_cpp`.
- **Streaming Chunks Optimization**:
  - `stream_speech` accepts full synthesis options.
  - Emits pure raw PCM byte chunks when `response_format == "pcm"` to allow gapless playback without parsing or stripping WAV headers on subsequent chunks.
- **FRB Codegen & Verification**:
  - Run `flutter_rust_bridge_codegen generate` to update bindings.
  - Add comprehensive unit tests in `packages/vieneu_tts/test/` verifying options encoding, voice alias mapping, PCM vs WAV byte sizes, downmixing, and sample rate downscaling.

## Capabilities

### New Capabilities
- `tts-synthesis-options`: Full TTS inference options, audio format conversion (PCM / WAV), channel downmixing (Mono / Stereo), dynamic resampling (48k, 24k, 16k, 8k), and streaming chunk delivery for `vieneu_tts`.

### Modified Capabilities
<!-- None: No existing capability requirements are modified; this introduces client synthesis options. -->

## Impact

- **Codebases affected**:
  - `packages/vieneu_tts/rust/src/api.rs`: Struct definitions, resampling/downmix algorithms, sampling parameters plumbing.
  - `packages/vieneu_tts/rust/src/embedded_voices.rs`: Flexible case-insensitive name and display title lookup.
  - `packages/vieneu_tts/lib/vieneu_tts.dart`: `TtsSynthesisOptions`, `AudioFormat`, updated `synthesize` and `stream` methods.
  - `packages/vieneu_tts/lib/src/rust/`: Auto-generated bindings from `flutter_rust_bridge_codegen`.
  - `packages/vieneu_tts/test/`: New and updated unit tests.
- **Dependencies**: Uses existing `hound` and `audio_cpp` crates; no additional heavy third-party dependencies required.
- **Compatibility**: 100% backward-compatible with existing call signatures (`synthesize(text: ..., voice: ..., speed: ...)`).
