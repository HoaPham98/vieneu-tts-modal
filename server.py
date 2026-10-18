import base64
import functools
import json
import os
import re
import secrets
import subprocess
from typing import Literal, Optional

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request, Security, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response, StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import httpx
from pydantic import BaseModel

from webui import get_webui_html

# =====================================================================
# 1. CẤU HÌNH VÀ THÔNG SỐ TOÀN CỤC
# =====================================================================

from pathlib import Path

VOICES_DIR = Path(os.environ.get("VOICES_DIR", "/app/voices"))
if not VOICES_DIR.exists() or not (VOICES_DIR / "manifest.json").exists():
    local_voices = Path(__file__).parent / "preset_voices"
    if local_voices.exists() and (local_voices / "manifest.json").exists():
        VOICES_DIR = local_voices

BACKEND_URL = os.environ.get("BACKEND_URL", "http://127.0.0.1:8080").rstrip("/")
EXPECTED_API_KEY = os.environ.get("API_KEY", "").strip()

DEFAULT_VOICE = "minh_quan_pro"
VOICE_CATALOG: dict[str, dict] = {}
VOICE_LIST: list[dict] = []

OPENAI_VOICE_ALIASES = {
    "alloy": "minh_quan_pro",
    "echo": "minh_quan_pro",
    "fable": "minh_quan_pro",
    "onyx": "minh_quan_pro",
    "nova": "ngoc_huyen",
    "shimmer": "ngoc_huyen",
    "ash": "anh_khoi",
    "ballad": "thien_tam_duc",
    "coral": "mai_anh",
    "sage": "quang_son",
    "verse": "thuy_dung",
}

def load_voice_catalog():
    global DEFAULT_VOICE, VOICE_CATALOG, VOICE_LIST
    manifest_path = VOICES_DIR / "manifest.json"
    if not manifest_path.exists():
        print(f"⚠️ Không tìm thấy manifest.json tại {manifest_path}")
        return
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        DEFAULT_VOICE = manifest.get("default", "minh_quan_pro")
        VOICE_CATALOG.clear()
        VOICE_LIST.clear()
        for v in manifest.get("voices", []):
            vid = v["id"]
            vdir = VOICES_DIR / vid
            meta = {
                "id": vid,
                "name": v.get("name", vid),
                "label": v.get("label", vid),
                "codes_file": str(vdir / "ref_codes.txt"),
                "emb_file": str(vdir / "speaker.emb.txt"),
            }
            VOICE_CATALOG[vid.lower()] = meta
            VOICE_CATALOG[v.get("name", "").lower()] = meta
            VOICE_LIST.append(meta)
        print(f"✅ Đã tải danh mục {len(VOICE_LIST)} voice presets (Mặc định: {DEFAULT_VOICE}) từ {VOICES_DIR}")
    except Exception as e:
        print(f"⚠️ Lỗi khi tải voice catalog từ {manifest_path}: {e}")

load_voice_catalog()

def resolve_voice_meta(voice_input: Optional[str]) -> dict:
    if not voice_input:
        return VOICE_CATALOG.get(DEFAULT_VOICE.lower()) or (VOICE_LIST[0] if VOICE_LIST else {})
    v_clean = voice_input.strip().lower()
    if v_clean in OPENAI_VOICE_ALIASES:
        v_clean = OPENAI_VOICE_ALIASES[v_clean]
    if v_clean in VOICE_CATALOG:
        return VOICE_CATALOG[v_clean]
    # Thử match tiền tố hoặc tên không dấu đơn giản
    for key, meta in VOICE_CATALOG.items():
        if key == v_clean or key.replace("_", " ") == v_clean.replace("_", " "):
            return meta
    return VOICE_CATALOG.get(DEFAULT_VOICE.lower()) or (VOICE_LIST[0] if VOICE_LIST else {})

