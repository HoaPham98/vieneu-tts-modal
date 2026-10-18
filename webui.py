# =====================================================================
# webui.py: Embedded Single-Page WebUI for VieNeu-TTS v3 Turbo
# =====================================================================

def get_webui_html(api_key_enabled: bool = False, default_voice: str = "minh_quan_pro") -> str:
    auth_notice = "Bảo mật: Đang bật yêu cầu API Key" if api_key_enabled else "Bảo mật: Truy cập công khai (Không cần API Key)"
    auth_badge_color = "bg-amber-500/20 text-amber-300 border-amber-500/30" if api_key_enabled else "bg-emerald-500/20 text-emerald-300 border-emerald-500/30"

    return f"""<!DOCTYPE html>
<html lang="vi" class="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VieNeu-TTS v3 Turbo | WebUI</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  <script src="https://cdn.tailwindcss.com"></script>
  <script>
    tailwind.config = {{
      darkMode: 'class',
      theme: {{
        extend: {{
          fontFamily: {{
            sans: ['"Plus Jakarta Sans"', 'sans-serif'],
            mono: ['"JetBrains Mono"', 'monospace'],
          }},
          colors: {{
            brand: {{
              50: '#eff6ff',
              500: '#3b82f6',
              600: '#2563eb',
              700: '#1d4ed8',
            }}
          }}
        }}
      }}
    }}
  </script>
  <style>
    body {{
      background: radial-gradient(circle at 50% 0%, #1e1b4b 0%, #09090b 70%);
      min-height: 100vh;
    }}
  </style>
</head>
<body class="text-zinc-100 font-sans antialiased p-4 md:p-8">
  <div class="max-w-4xl mx-auto space-y-6">
    <!-- Header -->
    <header class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-zinc-800 pb-5">
      <div>
        <div class="flex items-center gap-3">
          <span class="text-3xl">🎙️</span>
          <h1 class="text-2xl font-bold tracking-tight text-white">VieNeu-TTS v3 Turbo</h1>
          <span class="text-xs px-2.5 py-0.5 rounded-full border bg-blue-500/10 text-blue-400 border-blue-500/20 font-medium">C++ GGUF Engine</span>
        </div>
        <p class="text-sm text-zinc-400 mt-1">Hệ thống tổng hợp giọng nói tiếng Việt tốc độ cao (25 Preset Voices · audio.cpp Runtime)</p>
      </div>
      <div class="flex items-center gap-2">
        <span class="text-xs px-3 py-1 rounded-full border {auth_badge_color} font-mono">{auth_notice}</span>
      </div>
    </header>

    <!-- Main Card -->
    <main class="bg-zinc-900/80 border border-zinc-800/80 rounded-2xl p-5 md:p-7 shadow-2xl backdrop-blur-xl space-y-6">
      <!-- Input Section -->
      <div class="space-y-2">
        <div class="flex items-center justify-between">
          <label for="textInput" class="text-sm font-semibold text-zinc-200">Văn bản tiếng Việt:</label>
          <div class="flex items-center gap-2">
            <span class="text-xs text-zinc-400" id="charCount">0 ký tự</span>
          </div>
        </div>
        <textarea
          id="textInput"
          rows="4"
          class="w-full bg-zinc-950/70 border border-zinc-700/60 rounded-xl p-3.5 text-sm text-zinc-100 placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500 transition-all resize-y"
          placeholder="Nhập văn bản tiếng Việt tại đây... (Ví dụ: Xin chào bạn! Hôm nay trời thật đẹp.)"
        >Xin chào, chào mừng bạn đến với hệ thống giọng đọc tiếng Việt VieNeu-TTS v3 Turbo chạy trên engine C++ cực nhanh!</textarea>

        <!-- Sample buttons -->
        <div class="flex flex-wrap items-center gap-2 pt-1 text-xs text-zinc-400">
          <span>Câu mẫu:</span>
          <button type="button" class="sample-btn px-2.5 py-1 rounded-md bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors" data-text="Xin chào! Tôi là giọng đọc AI tiếng Việt Minh Quân Pro, rất vui được hỗ trợ bạn.">Chào hỏi (Minh Quân)</button>
          <button type="button" class="sample-btn px-2.5 py-1 rounded-md bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors" data-text="Hôm nay thời tiết Hà Nội nắng ráo, nhiệt độ dao động từ hai mươi lăm đến ba mươi độ C.">Thời tiết</button>
          <button type="button" class="sample-btn px-2.5 py-1 rounded-md bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors" data-text="Ôi buồn cười quá [cười], chuyện này thật là thú vị!">Cảm xúc [cười]</button>
          <button type="button" class="sample-btn px-2.5 py-1 rounded-md bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors" data-text="Thật là mệt mỏi sau một ngày dài làm việc [thở dài].">Cảm xúc [thở dài]</button>
        </div>
      </div>

      <!-- Controls Grid -->
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 pt-2 border-t border-zinc-800/80">
        <!-- Voice -->
        <div>
          <label class="block text-xs font-medium text-zinc-400 mb-1.5">Giọng đọc (25 presets)</label>
          <select id="voiceSelect" class="w-full bg-zinc-950/70 border border-zinc-700/60 rounded-lg p-2.5 text-xs text-zinc-200 focus:outline-none focus:ring-1 focus:ring-blue-500">
            <optgroup label="⭐ Giọng Nổi Bật (Mặc Định & Phổ Biến)">
              <option value="minh_quan_pro" selected>⭐ Minh Quân Pro — Nam · Bắc (Chuẩn v3 Turbo)</option>
              <option value="ngoc_huyen">⭐ Ngọc Huyền — Nữ · Bắc (Tự nhiên)</option>
              <option value="mai_anh">⭐ Mai Anh — Nữ · Bắc (Tin tức)</option>
              <option value="thuy_dung">⭐ Thùy Dung — Nữ · Nam (Tin tức)</option>
              <option value="quang_son">⭐ Quang Sơn — Nam · Trung (Tự nhiên)</option>
            </optgroup>
            <optgroup label="Miền Bắc (Northern)">
              <option value="anh_khoi">Anh Khôi — Nam · Bắc (Kể chuyện)</option>
              <option value="truc_ly">Trúc Ly — Nữ · Bắc (Tự nhiên)</option>
              <option value="adam_bua">Adam bựa — Nam · Bắc (Tự nhiên / Hài hước)</option>
              <option value="thien_tam_duc">Thiền Tâm Đức — Nam · Bắc (Kể chuyện trầm)</option>
              <option value="minh_duc">Minh Đức — Nam · Bắc (Tin tức)</option>
              <option value="pham_tuyen">Phạm Tuyên — Nam · Bắc (Tự nhiên)</option>
              <option value="xuan_vinh">Xuân Vĩnh — Nam · Bắc (Tự nhiên)</option>
              <option value="thanh_binh">Thanh Bình — Nam · Bắc (Kể chuyện)</option>
              <option value="ngoc_linh">Ngọc Linh — Nữ · Bắc (Kể chuyện)</option>
              <option value="doan_trang">Đoan Trang — Nữ · Bắc (Tự nhiên)</option>
              <option value="quynh_anh">Quỳnh Anh — Nữ · Bắc (Đọc truyện)</option>
              <option value="manh_dung">Mạnh Dũng — Nam · Bắc (Tự nhiên)</option>
            </optgroup>
            <optgroup label="Miền Trung (Central)">
              <option value="ngoc_tran">Ngọc Trân — Nữ · Trung (Tự nhiên)</option>
            </optgroup>
            <optgroup label="Miền Nam (Southern)">
              <option value="thai_son">Thái Sơn — Nam · Nam (Kể chuyện)</option>
              <option value="thuc_doan">Thục Đoan — Nữ · Nam (Kể chuyện)</option>
              <option value="minh_triet">Minh Triết — Nam · Nam (Tin tức)</option>
              <option value="my_duyen">Mỹ Duyên — Nữ · Nam (Đọc truyện)</option>
              <option value="duc_tri">Đức Trí — Nam · Nam (Đọc truyện)</option>
              <option value="kim_thanh">Kim Thanh — Nữ · Nam (Đọc truyện)</option>
              <option value="adam">Adam — Nam · Nam (Tự nhiên)</option>
            </optgroup>
          </select>
        </div>

        <!-- Format -->
        <div>
          <label class="block text-xs font-medium text-zinc-400 mb-1.5">Định dạng Audio</label>
          <select id="formatSelect" class="w-full bg-zinc-950/70 border border-zinc-700/60 rounded-lg p-2.5 text-xs text-zinc-200 focus:outline-none focus:ring-1 focus:ring-blue-500">
            <option value="wav" selected>WAV (Chất lượng cao nhất 48kHz)</option>
            <option value="mp3">MP3 (Nhẹ & Tiết kiệm băng thông)</option>
            <option value="opus">Opus (Chuẩn WebRTC)</option>
            <option value="aac">AAC</option>
            <option value="flac">FLAC (Lossless)</option>
          </select>
        </div>

        <!-- Speed -->
        <div>
          <div class="flex justify-between items-center mb-1.5">
            <label class="text-xs font-medium text-zinc-400">Tốc độ đọc</label>
            <span id="speedVal" class="text-xs font-mono text-blue-400">1.0x</span>
          </div>
          <input id="speedRange" type="range" min="0.5" max="2.0" step="0.05" value="1.0" class="w-full accent-blue-500 cursor-pointer h-1.5 bg-zinc-800 rounded-lg">
        </div>

        <!-- API Key (optional) -->
        <div>
          <label class="block text-xs font-medium text-zinc-400 mb-1.5">Bearer API Key <span class="text-zinc-500">(nếu có)</span></label>
          <input id="apiKeyInput" type="password" placeholder="sk-..." class="w-full bg-zinc-950/70 border border-zinc-700/60 rounded-lg p-2 text-xs text-zinc-200 placeholder-zinc-600 focus:outline-none focus:ring-1 focus:ring-blue-500">
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="flex flex-col sm:flex-row items-center gap-3 pt-2">
        <button
          id="btnSpeak"
          type="button"
          class="w-full sm:w-auto flex-1 flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-500 active:bg-blue-700 text-white font-medium py-3 px-6 rounded-xl transition-all shadow-lg shadow-blue-600/20 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span id="speakIcon">🔊</span>
          <span id="speakText">Đọc văn bản</span>
        </button>

        <button
          id="btnPhonemize"
          type="button"
          class="w-full sm:w-auto flex items-center justify-center gap-2 bg-zinc-800 hover:bg-zinc-700 active:bg-zinc-850 text-zinc-300 font-medium py-3 px-5 rounded-xl border border-zinc-700/60 transition-all"
        >
          <span>🔤</span>
          <span>Xem âm vị IPA</span>
        </button>
      </div>

      <!-- Audio Result Player & Status -->
      <div id="playerContainer" class="hidden bg-zinc-950/60 border border-zinc-800 rounded-xl p-4 space-y-3">
        <div class="flex items-center justify-between text-xs">
          <span class="text-zinc-400">Kết quả phát âm thanh:</span>
          <span id="perfInfo" class="font-mono text-emerald-400"></span>
        </div>
        <audio id="audioPlayer" controls class="w-full outline-none"></audio>
        <div class="flex justify-end gap-2">
          <a id="btnDownload" href="#" download="speech.wav" class="inline-flex items-center gap-1.5 text-xs text-blue-400 hover:text-blue-300 bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 px-3 py-1.5 rounded-lg transition-colors">
            <span>⬇️</span> Tải file về máy
          </a>
        </div>
      </div>

      <!-- IPA Display Box -->
      <div id="ipaContainer" class="hidden bg-zinc-950/60 border border-zinc-800 rounded-xl p-4 space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Chuỗi âm vị IPA (Vietnamese G2P):</span>
          <button id="btnCopyIpa" class="text-xs text-zinc-500 hover:text-zinc-300 transition-colors">Sao chép</button>
        </div>
        <div id="ipaText" class="font-mono text-xs text-blue-300 bg-zinc-900/80 p-3 rounded-lg border border-zinc-800/80 break-words select-all"></div>
      </div>

      <!-- Error Box -->
      <div id="errorBox" class="hidden bg-red-950/30 border border-red-500/30 rounded-xl p-4 text-xs text-red-300"></div>
    </main>

    <!-- Footer -->
    <footer class="text-center text-xs text-zinc-500 space-y-1">
      <p>Mô hình: <a href="https://huggingface.co/phuocnguyen90/VieNeu-TTS-v3-Turbo-GGUF" target="_blank" class="text-zinc-400 hover:underline">VieNeu-TTS-v3-Turbo-GGUF</a> · Engine: <a href="https://github.com/0xshug0/audio.cpp" target="_blank" class="text-zinc-400 hover:underline">audio.cpp</a> · G2P: <a href="https://github.com/pnnbao97/sea-g2p" target="_blank" class="text-zinc-400 hover:underline">sea-g2p</a></p>
      <p>Tương thích chuẩn OpenAI Audio API: <code class="text-zinc-400">POST /v1/audio/speech</code></p>
    </footer>
  </div>

  <script>
    const textInput = document.getElementById('textInput');
    const charCount = document.getElementById('charCount');
    const speedRange = document.getElementById('speedRange');
    const speedVal = document.getElementById('speedVal');
    const formatSelect = document.getElementById('formatSelect');
    const voiceSelect = document.getElementById('voiceSelect');
    const apiKeyInput = document.getElementById('apiKeyInput');
    const btnSpeak = document.getElementById('btnSpeak');
    const btnPhonemize = document.getElementById('btnPhonemize');
    const speakIcon = document.getElementById('speakIcon');
    const speakText = document.getElementById('speakText');
    const playerContainer = document.getElementById('playerContainer');
    const audioPlayer = document.getElementById('audioPlayer');
    const btnDownload = document.getElementById('btnDownload');
    const perfInfo = document.getElementById('perfInfo');
    const ipaContainer = document.getElementById('ipaContainer');
    const ipaText = document.getElementById('ipaText');
    const btnCopyIpa = document.getElementById('btnCopyIpa');
    const errorBox = document.getElementById('errorBox');

    // Restore saved API Key from localStorage
    const savedKey = localStorage.getItem('vieneu_api_key');
    if (savedKey) apiKeyInput.value = savedKey;

    apiKeyInput.addEventListener('input', () => {{
      localStorage.setItem('vieneu_api_key', apiKeyInput.value.trim());
    }});

    // Character counter
    function updateCharCount() {{
      charCount.textContent = `${{textInput.value.length}} ký tự`;
    }}
    textInput.addEventListener('input', updateCharCount);
    updateCharCount();

    // Speed slider live update
    speedRange.addEventListener('input', () => {{
      speedVal.textContent = parseFloat(speedRange.value).toFixed(2) + 'x';
    }});

    // Sample buttons
    document.querySelectorAll('.sample-btn').forEach(btn => {{
      btn.addEventListener('click', () => {{
        textInput.value = btn.getAttribute('data-text');
        updateCharCount();
      }});
    }});

    function showError(msg) {{
      errorBox.textContent = msg;
      errorBox.classList.remove('hidden');
    }}

    function hideError() {{
      errorBox.classList.add('hidden');
    }}

    function getAuthHeaders() {{
      const headers = {{ 'Content-Type': 'application/json' }};
      const key = apiKeyInput.value.trim();
      if (key) {{
        headers['Authorization'] = `Bearer ${{key}}`;
      }}
      return headers;
    }}

    // Phonemize only
    btnPhonemize.addEventListener('click', async () => {{
      const text = textInput.value.trim();
      if (!text) {{
        showError('Vui lòng nhập văn bản tiếng Việt.');
        return;
      }}
      hideError();
      btnPhonemize.disabled = true;
      try {{
        const resp = await fetch('/v1/audio/phonemize', {{
          method: 'POST',
          headers: getAuthHeaders(),
          body: JSON.stringify({{ input: text }})
        }});
        if (!resp.ok) {{
          const errData = await resp.json().catch(() => ({{ detail: resp.statusText }}));
          throw new Error(errData.detail?.error?.message || errData.detail || 'Lỗi phiên âm');
        }}
        const data = await resp.json();
        ipaText.textContent = data.phonemes;
        ipaContainer.classList.remove('hidden');
      }} catch (err) {{
        showError(err.message);
      }} finally {{
        btnPhonemize.disabled = false;
      }}
    }});

    // Synthesize & Play
    btnSpeak.addEventListener('click', async () => {{
      const text = textInput.value.trim();
      if (!text) {{
        showError('Vui lòng nhập văn bản tiếng Việt.');
        return;
      }}
      hideError();
      btnSpeak.disabled = true;
      speakIcon.textContent = '⏳';
      speakText.textContent = 'Đang sinh âm thanh...';

      const fmt = formatSelect.value;
      const speed = parseFloat(speedRange.value);
      const voice = voiceSelect.value;
      const startTime = performance.now();

      try {{
        // Lấy trước IPA nếu cần hiển thị
        fetch('/v1/audio/phonemize', {{
          method: 'POST',
          headers: getAuthHeaders(),
          body: JSON.stringify({{ input: text }})
        }}).then(r => r.json()).then(d => {{
          if (d.phonemes) {{
            ipaText.textContent = d.phonemes;
            ipaContainer.classList.remove('hidden');
          }}
        }}).catch(() => {{}});

        const resp = await fetch('/v1/audio/speech', {{
          method: 'POST',
          headers: getAuthHeaders(),
          body: JSON.stringify({{
            model: 'vieneu-v3-turbo',
            input: text,
            voice: voice,
            speed: speed,
            response_format: fmt
          }})
        }});

        if (!resp.ok) {{
          const errData = await resp.json().catch(() => ({{ detail: resp.statusText }}));
          throw new Error(errData.detail?.error?.message || errData.detail || 'Lỗi sinh âm thanh');
        }}

        const audioBlob = await resp.blob();
        const durationSec = ((performance.now() - startTime) / 1000).toFixed(2);
        const audioUrl = URL.createObjectURL(audioBlob);

        audioPlayer.src = audioUrl;
        btnDownload.href = audioUrl;
        btnDownload.download = `speech_${{Date.now()}}.${{fmt}}`;
        perfInfo.textContent = `⚡ Hoàn thành trong ${{durationSec}}s (${{fmt.toUpperCase()}})`;
        playerContainer.classList.remove('hidden');
        audioPlayer.play().catch(() => {{}});
      }} catch (err) {{
        showError(err.message);
      }} finally {{
        btnSpeak.disabled = false;
        speakIcon.textContent = '🔊';
        speakText.textContent = 'Đọc văn bản';
      }}
    }});

    // Copy IPA
    btnCopyIpa.addEventListener('click', () => {{
      navigator.clipboard.writeText(ipaText.textContent);
      btnCopyIpa.textContent = 'Đã sao chép!';
      setTimeout(() => btnCopyIpa.textContent = 'Sao chép', 2000);
    }});
  </script>
</body>
</html>
"""
