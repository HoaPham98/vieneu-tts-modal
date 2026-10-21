# Proposal: Dedicated Android Example App CI with On-Device Integration Test & APK Artifact

## Why

Workflow CI hiện tại (`.github/workflows/vieneu-tts-lib.yml`) bao gồm 7 jobs tích hợp (sinh bridge bindings, kiểm tra iOS, phân tích Dart lint, biên dịch Rust native, kiểm tra inference trên host Linux, build NDK và đóng gói APK). Việc duy trì một pipeline tích hợp lớn khiến thời gian chạy mỗi lần mất từ 15-20 phút và phân tán sự tập trung. Quan trọng hơn, bài test trong pipeline cũ chỉ chạy headless trên Dart VM của máy chủ Linux mà không có thiết bị thật hoặc máy ảo Android, do đó không thể kiểm chứng được môi trường hệ điều hành Android thực tế (tải model qua mạng thiết bị, cấp phát bộ nhớ native, nạp file `.so` qua JNI và phát âm thanh).

Để đảm bảo ứng dụng Flutter Example hoạt động hoàn hảo 100% trên thiết bị Android, cần tạm tắt kích hoạt tự động của workflow cũ và tạo một pipeline CI độc lập, tinh gọn, tập trung hoàn toàn vào:
1. Biên dịch native thư viện NDK cho cả 2 kiến trúc (`arm64-v8a` cho điện thoại thật và `x86_64` cho máy ảo).
2. Khởi động Android Emulator có tăng tốc phần cứng KVM trên GitHub Actions.
3. Chạy toàn bộ kịch bản kiểm thử tích hợp trên thiết bị thật (On-Device Integration Test): chạm UI để tải model & dictionary qua mạng thật của emulator -> khởi tạo engine -> kiểm tra chuyển đổi văn bản sang WAV -> kiểm tra streaming PCM chunks thời gian thực.
4. Đóng gói Release APK (`arm64-v8a`) và xuất bản thành artifact để tải về thử nghiệm.

## What Changes

- **Tạm tắt tự động kích hoạt workflow cũ (`.github/workflows/vieneu-tts-lib.yml`)**:
  - Đổi sự kiện kích hoạt từ `push`/`pull_request` sang chỉ `workflow_dispatch` (kích hoạt thủ công khi cần).
- **Thêm workflow CI chuyên biệt mới (`.github/workflows/example-app-android.yml`)**:
  - Kích hoạt khi có thay đổi trong `packages/vieneu_tts/**` hoặc qua `workflow_dispatch`.
  - **Job 1: Build Native NDK Libraries**:
    - Chạy `flutter_rust_bridge_codegen` để sinh bindings Dart-Rust.
    - Cấu hình `cargo ndk` biên dịch song song cả 2 kiến trúc: `arm64-v8a` và `x86_64`.
    - Đóng gói và lưu trữ `jniLibs` thành artifact trung gian.
  - **Job 2: Android Emulator Integration Test & Release APK**:
    - Kích hoạt phần cứng ảo hoá KVM (`/dev/kvm`).
    - Khởi động Android Emulator API 30 (`google_apis;x86_64`) bằng `reactivecircus/android-emulator-runner@v2`.
    - Thực thi bài kiểm thử tích hợp `packages/vieneu_tts/example/integration_test/app_test.dart` trên máy ảo:
      - Tải model GGUF (188MB) và từ điển SEA-G2P (13MB) qua giao diện người dùng.
      - Xác minh engine offline chuyển sang trạng thái sẵn sàng.
      - Tổng hợp đoạn văn bản mẫu sang file WAV và xác nhận dung lượng âm thanh hợp lệ.
      - Chạy streaming âm thanh thời gian thực và xác nhận nhận đầy đủ các chunk PCM.
    - Biên dịch Release APK Android (`flutter build apk --release --target-platform android-arm64`).
    - Xác minh nhúng đầy đủ thư viện `librust_lib_vieneu_tts.so` và `libsea_g2p_rs-*.so`.
    - Upload artifact `vieneu-tts-example-apk`.

## Capabilities

### New Capabilities
- `android-emulator-ci`: Quy trình CI tự động hóa chuyên biệt khởi động Android Emulator với KVM hardware acceleration, nạp ứng dụng Flutter thật, chạy toàn bộ chu trình tải tài nguyên qua UI, tổng hợp giọng nói offline, và đóng gói Release APK.

### Modified Capabilities
*(Không có thay đổi về requirements đối với các capability hiện có)*

## Impact

- **CI Pipeline**: Giảm thiểu thời gian chờ đợi, tách biệt hoàn toàn luồng phát triển ứng dụng di động Android khỏi các tác vụ kiểm thử server backend/iOS.
- **Độ tin cậy của mã nguồn**: Phát hiện sớm 100% các lỗi runtime native (FFI linkage, ABI mismatch, out-of-memory, file permissions, Java/Kotlin runtime crash) trực tiếp trên Android OS trước khi phát hành.
- **Môi trường máy local**: Tiếp tục tuân thủ nghiêm ngặt nguyên tắc **Zero local installations** (không cài Rust, Cargo, Flutter, Android SDK lên máy host cục bộ).
