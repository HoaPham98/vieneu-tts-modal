# Spec Delta

## Purpose

Enables configurable on-device VieNeu-TTS speech synthesis with customizable sampling rates, channel downmix, raw PCM or WAV audio containers, voice name alias resolution, and sampling parameter controls matching Remote API capabilities.

## ADDED Requirements

### Requirement: Configurable Synthesis Options in Dart API
The `vieneu_tts` package SHALL provide a `TtsSynthesisOptions` configuration class and optional named parameters on `VieneuTts.synthesize` and `VieneuTts.stream` supporting voice selection, speaking rate, target sample rate, channel count, audio response format, and inference sampling parameters.

#### Scenario: Synthesizing with custom options
- **WHEN** consumer calls `VieneuTts.synthesize` with custom `sampleRate: 24000`, `channels: 1`, `responseFormat: AudioFormat.pcm`, and `temperature: 0.8`
- **THEN** the native engine applies the requested settings and returns raw 24 kHz mono PCM bytes.

#### Scenario: Synthesizing with default options (backward compatibility)
- **WHEN** consumer calls `VieneuTts.synthesize(text: "Xin chào")` without extra parameters
- **THEN** synthesis completes using `minh_quan_pro`, speed `1.0`, sample rate `24000`, mono channels `1`, and returns standard WAV bytes with a valid 44-byte header.

### Requirement: Flexible Voice Identifier and Name Resolution
The native engine and Dart interface SHALL resolve voice inputs case-insensitively, supporting both preset IDs (e.g. `mai_anh`, `minh_quan_pro`) and natural display names (e.g. `Mai Anh`, `Minh Quân Pro`), gracefully falling back to `minh_quan_pro` if an unrecognized voice is provided.

#### Scenario: Resolving voice by display name
- **WHEN** synthesis is requested with `voice: "Mai Anh"`
- **THEN** the engine resolves reference codes and speaker embeddings corresponding to the `mai_anh` preset.

#### Scenario: Resolving voice by preset ID
- **WHEN** synthesis is requested with `voice: "mai_anh"`
- **THEN** the engine loads the `mai_anh` preset files.

#### Scenario: Fallback for unknown voice
- **WHEN** synthesis is requested with an invalid or unrecognized voice name
- **THEN** the engine falls back to `minh_quan_pro` without throwing an error.

### Requirement: Audio Format Container and Raw PCM Output
The native synthesis engine SHALL format synthesized audio according to the specified `response_format`, producing raw 16-bit little-endian PCM (`s16le`) bytes without container headers when `pcm` is requested, and standard RIFF/WAVE container bytes with a 44-byte header when `wav` is requested.

#### Scenario: Requesting raw PCM output
- **WHEN** synthesis is invoked with `responseFormat: "pcm"`
- **THEN** the returned byte array consists strictly of raw `s16le` samples whose byte length equals `samples_count * channels * 2` without a 44-byte RIFF header.

#### Scenario: Requesting WAV container output
- **WHEN** synthesis is invoked with `responseFormat: "wav"`
- **THEN** the returned byte array starts with ASCII `RIFF` and `WAVE`, contains a 44-byte header specifying the exact sample rate and channel count, followed by `s16le` sample data.

### Requirement: Dynamic Audio Downmixing and Resampling
The native audio processing pipeline SHALL convert synthesized audio buffers (native 48 kHz stereo) to the target channel count and sampling rate, averaging stereo channels when mono (1 channel) is requested, and resampling between supported sample rates (48000 Hz, 24000 Hz, 16000 Hz, 8000 Hz).

#### Scenario: Resampling 48kHz audio to 24kHz Mono
- **WHEN** audio output is synthesized with `sampleRate: 24000` and `channels: 1`
- **THEN** stereo channels are averaged to mono and samples are decimated 2:1 from 48000 Hz to 24000 Hz, producing exactly half the sample count of a 48 kHz mono stream.

#### Scenario: Resampling to lower sample rates (16kHz or 8kHz)
- **WHEN** audio output is synthesized with `sampleRate: 16000` or `sampleRate: 8000`
- **THEN** the audio is resampled via linear interpolation to match the requested sample rate accurately.

#### Scenario: Preserving native 48kHz Stereo
- **WHEN** audio output is synthesized with `sampleRate: 48000` and `channels: 2`
- **THEN** the raw 48 kHz stereo audio samples are preserved without downmixing or resampling.

### Requirement: Sampling Parameters Pass-Through to Native Engine
The inference pipeline SHALL pass optional sampling hyperparameters (`temperature`, `top_k`, `top_p`, `repetition_penalty`, `text_chunk_size`, `text_chunk_min_size`, `seed`) into the underlying `audio_cpp` inference request when values are provided.

#### Scenario: Inference with custom sampling parameters
- **WHEN** synthesis options specify `temperature: 0.7`, `topK: 50`, `topP: 0.9`, `repetitionPenalty: 1.1`, and `maxChars: 400`
- **THEN** these parameters are formatted as options on `Request::tts()` before executing inference.

#### Scenario: Inference with default sampling parameters
- **WHEN** synthesis options omit sampling parameters
- **THEN** only standard voice codes and speaker embedding options are added to the inference request.

### Requirement: Low-Latency Streaming Chunks Delivery
The `VieneuTts.stream` API SHALL deliver synthesized audio chunks over `Stream<Uint8List>`, defaulting to raw 24 kHz Mono `s16le` PCM byte chunks without container headers, allowing real-time gapless ingestion into audio player sinks.

#### Scenario: Real-time PCM chunk streaming
- **WHEN** consumer calls `VieneuTts.stream` with default parameters
- **THEN** chunks emitted by the stream are raw `s16le` PCM bytes at 24000 Hz mono without any 44-byte WAV header on the initial or subsequent chunks.

#### Scenario: WAV chunk streaming
- **WHEN** consumer calls `VieneuTts.stream` with `responseFormat: "wav"`
- **THEN** the first emitted chunk contains the 44-byte WAV header followed by audio data.
