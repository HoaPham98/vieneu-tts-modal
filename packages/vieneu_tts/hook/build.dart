import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const String packageVersion = '0.1.0';
const String defaultRepo = 'HoaPham98/vieneu-tts-modal';

void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final packageName = input.packageName;
    final packageRoot = input.packageRoot.toFilePath();

    if (!input.config.buildCodeAssets) {
      return;
    }

    // 1. Resolve Target OS and Architecture
    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    final targetId = _resolveTargetId(targetOS, targetArch);
    if (targetId == null) {
      stderr.writeln(
        'Warning: Target OS $targetOS with architecture $targetArch is not currently supported with prebuilt binaries.',
      );
      return;
    }

    // 2. Check for Local Development Override (VIENEU_TTS_LOCAL_LIB)
    final localOverride = Platform.environment['VIENEU_TTS_LOCAL_LIB'];
    if (localOverride != null) {
      final overridePath = File(localOverride);
      if (overridePath.existsSync()) {
        stdout.writeln('Using local binary override from: $localOverride');
        _registerCodeAssets(
          output: output,
          packageName: packageName,
          binaryFile: overridePath,
          targetOS: targetOS,
        );
        return;
      }
    }

    // 3. Resolve Cache Directory in .dart_tool
    final cacheDir = Directory(
      p.join(packageRoot, '.dart_tool', 'vieneu_tts', 'cache', 'v$packageVersion', targetId),
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final binaryName = _getBinaryName(targetOS);
    final binaryFile = File(p.join(cacheDir.path, binaryName));
    File? extraAndroidLib;
    if (targetOS == OS.android) {
      extraAndroidLib = File(p.join(cacheDir.path, 'libc++_shared.so'));
    }

    // 4. Download and Extract Prebuilt Archive if not cached
    final needsDownload = !await binaryFile.exists() ||
        (extraAndroidLib != null && !await extraAndroidLib.exists());

    if (needsDownload) {
      stdout.writeln('Prebuilt binary missing in cache. Downloading for $targetId...');
      await _downloadAndExtract(
        targetId: targetId,
        cacheDir: cacheDir,
      );
    }

    if (!await binaryFile.exists()) {
      throw StateError(
        'Failed to find or download prebuilt binary $binaryName for $targetId at ${binaryFile.path}',
      );
    }

    // 5. Register CodeAsset
    _registerCodeAssets(
      output: output,
      packageName: packageName,
      binaryFile: binaryFile,
      targetOS: targetOS,
      extraLib: extraAndroidLib != null && await extraAndroidLib.exists() ? extraAndroidLib : null,
    );
  });
}

String? _resolveTargetId(OS targetOS, Architecture targetArch) {
  if (targetOS == OS.linux && targetArch == Architecture.x64) {
    return 'linux-x64';
  }
  if (targetOS == OS.android) {
    if (targetArch == Architecture.arm64) {
      return 'android-arm64';
    } else if (targetArch == Architecture.x64) {
      return 'android-x64';
    }
  }
  if (targetOS == OS.iOS) {
    return 'ios-arm64';
  }
  return null;
}

String _getBinaryName(OS targetOS) {
  if (targetOS == OS.linux || targetOS == OS.android) {
    return 'librust_lib_vieneu_tts.so';
  } else if (targetOS == OS.iOS || targetOS == OS.macOS) {
    return 'librust_lib_vieneu_tts.dylib';
  } else if (targetOS == OS.windows) {
    return 'rust_lib_vieneu_tts.dll';
  }
  return 'librust_lib_vieneu_tts.so';
}

void _registerCodeAssets({
  required BuildOutputBuilder output,
  required String packageName,
  required File binaryFile,
  required OS targetOS,
  File? extraLib,
}) {
  final binaryUri = binaryFile.uri;

  // Primary FFI asset matching FRB crate name: package:vieneu_tts/rust_lib_vieneu_tts
  output.assets.code.add(
    CodeAsset(
      package: packageName,
      name: 'rust_lib_vieneu_tts',
      linkMode: DynamicLoadingBundled(),
      os: targetOS,
      file: binaryUri,
    ),
  );

  // Register Android runtime dependencies (libc++_shared.so)
  if (extraLib != null) {
    output.assets.code.add(
      CodeAsset(
        package: packageName,
        name: 'libc++_shared.so',
        linkMode: DynamicLoadingBundled(),
        os: targetOS,
        file: extraLib.uri,
      ),
    );
  }
}

Future<void> _downloadAndExtract({
  required String targetId,
  required Directory cacheDir,
}) async {
  final archiveFileName = 'vieneu_tts-$targetId-v$packageVersion.tar.gz';

  // Support custom base URL (e.g., CI mock HTTP server in PRs)
  final baseUrl = Platform.environment['VIENEU_TTS_BINARY_URL'] ??
      'https://github.com/$defaultRepo/releases/download/v$packageVersion';

  final downloadUrl = '$baseUrl/$archiveFileName';
  stdout.writeln('Fetching prebuilt archive from $downloadUrl');

  final client = http.Client();
  try {
    final response = await client.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download prebuilt binary archive for $targetId from $downloadUrl (HTTP ${response.statusCode})',
      );
    }

    final archiveBytes = response.bodyBytes;

    // Optional SHA-256 verification if checksum file exists or is fetched
    try {
      final shaResponse = await client.get(Uri.parse('$downloadUrl.sha256'));
      if (shaResponse.statusCode == 200) {
        final expectedSha = shaResponse.body.trim().split(RegExp(r'\s+')).first;
        final actualSha = sha256.convert(archiveBytes).toString();
        if (expectedSha != actualSha) {
          throw StateError(
            'Checksum mismatch for $archiveFileName! Expected $expectedSha, got $actualSha',
          );
        }
        stdout.writeln('✓ Checksum verified for $archiveFileName');
      }
    } catch (e) {
      stdout.writeln('Checksum verification notice: $e');
    }

    // Extract tar.gz into cacheDir
    final decompressed = GZipDecoder().decodeBytes(archiveBytes);
    final tarArchive = TarDecoder().decodeBytes(decompressed);

    for (final file in tarArchive) {
      final filename = file.name;
      if (file.isFile) {
        final outFile = File(p.join(cacheDir.path, p.basename(filename)));
        await outFile.writeAsBytes(file.content as List<int>);
        stdout.writeln('Extracted: ${outFile.path}');
      }
    }
  } finally {
    client.close();
  }
}
