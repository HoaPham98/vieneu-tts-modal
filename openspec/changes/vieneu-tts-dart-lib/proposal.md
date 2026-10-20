# Proposal: VieNeu-TTS Dart Library with Flutter Rust Bridge & audio.cpp

## Why

Hiện tại, VieNeu-TTS v3 Turbo trong repository này chỉ được triển khai dưới dạng server-side (Modal serverless và Docker container). Để hỗ trợ các ứng dụng di động (Android và iOS) chạy tổng hợp giọng nói trực tiếp trên thiết bị (on-device) với độ trễ cực thấp, không phụ thuộc vào kết nối mạng khi phát âm thanh, và bảo mật dữ liệu tuyệt đối, cần có một thư viện Dart / Flutter nhẹ nhàng, hiệu năng cao.

Thư viện sử dụng `flutter_rust_bridge` để kết nối Dart với crate `audio-cpp` (`model-vieneu-v3-turbo`) và `sea-g2p-rs`, hỗ trợ tổng hợp giọng nói và stream chunk âm thanh theo thời gian thực. Toàn bộ quy trình kiểm thử, build artifact NDK/iOS được thực hiện tự động qua GitHub Actions (không cài Rust/Flutter trên máy cục bộ), đồng thời tối ưu hóa bộ lọc đường dẫn (path filters) cho các workflow hiện có để tránh kích hoạt chạy CI lãng phí.

## What Changes

- **Thêm thư viện Dart `vieneu_tts`** đặt tại `packages/vieneu_tts/`:
  - Public Dart API tinh gọn: Tải model on-demand (`downloadModel`), khởi tạo engine (`init`), tổng hợp âm thanh toàn bộ (`synthesize`), stream âm thanh thời gian thực (`stream`), và danh mục 25 preset giọng đọc (`availableVoices`).
  - Tầng Native Rust (`packages/vieneu_tts/rust/`) tích hợp `audio-cpp` (với feature `model-vieneu-v3-turbo`) và `sea-g2p-rs` (chuẩn hóa văn bản tiếng Việt sang âm vị IPA).
  - Cấu hình đóng gói native cho Android (Gradle + JNI NDK) và iOS (CocoaPods Podspec).
  - Nhúng sẵn 25 preset giọng đọc (`minh_quan_pro` và các giọng Bắc - Trung - Nam) trực tiếp trong package để người dùng chỉ cần tải duy nhất 1 file `model.gguf` (188 MB) là có thể sử dụng tất cả các giọng.
- **Thêm Flutter Android Example App (`packages/vieneu_tts/example/`)**:
  - Ứng dụng mẫu hoàn chỉnh hỗ trợ tải model & dictionary về máy, quản lý trạng thái offline, lựa chọn 25 giọng đọc, nhập văn bản và phát âm thanh (tổng hợp một lần hoặc stream).
  - Tích hợp bộ kiểm thử tự động integration test (`integration_test/app_test.dart`) kiểm chứng quy trình khởi chạy, tải tài nguyên, nạp native engine và tổng hợp tiếng Việt thực tế.
- **Thêm GitHub Actions CI chuyên trách (`.github/workflows/vieneu-tts-lib.yml`)**:
  - Hỗ trợ `workflow_dispatch` để trigger thủ công từ xa qua `gh cli` và `push`/`pull_request` lọc đường dẫn `packages/vieneu_tts/**`.
  - Matrix jobs: Codegen lint, build Android JNI libraries (`arm64-v8a`, `x86_64`), build iOS frameworks, chạy end-to-end unit test tổng hợp audio, chạy automated integration test cho example app, và build xuất bản Android Release APK (`vieneu-tts-android-apk`) vào GitHub Actions artifacts.
- **Cập nhật Path Filters cho các GitHub Workflow hiện có**:
  - Bổ sung `paths` filter vào `.github/workflows/deploy-modal.yml` để ngăn chặn việc deploy lên Modal khi chỉ thay đổi code Dart/Flutter hoặc tài liệu.
  - Tinh chỉnh `paths` trong `.github/workflows/docker-build.yml` đảm bảo không bị trigger ngoài ý muốn.

## Capabilities

### New Capabilities
- `on-device-tts`: Cung cấp Dart library API cho việc tổng hợp và streaming Text-to-Speech tiếng Việt on-device sử dụng VieNeu-TTS v3 Turbo GGUF và audio.cpp engine.
- `ci-workflow-routing`: Định tuyến và lọc đường dẫn (path filtering) cho các GitHub Actions workflows (Modal deployment, Docker build, và Dart library CI), cho phép điều khiển và kiểm tra log thông qua GitHub CLI (`gh`).

### Modified Capabilities
*(Không có thay đổi về requirements đối với các capability hiện có)*

## Impact

- **Mã nguồn hiện tại**: Không làm xáo trộn mã nguồn server hiện có (`modal_app.py`, `server.py`, `webui.py`). Thư viện mới nằm độc lập trong `packages/vieneu_tts/`.
- **Workflows**: File `.github/workflows/deploy-modal.yml` được cập nhật thêm bộ lọc `paths:`. Thêm mới `.github/workflows/vieneu-tts-lib.yml`.
- **Môi trường máy local**: Không cài đặt Rust hay Flutter trên máy này. Toàn bộ khâu build và test chạy trên GitHub Actions runners.
