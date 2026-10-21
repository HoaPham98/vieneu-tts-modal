import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vieneu_tts/flutter_vieneu_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VieneuTtsFlutter API Tests', () {
    test('exports VieneuTts voices and presets', () {
      expect(VieneuTts.availableVoices.length, equals(25));
    });

    test('initial status message and progress are defined', () {
      expect(VieneuTtsFlutter.downloadProgress.value, equals(0.0));
      expect(VieneuTtsFlutter.statusMessage.value, equals('Chưa khởi tạo'));
    });
  });
}
