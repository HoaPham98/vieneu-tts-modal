use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use audio_cpp::{Backend, Model, ModelFamily, Registry, Request, RunMode, TaskKind};
use flutter_rust_bridge::frb;
use hound::{WavSpec, WavWriter};
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use sea_g2p_rs::g2p::G2PEngine;
use sea_g2p_rs::lang::vi::Normalizer;

use crate::embedded_voices;

struct Phonemizer {
    engine: G2PEngine,
    normalizer: Normalizer,
}

impl Phonemizer {
    fn new(dict_path: &Path) -> Result<Self> {
        let path_str = dict_path.to_string_lossy();
        let engine = G2PEngine::new(&path_str)
            .map_err(|e| anyhow!("Failed to load sea_g2p dictionary at {}: {}", path_str, e))?;
        let normalizer = Normalizer::new("vi", Some(&path_str));
        Ok(Self { engine, normalizer })
    }

    fn phonemize(&self, text: &str) -> String {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return String::new();
        }
        let normalized = self.normalizer.normalize(trimmed, true);
        let mut phonemes = self.engine.phonemize(&normalized);
        if !phonemes.is_empty()
            && !phonemes.ends_with('.')
            && !phonemes.ends_with('?')
            && !phonemes.ends_with('!')
        {
            phonemes.push('.');
        }
        phonemes
    }
}

struct EngineState {
    _registry: Registry,
    model: Model,
    model_path: PathBuf,
    threads: i32,
    cache_dir: PathBuf,
    phonemizer: Option<Phonemizer>,
}

static ENGINE: Lazy<Arc<Mutex<Option<EngineState>>>> = Lazy::new(|| Arc::new(Mutex::new(None)));

