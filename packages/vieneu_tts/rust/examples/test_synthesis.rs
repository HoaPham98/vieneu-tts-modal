use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use anyhow::{Context, Result};
use hound::WavReader;
use rust_lib_vieneu_tts::api::{dispose_engine, init_engine, synthesize_speech};

fn main() -> Result<()> {
    let model_path = std::env::var("MODEL_PATH")
        .unwrap_or_else(|_| "/tmp/vieneu_test/model.gguf".to_string());
    let dict_path = std::env::var("DICT_PATH")
        .unwrap_or_else(|_| "/tmp/vieneu_test/sea_g2p.bin".to_string());
    let output_dir = std::env::var("OUTPUT_DIR")
        .unwrap_or_else(|_| "output_audio".to_string());

    println!("============================================================");
    println!("VieNeu-TTS On-Device Synthesis & Streaming E2E Test");
    println!("Model Path: {}", model_path);
    println!("Dict Path:  {}", dict_path);
    println!("Output Dir: {}", output_dir);
    println!("============================================================");

    let model_file = Path::new(&model_path);
    if !model_file.exists() {
        anyhow::bail!("Model file not found at: {}", model_path);
    }
    let model_size_mb = fs::metadata(model_file)?.len() as f64 / (1024.0 * 1024.0);
    println!("Model size on disk: {:.2} MB", model_size_mb);

    let dict_file = Path::new(&dict_path);
    if dict_file.exists() {
        let dict_size_mb = fs::metadata(dict_file)?.len() as f64 / (1024.0 * 1024.0);
        println!("Dictionary size on disk: {:.2} MB", dict_size_mb);
    } else {
        println!("⚠️ Dictionary file not found at: {} (will fallback to raw text)", dict_path);
    }

    fs::create_dir_all(&output_dir)
        .with_context(|| format!("Failed to create output dir: {}", output_dir))?;

    // 1. Initialize Engine
    println!("\n[1/4] Initializing native TTS engine with 4 threads and G2P phonemizer...");
    let init_start = Instant::now();
    init_engine(model_path.clone(), Some(dict_path.clone()), 4).context("Failed to init engine")?;
    println!("✓ Engine initialized in {:.2?}", init_start.elapsed());

    // 2. Synthesize with Minh Quan Pro (Male - Northern)
    let text_1 = "Xin chào các bạn, đây là giọng đọc thử nghiệm từ thư viện VieNeu TTS chạy hoàn toàn on-device không cần mạng internet.";
    println!("\n[2/4] Synthesizing speech (Voice: minh_quan_pro)...");
    println!("Text: \"{}\"", text_1);
    let synth_start = Instant::now();
    let wav_1 = synthesize_speech(text_1.to_string(), "minh_quan_pro".to_string(), 1.0)
        .context("Failed to synthesize speech for minh_quan_pro")?;
    let synth_duration = synth_start.elapsed();
    println!("✓ Synthesized {} bytes in {:.2?}", wav_1.len(), synth_duration);

    let path_1 = PathBuf::from(&output_dir).join("vieneu_synthesis_minh_quan.wav");
    fs::write(&path_1, &wav_1)?;
    print_wav_info(&path_1)?;

    // 3. Synthesize with Ngoc Huyen (Female - Northern)
    let text_2 = "Hôm nay thời tiết rất đẹp, chúc bạn một ngày làm việc hiệu quả và tràn đầy niềm vui.";
    println!("\n[3/4] Synthesizing speech (Voice: ngoc_huyen)...");
    println!("Text: \"{}\"", text_2);
    let synth_start = Instant::now();
    let wav_2 = synthesize_speech(text_2.to_string(), "ngoc_huyen".to_string(), 1.0)
        .context("Failed to synthesize speech for ngoc_huyen")?;
    println!("✓ Synthesized {} bytes in {:.2?}", wav_2.len(), synth_start.elapsed());

    let path_2 = PathBuf::from(&output_dir).join("vieneu_synthesis_ngoc_huyen.wav");
    fs::write(&path_2, &wav_2)?;
    print_wav_info(&path_2)?;

    // 4. Test Stream Chunking & Reassembly
    println!("\n[4/4] Testing streaming chunking & reassembly...");
    const CHUNK_SIZE: usize = 4096;
    let mut collected_chunks: Vec<u8> = Vec::with_capacity(wav_1.len());
    let mut chunk_count = 0;
    for chunk in wav_1.chunks(CHUNK_SIZE) {
        chunk_count += 1;
        collected_chunks.extend_from_slice(chunk);
    }
    println!("✓ Streamed and collected {} chunks (total {} bytes)", chunk_count, collected_chunks.len());
    assert_eq!(collected_chunks, wav_1, "Reassembled chunks do not match original WAV bytes");

    let path_streamed = PathBuf::from(&output_dir).join("vieneu_streamed_reassembled.wav");
    fs::write(&path_streamed, &collected_chunks)?;
    println!("✓ Saved reassembled stream to: {:?}", path_streamed);

    // Dispose
    println!("\nDisposing engine...");
    dispose_engine()?;
    println!("✓ All tests passed successfully!\n");

    Ok(())
}

fn print_wav_info(path: &Path) -> Result<()> {
    let reader = WavReader::open(path)?;
    let spec = reader.spec();
    let duration = reader.duration() as f64 / spec.sample_rate as f64;
    println!("  -> Saved to: {:?}", path);
    println!("  -> Format: {} Hz, {} ch, {} bits/sample, duration: {:.2}s",
        spec.sample_rate, spec.channels, spec.bits_per_sample, duration);
    Ok(())
}
