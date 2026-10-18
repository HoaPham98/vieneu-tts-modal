# VieNeu-TTS v3 Turbo GGUF on Modal & Docker (audio.cpp C++ Engine)

Triển khai **VieNeu-TTS v3 Turbo GGUF** — mô hình Text-to-Speech (TTS) tiếng Việt chất lượng cao chạy trên C++ runtime **audio.cpp** — thành một **Serverless / Standalone Container API tương thích chuẩn OpenAI Audio Speech**, với **25 preset giọng đọc chính thức** (mặc định: **Minh Quân Pro**, cùng Ngọc Huyền, Mai Anh, Thùy Dung, Quang Sơn, v.v.).

Hệ thống sử dụng **trọng số GGUF chính thức từ tác giả Phạm Nguyễn Ngọc Bảo (188 MB)** với MOSS Neural Codec giữ nguyên định dạng `f16` đạt 36.0 dB SNR (âm thanh 48 kHz chuẩn studio, triệt tiêu hoàn toàn rè tiếng), nạp model tức thì (<0.01s) và tốc độ sinh cực nhanh (RTF ~0.51 trên 1 CPU x86 của Modal, nhanh gấp đôi thời gian thực).

> 💡 **Ước tính chi phí với cấu hình tối ưu (1 CPU Physical Core + 4 GiB RAM trên Modal):**
> - Đơn giá Modal CPU: CPU `$0.0000137/core/giây`, RAM `$0.00000222/GiB/giây` ≈ **`$0.0000225/giây`** (~`$0.081/giờ`).
> - Với RTF ~0.51, mỗi câu nói 4 giây chỉ mất **~2.0 giây compute**!
> - **$30 credit/tháng** đủ cho **~500.000 câu đọc** (hoàn toàn không cần GPU đắt đỏ).
> - **Bảo mật Modal Proxy Auth**: Request sai/thiếu token bị chặn ngay tại tầng Edge Reverse Proxy của Modal — container **hoàn toàn không bị đánh thức**, triệt tiêu 100% chi phí phát sinh do quét bot/spam.

---

## Mục lục

