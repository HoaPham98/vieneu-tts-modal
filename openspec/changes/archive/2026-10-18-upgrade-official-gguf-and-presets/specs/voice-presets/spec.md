# Spec Delta: voice-presets

## Purpose

Enables multi-voice TTS synthesis using all 25 official VieNeu-TTS v3 Turbo voice presets and ensures highest acoustic fidelity via official author weights.

## ADDED Requirements

### Requirement: Official Model Weights and Codec Fidelity
The system SHALL use the official `vieneu-v3-turbo-q8_0.gguf` checkpoint from `pnnbao-ump/VieNeu-TTS-v3-Turbo` featuring `Q8_0` backbone quantization and `f16` neural codec precision.

#### Scenario: High fidelity audio synthesis
- **WHEN** audio is synthesized for any input text
- **THEN** the audio output has 48 kHz sampling rate with at least 36.0 dB SNR and no quantization haze on speech frames

### Requirement: Multi-Voice Presets Catalog
The system SHALL provide a `GET /v1/audio/voices` endpoint returning all 25 available voice presets parsed from `manifest.json`.

#### Scenario: Client queries available voices
- **WHEN** a client performs `GET /v1/audio/voices`
- **THEN** the system returns HTTP 200 with a JSON list containing `default: "minh_quan_pro"` and 25 voice objects, each including `id`, `name`, `label`, and regional/gender metadata

### Requirement: Dynamic Voice Selection in Speech API
The system SHALL accept a `voice` parameter in `POST /v1/audio/speech` and dynamically route inference to the selected voice preset without restarting or reloading the engine.

#### Scenario: Default voice synthesis
- **WHEN** a request arrives without specifying `voice` or with `voice="default"`
- **THEN** the system synthesizes speech using the `minh_quan_pro` preset files

#### Scenario: Specific voice selection
- **WHEN** a request arrives with `voice="ngoc_huyen"` (or any valid preset ID)
- **THEN** the system passes the corresponding `reference_codes_file` and `speaker_embedding_file` in the inference options to `audiocpp_server`

#### Scenario: Fallback for unknown voice
- **WHEN** a request specifies an invalid or nonexistent voice ID
- **THEN** the system falls back gracefully to `minh_quan_pro` without returning an HTTP error

### Requirement: Categorized Voice Selection in WebUI
The WebUI SHALL display all 25 voice presets in an organized dropdown menu grouped by region (Miền Bắc, Miền Trung, Miền Nam) and gender.

#### Scenario: User selects voice from dropdown in WebUI
- **WHEN** a user opens the WebUI
- **THEN** the voice dropdown displays 25 presets categorized cleanly with `Minh Quân Pro` pre-selected
- **WHEN** the user switches voice and clicks Synthesize
- **THEN** the WebUI posts the selected voice ID and receives synthesized audio rendered in that speaker's voice
