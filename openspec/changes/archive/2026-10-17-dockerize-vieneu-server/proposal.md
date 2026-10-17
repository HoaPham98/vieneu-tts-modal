# Proposal: Dockerize VieNeu-TTS Server & GitHub Actions Build

## Why

Currently, the VieNeu-TTS v3 Turbo server is coupled to Modal's serverless platform via `modal_app.py`. Users hosting on their own infrastructure—specifically low-cost or free-tier ARM64 instances like Oracle Cloud Infrastructure (OCI) Ampere A1 (4 OCPU, 24 GB RAM)—need a standalone Docker container that runs independently of Modal. Additionally, an automated GitHub Actions CI/CD workflow is required to build and push the multi-arch (especially `linux/arm64` and `linux/amd64`) Docker image to GitHub Container Registry (GHCR) or Docker Hub.

## What Changes

- **Standalone FastAPI Server (`server.py`)**: Extract the FastAPI gateway, Vietnamese G2P phonemizer (`sea-g2p`), audio transcoding (FFmpeg), and OpenAI-compatible `/v1/audio/speech` endpoints from Modal decorators into a clean, standalone ASGI application.
- **Dual-Process Entrypoint (`entrypoint.sh`)**: Orchestrate both `audiocpp_server` (internal C++ inference daemon on `127.0.0.1:8080`) and `uvicorn server:app` (public API on `0.0.0.0:8000`) with graceful shutdown and healthcheck waiting.
- **Production Multi-Arch Dockerfile (`Dockerfile`)**: Build from `ghcr.io/0xshug0/audio.cpp:full-cpu` (which natively supports `linux/arm64` and `linux/amd64`), bundle model weights (~163 MB GGUF), preset voices, and Python dependencies.
- **Docker Compose (`docker-compose.yml`)**: Provide a zero-friction local/VPS runner with port mappings (`8000:8000`) and configurable environment variables (`API_KEY`, `THREADS`).
- **GitHub Actions Workflow (`.github/workflows/docker-build.yml`)**: Automated multi-arch build and push workflow using QEMU / native ARM64 runners and Docker Buildx.

## Capabilities

### New Capabilities
- `docker-deployment`: Standalone containerized deployment of VieNeu-TTS server supporting both `linux/arm64` (OCI Ampere A1) and `linux/amd64`, complete with dual-process lifecycle management and automated GitHub Actions image build.

### Modified Capabilities
*(None - existing repository had no declared specs)*

## Impact

- **Existing code**: `modal_app.py` remains fully functional and intact for users who continue to deploy to Modal.
- **New files**: `server.py`, `entrypoint.sh`, `Dockerfile`, `docker-compose.yml`, `.github/workflows/docker-build.yml`.
- **Runtime dependencies**: Standalone image installs `fastapi[standard]`, `httpx`, `sea-g2p>=0.10.0`, `ffmpeg`, and uses pre-compiled `audiocpp_server`.
- **Resource profile**: Optimized for OCI Ampere A1 with configurable CPU thread concurrency (`THREADS=4`).
