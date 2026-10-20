# Vieneu TTS Flutter & Dart Library

On-device, high-performance Vietnamese Text-to-Speech library powered by **VieNeu-TTS v3 Turbo GGUF** and the C++ engine **audio.cpp**, exposed to Dart via **flutter_rust_bridge v2**.

## Features

- ⚡ **100% On-Device Offline Inference**: Runs entirely in-process using `audio.cpp` and `ggml` with instant `mmap` loading.
- 🎙️ **25 Embedded Voice Presets**: Includes Minh Quân Pro, Ngọc Huyền, Mai Anh, Quang Sơn, and 21 other regional accents embedded into the native binary.
- 🔤 **Automatic Vietnamese G2P**: Integrated text normalization and G2P via `sea-g2p-rs` (handles numbers, dates, abbreviations, and emotion cues).
- 🌊 **Audio Streaming**: Stream audio chunks in real-time as they are synthesized.
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

  // 3. Synthesize full audio
  final wavBytes = await VieneuTts.synthesize(
    text: 'Xin chào! Chúc bạn một ngày tốt lành.',
    voice: 'minh_quan_pro',
  );

  // 4. Or stream speech chunks
  final stream = VieneuTts.stream(
    text: 'Tỉ lệ giải ngân đầu tư công đạt 68,5% kế hoạch năm.',
    voice: 'minh_quan_pro',
  );
  
  await for (final chunk in stream) {
    // Pipe chunk to audio player or buffer
  }
}
```
