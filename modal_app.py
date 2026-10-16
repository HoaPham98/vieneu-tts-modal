import functools
import json
import os
import re
import secrets
import subprocess
import time
import urllib.request
from pathlib import Path
from typing import Literal, Optional

import modal

# =====================================================================
# 1. CẤU HÌNH IMAGE CONTAINER DỰA TRÊN AUDIO.CPP DOCKER
# =====================================================================

NGOC_HUYEN_REF_PHONEMES = "tʃˈɔŋ fˈɔ2ŋ ɹˈəɜt̪ t̪ˈu2 mˈu2, nˌen kˈɔɜ tˈe4 zˈe5 zˈaː2ŋ tʃˈɛ zˈəɜw nˈɔɜ."


def get_server_config():
    """Tạo cấu hình server.json cho audiocpp_server với preset Ngọc Huyền chuẩn embedding."""
    return {
        "host": "127.0.0.1",
        "port": 8080,
        "backend": "cpu",
        "threads": 2,
        "models": [
            {
                "id": "vieneu-v3-turbo",
                "family": "vieneu_v3_turbo",
                "path": "/app/models/VieNeu-TTS-v3-Turbo/model.gguf",
                "task": "tts",
                "mode": "offline",
                "default_request_options": {
                    "reference_codes_file": "/app/voices/ngoc_huyen.ref_codes.txt",
                    "speaker_embedding_file": "/app/voices/ngoc_huyen.wav.emb.txt",
                    "reference_text": NGOC_HUYEN_REF_PHONEMES,
                },
            }
        ],
    }


