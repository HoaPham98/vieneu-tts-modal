# Design: Standalone Dockerization & GitHub Actions CI/CD

## Context

See [proposal.md](file:///home/ubuntu/vieneu-tts-modal/openspec/changes/dockerize-vieneu-server/proposal.md) for motivation and problem statement.
Currently, the codebase provides `modal_app.py`, which is tailored specifically for the Modal cloud platform. To run on standard Linux servers (specifically OCI Ampere A1 ARM64 and x86_64 VPS), we need a decoupled architecture that packages both the C++ engine (`audio.cpp`) and the Python web API (`FastAPI`) into a portable, standard OCI container.

## Goals / Non-Goals

**Goals:**
- Provide a clean, standalone FastAPI application (`server.py`) independent of any Modal SDK.
- Provide a robust entrypoint script (`entrypoint.sh`) that manages both `audiocpp_server` and `uvicorn`, with healthcheck coordination and proper signal forwarding.
- Provide a production-ready `Dockerfile` supporting `linux/arm64` and `linux/amd64`.
- Provide a `docker-compose.yml` for single-command startup with environment variable overrides.
- Provide a GitHub Actions workflow (`docker-build.yml`) that builds and publishes multi-architecture images to GitHub Container Registry (GHCR).

**Non-Goals:**
- Modifying or deprecating `modal_app.py` (it remains as the Modal deployment vehicle).
- Building custom C++ binaries from source (we leverage the official prebuilt `ghcr.io/0xshug0/audio.cpp:full-cpu` multi-arch image).
- Implementing multi-node distributed clustering.

## Decisions

### Decision 1: Base Image Selection
- **Choice**: Use `ghcr.io/0xshug0/audio.cpp:full-cpu` as the base image.
- **Rationale**: It provides native multi-arch manifests for both `amd64` and `arm64`, already contains the compiled `audiocpp_server` and its runtime C++ dependencies, and is Debian/Ubuntu based, allowing easy installation of Python 3, FFmpeg, and required libraries.
- **Alternatives considered**:
  - *Compile audio.cpp from scratch in a Debian/Ubuntu base*: Increases build time significantly (5-10 minutes) and requires cmake, git, and build tools.
  - *Separate containers for C++ and Python (Docker Compose only)*: Requires users to manage multiple images and network links rather than having a single drop-in container.

### Decision 2: Process Orchestration via `entrypoint.sh`
- **Choice**: Use a lightweight bash script `entrypoint.sh` with `trap` signal forwarding and curl-based readiness check.
- **Rationale**: Avoids the extra memory overhead and dependency bloat of `supervisord`. The entrypoint starts `audiocpp_server` in the background on `127.0.0.1:8080`, polls `/health` until it returns 200 (or timeout), and then executes `uvicorn server:app --host 0.0.0.0 --port 8000` as the foreground process, cleanly capturing SIGTERM/SIGINT.
- **Alternatives considered**:
  - *Supervisord*: Standard in legacy containers, but adds unnecessary Python dependencies and config complexity.

### Decision 3: Model Weights Packaging Strategy
- **Choice**: Download and bake the GGUF weights (~163 MB) into `/app/models/VieNeu-TTS-v3-Turbo` during Docker build, while allowing runtime volume overrides (`-v /path/on/host:/app/models`).
- **Rationale**: Provides an instant "zero-download-at-startup" user experience. A 163 MB model is small enough to embed without bloating container download times unreasonably.
- **Alternatives considered**:
  - *Download on first boot*: Adds 1-2 minutes latency to initial container startup and fails if the container has restricted outbound internet access.

### Decision 4: Concurrency & Thread Optimization for ARM64
- **Choice**: Allow configuring `THREADS` via environment variable with a default of 4 (ideal for OCI Ampere A1 4-OCPU setups).
- **Rationale**: `audiocpp_server` accepts `--threads` or reads `threads` from `server.json`. Templating or dynamically generating `server.json` during entrypoint allows runtime tuning for different hardware profiles.

### Decision 5: GitHub Actions Multi-Arch CI/CD
- **Choice**: Use `docker/setup-qemu-action` + `docker/setup-buildx-action` with `platforms: linux/amd64,linux/arm64` and push to GHCR (`ghcr.io/${{ github.repository }}`).
- **Rationale**: Standard, automated, and produces universal images consumable directly on OCI ARM64 or x86 VPS.

## Risks / Trade-offs

- **[Risk] QEMU emulation slowness on GitHub Actions**: Emulating ARM64 on x86 runners can take 15-20 minutes for image layers.
  - *Mitigation*: Cache GitHub Actions layers via `cache-from: type=gha` and `cache-to: type=gha,mode=max`. Keep package installations concentrated in single RUN commands.
- **[Risk] Internal port collision (8080)**:
  - *Mitigation*: `audiocpp_server` binds strictly to `127.0.0.1:8080` (localhost loopback), never exposed to Docker host. Only Uvicorn (`0.0.0.0:8000`) is mapped to the host.

## Migration Plan

1. Verify `server.py` works locally against `modal_app.py` feature parity.
2. Build and run Docker container locally: `docker build -t vieneu-tts:latest . && docker run -p 8000:8000 vieneu-tts:latest`.
3. Test inference endpoints (`/v1/models`, `/v1/audio/voices`, `/v1/audio/speech`).
4. Set up GitHub Actions workflow and tag release.
