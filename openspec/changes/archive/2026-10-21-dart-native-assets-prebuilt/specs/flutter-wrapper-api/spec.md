# Spec Delta

## Purpose

Provides a specialized Flutter wrapper package (`flutter_vieneu_tts`) that integrates pure Dart `vieneu_tts` with Flutter application lifecycles, sandbox storage resolution, and reactive UI download progress states.

## ADDED Requirements

### Requirement: Autonomous Sandbox Storage Resolution
The Flutter wrapper package SHALL provide an initialization helper that automatically resolves device storage directories using `path_provider` without requiring manual path plumbing by the app developer.

#### Scenario: Initializing engine with default sandbox path
- **WHEN** consumer calls `VieneuTtsFlutter.init()`
- **THEN** model files and dictionaries are located within `getApplicationDocumentsDirectory()/vieneu_models` and engine initializes successfully.

### Requirement: Reactive Download Progress Notifier
The Flutter wrapper package SHALL expose reactive progress notifiers or streams for on-demand resource downloads to easily bind to Flutter UI widgets.

#### Scenario: Binding download progress to UI
- **WHEN** consumer app initiates resource download through the Flutter wrapper
- **THEN** progress values between 0.0 and 1.0 are emitted to the notifier and reflected in UI state.

### Requirement: Standalone Flutter Example App
The monorepo SHALL maintain a standalone Flutter reference application under `packages/flutter_vieneu_tts/example` demonstrating on-device download, synthesis, and audio playback.

#### Scenario: Running example app on target platform
- **WHEN** the example application is launched on Android, iOS, or Linux
- **THEN** the UI renders voice presets, handles download/initialization, and plays synthesized speech.
