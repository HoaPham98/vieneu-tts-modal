import base64
import io
import json
import os
import secrets
import shutil
import struct
import subprocess
import sys
from pathlib import Path
from typing import Literal, Optional
import modal

# =====================================================================
# CẤU HÌNH PHẦN CỨNG & ÉP INT8
# =====================================================================
USE_GPU = False
REQUIRE_INT8 = True  # Đặt True để ép Modal chỉ nhận node có VNNI (int8)

def patch_ort_symlinks():
    """Bọc trực tiếp onnxruntime.InferenceSession để biến mọi symlink trong thư mục
    chứa file .onnx và .data thành file thật (hardlink) ngay trước khi C++ engine mở file."""
    import onnxruntime as ort

    if getattr(ort.InferenceSession, "_is_patched", False):
        return

    _orig_init = ort.InferenceSession.__init__

    def _materialize_dir(directory: Path):
        if not directory.exists():
            return
        for item in list(directory.iterdir()):
            if item.is_symlink():
                target = item.resolve()
                if target.exists() and target.is_file():
                    item.unlink()
                    try:
                        os.link(target, item)
                    except OSError:
                        shutil.copy2(target, item)

    def _patched_init(self, path_or_bytes, sess_options=None, providers=None, **kwargs):
        if isinstance(path_or_bytes, (str, os.PathLike)):
            model_path = Path(path_or_bytes)
            _materialize_dir(model_path.parent)
            path_or_bytes = str(model_path)
        return _orig_init(self, path_or_bytes, sess_options=sess_options, providers=providers, **kwargs)

    ort.InferenceSession.__init__ = _patched_init
    ort.InferenceSession._is_patched = True

def download_models():
    """Hàm chạy 1 lần lúc build image để tải và gỡ symlink sẵn vào ổ cứng."""
    patch_ort_symlinks()
    from vieneu import Vieneu
    print("⏳ Đang tải sẵn trọng số VieNeu-TTS v3 Turbo vào Modal Image...")
    Vieneu(mode="v3turbo", precision="fp32")
    try:
        Vieneu(mode="v3turbo", precision="int8")
    except Exception:
        pass
    print("✅ Hoàn tất lưu cache model và gỡ bỏ toàn bộ symlink!")

# 1. Định nghĩa môi trường Container
if USE_GPU:
    image = (
        modal.Image.debian_slim(python_version="3.11")
        .apt_install("git", "curl", "ffmpeg", "espeak-ng", "libsndfile1")
        .pip_install(
            "torch", "torchaudio",
            "vieneu>=3.7.1", "fastapi[standard]", "soundfile", "numpy"
        )
        .run_function(download_models)
    )
    compute_config = {"gpu": "T4", "memory": 4096}
else:
    image = (
        modal.Image.debian_slim(python_version="3.11")
        .apt_install("git", "curl", "ffmpeg", "espeak-ng", "libsndfile1")
        .pip_install(
            "vieneu>=3.7.1", "fastapi[standard]", "soundfile", "numpy"
        )
        .env({
            "OMP_NUM_THREADS": "2",
            "ORT_INTRA_OP_NUM_THREADS": "2",
            "ORT_INTER_OP_NUM_THREADS": "1",
        })
        .run_function(download_models)
    )
    compute_config = {"cpu": 2.0, "memory": 2048}

app = modal.App("vieneu-tts-v3-turbo", image=image)

