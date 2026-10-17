# Tasks

## 1. Standalone Server & Process Orchestration

- [x] 1.1 Extract standalone FastAPI server into `server.py` and verify syntax/imports with `python3 -m py_compile server.py`
- [x] 1.2 Create `entrypoint.sh` for dual-process coordination (starting `audiocpp_server` & `uvicorn`) and verify executable permissions & bash syntax with `bash -n entrypoint.sh`

## 2. Docker & Container Configuration

- [x] 2.1 Create `Dockerfile` based on `ghcr.io/0xshug0/audio.cpp:full-cpu` supporting ARM64/AMD64 with model baking and verify Dockerfile syntax
- [x] 2.2 Create `docker-compose.yml` with port 8000 mapping, configurable `API_KEY` and `THREADS`, and verify yaml structure
- [x] 2.3 Create `.dockerignore` to exclude `.venv`, test audio recordings, cache files, and git metadata from build context

## 3. GitHub Actions CI/CD Workflow

- [x] 3.1 Create `.github/workflows/docker-build.yml` for automated multi-arch builds (`linux/amd64`, `linux/arm64`) and publishing to GHCR
- [x] 3.2 Update `README.md` with Docker quickstart guide, OCI ARM64 deployment instructions, and docker-compose usage examples

## Workflow follow-up

- Implement and verify tasks using `/opsx-apply`.
- Validate with `openspec validate` and archive the change when complete.
