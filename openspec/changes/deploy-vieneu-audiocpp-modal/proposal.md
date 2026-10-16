# Proposal

## Why

Hiện tại, việc chạy VieNeu-TTS v3 Turbo trên Modal dựa vào Python runtime và ONNX Runtime/PyTorch với dung lượng image lớn (>2 GB), thời gian khởi động container và nạp model chậm (~6-10s). 

Bằng việc chuyển đổi sang dùng model GGUF (`phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF` dung lượng chỉ 163 MB) và C++ engine của `audio.cpp` (`ghcr.io/0xshug0/audio.cpp:full-cpu`), tốc độ nạp model giảm xuống gần như tức thì (<0.01s), tốc độ sinh âm thanh nhanh gấp đôi (RTF ~0.24 trên CPU), và tiết kiệm đáng kể chi phí compute/credit trên Modal. Đồng thời, cấu hình mặc định preset giọng đọc chất lượng cao "Ngọc Huyền" cùng bộ tiền xử lý phiên âm (G2P proxy) giúp đảm bảo tương thích 100% với chuẩn OpenAI Speech API cho các ứng dụng chatbot và AI assistant.

## What Changes

- **Chuyển Base Image sang Docker `audio.cpp`**: Sử dụng `ghcr.io/0xshug0/audio.cpp:full-cpu` thay vì Debian slim + PyTorch/ONNX Runtime.
- **Tích hợp Model GGUF**: Tải và đóng gói sẵn trọng số `phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF` (163 MB) và các file tokenizer/config đi kèm.
- **Tích hợp Preset Giọng "Ngọc Huyền"**:
  - Trích xuất file audio mẫu `ngoc_huyen.wav` và text tham chiếu.
  - Tạo file vector đặc trưng 192 chiều `ngoc_huyen.wav.emb.txt` từ bộ trọng số preset gốc của VieNeu-TTS.
  - Cấu hình preset trong `server.json` của `audio.cpp` để làm giọng đọc mặc định.
- **Tích hợp Lightweight G2P Phonemizer Proxy**:
  - `audio.cpp` backend chạy `audiocpp_server` trên `localhost:8080`.
  - Một proxy mỏng (FastAPI / HTTP server) lắng nghe port công khai của Modal, nhận text tiếng Việt thông thường từ client, chuyển thành chuỗi âm vị IPA (thông qua `sea_g2p` / phonemizer), rồi chuyển tiếp tới `audiocpp_server` để trả về audio stream/file cho client.
- **Cập nhật Modal App definition**: Viết lại cấu hình deployment trong `modal_app.py` để khởi động container và dịch vụ proxy + backend.

## Capabilities

### New Capabilities
- `tts-serving`: Cung cấp OpenAI-compatible Text-to-Speech API (`/v1/audio/speech`, `/v1/models`, `/v1/audio/voices`) sử dụng backend C++ `audio.cpp` với trọng số GGUF, hỗ trợ preset giọng Ngọc Huyền và xử lý phiên âm tiếng Việt tự động.

### Modified Capabilities
*(Không có - dự án chưa có spec nào trước đó)*

## Impact

- **Mã nguồn**: Cập nhật `modal_app.py` (cấu hình Modal Image, quy trình tải model GGUF, cấu hình server C++, và proxy G2P).
- **Dependencies**: Thay thế dependencies nặng (`torch`, `torchaudio`, `onnxruntime`) bằng môi trường C++ siêu nhẹ và thư viện `sea-g2p`/`fastapi` cho proxy.
- **API Consumers**: Không gây breaking change cho client gọi API chuẩn OpenAI (`POST /v1/audio/speech`). Endpoint tiếp tục nhận văn bản tiếng Việt thông thường và trả về WAV/MP3.
