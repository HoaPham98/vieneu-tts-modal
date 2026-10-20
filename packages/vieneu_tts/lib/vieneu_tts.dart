import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'src/rust/api/api.dart' as rust_api;
import 'src/rust/frb_generated.dart';

/// Metadata for a Vietnamese voice preset.
class VoicePreset {
  final String id;
  final String name;
  final String label;

  const VoicePreset({
    required this.id,
    required this.name,
    required this.label,
  });

  @override
  String toString() => '$name ($id)';
}

/// Main entry point for on-device VieNeu-TTS.
class VieneuTts {
  static bool _initialized = false;
  static bool _bridgeInitialized = false;

  static const String defaultModelUrl =
      'https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/main/gguf/vieneu-v3-turbo-q8_0.gguf';

  /// Ensures native Rust bridge bindings are initialized.
  static Future<void> _ensureBridge() async {
    if (!_bridgeInitialized) {
      await RustLib.init();
      _bridgeInitialized = true;
    }
  }

  /// Downloads the official VieNeu-TTS v3 Turbo GGUF model (188 MB) to [destinationDir].
  ///
  /// Emits progress from 0.0 to 1.0 via [onProgress].
  /// Returns the absolute path of the downloaded file.
  static Future<String> downloadModel({
    required String destinationDir,
    String modelUrl = defaultModelUrl,
    String fileName = 'vieneu-v3-turbo-q8_0.gguf',
    void Function(double progress)? onProgress,
  }) async {
    final targetDir = Directory(destinationDir);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetPath = p.join(destinationDir, fileName);
    final targetFile = File(targetPath);

    // If file already exists and is non-empty (>180MB), return immediately
    if (await targetFile.exists()) {
      final len = await targetFile.length();
      if (len > 180 * 1024 * 1024) {
        onProgress?.call(1.0);
        return targetPath;
      }
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(modelUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode}',
          uri: Uri.parse(modelUrl),
        );
      }

      final totalBytes = response.contentLength ?? (188 * 1024 * 1024);
      var receivedBytes = 0;

