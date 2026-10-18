# Design: Official VieNeu-TTS v3 Turbo GGUF & 25 Preset Voices

## Context

VieNeu-TTS v3 Turbo is an advanced Vietnamese on-device text-to-speech model capable of 48 kHz high-fidelity speech and zero-shot voice cloning. The C++ runtime `audio.cpp` executes the GGUF model with high efficiency on CPU (RTF ~0.73 - 0.82 on 4 ARM64/x86 vCPUs).

To achieve optimal fidelity, authentic dialect representation, and flexible client usage, we are upgrading the weights to the author's official GGUF build and expanding voice support to all 25 presets.

## Architecture

```
+───────────────────────────────────────────────────────────────────────────────+
| CLIENT (Browser WebUI, OpenAI SDK, Pipecat, Dify)                             |
|  - GET  /v1/audio/voices                                                      |
|  - POST /v1/audio/speech { "input": "...", "voice": "minh_quan_pro" }          |
+──────────────────────────────────────┬────────────────────────────────────────+
                                       │
                                       ▼
+───────────────────────────────────────────────────────────────────────────────+
| FASTAPI GATEWAY (server.py / modal_app.py)                                    |
|                                                                               |
| 1. Voice Resolver:                                                            |
|    - Maps voice ID -> (/app/voices/<id>/ref_codes.txt, speaker.emb.txt)       |
|    - Fallback: "minh_quan_pro" if unspecified or unknown                      |
|                                                                               |
| 2. G2P Converter:                                                             |
|    - Input Vietnamese -> SEA-G2P -> IPA Phoneme string (~2ms)                 |
+──────────────────────────────────────┬────────────────────────────────────────+
                                       │ HTTP POST /v1/audio/speech
                                       │ {
                                       │   "model": "vieneu-v3-turbo",
                                       │   "input": "<ipa_phonemes>",
                                       │   "options": {
                                       │     "reference_codes_file": "/app/voices/<id>/ref_codes.txt",
                                       │     "speaker_embedding_file": "/app/voices/<id>/speaker.emb.txt"
                                       │   }
                                       │ }
                                       ▼
+───────────────────────────────────────────────────────────────────────────────+
| AUDIOCPP_SERVER (C++ Engine)                                                  |
|  - Model: /app/models/VieNeu-TTS-v3-Turbo/vieneu-v3-turbo-q8_0.gguf (188 MB)  |
|    (Q8_0 Backbone + f16 MOSS Neural Codec for 36 dB SNR, +4 dB cleaner)       |
|  - Dynamic voice enrollment per-request with zero model reload                |
+───────────────────────────────────────────────────────────────────────────────+
```

## Decisions

### 1. Official Model Weights Package
- **Source**: `https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/main/gguf/vieneu-v3-turbo-q8_0.gguf` (188 MB).
- **Rationale**:
  - The official GGUF build maintains the codec at `f16` (instead of `Q8_0` in `phuocnguyen90`), avoiding 4 dB SNR loss and background hiss.
  - Built from the latest `update/` weights by model author Phạm Nguyễn Ngọc Bảo.
  - Config, tokenizer, and special tokens are embedded directly in the GGUF container.
  - Filename in container will be `/app/models/VieNeu-TTS-v3-Turbo/model.gguf` (or referenced directly as `vieneu-v3-turbo-q8_0.gguf`).

### 2. Voice Presets Structure & Packaging
- **Source**: `https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/main/gguf/voices/`.
- **Local Layout in `preset_voices/`**:
  ```text
  preset_voices/
  ├── manifest.json
  ├── minh_quan_pro/
  │   ├── ref_codes.txt
  │   └── speaker.emb.txt
  ├── ngoc_huyen/
  │   ├── ref_codes.txt
  │   └── speaker.emb.txt
  ├── mai_anh/
  ├── anh_khoi/
  └── ... (25 voices total, < 150 KB combined)
  ```
- **Rationale**: Storing the lightweight text tokens and embeddings directly in the repo under `preset_voices/` allows deterministic Docker builds without external API dependencies during container image assembly.

### 3. Dynamic Voice Routing via Request `options`
- **Mechanism**:
  `audiocpp_server` natively accepts an `options` map inside the `POST /v1/audio/speech` JSON payload. When `reference_codes_file` and `speaker_embedding_file` are passed in `options`, the engine applies the corresponding speaker condition for that inference run.
- **Server Gateway Implementation**:
  ```python
  voice_id = request.voice or "minh_quan_pro"
  voice_meta = VOICE_REGISTRY.get(voice_id) or VOICE_REGISTRY["minh_quan_pro"]
  payload = {
      "model": "vieneu-v3-turbo",
      "input": ipa_phonemes,
      "options": {
          "reference_codes_file": str(voice_meta["codes_path"]),
          "speaker_embedding_file": str(voice_meta["emb_path"]),
      }
  }
  ```
- **No reload penalty**: Swapping presets in memory takes < 1 ms because the acoustic tokens and embedding are simply injected into the prompt prefix and decoder condition.

### 4. Categorized WebUI Dropdown
- Presets are grouped with `<optgroup>` tags in the WebUI:
  - **Miền Bắc (Northern)**: Minh Quân Pro (Default), Ngọc Huyền, Mai Anh, Anh Khôi, Trúc Ly, Adam bựa, Thiền Tâm Đức, v.v.
  - **Miền Trung (Central)**: Quang Sơn, Ngọc Trân.
  - **Miền Nam (Southern)**: Thùy Dung, Thái Sơn, Thục Đoan, Minh Triết, Mỹ Duyên, Đức Trí, Kim Thanh, Adam.
- The UI fetches or statically populates from `manifest.json`.

## Risks & Mitigations

- **Risk: Increased Docker build time**:
  - *Mitigation*: The official GGUF is 188 MB (only 18 MB larger than before), downloading in ~2-3 seconds. The 25 voice presets are tiny text files (< 150 KB total) committed to `preset_voices/`.
- **Risk: Client sending obsolete or unknown voice name**:
  - *Mitigation*: The voice resolver uses defensive alias matching (e.g. `Ngọc Huyền` -> `ngoc_huyen`, `minh_quan` -> `minh_quan_pro`) with a safe fallback to `minh_quan_pro`.
