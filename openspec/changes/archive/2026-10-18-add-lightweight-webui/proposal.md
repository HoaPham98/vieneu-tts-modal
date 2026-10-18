# Proposal: Add Lightweight Embedded WebUI

## Why

Currently, accessing the server's root endpoint (`/`) or testing TTS synthesis requires using `curl`, Python scripts, or third-party tools like Open WebUI/Dify. Users deploying on local machines or cloud VPS (such as OCI ARM64) benefit from an immediate, zero-dependency visual interface accessible directly from their browser to test voices, preview IPA phonemes, and play synthesized speech without installing external clients.

## What Changes

- **Embedded HTML5/JS WebUI**: Serve a responsive, modern single-page interface directly from the server at `/` (and `/ui`) with support for dark/light themes, text input, voice selection, speed adjustment, and audio format choice (`wav`, `mp3`).
- **In-Browser Audio Player**: Allow one-click audio synthesis, streaming playback, and direct audio file download.
- **IPA Phoneme Preview**: Display real-time or pre-synthesis Vietnamese IPA phonemes converted via `sea-g2p`.
- **API Key Support**: Allow passing an optional Bearer token directly from the WebUI when authentication is enabled.
- **Dual Support**: Integrate seamlessly into both standalone [`server.py`](file:///home/ubuntu/vieneu-tts-modal/server.py) and [`modal_app.py`](file:///home/ubuntu/vieneu-tts-modal/modal_app.py) without requiring heavy dependencies like Gradio or Streamlit.

## Capabilities

### New Capabilities
- `tts-webui`: Embedded responsive web interface providing interactive speech synthesis, audio playback, IPA phoneme visualization, and authentication configuration.

### Modified Capabilities
*(None - existing capabilities requirements remain intact)*

## Impact

- **Affected code**: `server.py` and `modal_app.py` (adds HTML/static response at `/` while keeping `/health` pure JSON).
- **Dependencies**: Zero new dependencies (uses FastAPI's built-in `HTMLResponse` and vanilla HTML5/JS/CSS with CDN styling).
- **Docker image & RAM**: Zero overhead on container size or memory usage.
