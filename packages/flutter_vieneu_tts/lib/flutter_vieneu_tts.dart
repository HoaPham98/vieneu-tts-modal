import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vieneu_tts/vieneu_tts.dart';

export 'package:vieneu_tts/vieneu_tts.dart';

/// Flutter-specific wrapper for on-device VieNeu-TTS.
///
/// Automatically manages local app sandbox storage using `path_provider`
/// and provides reactive progress notifiers for UI binding.
class VieneuTtsFlutter {
  static final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0.0);
  static final ValueNotifier<String> statusMessage = ValueNotifier<String>('Chưa khởi tạo');

  /// Resolves the default directory for storing GGUF models in the app sandbox.
  static Future<String> getModelsDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'vieneu_models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Checks if the model file is already present and valid in app storage.
  static Future<bool> isModelReady({
    String fileName = 'model.gguf',
    int minBytes = 100 * 1024 * 1024,
  }) async {
    final modelsDir = await getModelsDir();
    final file = File(p.join(modelsDir, fileName));
    if (await file.exists()) {
      final len = await file.length();
      return len >= minBytes;
    }
    return false;
  }

  /// Ensures model weights and dictionary are downloaded, then initializes the engine.
  static Future<void> init({
    String? modelPath,
    String? dictPath,
    int threads = 4,
    void Function(double progress, String status)? onProgress,
  }) async {
    final modelsDir = await getModelsDir();

    String resolvedModel = modelPath ?? p.join(modelsDir, 'model.gguf');
    String resolvedDict = dictPath ?? p.join(modelsDir, 'sea_g2p.bin');

    final modelFile = File(resolvedModel);
    if (!await modelFile.exists() || await modelFile.length() < 100 * 1024 * 1024) {
      statusMessage.value = 'Đang tải model GGUF (188 MB)...';
      onProgress?.call(0.0, statusMessage.value);

      resolvedModel = await VieneuTts.downloadModel(
        destinationDir: modelsDir,
        fileName: 'model.gguf',
        onProgress: (pVal) {
          downloadProgress.value = pVal * 0.75;
          onProgress?.call(downloadProgress.value, statusMessage.value);
        },
      );
    }

    final dictFile = File(resolvedDict);
    if (!await dictFile.exists() || await dictFile.length() < 10 * 1024 * 1024) {
      statusMessage.value = 'Đang tải từ điển SEA-G2P...';
      onProgress?.call(0.75, statusMessage.value);

      resolvedDict = await VieneuTts.downloadDictionary(
        destinationDir: modelsDir,
        fileName: 'sea_g2p.bin',
        onProgress: (pVal) {
          downloadProgress.value = 0.75 + pVal * 0.25;
          onProgress?.call(downloadProgress.value, statusMessage.value);
        },
      );
    }

    statusMessage.value = 'Đang khởi tạo engine TTS...';
    onProgress?.call(1.0, statusMessage.value);

    await VieneuTts.init(
      modelPath: resolvedModel,
      dictPath: resolvedDict,
      threads: threads,
    );

    statusMessage.value = 'Sẵn sàng phát âm';
    downloadProgress.value = 1.0;
  }

  /// Disposes the underlying native engine.
  static Future<void> dispose() async {
    await VieneuTts.dispose();
    statusMessage.value = 'Đã giải phóng';
  }
}
