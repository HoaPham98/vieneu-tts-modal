# Vieneu TTS Flutter & Dart Library

On-device, high-performance Vietnamese Text-to-Speech library powered by **VieNeu-TTS v3 Turbo GGUF** and the C++ engine **audio.cpp**, exposed to Dart via **flutter_rust_bridge v2**.

## Features

- ⚡ **100% On-Device Offline Inference**: Runs entirely in-process using `audio.cpp` and `ggml` with instant `mmap` loading.
- 🎙️ **25 Embedded Voice Presets**: Includes Minh Quân Pro, Ngọc Huyền, Mai Anh, Quang Sơn, and 21 other regional accents embedded into the native binary.
- 🔤 **Automatic Vietnamese G2P**: Integrated text normalization and G2P via `sea-g2p-rs` (handles numbers, dates, abbreviations, and emotion cues).
- 🌊 **Audio Streaming**: Stream audio chunks in real-time as they are synthesized.
- 🎛️ **Remote API Parity**: Configure sample rate (48/24/16/8 kHz), mono/stereo, PCM or WAV output, and sampling parameters (`temperature`, `top_k`, `top_p`, `repetition_penalty`, `max_chars`, `min_chars`, `seed`).
- 🗣️ **Flexible Voice Names**: Accepts preset IDs (`mai_anh`) or display names (`Mai Anh`), case- and diacritic-insensitively.
- 📥 **On-Demand Model Download**: Simple utility to download the official 188 MB GGUF weights on first launch.

## Usage

```dart
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vieneu_tts/vieneu_tts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final dir = await getApplicationSupportDirectory();
  final modelPath = '${dir.path}/vieneu-v3-turbo-q8_0.gguf';

  // 1. Download model on first run if not present
  if (!File(modelPath).existsSync()) {
    await VieneuTts.downloadModel(
      destinationDir: dir.path,
      onProgress: (progress) {
        print('Downloading: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );
  }

  // 2. Initialize the native engine
  await VieneuTts.init(modelPath: modelPath, threads: 4);

  // 3. Synthesize full audio (24 kHz mono WAV by default)
  final wavBytes = await VieneuTts.synthesize(
    text: 'Xin chào! Chúc bạn một ngày tốt lành.',
    voice: 'Minh Quân Pro',
  );

  // 4. Or stream speech chunks (raw 24 kHz mono PCM by default)
  final stream = VieneuTts.stream(
    text: 'Tỉ lệ giải ngân đầu tư công đạt 68,5% kế hoạch năm.',
    voice: 'minh_quan_pro',
    sampleRate: 24000,
    channels: 1,
  );

  await for (final chunk in stream) {
    // Pipe chunk straight into an audio player sink
  }
}
```

## Synthesis Options

Every option mirrors the Remote API's `/v1/audio/speech` parameters and is
available either as an individual named argument or as a reusable preset.

```dart
// Reusable preset, overridden per call where needed.
const preset = TtsSynthesisOptions(
  temperature: 0.7,
  topK: 50,
  topP: 0.9,
  repetitionPenalty: 1.1,
  maxChars: 400,
);

final wav = await VieneuTts.synthesize(
  text: 'Xin chào',
  options: preset,
  voice: 'Ngọc Huyền',      // overrides preset.voice
  sampleRate: 16000,
  channels: 1,
  responseFormat: AudioFormat.wav,
);

// Raw PCM (s16le, no header) for low-latency pipelines
final pcm = await VieneuTts.synthesize(
  text: 'Xin chào',
  sampleRate: 24000,
  channels: 1,
  responseFormat: AudioFormat.pcm,
);
```

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `voice` | `String?` | `minh_quan_pro` | Preset ID or display name, case/diacritic-insensitive |
| `speed` | `double?` | `1.0` | Speaking rate multiplier |
| `sampleRate` | `int?` | `24000` | `48000`, `24000`, `16000`, `8000` |
| `channels` | `int?` | `1` | `1` (downmix) or `2` (passthrough/duplicate) |
| `responseFormat` | `AudioFormat?` | `wav` for `synthesize`, `pcm` for `stream` | Raw `s16le` vs 44-byte RIFF/WAVE |
| `temperature` | `double?` | model default | Sampling temperature |
| `topK` / `topP` | `int?` / `double?` | model default | Sampling cutoffs |
| `repetitionPenalty` | `double?` | model default | Decoding penalty |
| `maxChars` / `minChars` | `int?` | model default | Text chunk sizing |
| `seed` | `int?` | model default | Deterministic sampling |

Voice names can also be resolved independently:

```dart
VieneuTts.resolveVoiceId('Mai Anh');   // 'mai_anh'
VieneuTts.resolveVoiceId('MINH_QUAN'); // 'minh_quan_pro' (fallback)
VieneuTts.findVoice('Adam bựa')?.id;   // 'adam_bua'
```

## Native Assets & Build Modes

`vieneu_tts` utilizes Dart Native Assets via `hook/build.dart` with automatic dual-mode operation:

- **Local Development Mode**: When working inside this repository with Rust/NDK installed, `hook/build.dart` automatically compiles the native crate directly from `rust/` using `flutter_rust_bridge_hooks` (`FlutterRustBridgeNativeAssetsBuilder`).
- **Release / Consumer Mode**: When consumed via `pub.dev` or `git:` dependency, the package automatically downloads precompiled binaries for your target platform from GitHub Releases.

You can explicitly control the build behavior using the `VIENEU_TTS_BUILD_MODE` environment variable:

```bash
# Force compilation from local Rust source
export VIENEU_TTS_BUILD_MODE=source

# Force resolution of prebuilt release binaries
export VIENEU_TTS_BUILD_MODE=prebuilt
```
