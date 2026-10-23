import 'package:test/test.dart';
import 'package:vieneu_tts/src/rust/api.dart' as bridge;
import 'package:vieneu_tts/vieneu_tts.dart';

/// Reads an unsigned 16-bit little-endian value at [offset].
int _u16le(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

/// Reads an unsigned 32-bit little-endian value at [offset].
int _u32le(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// Returns true when [bytes] starts with a 44-byte RIFF/WAVE `s16le` header.
bool _hasWavHeader(List<int> bytes) {
  if (bytes.length < 44) return false;
  const riff = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
  const wave = [0x57, 0x41, 0x56, 0x45]; // "WAVE"
  const fmt = [0x66, 0x6D, 0x74, 0x20]; // "fmt "
  const data = [0x64, 0x61, 0x74, 0x61]; // "data"
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != riff[i]) return false;
    if (bytes[8 + i] != wave[i]) return false;
    if (bytes[12 + i] != fmt[i]) return false;
    if (bytes[36 + i] != data[i]) return false;
  }
  return true;
}

void main() {
  group('VieneuTts Voices Catalog Tests', () {
    test('contains 25 default voice presets', () {
      final voices = VieneuTts.availableVoices;
      expect(voices.length, equals(25));
    });

    test('default voice is minh_quan_pro', () {
      final voices = VieneuTts.availableVoices;
      expect(voices.any((v) => v.id == 'minh_quan_pro'), isTrue);
      expect(VieneuTts.defaultVoiceId, equals('minh_quan_pro'));
    });

    test('model download URL is valid', () {
      expect(
        VieneuTts.defaultModelUrl,
        contains('huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo'),
      );
    });

    test('bridge codegen version matches expected version 2.0.0', () {
      expect(
        VieneuTts.bridgeCodegenVersion,
        equals('2.0.0'),
        reason: 'FRB codegen version must match 2.0.0',
      );
    });
  });

  group('AudioFormat', () {
    test('exposes the wire values used by the native bridge', () {
      expect(AudioFormat.pcm.value, equals('pcm'));
      expect(AudioFormat.wav.value, equals('wav'));
      expect(AudioFormat.values.length, equals(2));
    });

    test('fromValue resolves known formats case-insensitively', () {
      expect(AudioFormat.fromValue('pcm'), equals(AudioFormat.pcm));
      expect(AudioFormat.fromValue('PCM'), equals(AudioFormat.pcm));
      expect(AudioFormat.fromValue('wav'), equals(AudioFormat.wav));
      expect(AudioFormat.fromValue('Wav'), equals(AudioFormat.wav));
      expect(AudioFormat.fromValue(' pcm '), equals(AudioFormat.pcm));
    });

    test('fromValue defaults to wav for unknown or missing values', () {
      expect(AudioFormat.fromValue(null), equals(AudioFormat.wav));
      expect(AudioFormat.fromValue(''), equals(AudioFormat.wav));
      expect(AudioFormat.fromValue('mp3'), equals(AudioFormat.wav));
    });
  });

  group('TtsSynthesisOptions', () {
    test('defaults match the Remote API baseline', () {
      const options = TtsSynthesisOptions();
      expect(options.voice, isNull);
      expect(options.speed, isNull);
      expect(options.sampleRate, isNull);
      expect(options.channels, isNull);
      expect(options.responseFormat, isNull);
      expect(options.temperature, isNull);
      expect(options.topK, isNull);
      expect(options.topP, isNull);
      expect(options.repetitionPenalty, isNull);
      expect(options.maxChars, isNull);
      expect(options.minChars, isNull);
      expect(options.seed, isNull);
    });

    test('resolves 24 kHz mono when nothing is specified', () {
      const options = TtsSynthesisOptions();
      expect(options.resolvedSampleRate, equals(24000));
      expect(options.resolvedChannels, equals(1));
      expect(TtsSynthesisOptions.defaultSampleRate, equals(24000));
      expect(TtsSynthesisOptions.defaultChannels, equals(1));
    });

    test('honours explicitly configured values', () {
      const options = TtsSynthesisOptions(
        voice: 'Mai Anh',
        speed: 1.25,
        sampleRate: 16000,
        channels: 2,
        responseFormat: AudioFormat.pcm,
        temperature: 0.7,
        topK: 50,
        topP: 0.9,
        repetitionPenalty: 1.1,
        maxChars: 400,
        minChars: 40,
        seed: 42,
      );
      expect(options.voice, equals('Mai Anh'));
      expect(options.speed, equals(1.25));
      expect(options.resolvedSampleRate, equals(16000));
      expect(options.resolvedChannels, equals(2));
      expect(options.responseFormat, equals(AudioFormat.pcm));
      expect(options.temperature, equals(0.7));
      expect(options.topK, equals(50));
      expect(options.topP, equals(0.9));
      expect(options.repetitionPenalty, equals(1.1));
      expect(options.maxChars, equals(400));
      expect(options.minChars, equals(40));
      expect(options.seed, equals(42));
    });

    test('ignores non-positive sample rate and channel values', () {
      const options = TtsSynthesisOptions(sampleRate: 0, channels: 0);
      expect(options.resolvedSampleRate, equals(24000));
      expect(options.resolvedChannels, equals(1));
    });

    test('accepts every supported sample rate', () {
      for (final rate in [48000, 24000, 16000, 8000]) {
        final options = TtsSynthesisOptions(sampleRate: rate);
        expect(options.resolvedSampleRate, equals(rate));
      }
    });

    test('copyWith replaces only the requested fields', () {
      const base = TtsSynthesisOptions(
        voice: 'mai_anh',
        speed: 1.0,
        sampleRate: 24000,
        channels: 1,
        responseFormat: AudioFormat.wav,
      );
      final updated = base.copyWith(sampleRate: 8000, channels: 2);

      expect(updated.sampleRate, equals(8000));
      expect(updated.channels, equals(2));
      expect(updated.voice, equals('mai_anh'));
      expect(updated.speed, equals(1.0));
      expect(updated.responseFormat, equals(AudioFormat.wav));
    });

    test('mergedWith lets explicit arguments win over preset fields', () {
      const preset = TtsSynthesisOptions(
        voice: 'mai_anh',
        sampleRate: 24000,
        responseFormat: AudioFormat.wav,
        temperature: 0.5,
      );
      final merged = preset.mergedWith(
        voice: 'ngoc_huyen',
        sampleRate: 48000,
        seed: 7,
      );

      expect(merged.voice, equals('ngoc_huyen'));
      expect(merged.sampleRate, equals(48000));
      expect(merged.seed, equals(7));
      // Untouched preset fields survive the merge.
      expect(merged.responseFormat, equals(AudioFormat.wav));
      expect(merged.temperature, equals(0.5));
    });

    test('mergedWith over an empty preset behaves like a plain override', () {
      const empty = TtsSynthesisOptions();
      final merged = empty.mergedWith(speed: 1.5, topK: 20);
      expect(merged.speed, equals(1.5));
      expect(merged.topK, equals(20));
      expect(merged.resolvedSampleRate, equals(24000));
      expect(merged.resolvedChannels, equals(1));
    });
  });

  group('Voice name resolution', () {
    test('resolves presets by canonical ID', () {
      for (final preset in VieneuTts.availableVoices) {
        expect(VieneuTts.resolveVoiceId(preset.id), equals(preset.id));
      }
    });

    test('resolves presets by display name', () {
      for (final preset in VieneuTts.availableVoices) {
        expect(
          VieneuTts.resolveVoiceId(preset.name),
          equals(preset.id),
          reason: '${preset.name} should resolve to ${preset.id}',
        );
      }
    });

    test('resolves "Mai Anh" to the mai_anh preset', () {
      expect(VieneuTts.resolveVoiceId('Mai Anh'), equals('mai_anh'));
      expect(
          VieneuTts.resolveVoiceId('minh_quan_pro'), equals('minh_quan_pro'));
      expect(
          VieneuTts.resolveVoiceId('Minh Quân Pro'), equals('minh_quan_pro'));
    });

    test('is case and separator insensitive', () {
      expect(VieneuTts.resolveVoiceId('MAI_ANH'), equals('mai_anh'));
      expect(VieneuTts.resolveVoiceId('  mai anh  '), equals('mai_anh'));
      expect(VieneuTts.resolveVoiceId('MaiAnh'), equals('mai_anh'));
      expect(VieneuTts.resolveVoiceId('mAi AnH'), equals('mai_anh'));
    });

    test('is diacritic insensitive', () {
      expect(
          VieneuTts.resolveVoiceId('thien tam duc'), equals('thien_tam_duc'));
      expect(VieneuTts.resolveVoiceId('thuy dung'), equals('thuy_dung'));
      expect(VieneuTts.resolveVoiceId('duc tri'), equals('duc_tri'));
    });

    test('falls back to minh_quan_pro for unknown or empty voices', () {
      expect(
          VieneuTts.resolveVoiceId('khong_ton_tai'), equals('minh_quan_pro'));
      expect(VieneuTts.resolveVoiceId('unrecognized voice'),
          equals('minh_quan_pro'));
      expect(VieneuTts.resolveVoiceId(''), equals('minh_quan_pro'));
      expect(VieneuTts.resolveVoiceId('   '), equals('minh_quan_pro'));
      expect(VieneuTts.resolveVoiceId(null), equals('minh_quan_pro'));
    });

    test('findVoice returns the catalog entry for IDs and names', () {
      expect(VieneuTts.findVoice('mai_anh')?.id, equals('mai_anh'));
      expect(VieneuTts.findVoice('Mai Anh')?.id, equals('mai_anh'));
      expect(
          VieneuTts.findVoice('Minh Quân Pro')?.name, equals('Minh Quân Pro'));
      expect(VieneuTts.findVoice('Adam bựa')?.id, equals('adam_bua'));
    });

    test('findVoice returns null for unknown voices without falling back', () {
      expect(VieneuTts.findVoice('khong_ton_tai'), isNull);
      expect(VieneuTts.findVoice(''), isNull);
    });
  });

  group('Bridge options contract', () {
    test('generated SynthesisOptions accepts every plumbed field', () {
      const options = bridge.SynthesisOptions(
        voice: 'mai_anh',
        speed: 1.1,
        sampleRate: 16000,
        channels: 2,
        responseFormat: 'pcm',
        temperature: 0.7,
        topK: 50,
        topP: 0.9,
        repetitionPenalty: 1.1,
        maxChars: 400,
        minChars: 40,
        seed: 42,
      );

      expect(options.voice, equals('mai_anh'));
      expect(options.speed, equals(1.1));
      expect(options.sampleRate, equals(16000));
      expect(options.channels, equals(2));
      expect(options.responseFormat, equals('pcm'));
      expect(options.temperature, equals(0.7));
      expect(options.topK, equals(50));
      expect(options.topP, equals(0.9));
      expect(options.repetitionPenalty, equals(1.1));
      expect(options.maxChars, equals(400));
      expect(options.minChars, equals(40));
      expect(options.seed, equals(42));
    });

    test('bridge round-trips AudioFormat wire values unchanged', () {
      for (final format in AudioFormat.values) {
        final options = bridge.SynthesisOptions(responseFormat: format.value);
        expect(options.responseFormat, equals(format.value));
        expect(AudioFormat.fromValue(options.responseFormat), equals(format));
      }
    });

    test('bridge options default to null so native defaults apply', () {
      const options = bridge.SynthesisOptions();
      expect(options.voice, isNull);
      expect(options.sampleRate, isNull);
      expect(options.channels, isNull);
      expect(options.responseFormat, isNull);
      expect(options.temperature, isNull);
      expect(options.topK, isNull);
      expect(options.topP, isNull);
      expect(options.repetitionPenalty, isNull);
      expect(options.maxChars, isNull);
      expect(options.minChars, isNull);
      expect(options.seed, isNull);
    });
  });

  group('Audio container expectations', () {
    test('raw PCM payload carries exactly two bytes per sample and no header',
        () {
      const sampleCount = 240;
      final pcm = _syntheticPcmBytes(sampleCount);
      expect(pcm.length, equals(sampleCount * 2));
      expect(_hasWavHeader(pcm), isFalse);
    });

    test('WAV container carries a 44-byte RIFF header and s16le payload', () {
      const sampleCount = 240;
      const sampleRate = 24000;
      const channels = 1;
      final wav = _syntheticWavBytes(
        sampleCount: sampleCount,
        sampleRate: sampleRate,
        channels: channels,
      );

      expect(wav.length, equals(sampleCount * 2 + 44));
      expect(_hasWavHeader(wav), isTrue);
      expect(_u32le(wav, 24), equals(sampleRate));
      expect(_u16le(wav, 22), equals(channels));
      expect(_u16le(wav, 34), equals(16));
      expect(_u32le(wav, 40), equals(sampleCount * 2));
      expect(_u32le(wav, 4), equals(sampleCount * 2 + 36));
    });

    test('WAV header reports the requested sample rate and channel count', () {
      for (final rate in [48000, 24000, 16000, 8000]) {
        final wav = _syntheticWavBytes(
          sampleCount: 120,
          sampleRate: rate,
          channels: 2,
        );
        expect(_u32le(wav, 24), equals(rate));
        expect(_u16le(wav, 22), equals(2));
        expect(_u16le(wav, 32), equals(4)); // block align = channels * 2 bytes
        expect(_u32le(wav, 28), equals(rate * 4)); // byte rate
      }
    });

    test('PCM output scales with channel count', () {
      const frames = 100;
      final mono = _syntheticPcmBytes(frames);
      final stereo = _syntheticPcmBytes(frames * 2);
      expect(stereo.length, equals(mono.length * 2));
      expect(_hasWavHeader(mono), isFalse);
      expect(_hasWavHeader(stereo), isFalse);
    });
  });
}

