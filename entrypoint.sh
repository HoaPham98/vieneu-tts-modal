#!/usr/bin/env bash
set -e

# =====================================================================
# VieNeu-TTS Standalone Entrypoint Script
# Quản lý tiến trình kép: audiocpp_server (C++) & Uvicorn (FastAPI)
# Tối ưu hóa cho VPS Linux x86_64 và OCI ARM64 (Ampere A1)
# =====================================================================

THREADS="${THREADS:-4}"
PORT="${PORT:-8000}"
BACKEND_PORT="${BACKEND_PORT:-8080}"
BACKEND_URL="http://127.0.0.1:${BACKEND_PORT}"
export BACKEND_URL

echo "=========================================================="
echo "🚀 Khởi động VieNeu-TTS v3 Turbo Container"
echo "   - Cấu trúc: Dual-process (audio.cpp + FastAPI Gateway)"
echo "   - CPU Threads: ${THREADS}"
echo "   - Cổng Public: ${PORT}"
echo "   - Cổng Backend C++: ${BACKEND_PORT}"
echo "=========================================================="

# 1. Sinh file cấu hình server.json cho audiocpp_server nếu chưa có hoặc cập nhật số luồng
cat <<EOF > /app/server.json
{
  "host": "127.0.0.1",
  "port": ${BACKEND_PORT},
  "backend": "cpu",
  "threads": ${THREADS},
  "models": [
    {
      "id": "vieneu-v3-turbo",
      "family": "vieneu_v3_turbo",
      "path": "/app/models/VieNeu-TTS-v3-Turbo/model.gguf",
      "task": "tts",
      "mode": "offline",
      "default_request_options": {
        "reference_codes_file": "/app/voices/minh_quan_pro/ref_codes.txt",
        "speaker_embedding_file": "/app/voices/minh_quan_pro/speaker.emb.txt"
      }
    }
  ]
}
EOF

# 2. Định vị binary audiocpp_server
SERVER_BIN="$(which audiocpp_server 2>/dev/null || true)"
if [ -z "$SERVER_BIN" ] && [ -x "/app/audiocpp_server" ]; then
  SERVER_BIN="/app/audiocpp_server"
fi

if [ -z "$SERVER_BIN" ]; then
  echo "⚠️ Không tìm thấy audiocpp_server trong PATH, thử dùng lệnh trực tiếp..."
  SERVER_BIN="audiocpp_server"
fi

# 3. Thiết lập trap tín hiệu tắt tiến trình an toàn
SERVER_PID=""
UVICORN_PID=""

cleanup() {
  echo ""
  echo "🛑 Nhận tín hiệu dừng, đang đóng các tiến trình..."
  if [ -n "$UVICORN_PID" ] && kill -0 "$UVICORN_PID" 2>/dev/null; then
    kill -TERM "$UVICORN_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
  fi
  wait 2>/dev/null || true
  echo "✅ Đã đóng sạch các tiến trình."
  exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# 4. Khởi động tiến trình C++ ngầm
echo "⚡ Đang khởi động audiocpp_server trên cổng nội bộ ${BACKEND_PORT}..."
"$SERVER_BIN" --config /app/server.json --backend cpu &
SERVER_PID=$!

# 5. Kiểm tra tính sẵn sàng (Healthcheck loop)
echo "⏳ Chờ backend C++ tải model và sẵn sàng..."
READY=0
for i in $(seq 1 40); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ audiocpp_server đã dừng đột ngột!"
    exit 1
  fi

  if curl -s -f "${BACKEND_URL}/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" -eq 1 ]; then
  echo "✅ audiocpp_server đã sẵn sàng phục vụ!"
else
  echo "⚠️ Cảnh báo: audiocpp_server chưa phản hồi kịp thời, tiếp tục khởi động FastAPI gateway..."
fi

# 6. Khởi động FastAPI / Uvicorn server ở foreground
echo "🌐 Bắt đầu lắng nghe API OpenAI TTS trên 0.0.0.0:${PORT}..."
exec uvicorn server:app --host 0.0.0.0 --port "${PORT}"
