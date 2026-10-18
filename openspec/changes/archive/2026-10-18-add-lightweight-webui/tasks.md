# Tasks

## 1. WebUI Frontend Template

- [x] 1.1 Create `webui.py` with an embedded modern HTML5/JS/Tailwind single-page interface featuring audio playback, speed slider, format selector, and IPA preview
- [x] 1.2 Add `/v1/audio/phonemize` endpoint to support real-time IPA phoneme preview and verification

## 2. Server Integration & Content Negotiation

- [x] 2.1 Integrate WebUI into `server.py` with content negotiation on `/` (`text/html` vs `application/json`) and dedicated `/ui` route
- [x] 2.2 Integrate WebUI and phonemize endpoint into `modal_app.py` for Modal deployment parity
- [x] 2.3 Verify WebUI and phonemize routes with automated test commands
- [x] 2.4 Verify WebUI visual rendering with Chrome in running Browserless container (:9222) and capture a screenshot to scratch/webui_preview.png

## 3. Documentation

- [x] 3.1 Update `README.md` with WebUI access instructions and screenshots/feature descriptions

## Workflow follow-up

- Apply implementation with `/opsx-apply`.
- Archive change with `/opsx-archive`.
