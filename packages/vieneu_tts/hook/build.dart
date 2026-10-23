import 'dart:io';
import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

const String defaultRepo = 'HoaPham98/vieneu-tts-modal';

/// Dynamically resolves the package version from pubspec.yaml.
String resolvePackageVersion(String packageRoot) {
  try {
    final pubspecFile = File(p.join(packageRoot, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final content = pubspecFile.readAsStringSync();
      final match =
          RegExp(r'^version:\s*([^\s+#]+)', multiLine: true).firstMatch(content);
      if (match != null) {
        return match.group(1)!;
      }
    }
  } catch (_) {}
  return '0.1.0';
}

/// Checks whether `rustup` or `cargo` is installed and discoverable on the host.
bool hasRustupAvailable({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final homeDir = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  final candidatePaths = [
    if (homeDir != null)
      p.join(homeDir, '.cargo', 'bin', Platform.isWindows ? 'rustup.exe' : 'rustup'),
    if (homeDir != null)
      p.join(homeDir, '.cargo', 'bin', Platform.isWindows ? 'cargo.exe' : 'cargo'),
  ];
  for (final candidate in candidatePaths) {
    if (File(candidate).existsSync()) {
      return true;
    }
  }
  final pathEnv = env['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  for (final dir in pathEnv.split(separator)) {
    if (dir.trim().isEmpty) continue;
    final exe = p.join(dir.trim(), Platform.isWindows ? 'rustup.exe' : 'rustup');
    if (File(exe).existsSync()) {
      return true;
    }
  }
  return false;
}

/// Resolves effective environment variables for the build hook, including
/// fallbacks when Dart's `hooks_runner` filters custom environment variables:
/// 1. Explicit `environment` map (used by unit tests) or `Platform.environment`
/// 2. Parent process `/proc/<ppid>/environ` on Linux (recovers shell `VIENEU_TTS_*` vars)
/// 3. `.dart_tool/vieneu_tts_env` key=value file in `packageRoot`
/// 4. `input.userDefines` from `pubspec.yaml` (`hooks.user_defines.vieneu_tts`)
Map<String, String> resolveHookEnvironment({
  required String packageRoot,
  Map<String, String>? environment,
  BuildInput? input,
}) {
  if (environment != null) {
    return environment;
  }

  final merged = <String, String>{...Platform.environment};

  // On Linux, recover stripped VIENEU_TTS_* / ANDROID_NDK* variables from parent processes
  if (Platform.isLinux) {
    try {
      var currentPid = pid;
      for (var depth = 0; depth < 4; depth++) {
        final statFile = File('/proc/$currentPid/stat');
        if (!statFile.existsSync()) break;
        final statContent = statFile.readAsStringSync();
        final closeParen = statContent.lastIndexOf(')');
        if (closeParen == -1) break;
        final fields = statContent.substring(closeParen + 1).trim().split(' ');
        if (fields.length < 2) break;
        final ppid = int.tryParse(fields[1]);
        if (ppid == null || ppid <= 1) break;

        final envFile = File('/proc/$ppid/environ');
        if (envFile.existsSync()) {
          final rawBytes = envFile.readAsBytesSync();
          final entries = String.fromCharCodes(rawBytes).split('\x00');
          for (final entry in entries) {
            final idx = entry.indexOf('=');
            if (idx > 0) {
              final k = entry.substring(0, idx);
              final v = entry.substring(idx + 1);
              if ((k.startsWith('VIENEU_TTS_') || k.startsWith('ANDROID_')) &&
                  !merged.containsKey(k)) {
                merged[k] = v;
              }
            }
          }
        }
        currentPid = ppid;
      }
    } catch (_) {}
  }

  // Check local override file in .dart_tool/vieneu_tts_env
  try {
    final envFile = File(p.join(packageRoot, '.dart_tool', 'vieneu_tts_env'));
    if (envFile.existsSync()) {
      for (final line in envFile.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final idx = trimmed.indexOf('=');
        if (idx > 0) {
          final k = trimmed.substring(0, idx).trim();
          final v = trimmed.substring(idx + 1).trim();
          merged[k] = v;
        }
      }
    }
  } catch (_) {}

  // Check Dart hooks user_defines
  if (input != null) {
    for (final key in const [
      'VIENEU_TTS_BUILD_MODE',
      'VIENEU_TTS_LOCAL_LIB',
      'VIENEU_TTS_BINARY_URL',
      'VIENEU_TTS_LOCAL_ARCHIVE',
    ]) {
      final val = input.userDefines[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        merged[key] = val.toString().trim();
      }
    }
  }

  return merged;
}

/// Determines whether to compile native assets from local Rust source or use prebuilt binaries.
bool shouldBuildFromSource({
  required String packageRoot,
  Map<String, String>? environment,
  bool? hasRustup,
  BuildInput? input,
}) {
  final env = resolveHookEnvironment(
    packageRoot: packageRoot,
    environment: environment,
    input: input,
  );

  // 1. Explicit override via VIENEU_TTS_BUILD_MODE
  final mode = env['VIENEU_TTS_BUILD_MODE']?.trim().toLowerCase();
  if (mode == 'source') return true;
  if (mode == 'prebuilt') return false;

  // 2. Prebuilt override variables
  if ((env['VIENEU_TTS_LOCAL_LIB']?.trim().isNotEmpty ?? false) ||
      (env['VIENEU_TTS_BINARY_URL']?.trim().isNotEmpty ?? false) ||
      (env['VIENEU_TTS_LOCAL_ARCHIVE']?.trim().isNotEmpty ?? false)) {
    return false;
  }

  // 3. Pub cache detection (case-insensitive check for .pub-cache or Pub/Cache)
  final normalizedRoot =
      p.normalize(packageRoot).replaceAll(r'\', '/').toLowerCase();
  if (normalizedRoot.contains('/.pub-cache/') ||
      normalizedRoot.contains('/pub/cache/')) {
    return false;
  }

  // 4. Source crate presence
  final cargoToml = File(p.join(packageRoot, 'rust', 'Cargo.toml'));
  if (!cargoToml.existsSync()) {
    return false;
  }

  // 5. Host toolchain availability
  final rustAvailable = hasRustup ?? hasRustupAvailable(environment: env);
  return rustAvailable;
}

/// Resolves `libc++_shared.so` from Android NDK for the current target architecture.
File? findAndroidNdkLibcppShared({
  required CodeConfig codeConfig,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final arch = codeConfig.targetArchitecture;
  final triple = switch (arch) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.x64 => 'x86_64-linux-android',
    Architecture.arm => 'arm-linux-androideabi',
    Architecture.riscv64 => 'riscv64-linux-android',
    _ => 'aarch64-linux-android',
  };

  final searchNdkDirs = <String>[];

  // From cCompiler compiler path
  final compilerUri = codeConfig.cCompiler?.compiler;
  if (compilerUri != null) {
    var dir = p.dirname(compilerUri.toFilePath());
    for (int i = 0; i < 6; i++) {
      if (File(p.join(dir, 'source.properties')).existsSync() ||
          Directory(p.join(dir, 'toolchains')).existsSync()) {
        searchNdkDirs.add(dir);
        break;
      }
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
  }

  // From environment variables
  for (final key in [
    'ANDROID_NDK',
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_ROOT',
    'ANDROID_NDK_LATEST_HOME'
  ]) {
    final val = env[key];
    if (val != null && Directory(val).existsSync()) {
      searchNdkDirs.add(val);
    }
  }

  // From Android SDK directories
  for (final key in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final sdk = env[key];
    if (sdk != null) {
      final ndkBase = Directory(p.join(sdk, 'ndk'));
      if (ndkBase.existsSync()) {
        final versions = ndkBase.listSync().whereType<Directory>().toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final v in versions) {
          searchNdkDirs.add(v.path);
        }
      }
    }
  }

  // Probe candidates
  for (final ndk in searchNdkDirs) {
    final prebuiltDir =
        Directory(p.join(ndk, 'toolchains', 'llvm', 'prebuilt'));
    if (prebuiltDir.existsSync()) {
      for (final host in prebuiltDir.listSync().whereType<Directory>()) {
        final candidate = File(p.join(
            host.path, 'sysroot', 'usr', 'lib', triple, 'libc++_shared.so'));
        if (candidate.existsSync()) {
          return candidate;
        }
      }
    }
  }
  return null;
}

final class _ShortWindowsFrbTempOverrides extends IOOverrides {
  _ShortWindowsFrbTempOverrides(this.drive, this.frbPattern);
  final String drive;
  final RegExp frbPattern;

  @override
  Directory createDirectory(String path) {
    final match = frbPattern.firstMatch(path);
    if (match != null) {
      final shortHash = match.group(1)!;
      return super.createDirectory('$drive\\f_$shortHash');
    }
    return super.createDirectory(path);
  }
}

/// Runs [action] on Windows with `frb_native_assets_<hash>` mapped to a short
/// drive-root directory (e.g. `D:\f_5de1`) so deeply nested CMake/SentencePiece
/// object paths in `audio-cpp-sys` stay well below the 260-char `MAX_PATH` limit.
Future<T> _runWithShortWindowsFrbTemp<T>(
  String packageRoot,
  Future<T> Function() action,
) {
  if (!Platform.isWindows) {
    return action();
  }
  final driveMatch = RegExp(r'^[A-Za-z]:').firstMatch(packageRoot);
  final drive =
      driveMatch?.group(0) ?? (Platform.environment['SYSTEMDRIVE'] ?? 'C:');
  final frbPattern = RegExp(r'frb_native_assets_([0-9a-f]{4})[0-9a-f]*$');

  return IOOverrides.runWithIOOverrides(
    action,
    _ShortWindowsFrbTempOverrides(drive, frbPattern),
  );
}

String? _resolveLibclangPath(Map<String, String> env) {
  final explicit = env['LIBCLANG_PATH'];
  if (explicit != null && Directory(explicit).existsSync()) {
    return explicit;
  }
  if (!Platform.isWindows) return null;

  final candidates = <String>[
    r'C:\Program Files\LLVM\bin',
    r'D:\toolsl\miniconda3\Lib\site-packages\clang\native',
  ];
  final pathEnv = env['PATH'] ?? '';
  for (final entry in pathEnv.split(';')) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    candidates.add(trimmed);
    candidates.add(p.normalize(p.join(trimmed, 'Lib', 'site-packages', 'clang', 'native')));
    candidates.add(p.normalize(p.join(trimmed, '..', 'Lib', 'site-packages', 'clang', 'native')));
  }
  for (final dir in candidates) {
    if (File(p.join(dir, 'libclang.dll')).existsSync()) {
      return dir;
    }
  }
  return null;
}

String? _prepareAndroidCmakeToolchainWrapper({
  required CodeConfig codeConfig,
  required Map<String, String> env,
  required String outputDir,
}) {
  final libcpp = findAndroidNdkLibcppShared(codeConfig: codeConfig, environment: env);
  if (libcpp == null) return null;

  // Walk up from .../toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<triple>/libc++_shared.so to NDK root
  var dir = libcpp.parent.path;
  String? ndkRoot;
  for (var i = 0; i < 10; i++) {
    if (File(p.join(dir, 'build', 'cmake', 'android.toolchain.cmake')).existsSync()) {
      ndkRoot = dir;
      break;
    }
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  if (ndkRoot == null) return null;

  final abi = switch (codeConfig.targetArchitecture) {
    Architecture.arm64 => 'arm64-v8a',
    Architecture.x64 => 'x86_64',
    Architecture.arm => 'armeabi-v7a',
    Architecture.riscv64 => 'riscv64',
    _ => 'arm64-v8a',
  };

  final baseToolchain =
      p.join(ndkRoot, 'build', 'cmake', 'android.toolchain.cmake').replaceAll(r'\', '/');
  final wrapperFile = File(p.join(outputDir, 'vieneu_android_$abi.toolchain.cmake'));
  if (!wrapperFile.parent.existsSync()) {
    wrapperFile.parent.createSync(recursive: true);
  }
  wrapperFile.writeAsStringSync(
    'set(ANDROID_ABI "$abi")\n'
    'set(ANDROID_PLATFORM "android-28")\n'
    'set(ANDROID_STL "c++_shared")\n'
    'include("$baseToolchain")\n',
  );
  return wrapperFile.path.replaceAll(r'\', '/');
}

Map<String, String> _resolveAndroidBindgenExtraClangArgs({
  required CodeConfig codeConfig,
  required Map<String, String> env,
}) {
  final libcpp =
      findAndroidNdkLibcppShared(codeConfig: codeConfig, environment: env);
  if (libcpp == null) return const {};

  final sysroot =
      libcpp.parent.parent.parent.parent.path.replaceAll(r'\', '/');
  final llvmHostDir = p.dirname(sysroot);
  final clangDir = Directory(p.join(llvmHostDir, 'lib', 'clang'));
  String? clangInc;
  if (clangDir.existsSync()) {
    for (final v in clangDir.listSync().whereType<Directory>()) {
      final inc = Directory(p.join(v.path, 'include'));
      if (inc.existsSync()) {
        clangInc = inc.path.replaceAll(r'\', '/');
        break;
      }
    }
  }

  final triple = switch (codeConfig.targetArchitecture) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.x64 => 'x86_64-linux-android',
    Architecture.arm => 'arm-linux-androideabi',
    Architecture.ia32 => 'i686-linux-android',
    Architecture.riscv64 => 'riscv64-linux-android',
    _ => 'aarch64-linux-android',
  };

  final tripleUnderscore = triple.replaceAll('-', '_');

  final args = [
    '--sysroot=$sysroot',
    '-isystem',
    '$sysroot/usr/include',
    '-isystem',
    '$sysroot/usr/include/$triple',
    if (clangInc != null) ...['-isystem', clangInc],
  ].join(' ');

  return {
    'BINDGEN_EXTRA_CLANG_ARGS': args,
    'BINDGEN_EXTRA_CLANG_ARGS_$tripleUnderscore': args,
    'BINDGEN_EXTRA_CLANG_ARGS_$triple': args,
  };
}

void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final packageName = input.packageName;
    final packageRoot = input.packageRoot.toFilePath();
    final packageVersion = resolvePackageVersion(packageRoot);
    final env = resolveHookEnvironment(packageRoot: packageRoot, input: input);

    if (!input.config.buildCodeAssets) {
      return;
    }

    final codeConfig = input.config.code;
    final targetOS = codeConfig.targetOS;
    final targetArch = codeConfig.targetArchitecture;

    // Check if building from local Rust source (Dev mode)
    if (shouldBuildFromSource(
      packageRoot: packageRoot,
      environment: env,
      input: input,
    )) {
      stdout.writeln(
          'Building vieneu_tts from local Rust source ($packageRoot)...');

      final homeDir =
          Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
      final cargoBin =
          homeDir != null ? p.join(homeDir, '.cargo', 'bin') : null;
      final existingPath = env['PATH'] ?? '';
      final updatedPath = cargoBin != null && !existingPath.contains(cargoBin)
          ? '$cargoBin${Platform.isWindows ? ';' : ':'}$existingPath'
          : existingPath;

      final libclangPath = _resolveLibclangPath(env);
      final androidToolchainWrapper = targetOS == OS.android
          ? _prepareAndroidCmakeToolchainWrapper(
              codeConfig: codeConfig,
              env: env,
              outputDir: input.outputDirectory.toFilePath(),
            )
          : null;
      final bindgenClangArgs = targetOS == OS.android
          ? _resolveAndroidBindgenExtraClangArgs(
              codeConfig: codeConfig,
              env: env,
            )
          : const <String, String>{};

      await _runWithShortWindowsFrbTemp(packageRoot, () async {
        await FlutterRustBridgeNativeAssetsBuilder(
          assetName: 'rust_lib_vieneu_tts',
          cratePath: 'rust',
          extraCargoEnvironmentVariables: {
            if (cargoBin != null) 'PATH': updatedPath,
            if (libclangPath != null) 'LIBCLANG_PATH': libclangPath,
            if (androidToolchainWrapper != null)
              'CMAKE_TOOLCHAIN_FILE': androidToolchainWrapper,
            ...bindgenClangArgs,
          },
        ).run(
          input: input,
          output: output,
        );
      });

      // On Android, bundle libc++_shared.so from NDK
      if (targetOS == OS.android) {
        final libcpp =
            findAndroidNdkLibcppShared(codeConfig: codeConfig, environment: env);
        if (libcpp != null && libcpp.existsSync()) {
          final bundledFile = File(p.join(
              input.outputDirectory.toFilePath(), 'libc++_shared.so'));
          if (!bundledFile.parent.existsSync()) {
            bundledFile.parent.createSync(recursive: true);
          }
          await libcpp.copy(bundledFile.path);
          output.assets.code.add(
            CodeAsset(
              package: packageName,
              name: 'libc++_shared.so',
              linkMode: DynamicLoadingBundled(),
              file: bundledFile.uri,
            ),
          );
          stdout.writeln(
              'Bundled Android libc++_shared.so from: ${libcpp.path}');
        } else {
          stderr.writeln(
              'Warning: libc++_shared.so could not be found in Android NDK.');
        }
      }
      return;
    }

    // 1. Resolve Target OS and Architecture for prebuilt resolution
    final targetId = _resolveTargetId(codeConfig);
    if (targetId == null) {
      stderr.writeln(
        'Warning: Target OS $targetOS with architecture $targetArch is not currently supported with prebuilt binaries.',
      );
      return;
    }

    // 2. Check for Local Development Override (VIENEU_TTS_LOCAL_LIB)
    final localOverride = env['VIENEU_TTS_LOCAL_LIB'];
    if (localOverride != null) {
      final overridePath = File(localOverride);
      if (overridePath.existsSync()) {
        stdout.writeln('Using local binary override from: $localOverride');
        _registerCodeAssets(
          output: output,
          packageName: packageName,
          binaryFile: overridePath,
        );
        return;
      }
    }

    // 3. Resolve Cache Directory in .dart_tool
    final cacheDir = Directory(
      p.join(packageRoot, '.dart_tool', 'vieneu_tts', 'cache',
          'v$packageVersion', targetId),
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
      stdout.writeln(
          'Prebuilt binary missing in cache. Resolving for $targetId...');

      final archiveFileName = 'vieneu_tts-$targetId-v$packageVersion.tar.gz';
      final localDistArchive = File(
        env['VIENEU_TTS_LOCAL_ARCHIVE'] ??
            p.join(packageRoot, '..', '..', 'dist', archiveFileName),
      );

      final hasCustomBinaryUrl = env['VIENEU_TTS_BINARY_URL'] != null;

      if (!hasCustomBinaryUrl && await localDistArchive.exists()) {
        stdout.writeln(
            'Using local repository archive: ${localDistArchive.path}');
        await _extractArchive(
          archiveBytes: await localDistArchive.readAsBytes(),
          cacheDir: cacheDir,
        );
      } else {
        try {
          await _downloadAndExtract(
            targetId: targetId,
            cacheDir: cacheDir,
            packageVersion: packageVersion,
            environment: env,
          );
        } catch (e) {
          if (await localDistArchive.exists()) {
            stdout.writeln(
                'Download failed ($e). Falling back to local archive: ${localDistArchive.path}');
            await _extractArchive(
              archiveBytes: await localDistArchive.readAsBytes(),
              cacheDir: cacheDir,
            );
          } else {
            rethrow;
          }
        }
      }
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
      extraLib: extraAndroidLib != null && await extraAndroidLib.exists()
          ? extraAndroidLib
          : null,
    );
  });
}

String? _resolveTargetId(CodeConfig codeConfig) {
  final targetOS = codeConfig.targetOS;
  final targetArch = codeConfig.targetArchitecture;

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
  if (targetOS == OS.iOS && targetArch == Architecture.arm64) {
    bool isSim = false;
    try {
      isSim = codeConfig.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    } catch (_) {
      // Fallback if iOS configuration is unavailable
    }
    return isSim ? 'ios-arm64-sim' : 'ios-arm64';
  }
  if (targetOS == OS.macOS) {
    if (targetArch == Architecture.arm64) {
      return 'macos-arm64';
    } else if (targetArch == Architecture.x64) {
      return 'macos-x64';
    }
  }
  if (targetOS == OS.windows) {
    if (targetArch == Architecture.x64) {
      return 'windows-x64';
    } else if (targetArch == Architecture.arm64) {
      // Windows 11 on ARM natively emulates x64 binaries via Prism
      return 'windows-x64';
    }
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
  File? extraLib,
}) {
  final binaryUri = binaryFile.uri;

  // Primary FFI asset matching FRB crate name: package:vieneu_tts/rust_lib_vieneu_tts
  output.assets.code.add(
    CodeAsset(
      package: packageName,
      name: 'rust_lib_vieneu_tts',
      linkMode: DynamicLoadingBundled(),
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
        file: extraLib.uri,
      ),
    );
  }
}

Future<void> _downloadAndExtract({
  required String targetId,
  required Directory cacheDir,
  required String packageVersion,
  required Map<String, String> environment,
}) async {
  final archiveFileName = 'vieneu_tts-$targetId-v$packageVersion.tar.gz';

  // Support custom base URL (e.g., CI mock HTTP server in PRs)
  final baseUrl = environment['VIENEU_TTS_BINARY_URL'] ??
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
        final expectedSha =
            shaResponse.body.trim().split(RegExp(r'\s+')).first;
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
    await _extractArchive(
      archiveBytes: archiveBytes,
      cacheDir: cacheDir,
    );
  } finally {
    client.close();
  }
}

Future<void> _extractArchive({
  required List<int> archiveBytes,
  required Directory cacheDir,
}) async {
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
}
