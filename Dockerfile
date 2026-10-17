# =====================================================================
# Dockerfile: VieNeu-TTS v3 Turbo Serverless-to-Container
# Hỗ trợ đa kiến trúc: linux/amd64 và linux/arm64 (OCI Ampere A1)
# =====================================================================

FROM ghcr.io/0xshug0/audio.cpp:full-cpu

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    THREADS=4 \
    PORT=8000 \
    BACKEND_PORT=8080

WORKDIR /app

# 1. Cài đặt Python và các công cụ hệ thống cần thiết
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    ffmpeg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt thư viện Python trong virtual environment chuyên dụng
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir "fastapi[standard]" "httpx" "sea-g2p>=0.10.0"

# 3. Copy thư mục preset voices mặc định (Ngọc Huyền)
COPY preset_voices /app/voices

# 4. Tải trọng số mô hình GGUF và config từ Hugging Face
RUN mkdir -p /app/models/VieNeu-TTS-v3-Turbo/speech_tokenizer && \
    BASE_URL="https://huggingface.co/phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF/resolve/main" && \
    echo "⏳ Đang tải file model.gguf (~163 MB)..." && \
    curl -sSfL -o /app/models/VieNeu-TTS-v3-Turbo/model.gguf "${BASE_URL}/model.gguf" && \
    curl -sSfL -o /app/models/VieNeu-TTS-v3-Turbo/config.json "${BASE_URL}/config.json" && \
    curl -sSfL -o /app/models/VieNeu-TTS-v3-Turbo/tokenizer.json "${BASE_URL}/tokenizer.json" && \
    curl -sSfL -o /app/models/VieNeu-TTS-v3-Turbo/tokenizer_config.json "${BASE_URL}/tokenizer_config.json" && \
    curl -sSfL -o /app/models/VieNeu-TTS-v3-Turbo/special_tokens_map.json "${BASE_URL}/special_tokens_map.json" && \
    curl -sSfL -o /app/models/VieNeu-TTS-v3-Turbo/speech_tokenizer/config.json "${BASE_URL}/speech_tokenizer/config.json" && \
    echo "✅ Tải trọng số mô hình hoàn tất."

# 5. Copy mã nguồn server và entrypoint
COPY server.py /app/server.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# 6. Khai báo port và healthcheck
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://127.0.0.1:8000/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
