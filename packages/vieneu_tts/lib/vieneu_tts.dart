import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'src/rust/api.dart' as rust_api;
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

/// Audio container format for synthesized speech.
enum AudioFormat {
  /// Raw 16-bit little-endian PCM bytes with no container header.
  pcm('pcm'),

  /// Standard RIFF/WAVE container with a 44-byte header followed by PCM data.
  wav('wav');

  const AudioFormat(this.value);

  /// Wire value used by the native bridge and Remote API (`pcm` / `wav`).
  final String value;

  /// Resolves an [AudioFormat] from a wire value, defaulting to [AudioFormat.wav].
  static AudioFormat fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'pcm':
        return AudioFormat.pcm;
      case 'wav':
        return AudioFormat.wav;
      default:
        return AudioFormat.wav;
    }
  }
}

/// Options controlling on-device speech synthesis.
///
/// Every field is optional and mirrors the Remote API's `/v1/audio/speech`
/// parameters. Omitted values keep the historical behaviour: 24 kHz mono WAV
/// for [VieneuTts.synthesize] and raw 24 kHz mono PCM chunks for
/// [VieneuTts.stream].
class TtsSynthesisOptions {
  /// Voice preset ID or display name (e.g. `mai_anh` or `Mai Anh`).
  final String? voice;

  /// Speaking rate multiplier, where `1.0` is the model's natural pace.
  final double? speed;

  /// Target sample rate in Hz. Supported: 48000, 24000, 16000, 8000.
  final int? sampleRate;

  /// Target channel count: `1` for mono, `2` for stereo.
  final int? channels;

  /// Container format for the emitted audio bytes.
  final AudioFormat? responseFormat;

  /// Sampling temperature.
  final double? temperature;

  /// Top-k sampling cutoff.
  final int? topK;

  /// Nucleus (top-p) sampling probability.
  final double? topP;

  /// Repetition penalty applied during decoding.
  final double? repetitionPenalty;

  /// Maximum characters per text chunk.
  final int? maxChars;

  /// Minimum characters per text chunk.
  final int? minChars;

  /// Deterministic sampling seed.
  final int? seed;

  const TtsSynthesisOptions({
    this.voice,
    this.speed,
    this.sampleRate,
    this.channels,
    this.responseFormat,
    this.temperature,
    this.topK,
    this.topP,
    this.repetitionPenalty,
    this.maxChars,
    this.minChars,
    this.seed,
  });

  /// Default sample rate used when none is requested.
  static const int defaultSampleRate = 24000;

  /// Default channel count used when none is requested.
  static const int defaultChannels = 1;

  /// Resolved sample rate, defaulting to [defaultSampleRate].
  int get resolvedSampleRate =>
      (sampleRate != null && sampleRate! > 0) ? sampleRate! : defaultSampleRate;

  /// Resolved channel count, defaulting to [defaultChannels].
  int get resolvedChannels =>
      (channels != null && channels! > 0) ? channels! : defaultChannels;

  /// Returns a copy with the given fields replaced.
  TtsSynthesisOptions copyWith({
    String? voice,
    double? speed,
    int? sampleRate,
    int? channels,
    AudioFormat? responseFormat,
    double? temperature,
    int? topK,
    double? topP,
    double? repetitionPenalty,
    int? maxChars,
    int? minChars,
    int? seed,
  }) {
    return TtsSynthesisOptions(
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      responseFormat: responseFormat ?? this.responseFormat,
      temperature: temperature ?? this.temperature,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      maxChars: maxChars ?? this.maxChars,
      minChars: minChars ?? this.minChars,
      seed: seed ?? this.seed,
    );
  }

  /// Merges this options object with explicit named call arguments.
  ///
  /// Explicit arguments win over the matching fields in this options object,
  /// which lets consumers keep a reusable preset while overriding one value
  /// per call.
  TtsSynthesisOptions mergedWith({
    String? voice,
    double? speed,
    int? sampleRate,
    int? channels,
    AudioFormat? responseFormat,
    double? temperature,
    int? topK,
    double? topP,
    double? repetitionPenalty,
    int? maxChars,
    int? minChars,
    int? seed,
  }) {
    return TtsSynthesisOptions(
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      responseFormat: responseFormat ?? this.responseFormat,
      temperature: temperature ?? this.temperature,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      maxChars: maxChars ?? this.maxChars,
      minChars: minChars ?? this.minChars,
      seed: seed ?? this.seed,
    );
  }
}

/// Main entry point for on-device VieNeu-TTS.
class VieneuTts {
  static bool _initialized = false;
  static bool _bridgeInitialized = false;

