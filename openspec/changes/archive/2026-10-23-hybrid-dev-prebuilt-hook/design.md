# Design

## Context

See `proposal.md` for motivation and scope. Currently:
- `packages/vieneu_tts/hook/build.dart` imports `package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart` (`2.13.0`), but only implements the prebuilt download path with a hardcoded `const String packageVersion = '0.1.0'`.
- `packages/vieneu_tts/pubspec.yaml` depends on `flutter_rust_bridge: 2.13.0` and `flutter_rust_bridge_hooks: 2.13.0`, whereas `packages/vieneu_tts/rust/Cargo.toml` and `packages/flutter_vieneu_tts/example/pubspec.yaml` still pin `flutter_rust_bridge` `2.0.0`, and CI workflows download `flutter_rust_bridge_codegen` `v2.0.0`.
- `packages/vieneu_tts/rust/rust-toolchain.toml` pins `channel = "1.93.1"`, while `packages/flutter_vieneu_tts/example/android/` was previously hand-crafted with legacy Groovy Gradle files (AGP 8.3.2, Gradle 8.14.6, hardcoded `jniLibs`/`abiFilters`) and lacked Windows desktop scaffolding.

## Goals / Non-Goals

**Goals:**
- Seamless zero-config local development: running `flutter run` or `dart test` inside the repository automatically builds the local Rust crate via `FlutterRustBridgeNativeAssetsBuilder`.
- Seamless zero-Rust consumer experience: installing `vieneu_tts` via Pub cache (`pub.dev` or `git:` dependency) or running in a toolchain-purged CI environment automatically downloads the matching prebuilt release archive.
- Single source of truth for versioning: `hook/build.dart` reads `version` from `pubspec.yaml`, and CI enforces parity across `pubspec.yaml`, `Cargo.toml`, and the Git release tag.
- Automated CI coverage for both `source` and `prebuilt` modes.
- Official Flutter SDK template structure for `packages/flutter_vieneu_tts/example` targeting both `android` and `windows`.

**Non-Goals:**
- Changing the Rust TTS engine API or model inference pipeline.
- Supporting Android NDK versions older than r27 in local `source` mode (since `native_toolchain_rust` requires NDK >= 27 for API 35 clang wrappers).

## Decisions

### 1. Build Mode Detection Hierarchy (`_shouldBuildFromSource`)
In `packages/vieneu_tts/hook/build.dart`, mode selection follows a deterministic 4-step precedence:
1. **Explicit `VIENEU_TTS_BUILD_MODE` environment variable**:
   - `source` -> returns `true` (build from local Rust source).
   - `prebuilt` -> returns `false` (use prebuilt resolution).
2. **Prebuilt Override Environment Variables**:
   - If `VIENEU_TTS_LOCAL_LIB`, `VIENEU_TTS_BINARY_URL`, or `VIENEU_TTS_LOCAL_ARCHIVE` is set and non-empty -> returns `false` (so CI mock servers and local binary overrides always test the prebuilt path unless `VIENEU_TTS_BUILD_MODE=source` is explicitly set).
3. **Package Location & Source Presence**:
   - Normalize `packageRoot` separators and check if it resides in a Pub cache directory (contains `/.pub-cache/` or `/Pub/Cache/`, case-insensitive). If inside Pub cache -> returns `false` (even if the consumer machine happens to have Rust installed).
   - Check if `File(p.join(packageRoot, 'rust', 'Cargo.toml')).existsSync()` is true. If false -> returns `false`.
4. **Host Toolchain Availability**:
   - Check if `rustup` (`rustup` on `PATH` or `~/.cargo/bin/rustup[.exe]`) is available on the host machine. If available -> returns `true`; otherwise returns `false`.

*Alternatives considered*:
- *Checking only `rust/Cargo.toml` existence*: Rejected because `git:` dependencies in `.pub-cache/git/...` still contain `rust/Cargo.toml`, which would force end-users using git dependencies to compile Rust/C++ from source.
- *Checking only `.pub-cache`*: Rejected because `.github/workflows/example-app-android.yml` tests consumer mode inside a repo checkout after purging Rust/NDK. Combining `.pub-cache` detection, override env vars, and `rustup` presence handles all local, consumer, and CI environments cleanly.

### 2. Source Mode Execution via `FlutterRustBridgeNativeAssetsBuilder` + Android `libc++_shared.so`
When `_shouldBuildFromSource` is `true`:
- Ensure `~/.cargo/bin` (or `%USERPROFILE%\.cargo\bin` on Windows) is included in `PATH` inside `extraCargoEnvironmentVariables` so child `cargo` / `cmake` processes invoked during build always find Rust tools even when the IDE/shell did not inherit `~/.cargo/bin`.
- Invoke:
  ```dart
  await const FlutterRustBridgeNativeAssetsBuilder(
    assetName: 'rust_lib_vieneu_tts',
    cratePath: 'rust',
  ).run(
    input: input,
    output: output,
  );
  ```
  Using `assetName: 'rust_lib_vieneu_tts'` matches the `CodeAsset` name registered by the prebuilt flow (`package:vieneu_tts/rust_lib_vieneu_tts`), ensuring identical FFI symbol/library lookup in both modes.
