# VieNeu-TTS v3 Turbo GGUF on Modal & Docker (audio.cpp C++ Engine)

Triển khai **VieNeu-TTS v3 Turbo GGUF** — mô hình Text-to-Speech (TTS) tiếng Việt chất lượng cao chạy trên C++ runtime **audio.cpp** — thành một **Serverless / Standalone Container API tương thích chuẩn OpenAI Audio Speech**, với **25 preset giọng đọc chính thức** (mặc định: **Minh Quân Pro**, cùng Ngọc Huyền, Mai Anh, Thùy Dung, Quang Sơn, v.v.).

Hệ thống sử dụng **trọng số GGUF chính thức từ tác giả Phạm Nguyễn Ngọc Bảo (188 MB)** với MOSS Neural Codec giữ nguyên định dạng `f16` đạt 36.0 dB SNR (+4 dB SNR so với các bản nén thông thường, triệt tiêu hoàn toàn rè tiếng), nạp model tức thì (<0.01s) và tốc độ sinh cực nhanh (RTF ~0.73 - 0.82 trên 4 vCPU, nhanh gấp 1.2x - 1.35x thời gian thực).

> 💡 **Ước tính chi phí với cấu hình mặc định (2 CPU + 2 GiB RAM, Base Price 1.0× trên Modal):**
> - Đơn giá: CPU `$0.0000131/core/giây`, RAM `$0.00000222/GiB/giây` ≈ **`$0.0000306/giây`** (~`$0.110/giờ`).
> - Với RTF ~0.73 - 0.82, mỗi câu nói 3.5 giây chỉ mất **~2.5 - 2.8 giây compute**!
> - **$30 credit/tháng** đủ cho **~350.000 câu đọc** (hoàn toàn không cần GPU đắt đỏ).

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
- [Triển khai bằng Docker & VPS (Tối ưu cho OCI ARM64)](#triển-khai-bằng-docker--vps-tối-ưu-cho-oci-arm64)
  - [Chạy nhanh bằng Docker Compose](#chạy-nhanh-bằng-docker-compose)
  - [Build Docker Image cục bộ](#build-docker-image-cục-bộ)
  - [Cấu hình trên VPS OCI Ampere A1 (ARM64)](#cấu-hình-trên-vps-oci-ampere-a1-arm64)
  - [Tự động hóa Multi-Arch Build bằng GitHub Actions](#tự-động-hóa-multi-arch-build-bằng-github-actions)
- [Hướng dẫn sử dụng](#hướng-dẫn-sử-dụng)
  - [Trải nghiệm qua WebUI nhúng sẵn (Trình duyệt)](#trải-nghiệm-qua-webui-nhúng-sẵn-trình-duyệt)
  - [Xác định Base URL của bạn](#xác-định-base-url-của-bạn)
  - [Health check](#health-check)
  - [Xem trước âm vị IPA (`/v1/audio/phonemize`)](#xem-trước-âm-vị-ipa-v1audiophonemize)
  - [Danh mục 25 giọng đọc (`/v1/audio/voices`)](#danh-mục-25-giọng-đọc-v1audiovoices)
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
- 📦 **Trọng số GGUF Chính Thức (188 MB)**: Tải từ `pnnbao-ump/VieNeu-TTS-v3-Turbo` với Q8_0 talker backbone và Codec MOSS `f16` chất lượng cao (+4 dB SNR so với các bản nén thông thường).
- 🎙️ **25 Preset Giọng Đọc Đa Dạng**: Hỗ trợ đầy đủ 25 preset giọng chính thức qua 3 miền Bắc - Trung - Nam, mặc định là **Minh Quân Pro** (`minh_quan_pro`). Đổi giọng tức thì theo từng request mà không cần nạp lại model.
- 🖥️ **WebUI Nhúng Sẵn**: Giao diện người dùng trực quan, chọn 25 giọng theo vùng miền, nghe thử trực tiếp trong trình duyệt tại `/` hoặc `/ui`.
- 🔄 **Tự động G2P (Phonemizer)**: Tích hợp proxy chuyển đổi văn bản tiếng Việt tự nhiên sang chuỗi âm vị IPA trong ~1-2ms qua `sea-g2p`.
- 🔌 **Chuẩn OpenAI Compatible**: Hỗ trợ route `/v1/audio/speech`, `/v1/models`, `/v1/audio/voices` — tương thích trực tiếp với OpenAI SDK, Dify, NextChat, Open WebUI.
- 🌊 **Streaming Audio**: Hỗ trợ truyền stream chunked WAV hoặc SSE theo chuẩn OpenAI.
- 🗣️ **Hỗ trợ đa định dạng**: Mặc định `wav` (chất lượng 48 kHz cao cấp) hoặc `mp3`, `opus`, `aac`, `flac` (chuyển đổi qua `ffmpeg`).
- 🔐 **Bảo mật**: Xác thực Bearer Token (`API_KEY`).
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

## Triển khai bằng Docker & VPS (Tối ưu cho OCI ARM64)

Ngoài việc chạy Serverless trên Modal, bạn hoàn toàn có thể tự lưu trữ (self-host) server trên VPS riêng hoặc máy cá nhân bằng Docker. Ứng dụng đã được đóng gói sẵn kiến trúc tiến trình kép (C++ backend `audio.cpp` + FastAPI gateway), hỗ trợ đầy đủ các kiến trúc **`linux/arm64` (đặc biệt tối ưu cho Oracle Cloud Ampere A1)** và **`linux/amd64`**.

### Chạy nhanh bằng Docker Compose

Khởi động server chỉ với 1 lệnh:

```bash
# Đặt API_KEY (tùy chọn) và số luồng CPU (khuyến nghị 4 cho OCI Ampere A1)
export API_KEY="my-secret-key-123"
export THREADS=4

docker compose up -d
```

Kiểm tra log container:
```bash
docker compose logs -f
```

### Build Docker Image cục bộ

Nếu muốn tự build image trên máy của bạn:

```bash
docker build -t vieneu-tts:latest .

# Chạy container
docker run -d \
  -p 8000:8000 \
  -e API_KEY="my-secret-key-123" \
  -e THREADS=4 \
  --name vieneu-tts \
  vieneu-tts:latest
```

### Cấu hình trên VPS OCI Ampere A1 (ARM64)

Máy ảo Oracle Cloud Infrastructure (OCI) Ampere A1 (Free Tier cung cấp tới 4 OCPU, 24 GB RAM) là nền tảng cực kỳ lý tưởng để host VieNeu-TTS:

1. **Mở cổng 8000 trên OCI Security List (VCN)**:
   - Vào OCI Console > **Networking** > **Virtual Cloud Networks** > Chọn VCN và Subnet của bạn.
   - Chọn **Default Security List** > **Add Ingress Rules**:
     - Source CIDR: `0.0.0.0/0`
     - IP Protocol: `TCP`
     - Destination Port Range: `8000`
2. **Mở cổng trong firewall nội bộ của VM (Ubuntu)**:
   ```bash
   sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8000 -j ACCEPT
   sudo netfilter-persistent save
   # Hoặc nếu dùng ufw:
   sudo ufw allow 8000/tcp
   ```
3. **Chạy server với 4 threads**:
   ```bash
   THREADS=4 API_KEY="your-key" docker compose up -d
   ```
   > 💡 Với 4 nhân ARM Neoverse-N1 và tập lệnh ARM NEON, tốc độ RTF đạt ~0.2x (câu đọc 3.5 giây chỉ mất ~0.7s để sinh âm thanh).

### Tự động hóa Multi-Arch Build bằng GitHub Actions

Repo đã cấu hình sẵn workflow [`.github/workflows/docker-build.yml`](.github/workflows/docker-build.yml):
- Tự động kích hoạt khi push vào nhánh `main` hoặc gắn thẻ phiên bản (`v*.*.*`).
- Sử dụng QEMU và Docker Buildx để build song song cho cả hai kiến trúc `linux/amd64` và `linux/arm64`.
- Tự động đẩy image lên GitHub Container Registry (GHCR): `ghcr.io/<tên-user-hoặc-org>/vieneu-tts-modal:latest`.
- Để sử dụng image dựng sẵn từ GHCR trên VPS:
  ```bash
  docker pull ghcr.io/<tên-user>/vieneu-tts-modal:latest
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

## Hướng dẫn sử dụng

### Trải nghiệm qua WebUI nhúng sẵn (Trình duyệt)

Hệ thống đã tích hợp sẵn một **WebUI hiện đại, siêu nhẹ** (không cần cài thêm Gradio hay Streamlit):

- 🌐 Mở trình duyệt và truy cập:
  - Khi chạy Docker: `http://localhost:8000/` (hoặc `http://<ip-vps>:8000/ui`)
  - Khi chạy Modal: `https://<your-workspace>--vieneu-tts-v3-turbo-web-app.modal.run/`
- ✨ **Tính năng nổi bật:**
  - 📝 **Nhập văn bản tiếng Việt**: Có kèm các nút câu mẫu (chào hỏi, thời tiết, cảm xúc `[cười]`, `[thở dài]`).
  - 🎚️ **Tùy chỉnh tốc độ & định dạng**: Điều chỉnh thanh trượt tốc độ (0.5x - 2.0x) và chọn xuất âm thanh (`WAV`, `MP3`, `Opus`, `AAC`, `FLAC`).
  - 🔊 **Trình phát Audio HTML5**: Tự động phát âm thanh ngay khi sinh xong kèm nút tải file về máy.
  - 🔤 **Xem trước âm vị IPA**: Hiển thị chính xác chuỗi âm vị IPA sau khi được chuẩn hóa qua `sea-g2p`.
  - 🔑 **Lưu trữ API Key**: Tự động lưu Bearer Token trong trình duyệt (localStorage) nếu server của bạn có bật bảo mật.

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

### Xem trước âm vị IPA (`/v1/audio/phonemize`)

Xem chuỗi âm vị IPA mà mô hình VieNeu-TTS nhận vào sau khi chuẩn hóa tiếng Việt:

```bash
curl "$BASE_URL/v1/audio/phonemize" \
  -H "Content-Type: application/json" \
  -d '{"input": "Hôm nay tôi rất vui [cười]"}'
```

Kết quả:
```json
{
  "input": "Hôm nay tôi rất vui [cười]",
  "phonemes": "hˈom nˈaj t̪ˈoj ɹˈəɜt̪ vˈuj <|emotion_1|>."
}
```

### Danh mục 25 giọng đọc (`/v1/audio/voices`)

API cung cấp đầy đủ 25 preset giọng đọc chính thức từ tác giả VieNeu-TTS v3 Turbo:

```bash
curl "$BASE_URL/v1/audio/voices" \
  -H "Authorization: Bearer $API_KEY"
```

Kết quả mẫu:
```json
{
  "object": "list",
  "default": "minh_quan_pro",
  "total": 25,
  "voices": [
    {"id": "minh_quan_pro", "name": "Minh Quân Pro", "label": "⭐ Minh Quân Pro — Nam · Bắc · Phong cách tự nhiên"},
    {"id": "ngoc_huyen", "name": "Ngọc Huyền", "label": "⭐ Ngọc Huyền — Nữ · Bắc · Giọng đọc tự nhiên"},
    {"id": "mai_anh", "name": "Mai Anh", "label": "⭐ Mai Anh — Nữ · Bắc · Phong cách tin tức"},
    {"id": "thuy_dung", "name": "Thùy Dung", "label": "⭐ Thùy Dung — Nữ · Nam · Phong cách tin tức"},
    {"id": "quang_son", "name": "Quang Sơn", "label": "⭐ Quang Sơn — Nam · Trung · Phong cách tự nhiên"}
  ]
}
```

#### Bảng danh sách 25 giọng đọc chính thức:

| Vùng miền | Giọng nam | Giọng nữ |
| :--- | :--- | :--- |
| **Miền Bắc** | **`minh_quan_pro`** *(Mặc định)*, `anh_khoi`, `adam_bua`, `thien_tam_duc`, `minh_duc`, `pham_tuyen`, `xuan_vinh`, `thanh_binh`, `manh_dung` | `ngoc_huyen`, `mai_anh`, `truc_ly`, `ngoc_linh`, `doan_trang`, `quynh_anh` |
| **Miền Trung** | `quang_son` | `ngoc_tran` |
| **Miền Nam** | `thai_son`, `minh_triet`, `duc_tri`, `adam` | `thuy_dung`, `thuc_doan`, `my_duyen`, `kim_thanh` |

> 💡 **Tương thích OpenAI**: Các tên giọng chuẩn của OpenAI (`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`, `ash`, `coral`, `sage`, `verse`) đều được tự động ánh xạ thông minh sang các preset tiếng Việt tương ứng.

### Tạo file âm thanh (WAV / MP3)

**Xuất file WAV chuẩn giọng Minh Quân Pro (mặc định):**

```bash
curl "$BASE_URL/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vieneu-v3-turbo",
    "input": "Xin chào, đây là giọng đọc tiếng Việt chạy trên hạ tầng C++ siêu tốc độ.",
    "voice": "minh_quan_pro",
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
