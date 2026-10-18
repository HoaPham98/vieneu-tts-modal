# Design: Lightweight Embedded WebUI

## Context

See [proposal.md](file:///home/ubuntu/vieneu-tts-modal/openspec/changes/add-lightweight-webui/proposal.md) for motivation.
Currently, `server.py` and `modal_app.py` serve JSON on `/` and `/health`. When developers or users visit the server via a web browser, they see raw JSON rather than an interactive interface to test the text-to-speech model.

## Goals / Non-Goals

**Goals:**
- Provide a responsive single-page WebUI embedded directly within the application without adding any new Python dependencies (no Gradio, no Streamlit).
- Support content negotiation on `/`: return WebUI HTML when accessed by a browser (`text/html`), and JSON when requested by API clients (`application/json`).
- Provide an explicit `/ui` route that always serves the WebUI.
- Provide a `/v1/audio/phonemize` endpoint to allow previewing Vietnamese IPA phonemes before or during synthesis.
- Integrate identical WebUI capabilities into both `server.py` and `modal_app.py`.

**Non-Goals:**
- Multi-user authentication database or user management (only standard API Key Bearer token).
- Heavy asset bundles or Node.js frontend build steps (uses self-contained HTML/CSS/JS with CDN styling).

## Decisions

### Decision 1: Single-File Embedded HTML Template
- **Choice**: Store the WebUI as a modular HTML template string or template file rendered via `fastapi.responses.HTMLResponse`.
- **Rationale**: Keeps the project self-contained, adds zero build steps, requires no webpack/vite, and does not increase Docker image size.
- **Alternatives considered**:
  - *Gradio*: Adds heavy PyTorch/NumPy dependencies, adds ~300MB to image, and introduces potential port collisions.
  - *React/Vue build*: Adds Node.js build complexity to Dockerfile.

### Decision 2: Content Negotiation on `/`
- **Choice**: Check the `Accept` header on `GET /`. If it contains `text/html`, return `HTMLResponse(content=WEBUI_HTML)`. Otherwise, return the standard JSON health dictionary. Additionally, expose `/ui` as a dedicated web page.
- **Rationale**: Keeps backward compatibility for monitoring tools and scripts checking `http://localhost:8000/`, while providing a delightful visual experience when opened in a web browser.

### Decision 3: Endpoint `/v1/audio/phonemize`
- **Choice**: Expose `POST /v1/audio/phonemize` (and `GET /v1/audio/phonemize?text=...`) returning `{"input": text, "phonemes": ipa_text}`.
- **Rationale**: Enables users to inspect how Vietnamese diacritics and emotion tags (`[cười]`, `[thở dài]`) are parsed into IPA phonemes.

### Decision 4: Headless Browser Visual Verification
- **Choice**: Sử dụng container Browserless Chromium cục bộ (port 9222) với endpoint REST `/screenshot` để chụp ảnh màn hình WebUI.
- **Rationale**: Đảm bảo layout Tailwind CSS, nút bấm và player HTML5 hiển thị chuẩn xác mà không cần mở trình duyệt thủ công trên máy client.

## Risks / Trade-offs

- **[Risk] CDN Dependency for CSS**: If the server runs in a completely air-gapped network with no internet access, CDN styling might fail to load.
  - *Mitigation*: Fall back to clean vanilla CSS embedded directly in the HTML string, with modern Tailwind styling loaded from CDN when online.

## Migration Plan

1. Create `webui.py` (or embed template) containing the HTML/JS/CSS frontend.
2. Update `server.py` and `modal_app.py` to route `/` (with content negotiation), `/ui`, and `/v1/audio/phonemize`.
3. Test locally in browser and via curl.
