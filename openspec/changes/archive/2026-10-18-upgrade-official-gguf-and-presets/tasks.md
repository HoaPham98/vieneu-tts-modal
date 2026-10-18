# Tasks

## 1. Download & Organize Voice Presets

- [x] 1.1 Download all 25 voice presets and `manifest.json` from `pnnbao-ump/VieNeu-TTS-v3-Turbo/gguf/voices/` into `preset_voices/`
- [x] 1.2 Verify all 25 voice directories contain valid `ref_codes.txt` and `speaker.emb.txt` (192 floats)

## 2. Docker & Environment Configuration

- [x] 2.1 Update `Dockerfile` to download the official `vieneu-v3-turbo-q8_0.gguf` (188 MB) from `pnnbao-ump/VieNeu-TTS-v3-Turbo`
- [x] 2.2 Update `entrypoint.sh` to configure `server.json` using `minh_quan_pro` as the baseline default voice option without obsolete `reference_text`

## 3. Server Gateway & API Implementation

- [x] 3.1 Implement voice catalog loader in `server.py` to parse `manifest.json` and resolve voice aliases
- [x] 3.2 Add `GET /v1/audio/voices` endpoint returning the catalog of 25 voices and default voice
- [x] 3.3 Update `POST /v1/audio/speech` in `server.py` to forward dynamic `options` (`reference_codes_file`, `speaker_embedding_file`) based on `request.voice`
- [x] 3.4 Update `modal_app.py` with identical voice catalog and dynamic option routing for Modal serverless parity

## 4. WebUI Enhancement

- [x] 4.1 Update `webui.py` voice selector dropdown to render all 25 presets organized by region and gender, defaulting to `minh_quan_pro`
- [x] 4.2 Update WebUI client JavaScript to send the selected voice ID with synthesis requests

## 5. Verification & Testing

- [x] 5.1 Test voice catalog endpoint `GET /v1/audio/voices`
- [x] 5.2 Test audio synthesis via `POST /v1/audio/speech` with multiple voices (`minh_quan_pro`, `ngoc_huyen`, `quang_son`, `thuy_dung`) and verify generated WAV audio
- [x] 5.3 Test WebUI visual rendering with Chrome in Browserless container (`:9222`) and capture screenshot to `scratch/webui_voices_preview.png`
- [x] 5.4 Update `README.md` documenting available voices, default voice, and API usage

## Workflow follow-up

- Apply implementation with `/opsx-apply`.
- Archive change with `/opsx-archive`.