AVAILABLE_MODELS = [
    {"id": "vieneu-v3-turbo", "object": "model", "created": 1740000000, "owned_by": "pnnbao-ump"},
    {"id": "gpt-4o-mini-tts", "object": "model", "created": 1740000000, "owned_by": "openai-compatible"},
    {"id": "tts-1", "object": "model", "created": 1740000000, "owned_by": "openai-compatible"},
    {"id": "tts-1-hd", "object": "model", "created": 1740000000, "owned_by": "openai-compatible"},
]

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
# 3. SCHEMA VÀ TIỆN ÍCH TRANSCODE AUDIO
# =====================================================================

class SpeechRequest(BaseModel):
    model: str = "vieneu-v3-turbo"
    input: str
    voice: Optional[str] = DEFAULT_VOICE
    response_format: Optional[Literal["mp3", "opus", "aac", "flac", "wav", "pcm"]] = "wav"
    stream_format: Optional[Literal["sse", "audio"]] = None
    speed: Optional[float] = 1.0
    stream: bool = False
    sample_rate: Optional[int] = 24000
    # Extra fields từ các UI client (ví dụ epub-to-audio)
    max_chars: Optional[int] = None
    temperature: Optional[float] = None
    top_k: Optional[int] = None
    top_p: Optional[float] = None
    repetition_penalty: Optional[float] = None


class PhonemizeRequest(BaseModel):
    input: str


def transcode_audio(wav_data: bytes, fmt: str, sample_rate: int = 24000, channels: int = 1) -> tuple[bytes, str]:
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", "pipe:0"]
    if sample_rate:
        cmd.extend(["-ar", str(sample_rate)])
    if channels:
        cmd.extend(["-ac", str(channels)])

    mime_map = {
        "pcm": ("s16le", "audio/pcm", ["-acodec", "pcm_s16le"]),
        "mp3": ("mp3", "audio/mpeg", []),
        "opus": ("opus", "audio/opus", []),
        "aac": ("adts", "audio/aac", []),
        "flac": ("flac", "audio/flac", []),
        "wav": ("wav", "audio/wav", []),
    }
    ffmpeg_fmt, mime_type, extra_args = mime_map.get(fmt, ("wav", "audio/wav", []))
    cmd.extend(extra_args)
    cmd.extend(["-f", ffmpeg_fmt, "pipe:1"])

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out_bytes, err = proc.communicate(input=wav_data)
    if proc.returncode != 0:
        print(f"⚠️ FFmpeg transcode warning: {err.decode('utf-8')}")
        return wav_data, "audio/wav"
    return out_bytes, mime_type


# =====================================================================
# 4. KHỞI TẠO FASTAPI APP VÀ ROUTER
# =====================================================================

