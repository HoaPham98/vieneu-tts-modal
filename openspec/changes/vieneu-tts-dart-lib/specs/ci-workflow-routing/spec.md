# Spec Delta: ci-workflow-routing

## Purpose

Enforces precise path-filtering and selective triggering across GitHub Actions workflows (Modal deployment, Docker image builds, and Dart/Rust library CI) with remote inspection via GitHub CLI.

## ADDED Requirements

### Requirement: Path-Filtered Existing Workflows
All existing repository workflows (specifically Modal deployment and Docker container build) SHALL define explicit path filters so that changes outside their domain do not trigger execution.

#### Scenario: Commits to Dart package do not trigger Modal deploy
- **WHEN** a commit is pushed affecting only `packages/vieneu_tts/**`
- **THEN** neither `deploy-modal.yml` nor `docker-build.yml` is triggered

### Requirement: Dart & Rust Library CI Workflow
The repository SHALL provide a dedicated GitHub Actions workflow (`vieneu-tts-lib.yml`) that builds native libraries, runs lints, and executes tests for the Dart library.

#### Scenario: Pull request or push to Dart package
- **WHEN** changes are pushed to `packages/vieneu_tts/**` or the workflow file
- **THEN** CI automatically executes linting, cross-compilation checks, and test suites

### Requirement: Remote Workflow Dispatch and Log Inspection
The CI workflow SHALL support manual invocation with configurable parameters and permit inspecting execution status and failure logs via GitHub CLI (`gh`).

#### Scenario: Manual trigger via gh cli
- **WHEN** a developer runs `gh workflow run vieneu-tts-lib.yml` with optional parameters
- **THEN** GitHub Actions initiates the job and results/logs are retrievable via `gh run watch` and `gh run view`

### Requirement: Android Example App APK Artifact
The CI workflow SHALL compile the Flutter example application into an Android release APK and upload it as a workflow artifact (`vieneu-tts-android-apk`).

#### Scenario: Release APK artifact generation
- **WHEN** the CI workflow executes
- **THEN** it builds the Flutter Android release APK with native libraries (`arm64-v8a`) and saves it under the artifact name `vieneu-tts-android-apk`
