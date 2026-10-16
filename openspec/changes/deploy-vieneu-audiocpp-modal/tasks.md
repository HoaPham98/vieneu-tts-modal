# Tasks

## 1. Môi trường Image & Tài nguyên Model

- [x] 1.1 Khai báo `modal.Image` sử dụng base image `ghcr.io/0xshug0/audio.cpp:full-cpu`, bổ sung Python 3.11 và các package cần thiết (`fastapi[standard]`, `httpx`, `sea-g2p`). Xác nhận image build thành công.
- [x] 1.2 Viết script tải trọng số `phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF` (`model.gguf`, `config.json`, `tokenizer.json`, `tokenizer_config.json`, `special_tokens_map.json`, `speech_tokenizer/config.json`) và lưu vào `/app/models/VieNeu-TTS-v3-Turbo/`. Xác nhận các file được đóng gói đủ trong container.
- [x] 1.3 Thiết lập tài nguyên preset giọng Ngọc Huyền bao gồm file audio tham chiếu `ngoc_huyen.wav`, file vector đặc trưng `ngoc_huyen.wav.emb.txt` (192 float numbers), và text tham chiếu. Xác nhận các file preset tồn tại ở `/app/voices/`.

## 2. Cấu hình audio.cpp Server & Tiến trình nền

- [x] 2.1 Tạo cấu hình `/app/server.json` cho `audiocpp_server` định nghĩa model `vieneu-v3-turbo` (family `vietneu_tts`, path model GGUF, và preset Ngọc Huyền). Xác nhận cú pháp JSON hợp lệ theo schema của `audio.cpp`.
- [x] 2.2 Xây dựng hàm quản lý tiến trình nền trong Modal container để khởi chạy `/app/audiocpp_server` trên `localhost:8080` kèm vòng lặp polling healthcheck xác nhận server C++ sẵn sàng.

## 3. Proxy G2P & OpenAI API Endpoints

- [x] 3.1 Tích hợp module chuyển đổi văn bản tiếng Việt sang chuỗi âm vị IPA (`sea_g2p`) với xử lý ngắt câu và dấu câu. Xác nhận test case chuyển đổi text thông thường thành IPA chính xác.
- [x] 3.2 Hiện thực endpoint `POST /v1/audio/speech` trên FastAPI Proxy: nhận text tiếng Việt thô, chuyển đổi qua G2P, chuyển tiếp payload tới `http://127.0.0.1:8080/v1/audio/speech`, và stream dữ liệu audio trả về cho client.
- [x] 3.3 Hiện thực các endpoint phụ trợ: `GET /v1/models`, `GET /v1/audio/voices`, và `GET /health` cung cấp đầy đủ metadata về model `vieneu-v3-turbo` và preset Ngọc Huyền.

## 4. Kiểm thử & Cập nhật Tài liệu

- [x] 4.1 Chạy linting (`ruff check`) và xác thực cú pháp của `modal_app.py` để đảm bảo không có lỗi runtime/import.
- [x] 4.2 Cập nhật `README.md` mô tả kiến trúc mới C++ GGUF, hiệu năng cải tiến, và hướng dẫn gửi request tới endpoint với preset giọng Ngọc Huyền.