def download_models_and_setup():
    """Hàm chạy 1 lần lúc build Modal image để tải trọng số GGUF và sinh server.json."""
    model_dir = Path("/app/models/VieNeu-TTS-v3-Turbo")
    model_dir.mkdir(parents=True, exist_ok=True)
    (model_dir / "speech_tokenizer").mkdir(parents=True, exist_ok=True)

    base_url = "https://huggingface.co/phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF/resolve/main"
    files = [
        "model.gguf",
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "speech_tokenizer/config.json",
    ]

    for fname in files:
        dest = model_dir / fname
        if not dest.exists():
            url = f"{base_url}/{fname}"
            print(f"⏳ Đang tải {fname} từ {url}...")
            urllib.request.urlretrieve(url, dest)
            print(f"✅ Đã tải xong {fname} ({dest.stat().st_size} bytes)")

    # Tạo cấu hình server.json cho audiocpp_server
    config_path = Path("/app/server.json")
    config_path.write_text(json.dumps(get_server_config(), indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"✅ Đã tạo cấu hình server tại {config_path}")


image = (
    modal.Image.from_registry("ghcr.io/0xshug0/audio.cpp:full-cpu", add_python="3.11")
    .dockerfile_commands("ENTRYPOINT []")
    .apt_install("curl", "ffmpeg", "ca-certificates")
    .pip_install(
        "fastapi[standard]",
        "httpx",
        "sea-g2p>=0.10.0",
    )
    .add_local_dir("preset_voices", "/app/voices", copy=True)
    .run_function(download_models_and_setup)
)

app = modal.App("vieneu-tts-v3-turbo", image=image)

# =====================================================================
# 2. XỬ LÝ PHIÊN ÂM TIẾNG VIỆT (G2P PHONEMIZER)
# =====================================================================

_EMOTION_TAG_TO_K = {
    "chuckle": 1, "cười": 1, "cuoi": 1,
    "sigh": 2, "thở dài": 2, "tho dai": 2,
    "clear throat": 3, "hắng giọng": 3, "hang giong": 3,
}
_EMOTION_SPLIT_RE = re.compile(r"(\[[^\]]+\]|<\|emotion_\d+\|>)")
_pipeline = None


def get_pipeline():
    global _pipeline
    if _pipeline is None:
        from sea_g2p import SEAPipeline
        _pipeline = SEAPipeline(lang="vi")
    return _pipeline


def _emotion_tag_token(tag: str) -> Optional[str]:
    t = tag.strip()
    if t.startswith("<|"):
        return t
    inner = t[1:-1].strip().lower()
    k = _EMOTION_TAG_TO_K.get(inner)
    return f"<|emotion_{k}|>" if k is not None else None


@functools.lru_cache(maxsize=1024)
def phonemize_vietnamese(text: str) -> str:
    """Chuyển đổi văn bản tiếng Việt sang chuỗi âm vị IPA mà mô hình VieNeu-TTS yêu cầu."""
    pipeline = get_pipeline()
    tokens = _EMOTION_SPLIT_RE.split(text)
    if len(tokens) == 1:
        return pipeline.run(text, punc_norm=True)

    parts = []
    for token in tokens:
        if not token:
            continue
        em_tok = _emotion_tag_token(token)
        if em_tok is not None:
            parts.append(em_tok)
        else:
            ph = pipeline.run(token, punc_norm=False).strip()
            if ph:
                parts.append(ph)

    res = " ".join(parts).strip()
    if res and not any(res.endswith(p) for p in ".,!?;:…"):
        res += "."
    return res


# =====================================================================
# 3. SERVICE SERVERLESS KÈM TIẾN TRÌNH C++ VÀ FASTAPI PROXY
# =====================================================================

@app.cls(
    cpu=2.0,
    memory=4096,
    scaledown_window=60,
    secrets=[modal.Secret.from_name("vieneu-api-key")],
)
class AudioCppService:
    proc: Optional[subprocess.Popen] = None

    @modal.enter()
    def start_server(self):
        """Khởi động tiến trình audiocpp_server ngầm trên cổng nội bộ 8080."""
        import shutil
        import httpx

        if AudioCppService.proc is None or AudioCppService.proc.poll() is not None:
            # Đảm bảo /app/server.json luôn khớp cấu hình chuẩn mới nhất
            try:
                Path("/app/server.json").write_text(
                    json.dumps(get_server_config(), indent=2, ensure_ascii=False),
                    encoding="utf-8"
                )
            except Exception as e:
                print(f"⚠️ Cảnh báo ghi /app/server.json: {e}")

            print("🚀 Đang khởi động audiocpp_server subprocess...")
            server_bin = shutil.which("audiocpp_server") or ("/app/audiocpp_server" if Path("/app/audiocpp_server").exists() else None)
            if server_bin:
                args = [server_bin, "--config", "/app/server.json", "--backend", "cpu"]
            elif Path("/app/entrypoint.sh").exists():
                args = ["/app/entrypoint.sh", "server", "--config", "/app/server.json", "--backend", "cpu"]
            else:
                args = ["audiocpp_server", "--config", "/app/server.json", "--backend", "cpu"]

            print(f"🚀 Chạy lệnh backend: {' '.join(args)}")
            AudioCppService.proc = subprocess.Popen(
                args,
                cwd="/app",
            )

            # Polling kiểm tra health check
            for _ in range(40):
                exit_code = AudioCppService.proc.poll()
                if exit_code is not None:
                    print(f"❌ audiocpp_server đã dừng với exit code {exit_code}")
                    break
                try:
                    res = httpx.get("http://127.0.0.1:8080/health", timeout=1.0)
                    if res.status_code == 200:
                        print("✅ audiocpp_server C++ đã sẵn sàng phục vụ trên cổng nội bộ 8080!")
                        return
                except Exception:
                    pass
                time.sleep(0.5)
            print("⚠️ Cảnh báo: audiocpp_server chưa phản hồi healthcheck kịp thời, tiếp tục tiến trình...")

    @modal.asgi_app()
    def web_app(self):
        from fastapi import APIRouter, Depends, FastAPI, HTTPException, Security, status
        from fastapi.middleware.cors import CORSMiddleware
        from fastapi.responses import Response, StreamingResponse
        from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
        import httpx
        from pydantic import BaseModel

        web = FastAPI(title="VieNeu-TTS v3 Turbo (audio.cpp GGUF) OpenAI API", version="2.0.0")

        web.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

        security = HTTPBearer(auto_error=False)
        EXPECTED_API_KEY = os.environ.get("API_KEY", "").strip()

        def verify_api_key(credentials: Optional[HTTPAuthorizationCredentials] = Security(security)):
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

        DEFAULT_VOICE = "Ngọc Huyền"
        OPENAI_VOICE_ALIASES = {
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
            {"id": "vieneu-v3-turbo", "object": "model", "created": 1740000000, "owned_by": "pnnbao-ump"},
            {"id": "gpt-4o-mini-tts", "object": "model", "created": 1740000000, "owned_by": "openai-compatible"},
            {"id": "tts-1", "object": "model", "created": 1740000000, "owned_by": "openai-compatible"},
            {"id": "tts-1-hd", "object": "model", "created": 1740000000, "owned_by": "openai-compatible"},
        ]

        class SpeechRequest(BaseModel):
            model: str = "vieneu-v3-turbo"
            input: str
            voice: Optional[str] = DEFAULT_VOICE
            response_format: Literal["mp3", "opus", "aac", "flac", "wav", "pcm"] = "wav"
            speed: Optional[float] = 1.0
            stream: bool = False

        @web.get("/")
        @web.get("/health")
        def health():
            return {
                "status": "ok",
                "engine": "audio.cpp C++ Runtime (GGUF)",
                "model": "phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF",
                "default_voice": DEFAULT_VOICE,
                "auth_enabled": bool(EXPECTED_API_KEY),
                "endpoints": ["/v1/models", "/v1/audio/voices", "/v1/audio/speech"],
            }

        @v1_router.get("/models")
        def list_models():
            return {"object": "list", "data": AVAILABLE_MODELS}

        @v1_router.get("/audio/voices")
        @v1_router.get("/voices")
        def list_voices():
            voice_meta = {
                "id": DEFAULT_VOICE,
                "name": DEFAULT_VOICE,
                "description": "Nữ · Bắc · Giọng đọc tự nhiên (Chuẩn preset VieNeu-TTS)",
                "language": "vi-VN",
            }
            return {
                "object": "list",
                "voices": [voice_meta],
                "data": [{**voice_meta, "object": "voice"}],
            }

        @v1_router.post("/audio/speech")
        async def create_speech(req: SpeechRequest):
            text = req.input.strip()
            if not text:
                raise HTTPException(status_code=400, detail="Text input cannot be empty.")

            voice_req = (req.voice or DEFAULT_VOICE).strip()
            _ = OPENAI_VOICE_ALIASES.get(voice_req.lower(), voice_req)

            # Chuyển đổi text tiếng Việt tự nhiên sang chuỗi âm vị IPA
            ipa_text = phonemize_vietnamese(text)

            backend_payload = {
                "model": "vieneu-v3-turbo",
                "input": ipa_text,
            }

            if req.speed and abs(req.speed - 1.0) > 1e-3:
                backend_payload["speed"] = req.speed

            # Nếu client yêu cầu streaming
            if req.stream:
                client = httpx.AsyncClient(timeout=60.0)
                try:
                    req_backend = client.build_request(
                        "POST", "http://127.0.0.1:8080/v1/audio/speech", json=backend_payload
                    )
                    resp_backend = await client.send(req_backend, stream=True)
                    if resp_backend.status_code != 200:
                        err_content = await resp_backend.aread()
                        await client.aclose()
                        raise HTTPException(status_code=resp_backend.status_code, detail=err_content.decode("utf-8"))

                    return StreamingResponse(
                        resp_backend.aiter_bytes(),
                        status_code=200,
                        media_type="audio/wav",
                        background=client.aclose,
                    )
                except Exception as e:
                    await client.aclose()
                    if isinstance(e, HTTPException):
                        raise e
                    raise HTTPException(status_code=500, detail=f"Lỗi khi kết nối audio.cpp server: {str(e)}")

            # Yêu cầu tải toàn bộ file một lần
            async with httpx.AsyncClient(timeout=60.0) as client:
                try:
                    resp = await client.post("http://127.0.0.1:8080/v1/audio/speech", json=backend_payload)
                except Exception as e:
                    raise HTTPException(status_code=500, detail=f"Không thể kết nối đến audio.cpp server: {str(e)}")

                if resp.status_code != 200:
                    raise HTTPException(status_code=resp.status_code, detail=resp.text)

                audio_bytes = resp.content

                # Tự động transcode sang MP3 nếu client yêu cầu response_format="mp3"
                if req.response_format == "mp3":
                    proc = subprocess.Popen(
                        ["ffmpeg", "-y", "-i", "pipe:0", "-f", "mp3", "pipe:1"],
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                    )
                    mp3_data, _ = proc.communicate(input=audio_bytes)
                    if proc.returncode == 0 and mp3_data:
                        return Response(content=mp3_data, media_type="audio/mpeg")

                return Response(content=audio_bytes, media_type="audio/wav")

        web.include_router(v1_router)
        return web