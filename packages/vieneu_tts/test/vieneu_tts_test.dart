import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
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

    test('bridge codegen version matches flutter_rust_bridge runtime version', () {
      expect(
        VieneuTts.bridgeCodegenVersion,
        equals(kFrbVersion),
        reason:
            'FRB codegen version must match runtime package version exactly to prevent runtime StateError',
      );
    });
  });
}
