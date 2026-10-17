# Spec Delta

## Purpose

Provides standalone containerized deployment and automated multi-architecture Docker image builds for the VieNeu-TTS v3 Turbo speech synthesis server.

## ADDED Requirements

### Requirement: Standalone Containerized Server
The system SHALL provide a standalone Docker container capable of running both the audio.cpp C++ inference engine and the FastAPI gateway without relying on Modal infrastructure.

#### Scenario: Container starts and passes healthcheck
- **WHEN** the container is started via `docker run` or `docker compose up`
- **THEN** both internal `audiocpp_server` and public FastAPI server initialize and the `/health` endpoint returns HTTP 200 with engine details

#### Scenario: Speech generation via container API
- **WHEN** an authenticated client sends a valid `POST /v1/audio/speech` request to the container port
- **THEN** the system converts Vietnamese text to IPA phonemes, performs inference via audio.cpp, and returns synthesized audio in the requested format

### Requirement: Multi-Architecture Support
The system SHALL support both `linux/arm64` (e.g., Oracle Cloud Infrastructure Ampere A1) and `linux/amd64` architectures natively.

#### Scenario: ARM64 execution on OCI Ampere A1
- **WHEN** the Docker image is deployed on an ARM64 host
- **THEN** the container executes natively using 64-bit ARM binaries and precompiled AArch64 Rust wheels without emulation errors

### Requirement: Dual-Process Lifecycle Management
The container entrypoint SHALL orchestrate the lifecycle of both `audiocpp_server` and the FastAPI ASGI application, forwarding signals and shutting down cleanly.

#### Scenario: Process startup sequence
- **WHEN** the container launches
- **THEN** `audiocpp_server` starts first on internal port 8080, health is verified, and then the public Uvicorn server starts on port 8000

#### Scenario: Graceful shutdown
- **WHEN** the container receives a SIGTERM or SIGINT signal
- **THEN** both the Uvicorn web server and the background `audiocpp_server` terminate gracefully

### Requirement: Automated Multi-Arch Image Build
The repository SHALL provide a GitHub Actions workflow to build and publish multi-platform Docker images (`linux/arm64`, `linux/amd64`) to a container registry.

#### Scenario: Workflow trigger on push or manual dispatch
- **WHEN** code changes are pushed to main or the workflow is triggered manually via `workflow_dispatch`
- **THEN** GitHub Actions sets up Docker Buildx and builds the multi-arch container image
