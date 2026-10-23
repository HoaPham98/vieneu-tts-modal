# Design

## Context

The `vieneu_tts` package provides on-device neural TTS using `audio.cpp` and `sea_g2p_rs`. Currently:
- The Dart API exposes `synthesize(text, voice, speed)` and `stream(text, voice, speed)`.
- The Rust native layer (`rust/src/api.rs`) outputs hardcoded 48 kHz stereo WAV bytes regardless of client needs.
- The remote API (`POST /v1/audio/speech` in `modal_app.py`) accepts rich sampling parameters (`temperature`, `top_k`, `top_p`, `repetition_penalty`, `max_chars`) and supports 24 kHz mono output in both `pcm` and `wav` formats.
- Mobile and embedded applications experience unnecessary memory pressure and latency streaming 48 kHz stereo WAV headers on every audio slice.

See `proposal.md` for motivation and `specs/tts-synthesis-options/spec.md` for formal requirements.

## Goals / Non-Goals

**Goals:**
- Provide full feature parity between `vieneu_tts` local on-device synthesis options and the remote OpenAI-compatible `/v1/audio/speech` endpoint.
- Support target sample rates (`48000`, `24000`, `16000`, `8000` Hz) with zero-dependency, high-performance in-memory resampling.
- Support mono (1-channel downmix) and stereo (2-channel passthrough).
- Support raw `s16le` PCM byte output without headers, as well as valid 44-byte RIFF/WAVE containers.
- Deliver gapless PCM chunk streaming in `VieneuTts.stream` with default 24 kHz Mono format.
- Maintain full backward compatibility for existing Dart and Rust caller signatures.

**Non-Goals:**
- Supporting MP3, Opus, or AAC container encoding inside the Rust crate (these require FFmpeg or large external codec libraries; mobile apps can compress PCM/WAV using standard OS audio encoders).
- Arbitrary non-standard fractional resampling beyond standard telephony and speech rates (e.g. 44.1 kHz or 22.05 kHz are out of scope for voice TTS models).

## Decisions

### 1. `TtsSynthesisOptions` Data Structure & Parameter Ergonomics
**Decision**:
Introduce a `TtsSynthesisOptions` Dart class with an accompanying `AudioFormat` enum (`pcm`, `wav`).
On `VieneuTts.synthesize` and `VieneuTts.stream`, provide both an `options: TtsSynthesisOptions?` parameter and optional named parameters (`voice`, `speed`, `sampleRate`, `channels`, `responseFormat`, etc.) for seamless developer experience.

*Rationale*: Allows developers to define reusable synthesis presets while preserving straightforward one-liner calls.

### 2. Rust `SynthesisOptions` Struct & Bridge Signature
**Decision**:
Define a single `SynthesisOptions` struct in `rust/src/api.rs`:
```rust
pub struct SynthesisOptions {
    pub voice: Option<String>,
    pub speed: Option<f32>,
    pub sample_rate: Option<u32>,
    pub channels: Option<u16>,
    pub response_format: Option<String>,
    pub temperature: Option<f32>,
    pub top_k: Option<i32>,
    pub top_p: Option<f32>,
    pub repetition_penalty: Option<f32>,
    pub max_chars: Option<i32>,
    pub min_chars: Option<i32>,
    pub seed: Option<i32>,
}
```
Update `synthesize_speech` and `stream_speech` to accept `options: Option<SynthesisOptions>`.

*Alternative considered*: Adding 12 separate arguments to each function.
*Why rejected*: Parameter lists of 10+ arguments are unwieldy across the FFI bridge and break ABI stability whenever new sampling parameters are introduced.

### 3. Stereo-to-Mono Downmixing Algorithm
**Decision**:
Compute mono audio by averaging the left and right channels for each frame:
```rust
mono_sample = (stereo_samples[2 * i] + stereo_samples[2 * i + 1]) * 0.5;
```
If the model ever outputs mono and stereo is requested, duplicate the mono channel to both L and R.

*Rationale*: Prevents clipping without altering perceived loudness or phase cancellation for speech synthesis outputs.

### 4. Zero-Dependency Resampling Algorithm
**Decision**:
Model outputs 48000 Hz audio natively.
- **Fast-path 2:1 decimation (48 kHz -> 24 kHz)**:
  Apply a 2-point moving average anti-aliasing decimation:
  `y[n] = (x[2n] + x[2n + 1]) * 0.5`.
  This executes in a single SIMD-friendly loop with minimal CPU overhead.
- **Linear interpolation (48 kHz -> 16 kHz or 8 kHz)**:
  Ratio is integer 3:1 for 16 kHz and 6:1 for 8 kHz. Compute downsampled points via linear interpolation between neighboring samples.

*Alternative considered*: Pulling in external resampling crates like `rubato` or `dasp`.
*Why rejected*: Avoids adding large transitive dependencies, C++ linkage risks, or lookup table overhead into native asset builds. Speech at 24 kHz decimation with anti-aliasing preserves pristine acoustic quality.

### 5. Audio Output Encoding
**Decision**:
- When `response_format == "pcm"`: Convert clamped float samples `[-1.0, 1.0]` to `i16` signed little-endian bytes (`val.to_le_bytes()`) directly into `Vec<u8>`. No container header.
- When `response_format == "wav"`: Pass samples to `samples_to_wav` specifying `target_sample_rate` and `target_channels`. Emits a 44-byte standard RIFF/WAVE header followed by the `s16le` payload.

### 6. Voice Name & Alias Resolution
**Decision**:
Extend `get_voice_data` in `rust/src/embedded_voices.rs` to normalize query strings:
- Strip whitespace, lowercase, and remove underscores/spaces.
- Match both ID (`mai_anh` -> `maianh`) and display name (`Mai Anh` -> `maianh`).
- Fall back gracefully to `minh_quan_pro` if no match is found.

## Risks / Trade-offs

- **[Risk] Downsampling aliasing**: Direct decimation without low-pass filtering can cause subtle high-frequency aliasing.
  → *Mitigation*: 2-point moving average acts as a first-order low-pass filter with a zero at 24 kHz (Nyquist frequency), adequately suppressing foldover frequencies for speech.
- **[Risk] FRB binding synchronization**: Updating Rust signatures requires regenerating Dart bindings.
  → *Mitigation*: Run `flutter_rust_bridge_codegen generate` and include generated files in the changes, backed by automated unit tests.
- **[Risk] Backward compatibility**: Consumers relying on `synthesize(text, voice, speed)` must not experience compile or runtime breakage.
  → *Mitigation*: Preserve default parameter values matching previous behavior while providing optional options.

## Migration Plan

1. Implement core audio algorithms (resampling, downmixing, PCM conversion) in `packages/vieneu_tts/rust/src/api.rs`.
2. Update voice lookup in `embedded_voices.rs`.
3. Add `SynthesisOptions` struct and update `synthesize_speech` and `stream_speech`.
4. Run `flutter_rust_bridge_codegen generate`.
5. Implement `TtsSynthesisOptions`, `AudioFormat`, and update `VieneuTts.synthesize` / `VieneuTts.stream` in `lib/vieneu_tts.dart`.
6. Add unit tests in `packages/vieneu_tts/test/` to verify byte lengths, headers, and parameter passthrough.
