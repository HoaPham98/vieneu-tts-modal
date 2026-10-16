# VieNeu-TTS v3 Turbo GGUF on Modal (audio.cpp C++ Engine)

Triển khai **VieNeu-TTS v3 Turbo GGUF** — mô hình Text-to-Speech (TTS) tiếng Việt chất lượng cao chạy trên C++ runtime **audio.cpp** — lên [Modal](https://modal.com) thành một **Serverless API tương thích chuẩn OpenAI Audio Speech**, với preset mặc định giọng đọc **Ngọc Huyền**.

Tận dụng gói **Starter miễn phí của Modal ($30 credit mỗi tháng)**, container tự động bật khi có request và scale về 0 khi không dùng. Với trọng số GGUF siêu nhẹ (163 MB) và engine C++ thuần, container khởi động và nạp model gần như tức thì (<0.01s), tốc độ sinh cực nhanh (RTF ~0.24 trên CPU, nhanh gấp 4.1x thời gian thực).

> 💡 **Ước tính chi phí với cấu hình mặc định (2 CPU + 2 GiB RAM, Base Price 1.0×):**
> - Đơn giá: CPU `$0.0000131/core/giây`, RAM `$0.00000222/GiB/giây` ≈ **`$0.0000306/giây`** (~`$0.110/giờ`).
> - Với RTF ~0.24, mỗi câu nói 3.5 giây chỉ mất **~0.85 giây compute**!
> - **$30 credit/tháng** đủ cho **~1.150.000 câu đọc** (tối ưu gấp đôi so với ONNX CPU thông thường).

---

## Mục lục

- [Tính năng nổi bật](#tính-năng-nổi-bật)
- [Yêu cầu chuẩn bị](#yêu-cầu-chuẩn-bị)
- [Cấu trúc repo](#cấu-trúc-repo)
- [Hướng dẫn thiết lập cho người mới (Quickstart)](#hướng-dẫn-thiết-lập-cho-người-mới-quickstart)
  - [Bước 1: Clone repo và tạo môi trường Python](#bước-1-clone-repo-và-tạo-môi-trường-python)
  - [Bước 2: Cài đặt và đăng nhập Modal CLI](#bước-2-cài-đặt-và-đăng-nhập-modal-cli)
  - [Bước 3: Tạo Modal Secret lưu API Key](#bước-3-tạo-modal-secret-lưu-api-key)
  - [Bước 4: Deploy lên Modal](#bước-4-deploy-lên-modal)
- [Tùy chọn: Tự động hóa CI/CD bằng GitHub Actions (Fork)](#tùy-chọn-tự-động-hóa-cicd-bằng-github-actions-fork)
- [Hướng dẫn sử dụng API](#hướng-dẫn-sử-dụng-api)
  - [Xác định Base URL của bạn](#xác-định-base-url-của-bạn)
  - [Health check](#health-check)
  - [Lấy danh sách giọng đọc](#lấy-danh-sách-giọng-đọc)
  - [Tạo file âm thanh (WAV / MP3)](#tạo-file-âm-thanh-wav--mp3)
  - [Streaming âm thanh](#streaming-âm-thanh)
  - [Tích hợp với SDK OpenAI (Python & TypeScript)](#tích-hợp-với-sdk-openai)
  - [Tích hợp vào các UI/Chatbot (Dify, NextChat, Open WebUI)](#tích-hợp-vào-các-uichatbot)
- [Bảng tham số API `POST /v1/audio/speech`](#bảng-tham-số-api-post-v1audiospeech)
- [Tùy chỉnh cấu hình](#tùy-chỉnh-cấu-hình)
- [Mẹo tối ưu chi phí & Credit](#mẹo-tối-ưu-chi-phí--credit)
- [Xử lý sự cố thường gặp (FAQ)](#xử-lý-sự-cố-thường-gặp-faq)
- [Ghi công](#ghi-công)

---

## Tính năng nổi bật

- ⚡ **audio.cpp C++ Engine**: Chạy mô hình VieNeu-TTS v3 Turbo hoàn toàn bằng C++ thuần (dựa trên `ggml`), nạp model bằng `mmap` tức thì (<0.01s), không phụ thuộc PyTorch lúc inference.
- 📦 **GGUF Quantization (163 MB)**: Nén gọn Qwen3 talker backbone và codec MOSS-Audio-Tokenizer-Nano vào một file GGUF 163 MB duy nhất (`phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF`).
- 🎙️ **Preset Giọng Ngọc Huyền**: Mặc định chất giọng chuẩn nữ miền Bắc, đọc diễn cảm tự nhiên với speaker embedding 192 chiều chuẩn xác.
- 🔄 **Tự động G2P (Phonemizer)**: Tích hợp proxy siêu nhẹ chuyển đổi văn bản tiếng Việt tự nhiên sang chuỗi âm vị IPA trong ~1ms mà không đòi hỏi client phải tự xử lý.
- 🔌 **Chuẩn OpenAI Compatible**: Hỗ trợ route `/v1/audio/speech`, `/v1/models`, `/v1/audio/voices` — tương thích trực tiếp với OpenAI SDK, Dify, NextChat, Open WebUI.
- 🌊 **Streaming Audio**: Hỗ trợ truyền stream chunked WAV trực tiếp để phát âm thanh ngay lập tức.
- 🗣️ **Hỗ trợ định dạng**: Mặc định `wav` (chất lượng 48 kHz cao cấp) hoặc `mp3` (tự động chuyển đổi bằng `ffmpeg`).
- 🔐 **Bảo mật**: Xác thực Bearer Token qua Modal Secret (`API_KEY`).
- 💰 **Chi phí tối ưu**: Chạy mượt mà trên 2 vCPU + 2 GiB RAM, không cần GPU đắt đỏ.


---

## Yêu cầu chuẩn bị

| Thành phần | Ghi chú |
|---|---|
| **Python** | 3.11+ (cài trên máy cá nhân để chạy lệnh `modal`) |
| **Tài khoản Modal** | [Đăng ký miễn phí tại modal.com](https://modal.com/signup) — nhận ngay $30 credit/tháng |
| **Git** | Để clone và quản lý mã nguồn |
| **(Tùy chọn) GitHub account** | Nếu muốn fork repo để tự động deploy qua GitHub Actions |

---

## Cấu trúc repo

```text
.
├── modal_app.py                     # Toàn bộ logic app: image build, model weights, FastAPI app
├── requirements.txt                 # Dependencies cho local CLI và CI (modal, ruff)
├── .github/workflows/deploy-modal.yml # CI/CD tự động deploy lên Modal khi push code
├── ruff.toml                        # Cấu hình lint code
└── README.md
```

---

## Hướng dẫn thiết lập cho người mới (Quickstart)

Chỉ với 4 bước đơn giản, bạn sẽ có ngay một endpoint TTS riêng cho mình:

### Bước 1: Clone repo và tạo môi trường Python

Mở terminal và clone repo về máy:

```bash
git clone https://github.com/HoaPham98/vieneu-tts-modal.git
cd vieneu-tts-modal
```

Khuyến nghị tạo một virtual environment riêng:

```bash
# Trên macOS / Linux:
python3 -m venv .venv
source .venv/bin/activate

# Trên Windows (PowerShell):
python -m venv .venv
.venv\Scripts\Activate.ps1
```

Cài đặt các gói phụ trợ cần thiết cho CLI:

```bash
pip install -r requirements.txt
```

### Bước 2: Cài đặt và đăng nhập Modal CLI

Chạy lệnh xác thực tài khoản:

```bash
modal setup
```

Trình duyệt sẽ tự động mở trang cấp quyền của Modal. Sau khi bạn đồng ý, file cấu hình token sẽ được tự động lưu vào máy (`~/.modal.toml`).

### Bước 3: Tạo Modal Secret lưu API Key

API này được bảo vệ bởi khóa Bearer Token. Bạn cần tạo một secret tên là `vieneu-api-key` trên Modal chứa biến `API_KEY`:

```bash
# Thay 'my-secret-key-123' bằng mật khẩu API bạn muốn đặt
modal secret create vieneu-api-key API_KEY="my-secret-key-123"
```

> 💡 **Mẹo:**
> - Nếu bạn muốn mở công khai API (không cần mật khẩu), hãy đặt `API_KEY=""`.
> - Bạn cũng có thể quản lý hoặc tạo Secret trực tiếp trên web tại [Modal Secrets Dashboard](https://modal.com/secrets).

### Bước 4: Deploy lên Modal

Chạy lệnh deploy chính thức:

```bash
modal deploy modal_app.py
```

> ⏳ **Lưu ý ở lần deploy đầu tiên:**
> Modal sẽ tiến hành build container image: tải Ubuntu, cài thư viện âm thanh (`ffmpeg`, `espeak-ng`), tải trọng số model VieNeu v3 Turbo (~300MB) và gỡ symlink. Quá trình này mất khoảng **10–15 phút**.
> Ở các lần deploy tiếp theo hoặc khi container khởi động lại, Modal sẽ sử dụng cache image và memory snapshot nên chỉ mất vài giây!

Sau khi deploy thành công, terminal sẽ in ra URL của ứng dụng, có dạng:

```text
✓ Created objects.
├── 🔨 Created web function web_app => https://<your-workspace>--vieneu-tts-v3-turbo-web-app.modal.run
```

---

## Tùy chọn: Tự động hóa CI/CD bằng GitHub Actions (Fork)

Nếu bạn muốn chỉnh sửa code và tự động deploy mỗi khi push lên GitHub:

1. **Fork** repository này về tài khoản GitHub của bạn.
2. Lấy Modal Token:
   - Truy cập [Modal Settings > Tokens](https://modal.com/settings/tokens) và chọn **Create new token**.
   - Lưu lại `Token ID` và `Token Secret`.
3. Cấu hình GitHub Secrets trong repo đã Fork:
   - Vào **Settings** > **Secrets and variables** > **Actions** > **New repository secret**.
   - Thêm 2 secret:
     - `MODAL_TOKEN_ID`: Điền Token ID từ Modal.
     - `MODAL_TOKEN_SECRET`: Điền Token Secret từ Modal.
4. Đảm bảo bạn đã tạo secret `vieneu-api-key` trên Modal (như ở Bước 3).
5. Mỗi khi bạn push commit lên nhánh `main`, GitHub Actions sẽ tự động kiểm tra cú pháp và deploy phiên bản mới nhất lên Modal!

---

## Hướng dẫn sử dụng API

### Xác định Base URL của bạn

URL API của bạn có định dạng:
```text
https://<workspace-name>--vieneu-tts-v3-turbo-web-app.modal.run
```
*(Trong đó `<workspace-name>` là tên tài khoản hoặc tên workspace Modal của bạn, xem tại góc trên bên trái của [modal.com/apps](https://modal.com/apps)).*

Đặt các biến môi trường tiện cho việc test:

```bash
export BASE_URL="https://<your-workspace>--vieneu-tts-v3-turbo-web-app.modal.run"
export API_KEY="my-secret-key-123"
```

### Health check

Kiểm tra trạng thái máy chủ, loại CPU và precision:

```bash
curl "$BASE_URL/"
```

Kết quả trả về:
```json
{
  "status": "ok",
  "auth_enabled": true,
  "engine": "CPU (ONNX Runtime)",
  "precision": "int8",
  "cpu_model": "Intel(R) Xeon(R) Platinum ...",
  "stream_sample_rate": 24000,
  "endpoints": ["/v1/models", "/v1/audio/voices", "/v1/voices", "/v1/audio/speech"]
}
```

### Lấy danh sách giọng đọc

```bash
curl "$BASE_URL/v1/audio/voices" \
  -H "Authorization: Bearer $API_KEY"
```

### Tạo file âm thanh (WAV / MP3)

**Xuất file WAV (mặc định):**

```bash
curl "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vieneu-v3-turbo",
    "input": "Xin chào, đây là giọng đọc tiếng Việt chạy trên hạ tầng serverless của Modal.",
    "voice": "Minh Quân",
    "response_format": "wav"
  }' \
  --output chao.wav
```

**Xuất file MP3 nén (dung lượng nhỏ gọn):**

```bash
curl "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": "File này được nén sang định dạng MP3 thông qua ffmpeg.",
    "response_format": "mp3"
  }' \
  --output out.mp3
```

### Streaming âm thanh thật (PCM / SSE)

- **Streaming PCM thô (độ trễ thấp nhất):**
  ```bash
  curl -N "$BASE_URL/v1/audio/speech" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"input":"Âm thanh phát ra ngay lập tức khi đang tạo.","response_format":"pcm","stream":true}' \
    --output stream.pcm
  ```

- **Streaming Server-Sent Events (SSE) theo chuẩn OpenAI Realtime:**
  ```bash
  curl -N "$BASE_URL/v1/audio/speech" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"input":"Văn bản dài được gửi về từng phần kèm thông tin token.","stream_format":"sse"}'
  ```

---

### Tích hợp với SDK OpenAI

Vì API hoàn toàn tương thích với đặc tả của OpenAI, bạn có thể sử dụng trực tiếp SDK chính thức của OpenAI:

#### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://<your-workspace>--vieneu-tts-v3-turbo-web-app.modal.run/v1",
    api_key="my-secret-key-123",
)

with client.audio.speech.with_streaming_response.create(
    model="vieneu-v3-turbo",
    voice="Minh Quân",
    input="Xin chào bạn, tôi là trợ lý ảo sử dụng giọng đọc VieNeu v3 Turbo!",
    response_format="wav",
) as response:
    response.stream_to_file("output.wav")
```

#### Node.js / TypeScript

```typescript
import OpenAI from "openai";
import fs from "fs";

const openai = new OpenAI({
  baseURL: "https://<your-workspace>--vieneu-tts-v3-turbo-web-app.modal.run/v1",
  apiKey: "my-secret-key-123",
});

async function main() {
  const response = await openai.audio.speech.create({
    model: "vieneu-v3-turbo",
    voice: "Minh Quân",
    input: "Xin chào từ ứng dụng NodeJS!",
    response_format: "mp3",
  });

  const buffer = Buffer.from(await response.arrayBuffer());
  await fs.promises.writeFile("output.mp3", buffer);
}

main();
```

---

### Tích hợp vào các UI/Chatbot

Các ứng dụng mã nguồn mở hỗ trợ tùy chỉnh Custom OpenAI TTS Endpoint như **NextChat, LibreChat, Dify, Open WebUI**:

- **API Base URL**: `https://<your-workspace>--vieneu-tts-v3-turbo-web-app.modal.run/v1`
- **API Key**: Khóa bạn đã đặt trong `vieneu-api-key`
- **Model**: `vieneu-v3-turbo` hoặc alias `tts-1`
- **Voice**: `Minh Quân` hoặc các alias như `alloy`, `nova`, `echo` (tất cả alias mặc định sẽ tự map về giọng chuẩn tiếng Việt).

---

## Bảng tham số API `POST /v1/audio/speech`

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `input` | string | *(bắt buộc)* | Văn bản tiếng Việt cần đọc |
| `voice` | string | Giọng đầu tiên | Tên giọng đọc (lấy từ `/v1/audio/voices`) hoặc alias OpenAI (`alloy`, `echo`, `nova`, ...) |
| `model` | string | `vieneu-v3-turbo` | Chấp nhận cả `tts-1`, `tts-1-hd`, `gpt-4o-mini-tts` |
| `response_format` | enum | `wav` | `wav`, `mp3`, `pcm`, `opus`, `aac`, `flac` |
| `sample_rate` | int | `24000` | Tần số lấy mẫu: `24000` hoặc `48000` Hz |
| `speed` | float | `1.0` | Tốc độ đọc (ví dụ: `0.75` là chậm, `1.25` là nhanh) |
| `stream` | bool | `false` | `true` để nhận chunked streaming |
| `stream_format` | enum | `null` | `sse` (Server-Sent Events) hoặc `audio` |

---

## Tùy chỉnh cấu hình

Các thông số phần cứng nằm ở phần đầu file [modal_app.py](modal_app.py):

```python
# modal_app.py
USE_GPU = False       # False: CPU ONNX (tiết kiệm, hợp gói Starter) | True: GPU Nvidia T4
REQUIRE_INT8 = True   # True: bắt buộc node CPU có tập lệnh VNNI để đạt tốc độ cao nhất
```

Và cấu hình tài nguyên container:

```python
# Cấu hình mặc định tối ưu chi phí
compute_config = {"cpu": 2.0, "memory": 2048}
```

| Cấu hình | Vị trí | Mặc định | Giải thích & Gợi ý |
|---|---|---|---|
| `cpu` | `compute_config` | `2.0` | 2 physical cores (= 4 vCPUs). Rất mượt và tối ưu cho INT8. |
| `memory` | `compute_config` | `2048` MiB | 2 GiB RAM, đáp ứng thoải mái cho model INT8. |
| `region` | `compute_config` | *(không set)* | Không set region để hưởng giá gốc 1.0×. Ghim `us-east` sẽ bị tính 1.75×. |
| `scaledown_window`| `@app.cls` | `60` giây | Thời gian giữ container sau khi hết request. Giảm xuống `15`-`30` nếu traffic ít. |
| `max_inputs` | `@modal.concurrent` | `2` | Số lượng request đồng thời phục vụ trên cùng 1 container. |

---

## Mẹo tối ưu chi phí & Credit

1. **Không đặt `region` cố định:** Modal thu thêm phụ thu khi bạn chỉ định cụ thể region (1.15× cho broad region và 1.75× cho narrow region). Không ghim region giúp bạn luôn được hưởng giá gốc rẻ nhất (1.0×).
2. **Tận dụng `enable_memory_snapshot=True`:** Snapshot giúp phục hồi container trong ~200ms, do đó bạn có thể giảm `scaledown_window` từ `60` xuống `15` hoặc `20` giây nếu các cuộc gọi API cách nhau khá xa.
3. **Chỉ dùng GPU khi thật sự cần:** GPU T4 tốn `$0.000164/giây` — đắt hơn gấp **~5.3 lần** so với cấu hình CPU 2 core + 2GB (`$0.0000306/giây`). Với INT8 trên CPU hiện đại, tốc độ đọc đã gần như tức thì.
4. **Theo dõi chi phí:** Xem chi tiết credit đã dùng tại [Modal Usage Settings](https://modal.com/settings/usage).

---

## Xử lý sự cố thường gặp (FAQ)

### 1. Lỗi: `Secret 'vieneu-api-key' not found`
- **Nguyên nhân:** Bạn chưa tạo secret trên Modal hoặc đặt sai tên.
- **Khắc phục:** Chạy lệnh:
  ```bash
  modal secret create vieneu-api-key API_KEY="mat-khau-cua-ban"
  ```

### 2. Quá trình deploy lần đầu mất hơn 10 phút?
- **Nguyên nhân:** Hoàn toàn bình thường! Modal cần tải image base, cài thư viện C++ audio (`ffmpeg`, `espeak-ng`), tải trọng số mô hình VieNeu v3 Turbo và tạo bản chụp memory snapshot.
- **Khắc phục:** Không tắt terminal, các lần deploy sau sẽ nhanh hơn gấp nhiều lần nhờ cache.

### 3. Log hiển thị `⚠️ Node hiện tại không có VNNI`
- **Nguyên nhân:** Node máy ảo Modal cấp ngẫu nhiên lúc build không có tập lệnh AVX-512 VNNI.
- **Khắc phục:** Code sẽ tự động `sys.exit(1)` để Modal cấp phát một node mới đời mới hơn (Intel Ice Lake/Sapphire Rapids hoặc AMD Zen 4). Nếu bạn gặp tình trạng này lặp lại quá nhiều lần, có thể tạm đặt `REQUIRE_INT8 = False` trong `modal_app.py`.

### 4. Lỗi `401 Unauthorized` khi gọi API
- Kiểm tra header: `Authorization: Bearer <API_KEY>` phải khớp chính xác với `API_KEY` bạn đặt trong secret `vieneu-api-key`.

---

## Ghi công

- Mô hình âm thanh: [VieNeu-TTS](https://pypi.org/project/vieneu/) bởi tác giả `pnnbao-ump`.
- Nền tảng Serverless: [Modal Labs](https://modal.com).
