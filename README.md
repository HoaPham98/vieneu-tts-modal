# VieNeu-TTS v3 Turbo on Modal

Deploy **VieNeu-TTS v3 Turbo** — engine TTS tiếng Việt (ONNX Runtime) — lên [Modal](https://modal.com) dưới dạng **serverless API tương thích OpenAI**, tận dụng gói **Starter với $30 credit miễn phí mỗi tháng**.

> **Vì sao dùng gói Starter?**
> Modal Starter tặng **$30 compute credit mỗi tháng** (tạo tài khoản miễn phí) và serverless nghĩa là **chỉ trả tiền khi có request** — container tự scale về 0 khi rảnh nên credit không bị "đốt" lúc không dùng.
> Đơn giá cơ bản: CPU `$0.0000131/core/giây`, RAM `$0.00000222/GiB/giây`. Cấu hình mặc định **4 core + 4 GiB** ≈ `$0.0000613/giây`. Tuy nhiên `region="us-east"` là region **hẹp** nên bị nhân **1.75×** ⇒ thực tế ≈ `$0.000107/giây` (~`$0.39/giờ`), tức **$30 đủ cho ~77 giờ** compute mỗi tháng.
> Đổi `region` sang dạng **broad** (`"us"`) chỉ còn **1.15×**, tiết kiệm ~34% và cold start tốt hơn.
> Đăng ký: <https://modal.com/signup> — xem thêm [Modal Pricing](https://modal.com/pricing) và [Region selection](https://modal.com/docs/guide/region-selection).

---

## Mục lục

- [Tính năng](#tính-năng)
- [Yêu cầu](#yêu-cầu)
- [Cấu trúc repo](#cấu-trúc-repo)
- [Cài đặt lần đầu](#cài-đặt-lần-đầu)
- [Deploy](#deploy)
- [Sử dụng API](#sử-dụng-api)
- [Cấu hình](#cấu-hình)
- [Tối ưu chi phí với gói Starter](#tối-ưu-chi-phí-với-gói-starter)
- [CI/CD với GitHub Actions](#cicd-với-github-actions)
- [Xử lý sự cố](#xử-lý-sự-cố)

---

## Tính năng

- 🎙️ **VieNeu-TTS v3 Turbo** chạy trên ONNX Runtime (CPU) hoặc PyTorch (GPU).
- 🔌 **API tương thích OpenAI** — dùng được với SDK OpenAI, `curl`, hoặc bất kỳ client nào hỗ trợ `POST /v1/audio/speech`.
- ⚡ **Ép INT8 + VNNI**: tự động từ chối node CPU không có tập lệnh VNNI (`avx512_vnni` / `avx_vnni`) để Modal cấp node mới hơn ⇒ nhanh hơn nhiều.
- 📸 **Memory Snapshot**: model được nạp sẵn vào RAM và "đóng băng" bằng `enable_memory_snapshot=True` ⇒ cold start gần như tức thì (không phải load lại model).
- 🌊 **Streaming thật**: hỗ trợ SSE (`stream_format="sse"`), WAV chunked, và PCM thô — audio phát ra ngay khi đang sinh, không cần chờ hết câu.
- 🗣️ **Đa dạng định dạng**: `wav`, `pcm`, `mp3`, `opus`, `aac`, `flac` (mp3/opus/aac/flac qua `ffmpeg`).
- 🎚️ **Đổi tốc độ đọc** (`speed`) và **sample rate** (`24000` / `48000`).
- 🔐 **Bảo vệ bằng API key** (Bearer token) qua Modal Secret.
- 🤖 **Tự động deploy** bằng GitHub Actions mỗi lần push lên `main`.

---

## Yêu cầu

| Thành phần | Ghi chú |
|---|---|
| Python | 3.11+ (để chạy `modal` CLI local) |
| Tài khoản Modal | Gói **Starter** (miễn phí, có $30 credit/tháng) |
| `modal` CLI | `pip install modal` |
| Modal Secret `vieneu-api-key` | Chứa biến `API_KEY` để bảo vệ API |
| (CI/CD) GitHub repo + secrets | `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET` |

---

## Cấu trúc repo

```
.
├── modal_app.py                     # Toàn bộ app: image build, model loading, FastAPI routes
├── .github/workflows/deploy-modal.yml  # CI/CD: push lên main ⇒ deploy lên Modal (production)
├── ruff.toml                        # Cấu hình lint cho CI
└── .gitignore
```

---

## Cài đặt lần đầu

### 1. Cài Modal CLI và đăng nhập

```bash
pip install modal
modal setup          # mở trình duyệt để xác thực với tài khoản Modal
```

`modal setup` sẽ tạo sẵn file `~/.modal.toml` với token của bạn.

### 2. Tạo Modal Secret chứa API key

API key dùng để bảo vệ endpoint (`Authorization: Bearer <API_KEY>`). Nếu secret **không tồn tại**, app sẽ crash lúc khởi động vì `modal.Secret.from_name("vieneu-api-key")`.

```bash
# Gói Starter dùng một environment duy nhất ("main") = production
modal secret create vieneu-api-key API_KEY="doi-key-bao-mat-cua-ban"
```

> Không cần cờ `--env`: secret sẽ nằm trong environment mặc định (`main`).
> Để app chạy **không cần xác thực**, tạo secret với `API_KEY=""` — code sẽ tự bỏ qua bước kiểm tra.

### 3. Kiểm tra biến cấu hình trong `modal_app.py`

```python
USE_GPU = False       # False = CPU (rẻ, hợp gói Starter) | True = GPU T4
REQUIRE_INT8 = True   # True = chỉ nhận node CPU có VNNI (khuyến nghị)
```

---

## Deploy

### Deploy thủ công

```bash
# Deploy thẳng lên production (environment mặc định "main")
modal deploy modal_app.py
```

Lần deploy **đầu tiên** sẽ build image: cài `ffmpeg`, `espeak-ng`, `vieneu`, rồi chạy `download_models()` để tải sẵn trọng số v3 Turbo và gỡ toàn bộ symlink. Bước này mất **~10–20 phút**. Các lần deploy sau nhanh hơn nhiều nhờ cache layer của Modal.

Khi xong, CLI in ra URL dạng:

```
https://<workspace>--vieneu-tts-v3-turbo-web-app.modal.run
```

### Chạy thử tạm thời (không deploy chính thức)

```bash
# Tạo app ephemeral có URL -dev, tự tắt khi Ctrl+C
modal serve modal_app.py
```

### Xem log & quản lý

```bash
modal app list                        # Liệt kê app đã deploy
modal app logs vieneu-tts-v3-turbo    # Xem log realtime
modal app stop vieneu-tts-v3-turbo    # Dừng app
```

---

## Sử dụng API

Đặt biến cho tiện:

```bash
export BASE_URL="https://<workspace>--vieneu-tts-v3-turbo-web-app.modal.run"
export API_KEY="doi-key-bao-mat-cua-ban"
```

### Health check

```bash
curl "$BASE_URL/"
```

```json
{
  "status": "ok",
  "auth_enabled": true,
  "engine": "CPU (ONNX Runtime)",
  "precision": "int8",
  "cpu_model": "Intel(R) Xeon(R) ...",
  "stream_sample_rate": 24000,
  "endpoints": ["/v1/models", "/v1/audio/voices", "/v1/voices", "/v1/audio/speech"]
}
```

### Liệt kê giọng đọc

```bash
curl "$BASE_URL/v1/audio/voices" -H "Authorization: Bearer $API_KEY"
```

> 📌 Lấy ID giọng thật từ endpoint này rồi thay vào trường `voice` ở các ví dụ bên dưới. Nếu bỏ trống `voice`, app dùng giọng đầu tiên trong danh sách.

### Tổng hợp giọng nói (non-streaming → file WAV)

```bash
curl "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "model": "vieneu-v3-turbo",
        "input": "Xin chào, đây là VieNeu TTS phiên bản ba turbo.",
        "voice": "Minh Quân",
        "response_format": "wav"
      }' \
  --output out.wav
```

### Xuất MP3 (qua ffmpeg)

```bash
curl "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input":"Chuyển sang MP3 nhé.","response_format":"mp3"}' \
  --output out.mp3
```

### Streaming PCM thô (độ trễ thấp nhất)

```bash
curl -N "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input":"Câu này phát ra ngay khi đang sinh.","response_format":"pcm","stream":true}' \
  --output out.pcm
```

### Streaming SSE (giống OpenAI Realtime)

```bash
curl -N "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input":"Nội dung dài sẽ được trả về theo từng chunk base64.","stream_format":"sse"}'
```

Mỗi event trả về:

```
event: speech.audio.delta
data: {"type":"speech.audio.delta","audio":"<base64 pcm16>"}

event: speech.audio.done
data: {"type":"speech.audio.done","usage":{"input_tokens":9,"output_tokens":1234,"total_tokens":1243}}
```

### Dùng với SDK OpenAI (Python)

```python
from openai import OpenAI

client = OpenAI(base_url=f"{BASE_URL}/v1", api_key=API_KEY)

with client.audio.speech.with_streaming_response.create(
    model="vieneu-v3-turbo",
    voice="Minh Quân",
    input="Xin chào từ OpenAI SDK!",
    response_format="wav",
) as response:
    response.stream_to_file("hello.wav")
```

### Bảng tham số `POST /v1/audio/speech`

| Trường | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `input` | string | *(bắt buộc)* | Văn bản cần đọc |
| `voice` | string | giọng đầu tiên | ID/description của giọng, hoặc alias kiểu OpenAI (`alloy`, `nova`, ...) |
| `model` | string | `vieneu-v3-turbo` | Chấp nhận cả `gpt-4o-mini-tts`, `tts-1`, `tts-1-hd` |
| `response_format` | enum | `wav` | `wav`, `pcm`, `mp3`, `opus`, `aac`, `flac` |
| `sample_rate` | int | `24000` | `24000` hoặc `48000` |
| `speed` | float | `1.0` | Đổi tốc độ đọc (resampling) |
| `stream` | bool | `false` | `true` ⇒ trả về chunked stream |
| `stream_format` | enum | `null` | `sse` (Server-Sent Events) hoặc `audio` |
| `instructions` | string | `null` | Được chấp nhận để tương thích OpenAI (hiện chưa dùng) |

> 💡 Các alias giọng kiểu OpenAI (`alloy`, `echo`, `nova`, ...) đều được map về giọng mặc định của VieNeu.

---

## Cấu hình

Các thông số chính nằm ở đầu `modal_app.py` và trong decorator `@app.cls`:

| Cấu hình | Vị trí | Mặc định | Ghi chú |
|---|---|---|---|
| `USE_GPU` | `modal_app.py` | `False` | `True` ⇒ dùng **GPU T4**, RAM 4096 MiB, precision `fp16/cuda` |
| `REQUIRE_INT8` | `modal_app.py` | `True` | Từ chối node CPU không có VNNI để Modal cấp node tốt hơn |
| `cpu` | `compute_config` | `4.0` | Số physical core (1 core = 2 vCPU), chỉ khi `USE_GPU = False` |
| `memory` | `compute_config` | `4096` MiB | RAM |
| `region` | `compute_config` | `us-east` | Region chạy container. `us-east`/`us-west`/... là region **hẹp** ⇒ giá ×**1.75**; dạng broad (`"us"`, `"eu"`, `"ap"`) chỉ ×**1.15** |
| `scaledown_window` | `@app.cls` | `60` giây | Giữ container sống 60s sau request cuối (đổi lấy cold start nhanh hơn) |
| `max_inputs` | `@modal.concurrent` | `2` | Số request đồng thời mỗi container |
| `OMP_NUM_THREADS` | `.env()` | `4` | Số thread ONNX Runtime |

**Khuyến nghị:**
- Giữ số thread ONNX khớp với CPU. Lưu ý `cpu=4.0` là **4 physical core (= 8 vCPU)**; có thể giảm `cpu`/`OMP_NUM_THREADS` xuống `2` để rẻ hơn ~50% nếu chấp nhận chậm hơn.
- **Bỏ hẳn `region` khỏi `compute_config`** để trả đúng giá cơ bản (không bị nhân 1.15×/1.75×) — đây là cách tiết kiệm credit dễ nhất nếu không cần ghim vùng.

---

## Tối ưu chi phí với gói Starter

Gói Starter chỉ có **$30/tháng**, nên vài mẹo sau giúp credit kéo dài:

1. **Giữ `USE_GPU = False`.** GPU T4 tốn `$0.000164/giây` — gấp **~2,7 lần** cấu hình CPU 4 core + 4 GiB (`$0.0000613/giây`) ở cùng mức nhân region. Chỉ bật GPU nếu cần latency cực thấp.
2. **Bỏ hoặc nới `region`.** Hiện tại `region="us-east"` bị nhân **1.75×** (broad `"us"` chỉ **1.15×**). Bỏ hẳn `region` để trả giá cơ bản ⇒ tiết kiệm tới **~43%** và cold start nhanh hơn (pool node lớn hơn).
3. **Để `enable_memory_snapshot=True`.** Snapshot giúp cold start nhanh nên bạn không cần `scaledown_window` lớn để "giữ nóng" container.
4. **Giảm `scaledown_window`** (ví dụ `30`) nếu traffic thưa — container tắt sớm hơn ⇒ ít tốn credit lúc rảnh.
5. **Theo dõi usage** ở <https://modal.com/settings/usage> — Starter có log retention **1 ngày** và **200 app** đã deploy.
6. **Ước lượng nhanh:** với `region="us-east"` (×1.75), $30 ÷ `$0.000107/giây` ≈ **77 giờ** compute CPU mỗi tháng. Nếu bỏ `region` (giá cơ bản) thì ≈ **136 giờ**. Với ~2s mỗi câu TTS ⇒ khoảng **140.000–245.000 request/tháng**.

Nếu vượt hạn mức credit, compute sẽ **tạm dừng** cho tới chu kỳ sau — trừ khi bạn đã nâng cấp gói hoặc thêm phương thức thanh toán.

---

## CI/CD với GitHub Actions

Repo kèm workflow `.github/workflows/deploy-modal.yml`: mỗi lần push lên nhánh `main` (hoặc chạy tay qua `workflow_dispatch`) sẽ:

1. Checkout code
2. Cài Python 3.11 + `ruff` + `modal`
3. `python -m py_compile modal_app.py` (kiểm tra cú pháp)
4. `ruff check modal_app.py` (lint)
5. `modal deploy modal_app.py` → **production** (environment mặc định `main`)

### Thiết lập

**Bước 1 — Lấy Modal token**

Vào <https://modal.com/settings/tokens> → **Create new token** → lưu lại `Token ID` và `Token Secret`.

**Bước 2 — Thêm GitHub Secrets**

Repo → *Settings* → *Secrets and variables* → *Actions* → **New repository secret**:

| Secret | Giá trị |
|---|---|
| `MODAL_TOKEN_ID` | Token ID vừa tạo |
| `MODAL_TOKEN_SECRET` | Token Secret vừa tạo |

**Bước 3 — Đảm bảo Modal Secret `vieneu-api-key` tồn tại (production)**

```bash
modal secret create vieneu-api-key API_KEY="doi-key-bao-mat-cua-ban"
```

**Bước 4 — Push**

```bash
git add .
git commit -m "chore: add CI/CD"
git push origin main
```

Theo dõi tiến trình ở tab **Actions** của repo. Job có `timeout-minutes: 60` để đủ thời gian build image lần đầu.

> ⚠️ **Lưu ý:** workflow deploy thẳng vào **production** mỗi lần push lên `main`. Gói Starter chỉ có 1 environment, không có `dev`/`staging` tách biệt — hãy test bằng `modal serve modal_app.py` (chạy local, tạo URL tạm `-dev`) trước khi merge vào `main`. Ngoài ra gói Starter **không có deployment rollback** (tính năng đó chỉ có từ gói Team).

---

## Xử lý sự cố

| Vấn đề | Nguyên nhân & cách xử lý |
|---|---|
| App crash: *Secret 'vieneu-api-key' not found* | Chưa tạo Modal Secret, hoặc tạo sai environment. Chạy `modal secret create vieneu-api-key API_KEY="..." --env <env>`. |
| Bị **từ chối node liên tục**, log in `⚠️ Node hiện tại không có VNNI` | `REQUIRE_INT8 = True` đang chờ node Intel Xeon / AMD Zen 4+. Modal sẽ tự thử lại; nếu kéo dài, đổi `REQUIRE_INT8 = False` để chấp nhận `fp32` (chậm hơn). |
| Deploy lần đầu rất lâu (>15 phút) | Bình thường — đang tải trọng số VieNeu và gỡ symlink. Các lần sau dùng cache. |
| `401 Unauthorized` khi gọi API | Thiếu header `Authorization: Bearer <API_KEY>` hoặc key sai. |
| `ffmpeg` lỗi khi xin `mp3`/`opus`/`aac`/`flac` | `ffmpeg` được cài trong image; nếu lỗi, xem log `modal app logs`. |
| Muốn tắt xác thực khi test | Tạo secret với `API_KEY=""`, app sẽ bỏ qua kiểm tra. **Không dùng cho production.** |

---

## Ghi công

- Engine TTS: [VieNeu-TTS](https://pypi.org/project/vieneu/) (`pnnbao-ump`)
- Hạ tầng serverless: [Modal](https://modal.com)