- **Android NDK `libc++_shared.so` registration**:
  `audio-cpp` links dynamically against `libc++_shared.so` on Android, which `FlutterRustBridgeNativeAssetsBuilder` does not bundle automatically. When `input.config.code.targetOS == OS.android`:
  - Derive the NDK toolchain root from `input.config.code.cCompiler?.compiler` (located at `<ndk>/toolchains/llvm/prebuilt/<host>/bin/clang`).
  - Resolve `<ndk>/toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<sysrootTriple>/libc++_shared.so` (mapping `Architecture.arm64` -> `aarch64-linux-android`, `Architecture.x64` -> `x86_64-linux-android`, `Architecture.arm` -> `arm-linux-androideabi`).
  - Copy `libc++_shared.so` into `input.outputDirectory` (or register it directly) as a `CodeAsset(package: packageName, name: 'libc++_shared.so', linkMode: DynamicLoadingBundled(), file: ...)`.

### 3. Dynamic Version Resolution from `pubspec.yaml`
Instead of hardcoding `const String packageVersion = '0.1.0'`, `hook/build.dart` reads `File(p.join(packageRoot, 'pubspec.yaml'))` and parses `version:` via `package:yaml` (or regex `^version:\s*([^\s+#]+)`), falling back to `'0.1.0'` only if `pubspec.yaml` is unreadable.

### 4. CI Workflow Enhancements & Dual-Mode Testing
- **Version Parity Gate in `.github/workflows/vieneu-tts-native-release.yml`**:
  Add a `verify-version` step in `generate-bindings` (or a dedicated gate job) that extracts:
  1. Target release version (from `github.ref_name` tag `vX.Y.Z` or `inputs.version`).
  2. `version:` from `packages/vieneu_tts/pubspec.yaml`.
  3. `version =` from `packages/vieneu_tts/rust/Cargo.toml`.
  If any of the three differ, the workflow fails immediately before running matrix builds.
- **Toolchain Alignment**:
  Update `.github/workflows/vieneu-tts-native-release.yml`, `.github/workflows/example-app-android.yml`, and `.github/workflows/vieneu-tts-lib.yml` to use:
  - `flutter_rust_bridge_codegen` `v2.13.0`
  - Rust `1.93.1` (matching `packages/vieneu_tts/rust/rust-toolchain.toml`)
  - Android NDK `r28` (`28.2.13676358`)
- **Dual-Mode Hook Verification Jobs**:
  - In `.github/workflows/vieneu-tts-lib.yml` (and `.github/workflows/example-app-android.yml`):
    - **Source Mode Test**: Run `dart test` / `flutter test` with `VIENEU_TTS_BUILD_MODE=source` and Rust/CMake installed, verifying `FlutterRustBridgeNativeAssetsBuilder` compiles and registers the native library from source.
    - **Prebuilt Mode Test**: Package the built `.so` into `dist/vieneu_tts-<target>-v<version>.tar.gz`, set `VIENEU_TTS_BUILD_MODE=prebuilt`, and verify `hook/build.dart` extracts and registers the prebuilt asset without invoking Cargo.

### 5. Standardize Flutter Example Platform Scaffolding (`android` & `windows`)
- Remove the hand-crafted `packages/flutter_vieneu_tts/example/android` directory and run `flutter create --platforms=android,windows --org com.vieneu.tts --project-name vieneu_tts_example .` inside `packages/flutter_vieneu_tts/example`.
- Preserve all existing Dart application and test files (`pubspec.yaml`, `lib/main.dart`, `test/app_test.dart`, `integration_test/app_test.dart`).
- Rely on Flutter's native assets integration instead of legacy manual `jniLibs.srcDirs` or forced multi-ABI `abiFilters` in `app/build.gradle.kts`.
- Add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml` (for on-device model downloads in both debug and release builds) and align `applicationId = "com.vieneu.tts.example"` with `.github/scripts/run_emulator_test.sh`.

## Risks / Trade-offs

- **[Risk] Windows `MAX_PATH` limits during local CMake/Cargo builds of `audio-cpp`** -> **Mitigation**: `FlutterRustBridgeNativeAssetsBuilder` (2.13.0) combined with `_ShortWindowsFrbTempOverrides` redirects `out_dir_shared` on Windows to a short root path (`<drive>:\f_<hash>`) to keep all CMake/MSVC object paths well below 260 characters.
- **[Risk] Local developer machine missing `~/.cargo/bin` in GUI IDE `PATH`** -> **Mitigation**: `hook/build.dart` explicitly checks `~/.cargo/bin/rustup[.exe]` and appends `~/.cargo/bin` to `PATH` in `extraCargoEnvironmentVariables`.
- **[Risk] Version drift between `pubspec.yaml` and GitHub Release tags** -> **Mitigation**: `hook/build.dart` dynamically reads `pubspec.yaml`, and `vieneu-tts-native-release.yml` fails fast if the tag, `pubspec.yaml`, and `Cargo.toml` versions do not match.
