# Design: Dedicated Android Example App CI with On-Device Integration Test

## Context & Motivation

Việc kiểm thử ứng dụng Flutter có liên kết native FFI (C++/Rust) đòi hỏi kiểm chứng trên hệ điều hành Android thực tế thay vì máy chủ Linux host. 
Để đạt được điều này một cách nhanh chóng và tối ưu nhất:
- Tạm thời vô hiệu hóa bộ kích hoạt tự động của `.github/workflows/vieneu-tts-lib.yml`.
- Tạo workflow `.github/workflows/example-app-android.yml` chuyên trách kiểm thử ứng dụng trên Android Emulator và đóng gói APK phát hành.

## Technical Architecture

```
                                [ GitHub Actions: ubuntu-latest ]
                                                │
                ┌───────────────────────────────┴───────────────────────────────┐
                ▼                                                               ▼
    [ Job 1: Build Native NDK ]                                 [ Vô hiệu hóa legacy CI ]
    - flutter_rust_bridge_codegen 2.0.0                         - vieneu-tts-lib.yml
    - Rust toolchain (targets: aarch64, x86_64)                   on: workflow_dispatch only
    - Android NDK r26b + cargo-ndk
    - cargo ndk -t arm64-v8a -t x86_64 build --release
    - Upload artifact: android-jnilibs
                │
                ▼
    [ Job 2: Android Emulator Test & Build APK ]
    - Download bindings & android-jnilibs
    - KVM Hardware Acceleration (/dev/kvm)
    - reactivecircus/android-emulator-runner@v2:
        * API: 30 (Android 11)
        * Target: google_apis
        * Arch: x86_64
        * Script: flutter test integration_test/app_test.dart
            1. UI Download: Tải model (188MB) & dict (13MB) qua mạng máy ảo
            2. Offline Engine Init: Khởi tạo VieneuTts in-process
            3. WAV Synthesis: Nhập câu -> Bấm Đọc -> Kiểm tra header WAV
            4. PCM Streaming: Bấm Stream -> Kiểm tra nhận các chunk âm thanh
    - flutter build apk --release --target-platform android-arm64
    - Kiểm tra `librust_lib_vieneu_tts.so` và `libsea_g2p_rs-*.so` trong APK
    - Upload artifact: vieneu-tts-example-apk
```

## Detailed Decisions

### 1. Dual-Architecture NDK Compilation
- **Vấn đề:** Máy chủ CI là kiến trúc `x86_64`, trong khi điện thoại người dùng là kiến trúc `arm64-v8a`.
- **Giải pháp:** Cấu hình `cargo ndk` biên dịch đồng thời 2 target:
  ```bash
  cargo ndk -t arm64-v8a -t x86_64 -o ../android/src/main/jniLibs build --release
  ```
  - Thư viện `x86_64` được sử dụng trực tiếp bởi Android Emulator trên CI runner, cho tốc độ thực thi native tối đa và không phụ thuộc vào lớp dịch lệnh nhị phân ARM (Houdini).
  - Thư viện `arm64-v8a` được đóng gói vào Release APK để người dùng cài đặt lên điện thoại Android thực tế.

### 2. KVM Hardware Acceleration on GitHub Actions
- Runner `ubuntu-latest` hỗ trợ KVM. Ta cấp quyền `/dev/kvm`:
  ```bash
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
  sudo udevadm control --reload-rules
  sudo udevadm trigger --name-match=kvm
  ```
- Sử dụng action `reactivecircus/android-emulator-runner@v2`:
  - `api-level: 30` (Android 11 ổn định, nhẹ, khởi động nhanh).
  - `arch: x86_64`.
  - Flags khởi động headless: `-no-window -gpu swiftshader_indirect -no-audio -no-snapshot-save`.

### 3. On-Device Integration Test Flow (`integration_test/app_test.dart`)
- **Tải tài nguyên qua UI:** 
  - `tester.tap(find.text('Tải Model & Dictionary (~248 MB)'))`.
  - Chờ đợi vòng lặp (`pump`) cho tới khi tiến trình tải đạt 100% và file được lưu vào `app_flutter/vieneu_models/`.
- **Khởi tạo Engine:**
  - Xác minh `VieneuTts.isInitialized == true`.
  - Đảm bảo version FFI runtime hoàn toàn khớp với codegen (2.0.0).
- **Tổng hợp WAV:**
  - Nhập văn bản vào `TextField`.
  - `tester.tap(find.text('Đọc (WAV)'))`.
  - Xác nhận file sinh ra có WAV header chuẩn (> 44 bytes).
- **Streaming âm thanh:**
  - `tester.tap(find.text('Stream thời gian thực'))`.
  - Xác nhận nhận ít nhất một chunk âm thanh PCM và số lượng chunk tăng dần.

### 4. Release APK Packaging
- Stage thư viện native vào `android/app/src/main/jniLibs/arm64-v8a/`.
- Chạy:
  ```bash
  flutter build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation
  ```
- Dùng Python zipfile kiểm tra sự hiện diện của `librust_lib_vieneu_tts.so` trước khi upload artifact.
