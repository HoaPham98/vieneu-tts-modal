# Design

## Context

Xem `proposal.md` để nắm rõ bối cảnh và động lực.

Mục tiêu là triển khai mô hình `phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF` lên nền tảng serverless Modal bằng cách sử dụng Docker image chính thức của `audio.cpp` (`ghcr.io/0xshug0/audio.cpp:full-cpu`). Vì `audio.cpp` là runtime C++ thuần tối ưu hóa bằng `ggml` nhưng chưa tích hợp bộ phiên âm tiếng Việt (G2P), hệ thống cần một kiến trúc kết hợp giữa C++ engine cho inference nặng và một proxy mỏng bằng Python cho bước chuẩn hóa/phiên âm văn bản tiếng Việt.

## Goals / Non-Goals

**Goals:**
- Tối ưu thời gian khởi động container và nạp model xuống dưới 0.5s thông qua GGUF và `audio.cpp`.
- Giảm chi phí tài nguyên (chạy mượt trên cấu hình tối thiểu 2 vCPU + 2 GiB RAM của Modal Starter plan).
- Đảm bảo tương thích 100% chuẩn OpenAI Audio Speech API (`POST /v1/audio/speech`).
- Cấu hình preset giọng "Ngọc Huyền" làm giọng đọc chuẩn mặc định với vector đặc trưng 192 chiều chuẩn xác.
- Tự động chuyển đổi text tiếng Việt tự nhiên sang chuỗi âm vị IPA trước khi đưa vào mô hình C++.

**Non-Goals:**
- Tự biên dịch C++ từ source (tận dụng image pre-built chính thức `ghcr.io/0xshug0/audio.cpp:full-cpu`).
- Huấn luyện hoặc fine-tune lại model.
- Mở rộng nhiều giọng đọc tùy biến ngoài preset Ngọc Huyền trong giai đoạn này.

## Decisions

### 1. Base Image: `modal.Image.from_registry` kết hợp `add_python="3.11"`
- **Lựa chọn**: Sử dụng `ghcr.io/0xshug0/audio.cpp:full-cpu` làm base image trong Modal, cài thêm `python3.11` cùng thư viện `sea-g2p` và `fastapi`.
- **Lý do**: Image này đã có sẵn binary C++ tối ưu OpenMP cho CPU (`/app/audiocpp_server`, `/app/audiocpp_cli`) và toàn bộ cấu hình model specs cho `vietneu_tts`.
- **Phương án thay thế**: Tự build Dockerfile từ Ubuntu và compile cmake -> Tốn thời gian build image hơn nhiều và dễ phát sinh lỗi toolchain.

### 2. Kiến trúc Co-location (Proxy mỏng + C++ Subprocess trong 1 Container)
- **Lựa chọn**: Trong Modal container, khi khởi động (`@modal.enter()` hoặc startup event):
  1. Khởi động `/app/audiocpp_server --config /app/server.json --backend cpu` ở chế độ tiến trình nền (background subprocess) trên port nội bộ `127.0.0.1:8080`.
  2. Proxy FastAPI đóng vai trò `@modal.asgi_app()` lắng nghe request từ ngoài Internet:
     - Nhận JSON payload `{ "input": "Xin chào...", "voice": "..." }`.
     - Gọi `sea_g2p` chuyển `input` sang chuỗi âm vị IPA (`"sˈin tʃˈaː2w..."`).
     - Gửi HTTP request đã biến đổi tới `http://127.0.0.1:8080/v1/audio/speech`.
     - Stream luồng WAV audio trả về trực tiếp cho client.
- **Lý do**: Giữ nguyên tính năng server C++ của `audio.cpp` đồng thời lấp đầy khoảng trống G2P tiếng Việt mà không cần can thiệp sửa mã nguồn C++.
- **Phương án thay thế**: Bắt client tự phiên âm IPA -> Làm mất tính tương thích chuẩn OpenAI, gây khó khăn cho người dùng.

### 3. Đóng gói Model GGUF và Preset Giọng Ngọc Huyền
- **Tải Model**: Khi build image (`.run_commands(...)`), tự động tải file `model.gguf` (163 MB), `config.json`, `tokenizer.json`, `tokenizer_config.json`, `special_tokens_map.json`, và `speech_tokenizer/config.json` vào thư mục `/app/models/VieNeu-TTS-v3-Turbo/`.
- **Preset Ngọc Huyền**:
  - Tạo file vector đặc trưng `ngoc_huyen.wav.emb.txt` chứa đúng 192 giá trị float trích xuất từ preset gốc của VieNeu-TTS.
  - Chuẩn bị file audio tham chiếu `ngoc_huyen.wav` (khoảng 3-4s) và file text tham chiếu `ngoc_huyen.txt`.
- **Cấu hình `server.json`**:
  ```json
  {
    "host": "127.0.0.1",
    "port": 8080,
    "backend": "cpu",
    "threads": 2,
    "models": [
      {
        "id": "vieneu-v3-turbo",
        "family": "vietneu_tts",
        "path": "/app/models/VieNeu-TTS-v3-Turbo/model.gguf",
        "task": "tts",
        "mode": "offline",
        "voice_presets": {
          "Ngọc Huyền": {
            "voice_ref": "/app/voices/ngoc_huyen.wav",
            "reference_text": "..."
          }
        },
        "default_voice_preset": "Ngọc Huyền"
      }
    ]
  }
  ```

## Risks / Trade-offs

- **[Khởi động lệch nhịp giữa C++ server và Proxy]**: Proxy có thể nhận request trước khi `audiocpp_server` hoàn tất mở port 8080.
  - *Giải pháp*: Trong hàm lifecycle `@modal.enter()`, thêm một vòng lặp healthcheck ngắn (poll `http://127.0.0.1:8080/health`) tối đa 5-10s để đảm bảo C++ server sẵn sàng 100% trước khi Proxy mở nhận traffic.
- **[Chi phí và dung lượng bộ nhớ]**: 
  - Mô hình GGUF chỉ 163 MB, runtime C++ chiếm ~200-300 MB RAM, Proxy FastAPI chiếm ~100 MB RAM -> Tổng dung lượng sử dụng chưa tới 600 MB RAM, hoàn toàn nằm trong mức an toàn của gói 2048 MB RAM của Modal.
- **[Tốc độ G2P]**:
  - `sea_g2p` chạy bằng thuật toán dựa trên luật (rule-based) và từ điển, xử lý 1 câu tiếng Việt thông thường chỉ tốn ~2-5 ms CPU, không làm ảnh hưởng đến tổng thời gian sinh âm thanh.
