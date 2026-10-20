# Spec Delta: on-device-tts

## Purpose

Provides a standalone, offline on-device Text-to-Speech Dart library using VieNeu-TTS v3 Turbo GGUF and audio.cpp via Flutter Rust Bridge for mobile and desktop applications.

## ADDED Requirements

### Requirement: Model On-Demand Download
The library SHALL provide an asynchronous method to download the official VieNeu-TTS v3 Turbo GGUF model (~188 MB) to a specified local directory on the device with progress reporting.

#### Scenario: Successful model download
- **WHEN** client invokes downloadModel with a valid target directory and destination path
- **THEN** model file is downloaded from the official repository, verified, and saved locally while emitting progress updates

### Requirement: In-Process Offline Engine Initialization
The library SHALL initialize the audio.cpp inference engine in-process using the local GGUF model file without any network calls or background server processes.

#### Scenario: Offline engine initialization
- **WHEN** client calls init with the local path to a valid GGUF model file
- **THEN** engine memory-maps the model weights and becomes ready for inference within milliseconds

### Requirement: Full Audio Synthesis
The library SHALL convert Vietnamese natural text into complete 48 kHz stereo WAV audio bytes using embedded SEA-G2P text normalization and VieNeu-TTS inference.

#### Scenario: Synthesize speech from text
- **WHEN** client invokes synthesize with text "Xin chào Việt Nam" and a target voice
- **THEN** system normalizes text, generates acoustic tokens, decodes neural codec, and returns a valid 48 kHz WAV byte array

### Requirement: Real-Time Audio Chunk Streaming
The library SHALL support streaming raw audio chunks incrementally as they are synthesized through a Dart Stream for low-latency playback.

#### Scenario: Stream speech chunks
- **WHEN** client invokes stream with a sentence
- **THEN** system emits audio buffer chunks over a Stream<Uint8List> as frames are produced by the neural decoder before the entire sentence finishes

### Requirement: Voice Preset Selection
The library SHALL provide 25 embedded Vietnamese voice presets covering North, Central, and South accents, allowing instant voice selection without reloading the base model.

#### Scenario: Switch voice preset
- **WHEN** client specifies a voice identifier such as "minh_quan_pro" or "ngoc_huyen"
- **THEN** inference uses the corresponding speaker embedding and reference acoustic codes without reloading the model weights

### Requirement: Offline Example Application
The repository SHALL provide a runnable Flutter example application (`packages/vieneu_tts/example/`) demonstrating the full lifecycle: downloading the GGUF model and SEA-G2P dictionary on-demand, caching them in device storage, and performing offline TTS synthesis and streaming with voice preset selection.

#### Scenario: End-to-end offline TTS workflow in example app
- **WHEN** user opens the example app, downloads model and dictionary assets once, and inputs Vietnamese text
- **THEN** the app initializes the engine locally and synthesizes/plays speech without an active network connection
