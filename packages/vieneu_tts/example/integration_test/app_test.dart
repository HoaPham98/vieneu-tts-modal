import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vieneu_tts/vieneu_tts.dart';
import 'package:vieneu_tts_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('VieNeu TTS Example App Integration Test', () {
    testWidgets('App launches, renders UI, and displays voice catalogue',
        (WidgetTester tester) async {
      await tester.pumpWidget(const VieneuTtsExampleApp());
      await tester.pumpAndSettle();

      // Verify Title
      expect(find.text('VieNeu TTS (On-Device)'), findsOneWidget);

      // Verify Status Card renders
      expect(find.byType(Card), findsAtLeastNWidgets(2));

      // Verify Available Voices catalogue contains 25 presets
      expect(VieneuTts.availableVoices.length, equals(25));
      expect(
        VieneuTts.availableVoices.any((v) => v.id == 'minh_quan_pro'),
        isTrue,
      );
      expect(
        VieneuTts.availableVoices.any((v) => v.id == 'ngoc_huyen'),
        isTrue,
      );

      // Verify Text Field exists with default Vietnamese text
      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('VieNeu TTS'), findsAtLeastNWidgets(1));

      // Verify Synthesis buttons exist
      expect(find.text('Đọc (WAV)'), findsOneWidget);
      expect(find.text('Stream thời gian thực'), findsOneWidget);
    });

    testWidgets('Offline synthesis lifecycle test', (WidgetTester tester) async {
      await tester.pumpWidget(const VieneuTtsExampleApp());
      await tester.pumpAndSettle();

      // If test environment has cached models, verify initialization
      final modelEnv = Platform.environment['MODEL_PATH'];
      final dictEnv = Platform.environment['DICT_PATH'];

      if (modelEnv != null && File(modelEnv).existsSync()) {
        await VieneuTts.init(
          modelPath: modelEnv,
          dictPath: dictEnv,
        );
        expect(VieneuTts.isInitialized, isTrue);

        // Synthesize sample phrase
        final audioBytes = await VieneuTts.synthesize(
          text: 'Xin chào',
          voice: 'minh_quan_pro',
        );
        expect(audioBytes.isNotEmpty, isTrue);
        expect(audioBytes.length, greaterThan(44)); // Valid WAV header
      }
    });
  });
}