- [Tính năng nổi bật](#tính-năng-nổi-bật)
- [Cơ chế bảo mật Modal Proxy Auth](#cơ-chế-bảo-mật-modal-proxy-auth)
- [Cấu trúc repo](#cấu-trúc-repo)
- [Hướng dẫn thiết lập cho người mới (Quickstart)](#hướng-dẫn-thiết-lập-cho-người-mới-quickstart)
  - [Bước 1: Clone repo và tạo môi trường Python](#bước-1-clone-repo-và-tạo-môi-trường-python)
  - [Bước 2: Cài đặt và đăng nhập Modal CLI](#bước-2-cài-đặt-và-đăng-nhập-modal-cli)
  - [Bước 3: Tạo Modal Proxy Token](#bước-3-tạo-modal-proxy-token)
  - [Bước 4: Deploy lên Modal](#bước-4-deploy-lên-modal)
- [Triển khai bằng Docker & VPS (Tối ưu cho OCI ARM64 & x86)](#triển-khai-bằng-docker--vps-tối-ưu-cho-oci-arm64--x86)
  - [Chạy nhanh bằng Docker Compose](#chạy-nhanh-bằng-docker-compose)
  - [Build Docker Image cục bộ](#build-docker-image-cục-bộ)
  - [Cấu hình trên VPS OCI Ampere A1 (ARM64)](#cấu-hình-trên-vps-oci-ampere-a1-arm64)
- [Hướng dẫn sử dụng](#hướng-dẫn-sử-dụng)
  - [Trải nghiệm qua WebUI nhúng sẵn](#trải-nghiệm-qua-webui-nhúng-sẵn)
  - [Health check (`/health`)](#health-check-health)
  - [Xem trước âm vị IPA (`/v1/audio/phonemize`)](#xem-trước-âm-vị-ipa-v1audiophonemize)
  - [Danh mục 25 giọng đọc (`/v1/audio/voices`)](#danh-mục-25-giọng-đọc-v1audiovoices)
  - [Tạo file âm thanh (WAV / MP3)](#tạo-file-âm-thanh-wav--mp3)
  - [Streaming âm thanh thật (PCM / SSE)](#streaming-âm-thanh-thật-pcm--sse)
  - [Tích hợp với SDK OpenAI (Python & TypeScript)](#tích-hợp-với-sdk-openai)
  - [Tích hợp vào các UI/Chatbot (Dify, NextChat, Open WebUI)](#tích-hợp-vào-các-uichatbot)
- [Bảng tham số API `POST /v1/audio/speech`](#bảng-tham-số-api-post-v1audiospeech)
- [Thông số phần cứng & Hiệu năng](#thông-số-phần-cứng--hiệu-năng)
- [Xử lý sự cố thường gặp (FAQ)](#xử-lý-sự-cố-thường-gặp-faq)
- [Ghi công](#ghi-công)

---

## Tính năng nổi bật

- ⚡ **audio.cpp C++ Engine**: Chạy mô hình VieNeu-TTS v3 Turbo hoàn toàn bằng C++ thuần (dựa trên `ggml`), nạp model bằng `mmap` tức thì (<0.01s), không phụ thuộc PyTorch lúc inference.
- 📦 **Trọng số GGUF Chính Thức (188 MB)**: Tải từ `pnnbao-ump/VieNeu-TTS-v3-Turbo` với Q8_0 talker backbone và Codec MOSS `f16` chất lượng cao (36.0 dB SNR, âm thanh 48 kHz trung thực, trong trẻo).
- 🎙️ **25 Preset Giọng Đọc Đa Dạng**: Hỗ trợ đầy đủ 25 preset giọng chính thức qua 3 miền Bắc - Trung - Nam, mặc định là **Minh Quân Pro** (`minh_quan_pro`). Đổi giọng tức thì theo từng request mà không cần nạp lại model.
- 🛡️ **Bảo mật Modal Proxy Auth**: Chặn mọi truy cập trái phép tại tầng Edge Network của Modal, ngăn ngừa đánh thức container và bảo vệ chi phí $0 khi bị quét cổng/spam.
- 🖥️ **WebUI Nhúng Sẵn**: Giao diện người dùng trực quan, chọn 25 giọng theo vùng miền, nghe thử trực tiếp trong trình duyệt tại `/` hoặc `/ui`.
- 🔄 **Tự động G2P (Phonemizer)**: Tích hợp proxy chuyển đổi văn bản tiếng Việt tự nhiên sang chuỗi âm vị IPA trong ~1-2ms qua `sea-g2p`.
- 🔌 **Chuẩn OpenAI Compatible**: Hỗ trợ route `/v1/audio/speech`, `/v1/models`, `/v1/audio/voices` — tương thích trực tiếp với OpenAI SDK, Dify, NextChat, Open WebUI.
- 🌊 **Streaming Audio**: Hỗ trợ truyền stream chunked WAV hoặc SSE theo chuẩn OpenAI Realtime.
- 🗣️ **Hỗ trợ đa định dạng**: Mặc định `wav` (chất lượng 48 kHz cao cấp) hoặc `mp3`, `opus`, `aac`, `flac` (chuyển đổi qua `ffmpeg`).
- 💰 **Chi phí tối ưu**: Chạy mượt mà trên **1 Physical CPU Core** (`cpu=1.0`), đạt RTF ~0.51 (nhanh gấp đôi realtime), không cần GPU đắt đỏ.

---

## Cơ chế bảo mật Modal Proxy Auth

Ứng dụng sử dụng tính năng **Proxy Authentication** tích hợp sẵn của Modal (`requires_proxy_auth=True`):

```
Request từ Internet
       |
       v
+-----------------------------------+
|     Modal Edge / Reverse Proxy    |
|   (Kiểm tra Modal-Key & Secret)   |
+-----------------------------------+
       |
       +---> [Không có Token hoặc Token SAI] 
       |     ==> Chặn ngay lập tức với mã 401 Unauthorized.
       |     ==> CONTAINER HOÀN TOÀN KHÔNG BỊ BẬT! Chi phí = $0.
       |
       +---> [Token ĐÚNG]
             ==> Cho phép đi tiếp vào Container tính toán.
```

### Định dạng Bearer Token chuẩn OpenAI
Modal hỗ trợ gộp **Token ID** (`wk-...`) và **Token Secret** (`ws-...`) thành một chuỗi duy nhất:
```text
Authorization: Bearer <Token_ID>.<Token_Secret>
# Ví dụ: Authorization: Bearer wk-PpXKS75AJBSRao89B5kCNd.ws-535bYqsVWbYTzy3fF9VkTQ
```
Nhờ đó, bạn chỉ cần điền chuỗi `wk-xxx.ws-yyy` vào ô **API Key** của bất kỳ thư viện hay phần mềm nào hỗ trợ OpenAI (Dify, Open WebUI, Python OpenAI SDK...) là hệ thống sẽ hoạt động liền mạch!

---

## Cấu trúc repo

```text
.
├── modal_app.py                     # Cấu hình Modal, tải model GGUF, tiến trình audio.cpp & FastAPI
├── server.py                        # Entrypoint độc lập cho Docker / VPS self-hosted
├── webui.py                         # Giao diện WebUI nhúng sẵn siêu nhẹ
├── preset_voices/                   # Thư mục chứa 25 preset giọng đọc chính thức (codes & embeddings)
│   ├── manifest.json
│   ├── minh_quan_pro/
│   ├── ngoc_huyen/
│   └── ...
├── Dockerfile                       # Đóng gói Multi-Arch (amd64 / arm64) cho VPS
├── docker-compose.yml               # File compose chạy nhanh local / VPS
├── requirements.txt                 # Dependencies cho local CLI và CI (modal, ruff)
├── .github/workflows/
│   ├── deploy-modal.yml             # Tự động deploy lên Modal khi push code
│   └── docker-build.yml             # Tự động build Docker multi-arch lên GHCR
└── README.md
```

---

## Hướng dẫn thiết lập cho người mới (Quickstart)

### Bước 1: Clone repo và tạo môi trường Python

```bash
git clone https://github.com/HoaPham98/vieneu-tts-modal.git
cd vieneu-tts-modal

# Khởi tạo virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Cài đặt tooling
pip install -r requirements.txt
```

### Bước 2: Cài đặt và đăng nhập Modal CLI

```bash
modal setup
```
Trình duyệt sẽ tự động mở trang cấp quyền của Modal để xác thực tài khoản.

### Bước 3: Tạo Modal Proxy Token

Tạo một Proxy Token trong workspace của bạn để xác thực API:

```bash
modal workspace proxy-tokens create --name "vieneu-tts-token"
```

Lệnh sẽ trả về:
```text
 ─────────────────────────────────────────────────────────────────────────── 
  Modal-Key: wk-xxxxxxxxxxxxxxxxxxxx                                       
  Modal-Secret: ws-yyyyyyyyyyyyyyyyyyyy                                    
 ─────────────────────────────────────────────────────────────────────────── 
  Authorization: Bearer wk-xxxxxxxxxxxxxxxxxxxx.ws-yyyyyyyyyyyyyyyyyyyy  
 ─────────────────────────────────────────────────────────────────────────── 
```
👉 Hãy lưu lại chuỗi `wk-....ws-...` để dùng làm API Key cho client.

### Bước 4: Deploy lên Modal

Chạy lệnh deploy chính thức lên môi trường Production:

```bash
modal deploy modal_app.py
```

Sau khi deploy xong, terminal sẽ in ra URL của ứng dụng:
```text
✓ Created objects.
├── 🔨 Created web function AudioCppService.web_app => https://<workspace-name>--vieneu-tts-v3-turbo-audiocppservice-web-app.modal.run 🔑
```
*(Biểu tượng 🔑 thể hiện endpoint đã được bảo vệ bởi Modal Proxy Auth).*

---

## Triển khai bằng Docker & VPS (Tối ưu cho OCI ARM64 & x86)

Ngoài việc chạy Serverless trên Modal, bạn có thể tự lưu trữ (self-host) trên VPS riêng bằng Docker.

### Chạy nhanh bằng Docker Compose

```bash
# Đặt API_KEY (tùy chọn) và số luồng CPU (khuyến nghị 4 cho OCI Ampere A1)
export API_KEY="my-secret-key-123"
export THREADS=4

docker compose up -d
```

Kiểm tra log:
```bash
docker compose logs -f
```

### Build Docker Image cục bộ

```bash
docker build -t vieneu-tts:latest .

docker run -d \
  -p 8000:8000 \
  -e API_KEY="my-secret-key-123" \
  -e THREADS=4 \
  --name vieneu-tts \
  vieneu-tts:latest
```

### Cấu hình trên VPS OCI Ampere A1 (ARM64)

Máy ảo Oracle Cloud Free Tier (4 OCPU, 24 GB RAM ARM Ampere) chạy cực kỳ xuất sắc:
1. Mở cổng `8000` trên OCI Security List (Ingress Rule TCP 8000).
2. Mở firewall nội bộ Ubuntu:
   ```bash
   sudo ufw allow 8000/tcp
   ```
3. Chạy với 4 threads:
   ```bash
   THREADS=4 docker compose up -d
   ```
   > 💡 Tập lệnh ARM NEON trên nhân Ampere cho tốc độ RTF ~0.2x (3.5 giây audio tạo trong ~0.7s).

---

## Hướng dẫn sử dụng

### Trải nghiệm qua WebUI nhúng sẵn

- Khi chạy Docker: Mở trình duyệt vào `http://localhost:8000/` hoặc `http://<ip-vps>:8000/ui`.
- Khi chạy Modal: Do Modal Edge Proxy Auth yêu cầu Bearer token ở tầng HTTP, bạn có thể gửi token qua query/header hoặc dùng tiện ích ModHeader trên trình duyệt để thêm header `Authorization: Bearer <token>`.

### Health check (`/health`)

```bash
export BASE_URL="https://<workspace-name>--vieneu-tts-v3-turbo-audiocppservice-web-app.modal.run"
export MODAL_TOKEN="wk-xxxxxxxxxxxx.ws-yyyyyyyyyyyy"

curl -s "$BASE_URL/health" \
  -H "Authorization: Bearer $MODAL_TOKEN" | jq .
```

Kết quả:
```json
{
  "status": "ok",
  "engine": "audio.cpp C++ Runtime (GGUF)",
  "model": "pnnbao-ump/VieNeu-TTS-v3-Turbo-GGUF",
  "default_voice": "minh_quan_pro",
  "total_voices": 25,
  "auth_enabled": true,
  "auth_provider": "Modal Proxy Auth",
  "endpoints": [
    "/v1/models",
    "/v1/audio/voices",
    "/v1/audio/speech",
    "/v1/audio/phonemize"
  ]
}
```

### Xem trước âm vị IPA (`/v1/audio/phonemize`)

```bash
curl -s "$BASE_URL/v1/audio/phonemize" \
  -H "Authorization: Bearer $MODAL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"input": "Hôm nay thời tiết rất đẹp [cười]"}' | jq .
```

### Danh mục 25 giọng đọc (`/v1/audio/voices`)

```bash
curl -s "$BASE_URL/v1/audio/voices" \
  -H "Authorization: Bearer $MODAL_TOKEN" | jq .
```

#### Bảng danh sách 25 giọng đọc chính thức:

| Vùng miền | Giọng nam | Giọng nữ |
| :--- | :--- | :--- |
| **Miền Bắc** | **`minh_quan_pro`** *(Mặc định)*, `anh_khoi`, `adam_bua`, `thien_tam_duc`, `minh_duc`, `pham_tuyen`, `xuan_vinh`, `thanh_binh`, `manh_dung` | `ngoc_huyen`, `mai_anh`, `truc_ly`, `ngoc_linh`, `doan_trang`, `quynh_anh` |
| **Miền Trung** | `quang_son` | `ngoc_tran` |
| **Miền Nam** | `thai_son`, `minh_triet`, `duc_tri`, `adam` | `thuy_dung`, `thuc_doan`, `my_duyen`, `kim_thanh` |

> 💡 **Tự động ánh xạ alias OpenAI**: Các tên giọng như `alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`, `ash`, `coral`, `sage`, `verse` được tự động ánh xạ thông minh sang các preset tiếng Việt tương ứng (`nova` -> `ngoc_huyen`, `alloy` -> `minh_quan_pro`...).

### Tạo file âm thanh (WAV / MP3)

**Xuất file WAV chuẩn chất lượng 48 kHz (giọng Ngọc Huyền):**

```bash
curl -X POST "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $MODAL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vieneu-v3-turbo",
    "input": "Xin chào, đây là giọng đọc Ngọc Huyền chạy trực tiếp trên hạ tầng Modal CPU.",
    "voice": "ngoc_huyen",
    "response_format": "wav"
  }' \
  --output ngoc_huyen.wav
```

**Xuất file MP3 nén:**

```bash
curl -X POST "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $MODAL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "input": "File này được nén sang định dạng MP3 thông qua ffmpeg.",
    "voice": "minh_quan_pro",
    "response_format": "mp3"
  }' \
  --output out.mp3
```

### Streaming âm thanh thật (PCM / SSE)

- **Streaming PCM thô (độ trễ thấp nhất):**
  ```bash
  curl -N "$BASE_URL/v1/audio/speech" \
    -H "Authorization: Bearer $MODAL_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"input":"Âm thanh phát ra ngay lập tức khi đang tạo.","response_format":"pcm","stream":true}' \
    --output stream.pcm
  ```

- **Streaming Server-Sent Events (SSE) theo chuẩn OpenAI:**
  ```bash
  curl -N "$BASE_URL/v1/audio/speech" \
    -H "Authorization: Bearer $MODAL_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"input":"Văn bản dài được gửi về từng chunk base64.","stream_format":"sse"}'
  ```

---

### Tích hợp với SDK OpenAI

#### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://<workspace-name>--vieneu-tts-v3-turbo-audiocppservice-web-app.modal.run/v1",
    api_key="wk-xxxxxxxxxxxx.ws-yyyyyyyyyyyy",  # Chuỗi Proxy Token từ Modal
)

response = client.audio.speech.create(
    model="vieneu-v3-turbo",
    voice="ngoc_huyen",
    input="Xin chào bạn, tôi là trợ lý ảo sử dụng giọng đọc VieNeu v3 Turbo!",
    response_format="wav",
)
response.stream_to_file("output.wav")
```

#### TypeScript / Node.js

```typescript
import OpenAI from "openai";
import fs from "fs";

const openai = new OpenAI({
  baseURL: "https://<workspace-name>--vieneu-tts-v3-turbo-audiocppservice-web-app.modal.run/v1",
  apiKey: "wk-xxxxxxxxxxxx.ws-yyyyyyyyyyyy",
});

async function main() {
  const response = await openai.audio.speech.create({
    model="vieneu-v3-turbo",
    voice="ngoc_huyen",
    input="Xin chào từ ứng dụng NodeJS!",
    response_format="mp3",
  });

  const buffer = Buffer.from(await response.arrayBuffer());
  await fs.promises.writeFile("output.mp3", buffer);
}

main();
```

---

### Tích hợp vào các UI/Chatbot (Dify, NextChat, Open WebUI)

- **API Base URL**: `https://<workspace-name>--vieneu-tts-v3-turbo-audiocppservice-web-app.modal.run/v1`
- **API Key**: `wk-xxxxxxxxxxxx.ws-yyyyyyyyyyyy` (Proxy Token của bạn)
- **Model**: `vieneu-v3-turbo` hoặc `tts-1`
- **Voice**: `ngoc_huyen`, `minh_quan_pro` hoặc các alias như `nova`, `alloy`.

---

## Bảng tham số API `POST /v1/audio/speech`

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `input` | string | *(bắt buộc)* | Văn bản tiếng Việt cần đọc |
| `voice` | string | `minh_quan_pro` | Tên giọng đọc (từ `/v1/audio/voices`) hoặc alias OpenAI (`nova`, `alloy`...) |
| `model` | string | `vieneu-v3-turbo` | Chấp nhận cả `tts-1`, `tts-1-hd`, `gpt-4o-mini-tts` |
| `response_format` | enum | `wav` | `wav`, `mp3`, `pcm`, `opus`, `aac`, `flac` |
| `sample_rate` | int | `24000` | Tần số lấy mẫu xuất ra: `24000` hoặc `48000` Hz |
| `speed` | float | `1.0` | Tốc độ đọc (`0.75` là chậm, `1.25` là nhanh) |
| `stream` | bool | `false` | `true` để nhận chunked streaming |
| `stream_format` | enum | `null` | `sse` (Server-Sent Events) hoặc `audio` |

---

## Thông số phần cứng & Hiệu năng

Cấu hình hiện tại trong [modal_app.py](modal_app.py):

```python
@app.cls(
    cpu=1.0,            # 1 Physical Core x86 (tương đương 2 SMT threads)
    memory=4096,        # 4 GB RAM an toàn tuyệt đối
    scaledown_window=60,# Sau 60s không có request tự động tắt container về 0
    secrets=[],         # Bảo mật qua Modal Proxy Auth ở tầng Edge
)
```

| Thông số | Giá trị | Giải thích |
|---|---|---|
| **CPU Allocation** | `cpu=1.0` | Cấp 1 Physical Core x86 thật (có hỗ trợ AVX2 và Opportunistic Bursting). |
| **Backend Threads** | `threads: 2` | 2 worker threads chạy trên 2 SMT threads của core vật lý. |
| **RTF (Real-Time Factor)** | **~0.51** | Mất ~0.51 giây tính toán cho mỗi 1 giây âm thanh (nhanh gấp đôi realtime!). |
| **Độ trễ Warm Container** | ~4.2s | Xử lý xong toàn bộ đoạn audio 8.4s trong chỉ 4.2 giây. |
| **Độ trễ Cold Start** | ~5-7s | Thời gian boot container lần đầu khi đang ở trạng thái ngủ. |

---

## Xử lý sự cố thường gặp (FAQ)

### 1. Gặp lỗi `401 Unauthorized: modal-http: missing credentials for proxy authorization`?
- **Nguyên nhân:** Request của bạn chưa đính kèm Token hoặc Token không chính xác.
- **Khắc phục:** Đảm bảo thêm header `Authorization: Bearer <Token_ID>.<Token_Secret>` (chuỗi dạng `wk-xxx.ws-yyy` tạo từ lệnh `modal workspace proxy-tokens create`).

### 2. Làm thế nào để tạo thêm hoặc xóa Proxy Token?
- Liệt kê các token: `modal workspace proxy-tokens list`
- Tạo token mới: `modal workspace proxy-tokens create --name <tên>`
- Xóa token: `modal workspace proxy-tokens delete <Token_ID>`

### 3. Container có bị tính phí khi có kẻ xấu spam request sai vào URL không?
- **Không!** Nhờ cơ chế `requires_proxy_auth=True`, Modal Edge Reverse Proxy chặn ngay lập tức các request không có token hợp lệ. Container của bạn hoàn toàn không bị đánh thức và không phát sinh bất kỳ chi phí CPU/RAM nào.

---

## Ghi công

- Mô hình âm thanh: [VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS) bởi tác giả Phạm Nguyễn Ngọc Bảo (`pnnbao-ump`).
- Bộ suy luận C++ GGML: [audio.cpp](https://github.com/0xshug0/audio.cpp).
- Nền tảng Serverless: [Modal Labs](https://modal.com).