/// Builds a raw `s16le` byte buffer of [sampleCount] samples with no header.
List<int> _syntheticPcmBytes(int sampleCount) {
  final bytes = <int>[];
  for (var i = 0; i < sampleCount; i++) {
    final value = ((i % 200) - 100) * 200;
    bytes.add(value & 0xFF);
    bytes.add((value >> 8) & 0xFF);
  }
  return bytes;
}

/// Builds a 44-byte RIFF/WAVE header followed by [sampleCount] `s16le` samples.
List<int> _syntheticWavBytes({
  required int sampleCount,
  required int sampleRate,
  required int channels,
}) {
  final payload = _syntheticPcmBytes(sampleCount);
  final header = List<int>.filled(44, 0);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header[offset + i] = value.codeUnitAt(i);
    }
  }

  void writeU16(int offset, int value) {
    header[offset] = value & 0xFF;
    header[offset + 1] = (value >> 8) & 0xFF;
  }

  void writeU32(int offset, int value) {
    header[offset] = value & 0xFF;
    header[offset + 1] = (value >> 8) & 0xFF;
    header[offset + 2] = (value >> 16) & 0xFF;
    header[offset + 3] = (value >> 24) & 0xFF;
  }

  final byteRate = sampleRate * channels * 2;
  writeAscii(0, 'RIFF');
  writeU32(4, 36 + payload.length);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  writeU32(16, 16);
  writeU16(20, 1); // PCM
  writeU16(22, channels);
  writeU32(24, sampleRate);
  writeU32(28, byteRate);
  writeU16(32, channels * 2);
  writeU16(34, 16);
  writeAscii(36, 'data');
  writeU32(40, payload.length);

  return [...header, ...payload];
}
