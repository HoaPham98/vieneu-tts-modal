import 'package:test/test.dart';
import 'package:vieneu_tts/vieneu_tts.dart';

void main() {
  group('VieneuTts Voices Catalog Tests', () {
    test('contains 25 default voice presets', () {
      final voices = VieneuTts.availableVoices;
      expect(voices.length, equals(25));
    });

    test('default voice is minh_quan_pro', () {
      final voices = VieneuTts.availableVoices;
      expect(voices.any((v) => v.id == 'minh_quan_pro'), isTrue);
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
}
