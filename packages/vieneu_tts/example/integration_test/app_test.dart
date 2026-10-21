import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vieneu_tts/vieneu_tts.dart';
import 'package:vieneu_tts_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('VieNeu TTS Example App On-Device E2E Test', () {
    testWidgets(
      'Full lifecycle: UI render, Download resources, Init engine, Synthesize WAV, and Stream PCM',
      (WidgetTester tester) async {
        // 1. Launch Example Application
        await tester.pumpWidget(const VieneuTtsExampleApp());
        await tester.pumpAndSettle();

        // Verify Title and core components
        expect(find.text('VieNeu TTS (On-Device)'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(VieneuTts.availableVoices.length, equals(25));

        // 2. Resource Download & Engine Initialization
        final downloadBtn = find.textContaining('Tải Model');
        if (downloadBtn.evaluate().isNotEmpty) {
          // Tap download button on device
          await tester.tap(downloadBtn);
          await tester.pump();
        }

        // Wait for initialization to complete (up to 180s)
        var elapsedSeconds = 0;
        while (!VieneuTts.isInitialized && elapsedSeconds < 180) {
          await tester.pump(const Duration(seconds: 2));
          elapsedSeconds += 2;
          if (elapsedSeconds % 10 == 0) {
            final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).toList();
            debugPrint('[TEST] Elapsed: ${elapsedSeconds}s, UI texts: $texts');
          }
        }

        final currentUiTexts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).toList();
        debugPrint('[TEST] Final UI texts: $currentUiTexts');

        // Verify engine is initialized offline
        expect(VieneuTts.isInitialized, isTrue,
            reason: 'Engine must be initialized after model/dictionary download. UI state: $currentUiTexts');
        await tester.pumpAndSettle();

        // Enter a short test sentence for fast & reliable on-device synthesis
        final textField = find.byType(TextField);
        expect(textField, findsOneWidget);
        await tester.enterText(textField, 'Xin chào Việt Nam');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        // 3. Test Synthesis to WAV Audio
        final wavBtn = find.text('Đọc (WAV)');
        expect(wavBtn, findsOneWidget);
        await tester.ensureVisible(wavBtn);
        await tester.pumpAndSettle();
        await tester.tap(wavBtn);
        await tester.pump();

        // Wait for synthesis to complete (up to 180s)
        var synthWait = 0;
        var hasCompletedWav = false;
        while (synthWait < 180) {
          await tester.pump(const Duration(seconds: 2));
          synthWait += 2;
          if (find.textContaining('Thời gian sinh').evaluate().isNotEmpty ||
              find.byIcon(Icons.play_arrow).evaluate().isNotEmpty) {
            hasCompletedWav = true;
            break;
          }
          if (synthWait % 10 == 0) {
            final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).toList();
            debugPrint('[TEST-SYNTH] Waiting for WAV synthesis... Elapsed: ${synthWait}s, UI: $texts');
          }
        }
        expect(hasCompletedWav, isTrue,
            reason: 'WAV synthesis should complete and display latency/player');
        await tester.pumpAndSettle();

        // 4. Test Real-Time Audio Chunk Streaming
        final streamBtn = find.text('Stream thời gian thực');
        expect(streamBtn, findsOneWidget);
        await tester.ensureVisible(streamBtn);
        await tester.pumpAndSettle();
        await tester.tap(streamBtn);
        await tester.pump();

        // Wait for streaming to complete (up to 180s)
        var streamWait = 0;
        var hasStreamed = false;
        while (streamWait < 180) {
          await tester.pump(const Duration(seconds: 2));
          streamWait += 2;
          if (find.textContaining('Thời gian sinh').evaluate().isNotEmpty ||
              find.textContaining('Stream (').evaluate().isNotEmpty) {
            hasStreamed = true;
            break;
          }
          if (streamWait % 10 == 0) {
            final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).toList();
            debugPrint('[TEST-STREAM] Waiting for streaming... Elapsed: ${streamWait}s, UI: $texts');
          }
        }
        expect(hasStreamed, isTrue,
            reason: 'Real-time audio chunk streaming should emit chunks and complete');
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