def make_streaming_wav_header(sample_rate: int = 24000, channels: int = 1, bits_per_sample: int = 16) -> bytes:
    """Tạo WAV header 44-byte với kích thước mở (0x7FFFFFFF) để phát trực tiếp qua HTTP chunked stream."""
    byte_rate = sample_rate * channels * (bits_per_sample // 8)
    block_align = channels * (bits_per_sample // 8)
    data_size = 0x7FFFFFFF
    return struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF",
        data_size + 36,
        b"WAVE",
        b"fmt ",
        16,
        1,
        channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
        b"data",
        data_size,
    )

# 2. Khởi tạo Service Serverless kèm Memory Snapshot & Region Pinning
@app.cls(
    **compute_config,
    secrets=[modal.Secret.from_name("vieneu-api-key")],
    scaledown_window=60,
    enable_memory_snapshot=True,  # Khóa cứng trạng thái RAM & kiến trúc CPU sau khi nạp int8
    max_inputs=None if hasattr(modal, "concurrent") else 2,
)
@modal.concurrent(max_inputs=2)
class VieNeuService:
    @modal.enter(snap=True)
    def load_model(self):
        patch_ort_symlinks()
        from vieneu import Vieneu

        if USE_GPU:
            self.precision = "fp16/cuda"
            self.tts = Vieneu(mode="v3turbo")
        else:
            cpuinfo = Path("/proc/cpuinfo").read_text().lower()
            # Kiểm tra tên CPU và cờ tập lệnh VNNI
            model_name = ""
            for line in cpuinfo.splitlines():
                if "model name" in line:
                    model_name = line.split(":", 1)[-1].strip()
                    break

            has_vnni = any(flag in cpuinfo for flag in ("avx512_vnni", "avx_vnni", "vnni"))
            print(f"🔍 [CPU Check] Node CPU: '{model_name}' | VNNI Support: {has_vnni}")

            if REQUIRE_INT8 and not has_vnni:
                print("⚠️ Node hiện tại không có VNNI (int8). Tự động từ chối node này để Modal cấp node Intel Xeon/Zen 4 mới...")
                sys.exit(1)

            self.precision = "int8" if has_vnni else "fp32"
            self.cpu_model = model_name
            self.tts = Vieneu(mode="v3turbo", precision=self.precision)

        raw_voices = self.tts.list_preset_voices()
        self.voice_list = []
        for v in raw_voices:
            if isinstance(v, (tuple, list)) and len(v) >= 2:
                desc, vid = str(v[0]), str(v[1])
            else:
                desc = vid = str(v)
            self.voice_list.append({"id": vid, "name": vid, "description": desc})

        print(f"📸 Đã khóa Memory Snapshot thành công! (Precision: {self.precision}, CPU: {getattr(self, 'cpu_model', 'GPU')})")

    @modal.asgi_app()
    def web_app(self):
        import numpy as np
        import soundfile as sf
        from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request, Security, status
        from fastapi.middleware.cors import CORSMiddleware
        from fastapi.responses import Response, StreamingResponse
        from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
        from pydantic import BaseModel

        web = FastAPI(title="VieNeu-TTS v3 Turbo OpenAI-Compatible API", version="1.3.0")

        web.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

        security = HTTPBearer(auto_error=False)
        EXPECTED_API_KEY = os.environ.get("API_KEY", "").strip()

        def verify_api_key(
            credentials: Optional[HTTPAuthorizationCredentials] = Security(security),
        ):
            if not EXPECTED_API_KEY:
                return
            if (
                credentials is None
                or credentials.scheme.lower() != "bearer"
                or not secrets.compare_digest(credentials.credentials, EXPECTED_API_KEY)
            ):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail={
                        "error": {
                            "message": "Incorrect API key provided. Pass 'Authorization: Bearer <API_KEY>'.",
                            "type": "invalid_request_error",
                            "param": None,
                            "code": "invalid_api_key",
                        }
                    },
                    headers={"WWW-Authenticate": "Bearer"},
                )

        v1_router = APIRouter(prefix="/v1", dependencies=[Depends(verify_api_key)])

        DEFAULT_VOICE = self.voice_list[0]["id"] if self.voice_list else "Minh Quân"
        OPENAI_VOICE_ALIAS = {
            "alloy": DEFAULT_VOICE,
            "echo": DEFAULT_VOICE,
            "fable": DEFAULT_VOICE,
            "onyx": DEFAULT_VOICE,
            "nova": DEFAULT_VOICE,
            "shimmer": DEFAULT_VOICE,
            "ash": DEFAULT_VOICE,
            "ballad": DEFAULT_VOICE,
            "coral": DEFAULT_VOICE,
            "sage": DEFAULT_VOICE,
            "verse": DEFAULT_VOICE,
        }

        AVAILABLE_MODELS = [
            {
                "id": "vieneu-v3-turbo",
                "object": "model",
                "created": 1740000000,
                "owned_by": "pnnbao-ump",
            },
            {
                "id": "gpt-4o-mini-tts",
                "object": "model",
                "created": 1740000000,
                "owned_by": "openai-compatible",
            },
            {
                "id": "tts-1",
                "object": "model",
                "created": 1740000000,
                "owned_by": "openai-compatible",
            },
            {
                "id": "tts-1-hd",
                "object": "model",
                "created": 1740000000,
                "owned_by": "openai-compatible",
            },
        ]

        class SpeechRequest(BaseModel):
            model: str = "vieneu-v3-turbo"
            input: str
            voice: str = DEFAULT_VOICE
            response_format: Literal["mp3", "opus", "aac", "flac", "wav", "pcm"] = "wav"
            stream_format: Optional[Literal["sse", "audio"]] = None
            speed: Optional[float] = 1.0
            instructions: Optional[str] = None
            stream: bool = False
            sample_rate: Optional[Literal[24000, 48000]] = 24000

        def format_chunk_pcm16(chunk_48k: np.ndarray, target_sr: int = 24000, speed: float = 1.0) -> np.ndarray:
            arr = np.asarray(chunk_48k, dtype=np.float32)
            if len(arr) == 0:
                return np.array([], dtype=np.int16)

            if target_sr == 24000 and abs(speed - 1.0) < 1e-3:
                n = (len(arr) // 2) * 2
                if n > 0:
                    arr = 0.5 * (arr[:n:2] + arr[1:n:2])
            else:
                effective_ratio = (48000.0 / float(target_sr)) * float(speed)
                out_len = max(1, int(len(arr) / effective_ratio))
                idx = np.linspace(0, len(arr) - 1, out_len, dtype=np.float32)
                arr = np.interp(idx, np.arange(len(arr), dtype=np.float32), arr)

            return (np.clip(arr, -1.0, 1.0) * 32767.0).astype(np.int16)

        @web.get("/")
        def health():
            return {
                "status": "ok",
                "auth_enabled": bool(EXPECTED_API_KEY),
                "engine": "GPU (CUDA)" if USE_GPU else "CPU (ONNX Runtime)",
                "precision": self.precision,
                "cpu_model": getattr(self, "cpu_model", "GPU"),
                "stream_sample_rate": 24000,
                "endpoints": ["/v1/models", "/v1/audio/voices", "/v1/voices", "/v1/audio/speech"],
            }

        @v1_router.get("/models")
        def list_models():
            return {"object": "list", "data": AVAILABLE_MODELS}

        @v1_router.get("/models/{model_id}")
        def retrieve_model(model_id: str):
            for m in AVAILABLE_MODELS:
                if m["id"] == model_id:
                    return m
            return {
                "id": model_id,
                "object": "model",
                "created": 1740000000,
                "owned_by": "pnnbao-ump",
            }

        @v1_router.get("/audio/voices")
        @v1_router.get("/voices")
        def list_voices():
            return {
                "object": "list",
                "voices": [
                    {
                        "id": v["id"],
                        "voice_id": v["id"],
                        "name": v["name"],
                        "description": v["description"],
                        "language": "vi-VN",
                    }
                    for v in self.voice_list
                ],
                "data": [
                    {
                        "id": v["id"],
                        "object": "voice",
                        "name": v["name"],
                        "description": v["description"],
                        "language": "vi-VN",
                    }
                    for v in self.voice_list
                ],
            }

        @v1_router.post("/audio/speech")
        def create_speech(req: SpeechRequest, request: Request):
            text = req.input.strip()
            if not text:
                raise HTTPException(status_code=400, detail="Text input cannot be empty.")

            resolved_voice = OPENAI_VOICE_ALIAS.get(req.voice.lower(), req.voice)
            speed = float(req.speed or 1.0)
            target_sr = int(req.sample_rate or 24000)
            accept_header = request.headers.get("accept", "").lower()

            if req.stream_format == "sse" or "text/event-stream" in accept_header:
                def sse_generator():
                    input_tokens = max(1, len(text.split()))
                    output_tokens = 0

                    for chunk in self.tts.infer_stream(text, voice=resolved_voice):
                        pcm16 = format_chunk_pcm16(chunk, target_sr=target_sr, speed=speed)
                        if len(pcm16) == 0:
                            continue
                        b64_audio = base64.b64encode(pcm16.tobytes()).decode("ascii")
                        output_tokens += max(1, int(len(pcm16) / (target_sr // 50)))

                        delta_payload = {
                            "type": "speech.audio.delta",
                            "audio": b64_audio,
                        }
                        yield f"event: speech.audio.delta\ndata: {json.dumps(delta_payload)}\n\n"

                    done_payload = {
                        "type": "speech.audio.done",
                        "usage": {
                            "input_tokens": input_tokens,
                            "output_tokens": output_tokens,
                            "total_tokens": input_tokens + output_tokens,
                        },
                    }
                    yield f"event: speech.audio.done\ndata: {json.dumps(done_payload)}\n\n"

                return StreamingResponse(
                    sse_generator(),
                    media_type="text/event-stream",
                    headers={
                        "Cache-Control": "no-cache",
                        "Connection": "keep-alive",
                        "X-Accel-Buffering": "no",
                    },
                )

            if req.stream or req.response_format == "pcm":
                if req.response_format == "wav":
                    def wav_stream_generator():
                        yield make_streaming_wav_header(sample_rate=target_sr)
                        for chunk in self.tts.infer_stream(text, voice=resolved_voice):
                            pcm16 = format_chunk_pcm16(chunk, target_sr=target_sr, speed=speed)
                            if len(pcm16) > 0:
                                yield pcm16.tobytes()
                    return StreamingResponse(wav_stream_generator(), media_type="audio/wav")

                def pcm_generator():
                    for chunk in self.tts.infer_stream(text, voice=resolved_voice):
                        pcm16 = format_chunk_pcm16(chunk, target_sr=target_sr, speed=speed)
                        if len(pcm16) > 0:
                            yield pcm16.tobytes()
                return StreamingResponse(pcm_generator(), media_type="audio/pcm")

            audio = self.tts.infer(text, voice=resolved_voice)
            if abs(speed - 1.0) >= 1e-3:
                pcm_full = format_chunk_pcm16(audio, target_sr=48000, speed=speed)
                wav_buf = io.BytesIO()
                sf.write(wav_buf, pcm_full, 48000, format="WAV", subtype="PCM_16")
            else:
                wav_buf = io.BytesIO()
                sf.write(wav_buf, audio, 48000, format="WAV", subtype="PCM_16")
            wav_bytes = wav_buf.getvalue()

            if req.response_format == "wav":
                return Response(content=wav_bytes, media_type="audio/wav")

            mime_map = {
                "mp3": ("mp3", "audio/mpeg"),
                "opus": ("opus", "audio/opus"),
                "aac": ("adts", "audio/aac"),
                "flac": ("flac", "audio/flac"),
            }
            fmt_arg, mime_type = mime_map[req.response_format]
            proc = subprocess.run(
                ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "pipe:0", "-f", fmt_arg, "pipe:1"],
                input=wav_bytes,
                capture_output=True,
                check=True,
            )
            return Response(content=proc.stdout, media_type=mime_type)

        web.include_router(v1_router)
        return web