      final tempPath = '$targetPath.part';
      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(receivedBytes / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      await tempFile.rename(targetPath);
      onProgress?.call(1.0);
      return targetPath;
    } finally {
      client.close();
    }
  }

  /// Initializes the in-process audio.cpp inference engine with the given GGUF [modelPath].
  static Future<void> init({
    required String modelPath,
    int threads = 4,
  }) async {
    await _ensureBridge();
    if (!File(modelPath).existsSync()) {
      throw FileSystemException('GGUF model file not found', modelPath);
    }

    await rust_api.initEngine(modelPath: modelPath, threads: threads);
    _initialized = true;
  }

  /// Returns true if the TTS engine is currently initialized and ready for synthesis.
  static bool get isInitialized => _initialized;

  /// Synthesizes speech from natural Vietnamese [text] into complete 48 kHz stereo WAV bytes.
  static Future<Uint8List> synthesize({
    required String text,
    String voice = 'minh_quan_pro',
    double speed = 1.0,
  }) async {
    if (!_initialized) {
      throw StateError('VieneuTts has not been initialized. Call init() first.');
    }
    final rawBytes = await rust_api.synthesizeSpeech(
      text: text,
      voice: voice,
      speed: speed,
    );
    return Uint8List.fromList(rawBytes);
  }

  /// Streams speech chunks in real-time as they are synthesized.
  static Stream<Uint8List> stream({
    required String text,
    String voice = 'minh_quan_pro',
    double speed = 1.0,
  }) async* {
    if (!_initialized) {
      throw StateError('VieneuTts has not been initialized. Call init() first.');
    }
    await for (final chunk in rust_api.streamSpeech(
      text: text,
      voice: voice,
      speed: speed,
    )) {
      yield Uint8List.fromList(chunk);
    }
  }

  /// Returns the catalog of 25 embedded Vietnamese voice presets.
  static List<VoicePreset> get availableVoices {
    return const [
      VoicePreset(id: 'minh_quan_pro', name: 'Minh Quân Pro', label: '⭐ Minh Quân Pro — Nam · Bắc · Tự nhiên'),
      VoicePreset(id: 'ngoc_huyen', name: 'Ngọc Huyền', label: '⭐ Ngọc Huyền — Nữ · Bắc · Tự nhiên'),
      VoicePreset(id: 'mai_anh', name: 'Mai Anh', label: '⭐ Mai Anh — Nữ · Bắc · Tin tức'),
      VoicePreset(id: 'thuy_dung', name: 'Thùy Dung', label: '⭐ Thùy Dung — Nữ · Nam · Tin tức'),
      VoicePreset(id: 'quang_son', name: 'Quang Sơn', label: '⭐ Quang Sơn — Nam · Trung · Tự nhiên'),
      VoicePreset(id: 'ngoc_tran', name: 'Ngọc Trân', label: '⭐ Ngọc Trân — Nữ · Trung · Tự nhiên'),
      VoicePreset(id: 'anh_khoi', name: 'Anh Khôi', label: '⭐ Anh Khôi — Nam · Bắc · Kể chuyện'),
      VoicePreset(id: 'truc_ly', name: 'Trúc Ly', label: '⭐ Trúc Ly — Nữ · Bắc · Tự nhiên'),
      VoicePreset(id: 'adam_bua', name: 'Adam bựa', label: '⭐ Adam bựa — Nam · Bắc · Tự nhiên'),
      VoicePreset(id: 'thien_tam_duc', name: 'Thiền Tâm Đức', label: '⭐ Thiền Tâm Đức — Nam · Bắc · Kể chuyện'),
      VoicePreset(id: 'minh_duc', name: 'Minh Đức', label: 'Minh Đức — Nam · Bắc · Tin tức'),
      VoicePreset(id: 'pham_tuyen', name: 'Phạm Tuyên', label: 'Phạm Tuyên — Nam · Bắc · Tự nhiên'),
      VoicePreset(id: 'thai_son', name: 'Thái Sơn', label: 'Thái Sơn — Nam · Nam · Kể chuyện'),
      VoicePreset(id: 'xuan_vinh', name: 'Xuân Vĩnh', label: 'Xuân Vĩnh — Nam · Bắc · Tự nhiên'),
      VoicePreset(id: 'thanh_binh', name: 'Thanh Bình', label: 'Thanh Bình — Nam · Bắc · Kể chuyện'),
      VoicePreset(id: 'ngoc_linh', name: 'Ngọc Linh', label: 'Ngọc Linh — Nữ · Bắc · Kể chuyện'),
      VoicePreset(id: 'doan_trang', name: 'Đoan Trang', label: 'Đoan Trang — Nữ · Bắc · Tự nhiên'),
      VoicePreset(id: 'thuc_doan', name: 'Thục Đoan', label: 'Thục Đoan — Nữ · Nam · Kể chuyện'),
      VoicePreset(id: 'minh_triet', name: 'Minh Triết', label: 'Minh Triết — Nam · Nam · Tin tức'),
      VoicePreset(id: 'my_duyen', name: 'Mỹ Duyên', label: 'Mỹ Duyên — Nữ · Nam · Đọc truyện'),
      VoicePreset(id: 'quynh_anh', name: 'Quỳnh Anh', label: 'Quỳnh Anh — Nữ · Bắc · Đọc truyện'),
      VoicePreset(id: 'duc_tri', name: 'Đức Trí', label: 'Đức Trí — Nam · Nam · Đọc truyện'),
      VoicePreset(id: 'kim_thanh', name: 'Kim Thanh', label: 'Kim Thanh — Nữ · Nam · Đọc truyện'),
      VoicePreset(id: 'adam', name: 'Adam', label: 'Adam — Nam · Nam · Tự nhiên'),
      VoicePreset(id: 'manh_dung', name: 'Mạnh Dũng', label: 'Mạnh Dũng — Nam · Bắc · Tự nhiên'),
    ];
  }

  /// Disposes and unloads the native engine.
  static Future<void> dispose() async {
    if (_initialized) {
      await rust_api.disposeEngine();
      _initialized = false;
    }
  }
}
