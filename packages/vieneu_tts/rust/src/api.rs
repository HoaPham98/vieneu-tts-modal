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

    let registry = Registry::new().context("Failed to create audio.cpp Registry")?;
    let family_hint = ModelFamily::from_path(&model_path).unwrap_or(ModelFamily::VieneuV3Turbo);
    let model = registry
        .load(&model_path, Some(family_hint.clone()), None)
        .or_else(|_| registry.load(&model_path, Some(ModelFamily::VieneuV3Turbo), None))
        .or_else(|_| registry.load(&model_path, None, None))
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

/// Helper function to convert raw Float32 audio samples (48kHz stereo) into standard 16-bit PCM WAV bytes.
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

/// Synthesizes speech from natural Vietnamese text into complete 48 kHz stereo WAV bytes.
#[frb]
pub fn synthesize_speech(text: String, voice: String, speed: f32) -> Result<Vec<u8>> {
    let lock = ENGINE.lock();
    let state = lock
        .as_ref()
        .ok_or_else(|| anyhow!("Engine has not been initialized. Call init_engine first."))?;

    let (codes_path, emb_path) =
        embedded_voices::ensure_voice_files(&voice, &state.cache_dir)
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

    if (speed - 1.0).abs() > 0.01 {
        req = req.option("speaking_rate", speed.to_string());
    }

    let result = session.run_offline(req).context("TTS inference failed")?;
    let audio = result
        .audio_output
        .ok_or_else(|| anyhow!("Model produced no audio output"))?;

    let sample_rate = audio.sample_rate as u32;
    let channels = audio.channels as u16;
    let samples = audio
        .samples
        .ok_or_else(|| anyhow!("Model audio buffer contained no samples"))?;

    samples_to_wav(&samples, sample_rate, channels)
}

/// Streams speech chunks in real-time as they are synthesized.
#[frb]
pub fn stream_speech(
    sink: crate::frb_generated::StreamSink<Vec<u8>>,
    text: String,
    voice: String,
    speed: f32,
) -> Result<()> {
    let wav_bytes = synthesize_speech(text, voice, speed)?;

    // Stream out chunks of ~4096 bytes
    const CHUNK_SIZE: usize = 4096;
    for chunk in wav_bytes.chunks(CHUNK_SIZE) {
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