app = FastAPI(
    title="VieNeu-TTS v3 Turbo (audio.cpp GGUF) OpenAI API",
    version="2.0.0",
    description="Standalone OpenAI-compatible Text-To-Speech server for VieNeu-TTS v3 Turbo",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer(auto_error=False)


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


@app.get("/ui", response_class=HTMLResponse)
def ui_page():
    return HTMLResponse(content=get_webui_html(api_key_enabled=bool(EXPECTED_API_KEY), default_voice=DEFAULT_VOICE))


@app.get("/health")
def health():
    return {
        "status": "ok",
        "engine": "audio.cpp C++ Runtime (GGUF)",
        "model": "pnnbao-ump/VieNeu-TTS-v3-Turbo-GGUF",
        "default_voice": DEFAULT_VOICE,
        "total_voices": len(VOICE_LIST),
        "auth_enabled": bool(EXPECTED_API_KEY),
        "backend_url": BACKEND_URL,
        "endpoints": ["/v1/models", "/v1/audio/voices", "/v1/audio/speech", "/v1/audio/phonemize"],
    }


@app.get("/")
def root(request: Request):
    accept = request.headers.get("accept", "").lower()
    if "text/html" in accept:
        return HTMLResponse(content=get_webui_html(api_key_enabled=bool(EXPECTED_API_KEY), default_voice=DEFAULT_VOICE))
    return health()


@v1_router.get("/models")
def list_models():
    return {"object": "list", "data": AVAILABLE_MODELS}


@v1_router.get("/audio/voices")
@v1_router.get("/voices")
def list_voices():
    return {
        "object": "list",
        "default": DEFAULT_VOICE,
        "total": len(VOICE_LIST),
        "voices": VOICE_LIST,
        "data": [{**v, "object": "voice"} for v in VOICE_LIST],
    }


@v1_router.api_route("/audio/phonemize", methods=["GET", "POST"])
def phonemize_endpoint(req: Optional[PhonemizeRequest] = None, text: Optional[str] = None):
    input_text = ""
    if req and req.input:
        input_text = req.input.strip()
    elif text:
        input_text = text.strip()
    if not input_text:
        raise HTTPException(status_code=400, detail="Text input cannot be empty.")
    return {
        "input": input_text,
        "phonemes": phonemize_vietnamese(input_text),
    }


@v1_router.post("/audio/speech")
async def create_speech(req: SpeechRequest, request: Request):
    text = req.input.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Text input cannot be empty.")

    # 1. Tìm kiếm và ánh xạ voice preset
    voice_meta = resolve_voice_meta(req.voice)

    # 2. Chuyển đổi text tiếng Việt tự nhiên sang chuỗi âm vị IPA
    ipa_text = phonemize_vietnamese(text)

    backend_payload = {
        "model": "vieneu-v3-turbo",
        "input": ipa_text,
    }

    if voice_meta and "codes_file" in voice_meta and "emb_file" in voice_meta:
        backend_payload["options"] = {
            "reference_codes_file": voice_meta["codes_file"],
            "speaker_embedding_file": voice_meta["emb_file"],
        }

    if req.speed and abs(req.speed - 1.0) > 1e-3:
        backend_payload["speed"] = req.speed

    accept_header = request.headers.get("accept", "").lower()
    is_sse = (req.stream_format == "sse") or ("text/event-stream" in accept_header)
    target_sr = int(req.sample_rate or 24000)
    fmt = (req.response_format or "wav").lower()

    # Yêu cầu tải audio từ audio.cpp backend nội bộ
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(f"{BACKEND_URL}/v1/audio/speech", json=backend_payload)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Không thể kết nối đến audio.cpp server tại {BACKEND_URL}: {str(e)}")

        if resp.status_code != 200:
            raise HTTPException(status_code=resp.status_code, detail=resp.text)

        audio_bytes = resp.content

    # 1. Trả về Server-Sent Events (SSE) theo chuẩn OpenAI / epub-to-audio
    if is_sse:
        pcm_bytes, _ = transcode_audio(audio_bytes, fmt="pcm", sample_rate=target_sr, channels=1)

        def sse_generator():
            input_tokens = max(1, len(text.split()))
            output_tokens = 0
            chunk_size = target_sr * 2 // 5  # ~200ms mỗi chunk (9600 bytes ở 24kHz 16-bit mono)
            for i in range(0, len(pcm_bytes), chunk_size):
                chunk = pcm_bytes[i : i + chunk_size]
                if not chunk:
                    continue
                b64_audio = base64.b64encode(chunk).decode("ascii")
                output_tokens += max(1, int(len(chunk) / (target_sr // 50)))
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

    # 2. Trả về raw PCM nếu client yêu cầu response_format="pcm"
    if fmt == "pcm":
        pcm_bytes, mime = transcode_audio(audio_bytes, fmt="pcm", sample_rate=target_sr, channels=1)
        return Response(content=pcm_bytes, media_type=mime)

    # 3. Trả về các định dạng đã nén khác (mp3, opus, aac, flac)
    if fmt != "wav":
        out_bytes, mime = transcode_audio(audio_bytes, fmt=fmt, sample_rate=target_sr)
        return Response(content=out_bytes, media_type=mime)

    # 4. Mặc định trả về WAV
    return Response(content=audio_bytes, media_type="audio/wav")


app.include_router(v1_router)

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("server:app", host="0.0.0.0", port=port, reload=False)