  static const String defaultModelUrl =
      'https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/main/gguf/vieneu-v3-turbo-q8_0.gguf';
  static const String defaultDictUrl =
      'https://github.com/pnnbao97/sea-g2p/releases/download/v0.10.0/sea_g2p.bin';

  /// Canonical voice ID used when no voice (or an unknown one) is requested.
  static const String defaultVoiceId = 'minh_quan_pro';

  /// Ensures native Rust bridge bindings are initialized.
  static Future<void> _ensureBridge() async {
    if (!_bridgeInitialized) {
      await RustLib.init();
      _bridgeInitialized = true;
    }
  }

  /// The flutter_rust_bridge codegen version used for bridge generation.
  static String get bridgeCodegenVersion => RustLib.instance.codegenVersion;

  /// Downloads a file from [url] to [destinationDir]/[fileName].
  static Future<String> _downloadFile({
    required String destinationDir,
    required String url,
    required String fileName,
    int minExpectedBytes = 10 * 1024 * 1024,
    void Function(double progress)? onProgress,
  }) async {
    final targetDir = Directory(destinationDir);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetPath = p.join(destinationDir, fileName);
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      final len = await targetFile.length();
      if (len >= minExpectedBytes) {
        onProgress?.call(1.0);
        return targetPath;
      }
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download: HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      final totalBytes = response.contentLength ?? minExpectedBytes;
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

  /// Downloads the official VieNeu-TTS v3 Turbo GGUF model (188 MB) to [destinationDir].
  static Future<String> downloadModel({
    required String destinationDir,
    String modelUrl = defaultModelUrl,
    String fileName = 'model.gguf',
    void Function(double progress)? onProgress,
  }) async {
    return _downloadFile(
      destinationDir: destinationDir,
      url: modelUrl,
      fileName: fileName,
      minExpectedBytes: 180 * 1024 * 1024,
      onProgress: onProgress,
    );
  }

  /// Downloads the official SEA-G2P dictionary (60 MB) to [destinationDir].
  static Future<String> downloadDictionary({
    required String destinationDir,
    String dictUrl = defaultDictUrl,
    String fileName = 'sea_g2p.bin',
    void Function(double progress)? onProgress,
  }) async {
    return _downloadFile(
      destinationDir: destinationDir,
      url: dictUrl,
      fileName: fileName,
      minExpectedBytes: 50 * 1024 * 1024,
      onProgress: onProgress,
    );
  }

  /// Initializes the in-process inference engine with the given GGUF [modelPath] and optional [dictPath].
  static Future<void> init({
    required String modelPath,
    String? dictPath,
    int threads = 4,
  }) async {
    await _ensureBridge();
    if (!File(modelPath).existsSync()) {
      throw FileSystemException('GGUF model file not found', modelPath);
    }

    final resolvedDict =
        dictPath ?? p.join(p.dirname(modelPath), 'sea_g2p.bin');
    final actualDict = File(resolvedDict).existsSync() ? resolvedDict : null;

    await rust_api.initEngine(
      modelPath: modelPath,
      dictPath: actualDict,
      threads: BigInt.from(threads),
    );
    _initialized = true;
  }

  /// Returns true if the TTS engine is currently initialized and ready for synthesis.
  static bool get isInitialized => _initialized;

  /// Synthesizes speech from natural Vietnamese [text] into complete audio bytes.
  ///
  /// Defaults to 24 kHz mono WAV. Pass [options] to reuse a preset, or any of the
  /// optional named parameters to override a single value for this call.
  static Future<Uint8List> synthesize({
    required String text,
    String? voice,
    double? speed,
    TtsSynthesisOptions? options,
    int? sampleRate,
    int? channels,
    AudioFormat? responseFormat,
    double? temperature,
    int? topK,
    double? topP,
    double? repetitionPenalty,
    int? maxChars,
    int? minChars,
    int? seed,
  }) async {
    if (!_initialized) {
      throw StateError(
          'VieneuTts has not been initialized. Call init() first.');
    }
    final resolved = _resolveOptions(
      options: options,
      voice: voice,
      speed: speed,
      sampleRate: sampleRate,
      channels: channels,
      responseFormat: responseFormat,
      temperature: temperature,
      topK: topK,
      topP: topP,
      repetitionPenalty: repetitionPenalty,
      maxChars: maxChars,
      minChars: minChars,
      seed: seed,
      defaultFormat: AudioFormat.wav,
    );
    final rawBytes = await rust_api.synthesizeSpeech(
      text: text,
      voice: resolved.voice!,
      speed: resolved.speed ?? 1.0,
      options: _toBridgeOptions(resolved),
    );
    return Uint8List.fromList(rawBytes);
  }

  /// Streams speech chunks in real-time as they are synthesized.
  ///
  /// Defaults to raw 24 kHz mono `s16le` PCM chunks with no container header so
  /// chunks can be piped straight into an audio sink. Pass
  /// `responseFormat: AudioFormat.wav` to receive a WAV container instead.
  static Stream<Uint8List> stream({
    required String text,
    String? voice,
    double? speed,
    TtsSynthesisOptions? options,
    int? sampleRate,
    int? channels,
    AudioFormat? responseFormat,
    double? temperature,
    int? topK,
    double? topP,
    double? repetitionPenalty,
    int? maxChars,
    int? minChars,
    int? seed,
  }) async* {
    if (!_initialized) {
      throw StateError(
          'VieneuTts has not been initialized. Call init() first.');
    }
    final resolved = _resolveOptions(
      options: options,
      voice: voice,
      speed: speed,
      sampleRate: sampleRate,
      channels: channels,
      responseFormat: responseFormat,
      temperature: temperature,
      topK: topK,
      topP: topP,
      repetitionPenalty: repetitionPenalty,
      maxChars: maxChars,
      minChars: minChars,
      seed: seed,
      defaultFormat: AudioFormat.pcm,
    );
    await for (final chunk in rust_api.streamSpeech(
      text: text,
      voice: resolved.voice!,
      speed: resolved.speed ?? 1.0,
      options: _toBridgeOptions(resolved),
    )) {
      yield Uint8List.fromList(chunk);
    }
  }

  /// Merges presets with per-call overrides and applies call-site defaults.
  static TtsSynthesisOptions _resolveOptions({
    TtsSynthesisOptions? options,
    String? voice,
    double? speed,
    int? sampleRate,
    int? channels,
    AudioFormat? responseFormat,
    double? temperature,
    int? topK,
    double? topP,
    double? repetitionPenalty,
    int? maxChars,
    int? minChars,
    int? seed,
    required AudioFormat defaultFormat,
  }) {
    final merged = (options ?? const TtsSynthesisOptions()).mergedWith(
      voice: voice,
      speed: speed,
      sampleRate: sampleRate,
      channels: channels,
      responseFormat: responseFormat,
      temperature: temperature,
      topK: topK,
      topP: topP,
      repetitionPenalty: repetitionPenalty,
      maxChars: maxChars,
      minChars: minChars,
      seed: seed,
    );
    return TtsSynthesisOptions(
      voice: resolveVoiceId(merged.voice),
      speed: merged.speed,
      sampleRate: merged.resolvedSampleRate,
      channels: merged.resolvedChannels,
      responseFormat: merged.responseFormat ?? defaultFormat,
      temperature: merged.temperature,
      topK: merged.topK,
      topP: merged.topP,
      repetitionPenalty: merged.repetitionPenalty,
      maxChars: merged.maxChars,
      minChars: merged.minChars,
      seed: merged.seed,
    );
  }

  /// Converts resolved Dart options into the generated bridge options struct.
  static rust_api.SynthesisOptions _toBridgeOptions(
    TtsSynthesisOptions options,
  ) {
    return rust_api.SynthesisOptions(
      voice: options.voice,
      speed: options.speed,
      sampleRate: options.sampleRate,
      channels: options.channels,
      responseFormat: options.responseFormat?.value,
      temperature: options.temperature,
      topK: options.topK,
      topP: options.topP,
      repetitionPenalty: options.repetitionPenalty,
      maxChars: options.maxChars,
      minChars: options.minChars,
      seed: options.seed,
    );
  }

  /// Folds a name for comparison: lowercases and strips Vietnamese diacritics.
  static String _voiceKey(String value) {
    const diacritics = {
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'đ': 'd',
    };
    final buffer = StringBuffer();
    for (final rune in value.trim().toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      final folded = diacritics[char] ?? char;
      for (final c in folded.codeUnits) {
        final isAlnum = (c >= 0x30 && c <= 0x39) ||
            (c >= 0x61 && c <= 0x7A) ||
            (c >= 0x41 && c <= 0x5A);
        if (isAlnum) buffer.writeCharCode(c);
      }
    }
    return buffer.toString();
  }

  /// Resolves a user-provided voice name or ID to a canonical preset ID.
  ///
  /// Matching is case-insensitive, diacritic-insensitive, and separator-
  /// insensitive, so `mai_anh`, `Mai Anh`, and `MAI ANH` all resolve to
  /// `mai_anh`. Unknown values fall back to [defaultVoiceId].
  static String resolveVoiceId(String? value) {
    final key = value == null ? '' : _voiceKey(value);
    if (key.isEmpty) return defaultVoiceId;
    for (final preset in availableVoices) {
      if (_voiceKey(preset.id) == key || _voiceKey(preset.name) == key) {
        return preset.id;
      }
    }
    return defaultVoiceId;
  }

  /// Finds the catalog entry matching a voice ID or display name.
  ///
  /// Returns `null` when no preset matches (no fallback is applied).
  static VoicePreset? findVoice(String value) {
    final key = _voiceKey(value);
    if (key.isEmpty) return null;
    for (final preset in availableVoices) {
      if (_voiceKey(preset.id) == key || _voiceKey(preset.name) == key) {
        return preset;
      }
    }
    return null;
  }

  /// Returns the catalog of 25 embedded Vietnamese voice presets.
  static List<VoicePreset> get availableVoices {
    return const [
      VoicePreset(
          id: 'minh_quan_pro',
          name: 'Minh Quân Pro',
          label: '⭐ Minh Quân Pro — Nam · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'ngoc_huyen',
          name: 'Ngọc Huyền',
          label: '⭐ Ngọc Huyền — Nữ · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'mai_anh',
          name: 'Mai Anh',
          label: '⭐ Mai Anh — Nữ · Bắc · Tin tức'),
      VoicePreset(
          id: 'thuy_dung',
          name: 'Thùy Dung',
          label: '⭐ Thùy Dung — Nữ · Nam · Tin tức'),
      VoicePreset(
          id: 'quang_son',
          name: 'Quang Sơn',
          label: '⭐ Quang Sơn — Nam · Trung · Tự nhiên'),
      VoicePreset(
          id: 'ngoc_tran',
          name: 'Ngọc Trân',
          label: '⭐ Ngọc Trân — Nữ · Trung · Tự nhiên'),
      VoicePreset(
          id: 'anh_khoi',
          name: 'Anh Khôi',
          label: '⭐ Anh Khôi — Nam · Bắc · Kể chuyện'),
      VoicePreset(
          id: 'truc_ly',
          name: 'Trúc Ly',
          label: '⭐ Trúc Ly — Nữ · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'adam_bua',
          name: 'Adam bựa',
          label: '⭐ Adam bựa — Nam · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'thien_tam_duc',
          name: 'Thiền Tâm Đức',
          label: '⭐ Thiền Tâm Đức — Nam · Bắc · Kể chuyện'),
      VoicePreset(
          id: 'minh_duc',
          name: 'Minh Đức',
          label: 'Minh Đức — Nam · Bắc · Tin tức'),
      VoicePreset(
          id: 'pham_tuyen',
          name: 'Phạm Tuyên',
          label: 'Phạm Tuyên — Nam · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'thai_son',
          name: 'Thái Sơn',
          label: 'Thái Sơn — Nam · Nam · Kể chuyện'),
      VoicePreset(
          id: 'xuan_vinh',
          name: 'Xuân Vĩnh',
          label: 'Xuân Vĩnh — Nam · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'thanh_binh',
          name: 'Thanh Bình',
          label: 'Thanh Bình — Nam · Bắc · Kể chuyện'),
      VoicePreset(
          id: 'ngoc_linh',
          name: 'Ngọc Linh',
          label: 'Ngọc Linh — Nữ · Bắc · Kể chuyện'),
      VoicePreset(
          id: 'doan_trang',
          name: 'Đoan Trang',
          label: 'Đoan Trang — Nữ · Bắc · Tự nhiên'),
      VoicePreset(
          id: 'thuc_doan',
          name: 'Thục Đoan',
          label: 'Thục Đoan — Nữ · Nam · Kể chuyện'),
      VoicePreset(
          id: 'minh_triet',
          name: 'Minh Triết',
          label: 'Minh Triết — Nam · Nam · Tin tức'),
      VoicePreset(
          id: 'my_duyen',
          name: 'Mỹ Duyên',
          label: 'Mỹ Duyên — Nữ · Nam · Đọc truyện'),
      VoicePreset(
          id: 'quynh_anh',
          name: 'Quỳnh Anh',
          label: 'Quỳnh Anh — Nữ · Bắc · Đọc truyện'),
      VoicePreset(
          id: 'duc_tri',
          name: 'Đức Trí',
          label: 'Đức Trí — Nam · Nam · Đọc truyện'),
      VoicePreset(
          id: 'kim_thanh',
          name: 'Kim Thanh',
          label: 'Kim Thanh — Nữ · Nam · Đọc truyện'),
      VoicePreset(
          id: 'adam', name: 'Adam', label: 'Adam — Nam · Nam · Tự nhiên'),
      VoicePreset(
          id: 'manh_dung',
          name: 'Mạnh Dũng',
          label: 'Mạnh Dũng — Nam · Bắc · Tự nhiên'),
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
