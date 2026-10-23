import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../hook/build.dart';

void main() {
  group('Build Hook Version Resolution', () {
    test('resolves version from current package pubspec.yaml', () {
      final packageRoot = Directory.current.path;
      final version = resolvePackageVersion(packageRoot);
      expect(version, equals('0.1.1'));
    });

    test('falls back to 0.1.0 when pubspec.yaml is missing or invalid', () {
      final tempDir = Directory.systemTemp.createTempSync('hook_version_test_');
      try {
        final version = resolvePackageVersion(tempDir.path);
        expect(version, equals('0.1.0'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extracts custom version from temporary pubspec.yaml', () {
      final tempDir = Directory.systemTemp.createTempSync('hook_custom_version_');
      try {
        final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
        pubspec.writeAsStringSync('name: test_pkg\nversion: 1.2.3+4\n');
        final version = resolvePackageVersion(tempDir.path);
        expect(version, equals('1.2.3'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Build Mode Detection (shouldBuildFromSource)', () {
    test('explicit VIENEU_TTS_BUILD_MODE=source forces source mode', () {
      final result = shouldBuildFromSource(
        packageRoot: '/some/random/pub-cache/path',
        environment: {'VIENEU_TTS_BUILD_MODE': 'source'},
        hasRustup: false,
      );
      expect(result, isTrue);
    });

    test('explicit VIENEU_TTS_BUILD_MODE=prebuilt forces prebuilt mode', () {
      final result = shouldBuildFromSource(
        packageRoot: Directory.current.path,
        environment: {'VIENEU_TTS_BUILD_MODE': 'prebuilt'},
        hasRustup: true,
      );
      expect(result, isFalse);
    });

    test('prebuilt override variables force prebuilt mode', () {
      expect(
        shouldBuildFromSource(
          packageRoot: Directory.current.path,
          environment: {'VIENEU_TTS_LOCAL_LIB': '/custom/lib.so'},
          hasRustup: true,
        ),
        isFalse,
      );
      expect(
        shouldBuildFromSource(
          packageRoot: Directory.current.path,
          environment: {'VIENEU_TTS_BINARY_URL': 'http://127.0.0.1:8080'},
          hasRustup: true,
        ),
        isFalse,
      );
      expect(
        shouldBuildFromSource(
          packageRoot: Directory.current.path,
          environment: {'VIENEU_TTS_LOCAL_ARCHIVE': '/dist/archive.tar.gz'},
          hasRustup: true,
        ),
        isFalse,
      );
    });

    test('returns false when packageRoot is inside .pub-cache or Pub/Cache', () {
      expect(
        shouldBuildFromSource(
          packageRoot: 'C:/Users/runner/.pub-cache/hosted/pub.dev/vieneu_tts-0.1.0',
          environment: {},
          hasRustup: true,
        ),
        isFalse,
      );
      expect(
        shouldBuildFromSource(
          packageRoot: r'C:\Users\runner\AppData\Local\Pub\Cache\git\vieneu_tts',
          environment: {},
          hasRustup: true,
        ),
        isFalse,
      );
    });

    test('returns false when rust/Cargo.toml is missing in packageRoot', () {
      final tempDir = Directory.systemTemp.createTempSync('hook_no_rust_');
      try {
        final result = shouldBuildFromSource(
          packageRoot: tempDir.path,
          environment: {},
          hasRustup: true,
        );
        expect(result, isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns false when rustup is unavailable', () {
      final result = shouldBuildFromSource(
        packageRoot: Directory.current.path,
        environment: {},
        hasRustup: false,
      );
      expect(result, isFalse);
    });

    test('returns true in local repository with Cargo.toml and rustup', () {
      final result = shouldBuildFromSource(
        packageRoot: Directory.current.path,
        environment: {},
        hasRustup: true,
      );
      expect(result, isTrue);
    });

    test('reads overrides from .dart_tool/vieneu_tts_env when environment is not passed', () {
      final tempDir = Directory.systemTemp.createTempSync('hook_env_file_');
      try {
        final dartTool = Directory(p.join(tempDir.path, '.dart_tool'))
          ..createSync(recursive: true);
        File(p.join(dartTool.path, 'vieneu_tts_env'))
            .writeAsStringSync('VIENEU_TTS_BUILD_MODE=source\n');
        final env = resolveHookEnvironment(packageRoot: tempDir.path);
        expect(env['VIENEU_TTS_BUILD_MODE'], equals('source'));
        expect(
          shouldBuildFromSource(packageRoot: tempDir.path, hasRustup: false),
          isTrue,
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