/// Initializes the native TTS engine with the given GGUF model path.
#[frb]
pub fn init_engine(
    model_path: String,
    dict_path: Option<String>,
    threads: usize,
) -> Result<()> {
    let mut lock = ENGINE.lock();

    let path = PathBuf::from(&model_path);
    if !path.exists() {
        return Err(anyhow!("Model file does not exist at: {}", model_path));
    }

    let cache_dir = path
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir());

    let cache_dir_str = cache_dir.to_string_lossy().to_string();
    std::env::set_var("TMPDIR", &cache_dir_str);
    std::env::set_var("TEMP", &cache_dir_str);
    std::env::set_var("TMP", &cache_dir_str);
    #[cfg(unix)]
    unsafe {
        use std::ffi::CString;
        if let Ok(c_path) = CString::new(cache_dir_str.clone()) {
            libc::setenv(b"TMPDIR\0".as_ptr() as *const libc::c_char, c_path.as_ptr(), 1);
            libc::setenv(b"TEMP\0".as_ptr() as *const libc::c_char, c_path.as_ptr(), 1);
            libc::setenv(b"TMP\0".as_ptr() as *const libc::c_char, c_path.as_ptr(), 1);
        }
    }

    crate::embedded_configs::ensure_model_configs(&path)
        .context("Failed to ensure embedded model config sidecar files")?;

    // If the file is not named model.gguf, ensure model.gguf exists in the same directory
    let resolved_path = if path.file_name().and_then(|s| s.to_str()) != Some("model.gguf") {
        let parent = path.parent().unwrap_or_else(|| Path::new("."));
        let model_gguf = parent.join("model.gguf");
        if !model_gguf.exists() {
            #[cfg(unix)]
            let _ = std::os::unix::fs::symlink(&path, &model_gguf);
            if !model_gguf.exists() {
                let _ = std::fs::copy(&path, &model_gguf);
            }
        }
        if model_gguf.exists() {
            let _ = crate::embedded_configs::ensure_model_configs(&model_gguf);
            model_gguf
        } else {
            path.clone()
        }
    } else {
        path.clone()
    };

    let resolved_str = resolved_path.to_string_lossy().to_string();
    let registry = Registry::new().context("Failed to create audio.cpp Registry")?;
    let family_hint = ModelFamily::from_path(&resolved_str).unwrap_or(ModelFamily::VieneuV3Turbo);

    let spec_path = cache_dir.join("model_spec.json");
    let options_json = if spec_path.exists() {
        Some(format!(r#"{{"model_spec_override":"{}"}}"#, spec_path.to_string_lossy()))
    } else {
        None
    };
    let options_str = options_json.as_deref();

    let model = registry
        .load(&resolved_str, Some(ModelFamily::VieneuV3Turbo), options_str)
        .or_else(|e1| {
            eprintln!("Load attempt 1 (VieneuV3Turbo with spec override) failed: {:?}", e1);
            registry.load(&resolved_str, None, options_str)
        })
        .or_else(|e2| {
            eprintln!("Load attempt 2 (None with spec override) failed: {:?}", e2);
            registry.load(&resolved_str, Some(family_hint.clone()), options_str)
        })
        .or_else(|e3| {
            eprintln!("Load attempt 3 (family_hint with spec override) failed: {:?}", e3);
            registry.load(&resolved_str, Some(ModelFamily::Custom("vietneu_tts".to_string())), options_str)
        })
        .or_else(|e4| {
            eprintln!("Load attempt 4 (vietneu_tts with spec override) failed: {:?}", e4);
            registry.load(&resolved_str, None, None)
        })
        .or_else(|e5| {
            eprintln!("Load attempt 5 (None without spec override) failed: {:?}", e5);
            registry.load(&resolved_str, Some(ModelFamily::VieneuV3Turbo), None)
        })
        .or_else(|e6| {
            eprintln!("Load attempt 6 (VieneuV3Turbo without spec override) failed: {:?}", e6);
            registry.load(&model_path, None, None)
        })
        .context("Failed to load VieNeu-TTS GGUF model")?;

    let resolved_dict = dict_path
        .map(PathBuf::from)
        .or_else(|| path.parent().map(|p| p.join("sea_g2p.bin")));

    let phonemizer = match resolved_dict {
        Some(dp) if dp.exists() => match Phonemizer::new(&dp) {
            Ok(p) => Some(p),
            Err(e) => {
                eprintln!(
                    "Warning: Failed to initialize SEA-G2P phonemizer from {:?}: {:?}",
                    dp, e
                );
                None
            }
        },
        _ => None,
    };

    *lock = Some(EngineState {
        _registry: registry,
        model,
        model_path: path,
        threads: threads.max(1) as i32,
        cache_dir,
        phonemizer,
    });

    Ok(())
}

/// Default target sample rate for synthesis output.
pub const DEFAULT_SAMPLE_RATE: u32 = 24_000;

/// Default target channel count for synthesis output (mono).
pub const DEFAULT_CHANNELS: u16 = 1;

/// Optional synthesis configuration shared by `synthesize_speech` and `stream_speech`.
///
/// Every field is optional so that omitted values fall back to the historical
/// behaviour (24 kHz mono WAV) and only explicitly requested options are forwarded
/// to the underlying `audio.cpp` inference request.
#[derive(Debug, Clone, Default)]
pub struct SynthesisOptions {
    /// Voice preset ID or display name (e.g. `mai_anh` or `Mai Anh`).
    pub voice: Option<String>,
    /// Speaking rate multiplier, where `1.0` is the model's natural pace.
    pub speed: Option<f32>,
    /// Target sample rate in Hz (`48000`, `24000`, `16000`, or `8000`).
    pub sample_rate: Option<u32>,
    /// Target channel count: `1` for mono, `2` for stereo.
    pub channels: Option<u16>,
    /// Container format: `pcm` for raw `s16le` bytes, `wav` for a RIFF/WAVE container.
    pub response_format: Option<String>,
    /// Sampling temperature.
    pub temperature: Option<f32>,
    /// Top-k sampling cutoff.
    pub top_k: Option<i32>,
    /// Nucleus (top-p) sampling probability.
    pub top_p: Option<f32>,
    /// Repetition penalty applied during decoding.
    pub repetition_penalty: Option<f32>,
    /// Maximum characters per text chunk.
    pub max_chars: Option<i32>,
    /// Minimum characters per text chunk.
    pub min_chars: Option<i32>,
    /// Deterministic sampling seed.
    pub seed: Option<i32>,
}

impl SynthesisOptions {
    /// Resolves the requested sample rate, defaulting to [`DEFAULT_SAMPLE_RATE`].
    fn resolved_sample_rate(&self) -> u32 {
        match self.sample_rate {
            Some(rate) if rate > 0 => rate,
            _ => DEFAULT_SAMPLE_RATE,
        }
    }

    /// Resolves the requested channel count, defaulting to [`DEFAULT_CHANNELS`].
    fn resolved_channels(&self) -> u16 {
        match self.channels {
            Some(channels) if channels > 0 => channels,
            _ => DEFAULT_CHANNELS,
        }
    }

    /// Resolves the requested response format, defaulting to [`DEFAULT_RESPONSE_FORMAT`].
    fn resolved_response_format(&self) -> &str {
        match self.response_format.as_deref() {
            Some(fmt) if !fmt.trim().is_empty() => fmt,
            _ => DEFAULT_RESPONSE_FORMAT,
        }
    }
}

/// Supported target sample rates for on-device synthesis output.
pub const SUPPORTED_SAMPLE_RATES: [u32; 4] = [48_000, 24_000, 16_000, 8_000];

/// Default audio container format: 44-byte RIFF/WAVE header plus `s16le` payload.
pub const DEFAULT_RESPONSE_FORMAT: &str = "wav";

/// Convert clamped float samples `[-1.0, 1.0]` into signed 16-bit little-endian bytes.
fn samples_to_pcm_s16le(samples: &[f32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(samples.len() * 2);
    for &s in samples {
        let clamped = s.clamp(-1.0, 1.0);
        let val = (clamped * i16::MAX as f32).round() as i16;
        bytes.extend_from_slice(&val.to_le_bytes());
    }
    bytes
}

/// Helper function to convert raw Float32 audio samples into standard 16-bit PCM WAV bytes.
fn samples_to_wav(samples: &[f32], sample_rate: u32, channels: u16) -> Result<Vec<u8>> {
    let spec = WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut cursor = Cursor::new(Vec::with_capacity(samples.len() * 2 + 44));
    {
        let mut writer = WavWriter::new(&mut cursor, spec)?;
        for &s in samples {
            // Clamp float sample [-1.0, 1.0] to i16
            let clamped = s.max(-1.0).min(1.0);
            let val = (clamped * 32767.0) as i16;
            writer.write_sample(val)?;
        }
        writer.finalize()?;
    }

    Ok(cursor.into_inner())
}

/// Downmixes or upmixes interleaved samples to the requested channel count.
///
/// Stereo to mono averages the frame channels, mono to stereo duplicates the
/// single channel into both left and right slots.
fn convert_channels(samples: &[f32], from: u16, to: u16) -> Vec<f32> {
    if from == to || from == 0 || to == 0 {
        return samples.to_vec();
    }

    match (from, to) {
        (2, 1) => samples
            .chunks_exact(2)
            .map(|frame| (frame[0] + frame[1]) * 0.5)
            .collect(),
        (1, 2) => samples
            .iter()
            .flat_map(|&s| [s, s])
            .collect(),
        _ => samples.to_vec(),
    }
}

/// Resamples interleaved samples from `from_rate` to `to_rate`.
///
/// The native model emits 48 kHz audio. A 2:1 decimation with a 2-point moving
/// average (a first-order low-pass with a zero at the 24 kHz Nyquist frequency)
/// handles the common 48k -> 24k path; every other supported ratio falls back to
/// linear interpolation.
fn resample(samples: &[f32], channels: u16, from_rate: u32, to_rate: u32) -> Vec<f32> {
    if from_rate == to_rate || from_rate == 0 || to_rate == 0 || channels == 0 {
        return samples.to_vec();
    }

    let channels = channels as usize;
    let frames_in = samples.len() / channels;

    if from_rate == 48_000 && to_rate == 24_000 {
        let frames_out = frames_in / 2;
        let mut out = Vec::with_capacity(frames_out * channels);
        for frame in 0..frames_out {
            let a = frame * 2;
            let b = a + 1;
            for ch in 0..channels {
                out.push((samples[a * channels + ch] + samples[b * channels + ch]) * 0.5);
            }
        }
        return out;
    }

    let ratio = from_rate as f64 / to_rate as f64;
    let frames_out = ((frames_in as f64) / ratio).floor() as usize;
    let mut out = Vec::with_capacity(frames_out * channels);
    for frame in 0..frames_out {
        let src_pos = frame as f64 * ratio;
        let idx = src_pos.floor() as usize;
        let frac = src_pos - idx as f64;
        let idx_next = (idx + 1).min(frames_in - 1);
        for ch in 0..channels {
            let s0 = samples[idx * channels + ch] as f64;
            let s1 = samples[idx_next * channels + ch] as f64;
            out.push((s0 + (s1 - s0) * frac) as f32);
        }
    }
    out
}

/// Formats interleaved float samples into the requested response container.
fn encode_audio(
    samples: &[f32],
    sample_rate: u32,
    channels: u16,
    response_format: &str,
) -> Result<Vec<u8>> {
    if response_format.eq_ignore_ascii_case("pcm") {
        Ok(samples_to_pcm_s16le(samples))
    } else {
        samples_to_wav(samples, sample_rate, channels)
    }
}

/// Downmixes/resamples a native audio buffer into `samples`/`sample_rate`/`channels` and encodes it.
fn format_audio(
    samples: &[f32],
    source_rate: u32,
    source_channels: u16,
    options: &SynthesisOptions,
) -> Result<Vec<u8>> {
    let target_channels = options.resolved_channels();
    let target_rate = options.resolved_sample_rate();

    let mixed = convert_channels(samples, source_channels, target_channels);
    let resampled = resample(&mixed, target_channels, source_rate, target_rate);

    encode_audio(
        &resampled,
        target_rate,
        target_channels,
        options.resolved_response_format(),
    )
}

/// Synthesizes speech from natural Vietnamese text into complete audio bytes.
///
/// [voice] and [speed] provide the backward-compatible defaults; when [options]
/// carries a `voice` or `speed` value it takes precedence. Output is 24 kHz mono
/// WAV unless [options] requests another sample rate, channel count, or container.
#[frb]
pub fn synthesize_speech(
    text: String,
    voice: String,
    speed: f32,
    options: Option<SynthesisOptions>,
) -> Result<Vec<u8>> {
    let options = options.unwrap_or_default();
    let lock = ENGINE.lock();
    let state = lock
        .as_ref()
        .ok_or_else(|| anyhow!("Engine has not been initialized. Call init_engine first."))?;

    let requested_voice = options
        .voice
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .unwrap_or(voice.as_str());

    let (codes_path, emb_path) =
        embedded_voices::ensure_voice_files(requested_voice, &state.cache_dir)
            .context("Failed to prepare embedded voice files")?;

    let session = state
        .model
        .create_task_session(
            TaskKind::Tts,
            RunMode::Offline,
            Backend::Cpu,
            0,
            state.threads,
            None,
        )
        .context("Failed to create task session")?;

    let ipa_input = match &state.phonemizer {
        Some(ph) => {
            let res = ph.phonemize(&text);
            if res.is_empty() {
                text.clone()
            } else {
                res
            }
        }
        None => {
            eprintln!("Warning: SEA-G2P phonemizer not available, passing raw text to TTS engine!");
            text.clone()
        }
    };

    let mut req = Request::tts(&ipa_input)
        .option("reference_codes_file", codes_path.to_string_lossy().to_string())
        .option("speaker_embedding_file", emb_path.to_string_lossy().to_string());

    let speaking_rate = options.speed.filter(|s| *s > 0.0).unwrap_or(speed);
    if (speaking_rate - 1.0).abs() > 0.01 {
        req = req.option("speaking_rate", speaking_rate.to_string());
    }

    if let Some(temperature) = options.temperature {
        req = req.option("temperature", temperature);
    }
    if let Some(top_k) = options.top_k {
        req = req.option("top_k", top_k);
    }
    if let Some(top_p) = options.top_p {
        req = req.option("top_p", top_p);
    }
    if let Some(repetition_penalty) = options.repetition_penalty {
        req = req.option("repetition_penalty", repetition_penalty);
    }
    if let Some(max_chars) = options.max_chars.filter(|c| *c > 0) {
        req = req.option("text_chunk_size", max_chars);
    }
    if let Some(min_chars) = options.min_chars.filter(|c| *c > 0) {
        req = req.option("text_chunk_min_size", min_chars);
    }
    if let Some(seed) = options.seed {
        req = req.option("seed", seed);
    }

    let result = session.run_offline(req).context("TTS inference failed")?;
    let audio = result
        .audio_output
        .ok_or_else(|| anyhow!("Model produced no audio output"))?;

    let source_sample_rate = audio.sample_rate as u32;
    let source_channels = audio.channels as u16;
    let samples = audio
        .samples
        .ok_or_else(|| anyhow!("Model audio buffer contained no samples"))?;

    format_audio(&samples, source_sample_rate, source_channels, &options)
}

/// Streams speech chunks in real-time as they are synthesized.
///
/// Output defaults to raw 24 kHz mono `s16le` PCM so consumers can feed chunks
/// straight into an audio sink; pass `response_format: "wav"` for a container.
#[frb]
pub fn stream_speech(
    sink: crate::frb_generated::StreamSink<Vec<u8>>,
    text: String,
    voice: String,
    speed: f32,
    options: Option<SynthesisOptions>,
) -> Result<()> {
    let options = options.unwrap_or_default();
    // Streaming defaults to raw PCM so consumers can pipe chunks directly into an
    // audio sink without stripping a WAV header from every slice.
    let streaming_format = match options.response_format.as_deref() {
        Some(fmt) if !fmt.trim().is_empty() => fmt.to_string(),
        _ => "pcm".to_string(),
    };
    let options = SynthesisOptions {
        response_format: Some(streaming_format),
        ..options
    };
    let audio_bytes = synthesize_speech(text, voice, speed, Some(options))?;

    // Stream out chunks of ~4096 bytes
    const CHUNK_SIZE: usize = 4096;
    for chunk in audio_bytes.chunks(CHUNK_SIZE) {
        sink.add(chunk.to_vec())
            .map_err(|e| anyhow!("Stream sink error: {:?}", e))?;
    }

    Ok(())
}

/// Disposes and unloads the native engine.
#[frb]
pub fn dispose_engine() -> Result<()> {
    let mut lock = ENGINE.lock();
    *lock = None;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(frames: usize, channels: u16, freq: f32, sample_rate: u32) -> Vec<f32> {
        let mut out = Vec::with_capacity(frames * channels as usize);
        for frame in 0..frames {
            let t = frame as f32 / sample_rate as f32;
            let value = (2.0 * std::f32::consts::PI * freq * t * 0.5).sin();
            for _ in 0..channels {
                out.push(value);
            }
        }
        out
    }

    #[test]
    fn downmixes_stereo_to_mono_by_averaging() {
        let stereo = vec![1.0, 0.0, 0.5, 0.5, -1.0, 1.0, 0.25, -0.25];
        let mono = convert_channels(&stereo, 2, 1);
        assert_eq!(mono, vec![0.5, 0.5, 0.0, 0.0]);
    }

    #[test]
    fn upmixes_mono_to_stereo_by_duplication() {
        let mono = vec![0.1, -0.2, 0.3];
        let stereo = convert_channels(&mono, 1, 2);
        assert_eq!(stereo, vec![0.1, 0.1, -0.2, -0.2, 0.3, 0.3]);
    }

    #[test]
    fn channel_conversion_is_identity_when_counts_match() {
        let samples = vec![0.1, 0.2, 0.3, 0.4];
        assert_eq!(convert_channels(&samples, 2, 2), samples);
        assert_eq!(convert_channels(&samples, 1, 1), samples);
    }

    #[test]
    fn decimates_48k_to_24k_with_two_point_average() {
        let samples = vec![1.0, 0.0, 0.5, 0.5, -1.0, 1.0, 0.25, -0.25];
        let out = resample(&samples, 1, 48_000, 24_000);
        assert_eq!(out, vec![0.5, 0.5, 0.0, 0.0]);
    }

    #[test]
    fn decimation_halves_the_frame_count_per_channel() {
        let stereo = sine(480, 2, 440.0, 48_000);
        let out = resample(&stereo, 2, 48_000, 24_000);
        assert_eq!(out.len() * 2, stereo.len());
    }

    #[test]
    fn resamples_to_16k_with_linear_interpolation() {
        let samples = sine(4_800, 1, 220.0, 48_000);
        let out = resample(&samples, 1, 48_000, 16_000);
        // 100 ms of audio at 16 kHz is 1600 frames.
        assert_eq!(out.len(), 1_600);
    }

    #[test]
    fn resamples_to_8k_with_linear_interpolation() {
        let samples = sine(4_800, 1, 220.0, 48_000);
        let out = resample(&samples, 1, 48_000, 8_000);
        // 100 ms of audio at 8 kHz is 800 frames.
        assert_eq!(out.len(), 800);
    }

    #[test]
    fn resampling_is_identity_at_the_same_rate() {
        let samples = sine(100, 2, 200.0, 48_000);
        assert_eq!(resample(&samples, 2, 48_000, 48_000), samples);
    }

    #[test]
    fn resampled_signal_preserves_peak_amplitude() {
        let samples = sine(9_600, 1, 200.0, 48_000);
        let out = resample(&samples, 1, 48_000, 24_000);
        let peak = out.iter().fold(0.0f32, |acc, s| acc.max(s.abs()));
        assert!(peak > 0.9, "peak amplitude collapsed to {peak}");
    }

    #[test]
    fn raw_pcm_has_exactly_two_bytes_per_sample_and_no_header() {
        let samples = sine(240, 1, 440.0, 24_000);
        let pcm = encode_audio(&samples, 24_000, 1, "pcm").unwrap();
        assert_eq!(pcm.len(), samples.len() * 2);
        assert!(!pcm.starts_with(b"RIFF"));
        assert!(!pcm.starts_with(b"WAVE"));
    }

    #[test]
    fn raw_pcm_byte_length_scales_with_channel_count() {
        let samples = sine(120, 2, 440.0, 24_000);
        let pcm = encode_audio(&samples, 24_000, 2, "pcm").unwrap();
        assert_eq!(pcm.len(), samples.len() * 2);
    }

    #[test]
    fn pcm_encoding_is_case_insensitive() {
        let samples = vec![0.0f32; 8];
        let lower = encode_audio(&samples, 24_000, 1, "pcm").unwrap();
        let upper = encode_audio(&samples, 24_000, 1, "PCM").unwrap();
        assert_eq!(lower, upper);
    }

    #[test]
    fn pcm_clamps_out_of_range_samples() {
        let pcm = encode_audio(&[2.0, -2.0], 24_000, 1, "pcm").unwrap();
        assert_eq!(i16::from_le_bytes([pcm[0], pcm[1]]), i16::MAX);
        assert_eq!(i16::from_le_bytes([pcm[2], pcm[3]]), -i16::MAX);
    }

    #[test]
    fn wav_output_has_valid_44_byte_riff_header() {
        let samples = sine(240, 1, 440.0, 24_000);
        let wav = encode_audio(&samples, 24_000, 1, "wav").unwrap();

        assert!(wav.starts_with(b"RIFF"));
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(&wav[12..16], b"fmt ");
        assert_eq!(wav.len(), samples.len() * 2 + 44);

        let reader = hound::WavReader::new(std::io::Cursor::new(&wav)).unwrap();
        let spec = reader.spec();
        assert_eq!(spec.sample_rate, 24_000);
        assert_eq!(spec.channels, 1);
        assert_eq!(spec.bits_per_sample, 16);
        assert_eq!(reader.len() as usize, samples.len());
    }

    #[test]
    fn wav_header_reports_requested_sample_rate_and_channels() {
        let samples = sine(240, 2, 440.0, 16_000);
        let wav = encode_audio(&samples, 16_000, 2, "wav").unwrap();

        let reader = hound::WavReader::new(std::io::Cursor::new(&wav)).unwrap();
        let spec = reader.spec();
        assert_eq!(spec.sample_rate, 16_000);
        assert_eq!(spec.channels, 2);
    }

    #[test]
    fn unknown_format_falls_back_to_wav_container() {
        let wav = encode_audio(&[0.0f32; 16], 24_000, 1, "mp3").unwrap();
        assert!(wav.starts_with(b"RIFF"));
    }

    #[test]
    fn format_audio_applies_default_24k_mono_wav() {
        let stereo_48k = sine(960, 2, 300.0, 48_000);
        let output = format_audio(&stereo_48k, 48_000, 2, &SynthesisOptions::default()).unwrap();

        assert!(output.starts_with(b"RIFF"));
        let reader = hound::WavReader::new(std::io::Cursor::new(&output)).unwrap();
        let spec = reader.spec();
        assert_eq!(spec.sample_rate, 24_000);
        assert_eq!(spec.channels, 1);
        // 960 stereo frames at 48 kHz -> 960 mono samples -> 480 at 24 kHz.
        assert_eq!(reader.len() as usize, 480);
    }

    #[test]
    fn format_audio_honours_pcm_format_and_downmix() {
        let stereo_48k = sine(960, 2, 300.0, 48_000);
        let options = SynthesisOptions {
            sample_rate: Some(24_000),
            channels: Some(1),
            response_format: Some("pcm".to_string()),
            ..Default::default()
        };
        let output = format_audio(&stereo_48k, 48_000, 2, &options).unwrap();

        assert!(!output.starts_with(b"RIFF"));
        assert_eq!(output.len(), 480 * 2);
    }

    #[test]
    fn format_audio_preserves_native_48k_stereo() {
        let stereo_48k = sine(512, 2, 300.0, 48_000);
        let options = SynthesisOptions {
            sample_rate: Some(48_000),
            channels: Some(2),
            response_format: Some("pcm".to_string()),
            ..Default::default()
        };
        let output = format_audio(&stereo_48k, 48_000, 2, &options).unwrap();
        assert_eq!(output.len(), stereo_48k.len() * 2);
    }

    #[test]
    fn format_audio_upsamples_mono_output_to_stereo_when_requested() {
        let mono_48k = sine(960, 1, 300.0, 48_000);
        let options = SynthesisOptions {
            sample_rate: Some(24_000),
            channels: Some(2),
            response_format: Some("pcm".to_string()),
            ..Default::default()
        };
        let output = format_audio(&mono_48k, 48_000, 1, &options).unwrap();
        // 480 frames x 2 channels x 2 bytes.
        assert_eq!(output.len(), 480 * 2 * 2);
    }

    #[test]
    fn options_defaults_match_backward_compatible_behaviour() {
        let options = SynthesisOptions::default();
        assert_eq!(options.resolved_sample_rate(), 24_000);
        assert_eq!(options.resolved_channels(), 1);
        assert_eq!(options.resolved_response_format(), "wav");
    }

    #[test]
    fn options_ignore_invalid_zero_values() {
        let options = SynthesisOptions {
            sample_rate: Some(0),
            channels: Some(0),
            response_format: Some("   ".to_string()),
            ..Default::default()
        };
        assert_eq!(options.resolved_sample_rate(), 24_000);
        assert_eq!(options.resolved_channels(), 1);
        assert_eq!(options.resolved_response_format(), "wav");
    }

    #[test]
    fn options_honour_explicit_values() {
        let options = SynthesisOptions {
            sample_rate: Some(16_000),
            channels: Some(2),
            speed: Some(1.25),
            response_format: Some("pcm".to_string()),
            ..Default::default()
        };
        assert_eq!(options.resolved_sample_rate(), 16_000);
        assert_eq!(options.resolved_channels(), 2);
        assert_eq!(options.resolved_response_format(), "pcm");
        assert_eq!(options.speed, Some(1.25));
    }

    #[test]
    fn every_supported_sample_rate_produces_a_consistent_duration() {
        let source = sine(48_000, 1, 200.0, 48_000); // exactly 1 second
        for rate in SUPPORTED_SAMPLE_RATES {
            let out = resample(&source, 1, 48_000, rate);
            assert_eq!(
                out.len() as u32, rate,
                "1 second of audio should resample to {rate} frames"
            );
        }
    }
}
