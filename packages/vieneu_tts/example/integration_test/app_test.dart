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
        final downloadBtn = find.text('Tải Model & Dictionary (~248 MB)');
        if (downloadBtn.evaluate().isNotEmpty) {
          // Tap download button on device
          await tester.tap(downloadBtn);
          await tester.pump();

          // Wait for download & initialization to complete (up to 180s)
          var elapsedSeconds = 0;
          while (!VieneuTts.isInitialized && elapsedSeconds < 180) {
            await tester.pump(const Duration(seconds: 2));
            elapsedSeconds += 2;
          }
        } else {
          // If already downloaded or checking, wait for initialization
          var elapsedSeconds = 0;
          while (!VieneuTts.isInitialized && elapsedSeconds < 30) {
            await tester.pump(const Duration(seconds: 1));
            elapsedSeconds += 1;
          }
        }

        // Verify engine is initialized offline
        expect(VieneuTts.isInitialized, isTrue,
            reason: 'Engine must be initialized after model/dictionary download');
        await tester.pumpAndSettle();

        // 3. Test Synthesis to WAV Audio
        final wavBtn = find.text('Đọc (WAV)');
        expect(wavBtn, findsOneWidget);
        await tester.tap(wavBtn);
        await tester.pump();

        // Wait for synthesis to complete (up to 30s)
        var synthWait = 0;
        var hasCompletedWav = false;
        while (synthWait < 30) {
          await tester.pump(const Duration(seconds: 1));
          synthWait += 1;
          if (find.textContaining('Độ trễ').evaluate().isNotEmpty ||
              find.byIcon(Icons.play_arrow).evaluate().isNotEmpty) {
            hasCompletedWav = true;
            break;
          }
        }
        expect(hasCompletedWav, isTrue,
            reason: 'WAV synthesis should complete and display latency/player');

        // 4. Test Real-Time Audio Chunk Streaming
        final streamBtn = find.text('Stream thời gian thực');
        expect(streamBtn, findsOneWidget);
        await tester.tap(streamBtn);
        await tester.pump();

        // Wait for streaming to complete (up to 30s)
        var streamWait = 0;
        var hasStreamed = false;
        while (streamWait < 30) {
          await tester.pump(const Duration(seconds: 1));
          streamWait += 1;
          if (find.textContaining('Stream hoàn tất').evaluate().isNotEmpty ||
              find.textContaining('chunk').evaluate().isNotEmpty) {
            hasStreamed = true;
            break;
          }
        }
        expect(hasStreamed, isTrue,
            reason: 'Real-time audio chunk streaming should emit chunks and complete');
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
