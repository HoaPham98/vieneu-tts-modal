# Spec Delta

## Purpose

Cung cấp dịch vụ Text-to-Speech hiệu năng cao tương thích chuẩn OpenAI, phục vụ mô hình VieNeu-TTS v3 Turbo GGUF với chất giọng Ngọc Huyền qua backend C++ audio.cpp và bộ tiền xử lý âm vị tiếng Việt.

## ADDED Requirements

### Requirement: OpenAI Speech Endpoint Compatibility
The system SHALL expose a `POST /v1/audio/speech` endpoint adhering to the OpenAI Audio Speech API contract, accepting a JSON payload with `input`, `model`, and optional parameters including `voice`, `response_format`, and `speed`.

#### Scenario: Synthesize speech from Vietnamese text
- **WHEN** client sends a POST request to `/v1/audio/speech` with valid Vietnamese text in `input` and model `vieneu-v3-turbo`
- **THEN** system returns HTTP 200 OK with binary audio encoded in the requested format (default WAV)

#### Scenario: Reject empty text input
- **WHEN** client sends a POST request with empty or whitespace-only `input`
- **THEN** system returns HTTP 400 Bad Request with an error description

### Requirement: Default Voice Preset Ngoc Huyen
The system SHALL configure and utilize "Ngọc Huyền" (Northern natural female voice profile) as the default voice preset whenever no voice is specified or when "Ngọc Huyền" is requested.

#### Scenario: Request with explicit Ngoc Huyen voice
- **WHEN** client specifies `"voice": "Ngọc Huyền"` in the request body
- **THEN** system synthesizes speech using the enrolled 192-dimensional speaker embedding and reference audio for Ngọc Huyền

#### Scenario: Request without voice parameter
- **WHEN** client omits the `voice` parameter in the speech request
- **THEN** system automatically applies the "Ngọc Huyền" voice preset as the default voice

#### Scenario: Request with OpenAI standard voice alias
- **WHEN** client specifies an OpenAI alias such as `"voice": "alloy"`
- **THEN** system aliases the request to the default "Ngọc Huyền" voice preset

### Requirement: Automatic Vietnamese Text Phonemization
The system SHALL automatically normalize and phonemize raw Vietnamese input text into the target IPA phonetic representation expected by the underlying model before passing it to the C++ inference engine.

#### Scenario: Conversion of raw Vietnamese text
- **WHEN** client submits raw Vietnamese text such as `"Xin chào thế giới"`
- **THEN** system automatically converts the text to the corresponding IPA phoneme sequence before executing model inference

#### Scenario: Handling inline punctuation and pauses
- **WHEN** client text contains punctuation marks (periods, commas, question marks)
- **THEN** system maintains appropriate prosodic pauses and cadence in the synthesized output

### Requirement: Model and Voice Discovery Endpoints
The system SHALL provide discovery and health check endpoints including `GET /v1/models`, `GET /v1/audio/voices`, and `GET /health`.

#### Scenario: List available models
- **WHEN** client sends a GET request to `/v1/models`
- **THEN** system returns HTTP 200 OK with a list of available models including `vieneu-v3-turbo`

#### Scenario: List available voices
- **WHEN** client sends a GET request to `/v1/audio/voices`
- **THEN** system returns HTTP 200 OK with available voice metadata containing `Ngọc Huyền`
