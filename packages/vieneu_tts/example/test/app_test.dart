import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vieneu_tts/vieneu_tts.dart';
import 'package:vieneu_tts_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '/tmp/vieneu_test_docs',
    );
  });

  test('bridge codegen version matches expected version 2.0.0', () {
    expect(
      VieneuTts.bridgeCodegenVersion,
      equals('2.0.0'),
      reason: 'FRB codegen version must match 2.0.0',
    );
  });

  testWidgets('VieNeu TTS Example App widget test', (WidgetTester tester) async {
    await tester.pumpWidget(const VieneuTtsExampleApp());
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('VieNeu TTS (On-Device)'), findsOneWidget);

    // Verify Available Voices catalogue contains 25 presets
    expect(VieneuTts.availableVoices.length, equals(25));
    expect(
      VieneuTts.availableVoices.any((v) => v.id == 'minh_quan_pro'),
      isTrue,
    );

    // Verify UI components
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Đọc (WAV)'), findsOneWidget);
    expect(find.text('Stream thời gian thực'), findsOneWidget);
  });
}
