#!/usr/bin/env bash
set -eo pipefail

echo "=== 1. Waiting for Android Emulator to finish booting ==="
adb wait-for-device
while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
  echo "Waiting for emulator boot_completed..."
  sleep 2
done
echo "Emulator is fully booted."

echo "=== 2. Pre-building debug APK ==="
cd packages/vieneu_tts/example
flutter build apk --debug --target-platform android-x64 --android-skip-build-dependency-validation

echo "=== 2.1 Verifying debug APK native libraries ==="
python3 -c "import zipfile; z = zipfile.ZipFile('build/app/outputs/flutter-apk/app-debug.apk'); libs = [f.filename for f in z.infolist() if 'lib/' in f.filename]; print('Debug APK native libs:'); [print(' -', l) for l in libs]; assert any('librust_lib_vieneu_tts.so' in l for l in libs), 'Missing native so in debug APK!'; assert any('libc++_shared.so' in l for l in libs), 'Missing libc++_shared.so in debug APK!'"

echo "=== 3. Pre-installing debug APK to create app sandbox ==="
adb install -r build/app/outputs/flutter-apk/app-debug.apk

echo "=== 4. Pushing offline models to app sandbox ==="
adb root
adb wait-for-device
adb shell "mkdir -p /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models"
adb push /tmp/vieneu_models/. /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models/

APP_UID=$(adb shell stat -c '%u:%g' /data/user/0/com.vieneu.tts.example | tr -d '\r')
echo "Setting permissions for UID: $APP_UID..."
adb shell "chown -R $APP_UID /data/user/0/com.vieneu.tts.example/app_flutter"
adb shell "chmod -R 777 /data/user/0/com.vieneu.tts.example/app_flutter"
adb shell "mkdir -p /data/local/tmp && chmod 777 /data/local/tmp"
adb shell "ln -s /data/local/tmp /tmp 2>/dev/null || true"
adb shell "ls -laR /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models"

adb unroot
adb wait-for-device

echo "=== 5. Running On-Device Integration Test ==="
set +e
flutter test integration_test/app_test.dart --verbose
TEST_EXIT=$?
set -e

if [ $TEST_EXIT -ne 0 ]; then
  echo "=== Test failed! Capturing adb logcat ==="
  adb logcat -d -s flutter:V AndroidRuntime:E *:S
  exit $TEST_EXIT
fi
