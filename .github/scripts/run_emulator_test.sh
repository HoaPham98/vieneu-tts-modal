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
flutter build apk --debug

echo "=== 3. Pre-installing debug APK to create app sandbox ==="
adb install -r build/app/outputs/flutter-apk/app-debug.apk

echo "=== 4. Pushing offline models to app sandbox ==="
adb root
adb wait-for-device
adb shell "mkdir -p /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models"
adb push /tmp/vieneu_models/vieneu-v3-turbo-q8_0.gguf /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models/
adb push /tmp/vieneu_models/sea_g2p.bin /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models/

APP_UID=$(adb shell stat -c '%u:%g' /data/user/0/com.vieneu.tts.example | tr -d '\r')
echo "Setting permissions for UID: $APP_UID..."
adb shell "chown -R $APP_UID /data/user/0/com.vieneu.tts.example/app_flutter"
adb shell "chmod -R 777 /data/user/0/com.vieneu.tts.example/app_flutter"
adb shell "ls -la /data/user/0/com.vieneu.tts.example/app_flutter/vieneu_models"

adb unroot
adb wait-for-device

echo "=== 5. Running On-Device Integration Test ==="
flutter test integration_test/app_test.dart --verbose
