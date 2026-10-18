# Spec Delta

## Purpose

Provides a lightweight, embedded interactive WebUI for testing and listening to synthesized speech directly from the browser.

## ADDED Requirements

### Requirement: Interactive Web Interface
The system SHALL serve an embedded responsive HTML5/JavaScript user interface at the root endpoint `/` (and `/ui`).

#### Scenario: User visits root URL in browser
- **WHEN** a user opens the root URL in a web browser with `Accept: text/html`
- **THEN** the system serves the interactive WebUI page with input fields for text, speed, format, and API key

#### Scenario: API client healthcheck
- **WHEN** a client requests `/health` or sends `Accept: application/json` to `/`
- **THEN** the system responds with JSON health status and engine metadata

#### Scenario: Visual rendering verification via headless browser
- **WHEN** a headless browser loads the WebUI URL
- **THEN** the interactive audio controls, sliders, and buttons render properly and can be captured as an image screenshot

### Requirement: Audio Playback and Download
The WebUI SHALL allow users to trigger speech synthesis, listen to the audio directly via an embedded player, and download the audio file.

#### Scenario: Successful speech synthesis in WebUI
- **WHEN** the user inputs Vietnamese text and clicks the synthesize button
- **THEN** the WebUI calls `/v1/audio/speech`, loads the resulting audio into the HTML5 player, enables playback, and provides a download button

### Requirement: IPA Phoneme Visualization
The WebUI SHALL display the converted IPA phoneme sequence corresponding to the input Vietnamese text.

#### Scenario: Display IPA phonemes
- **WHEN** speech synthesis completes
- **THEN** the WebUI displays the Vietnamese IPA transcription generated for the model prompt
