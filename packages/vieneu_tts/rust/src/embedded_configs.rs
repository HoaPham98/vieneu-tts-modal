use std::fs;
use std::path::Path;
use anyhow::{Context, Result};

pub const MODEL_SPEC_JSON: &str = include_str!("../assets/model_spec.json");
pub const CONFIG_JSON: &str = include_str!("../assets/config.json");
pub const TOKENIZER_CONFIG_JSON: &str = include_str!("../assets/tokenizer_config.json");
pub const SPEECH_TOKENIZER_CONFIG_JSON: &str = include_str!("../assets/speech_tokenizer_config.json");

/// Ensures that audio.cpp model specification and config sidecar JSON files
/// exist in the directory containing the GGUF model.
///
/// audio.cpp requires these files to discover the package spec and load
/// the model architecture, tokenizers, and weights.
pub fn ensure_model_configs(model_path: &Path) -> Result<()> {
    let dir = match model_path.parent() {
        Some(p) => p,
        None => return Ok(()),
    };

    // 1. Root model spec candidates checked by discover_external_model_spec
    let spec_path = dir.join("model_spec.json");
    if !spec_path.exists() {
        let _ = fs::write(&spec_path, MODEL_SPEC_JSON);
    }
    let family_spec_path = dir.join("vieneu_v3_turbo.json");
    if !family_spec_path.exists() {
        let _ = fs::write(&family_spec_path, MODEL_SPEC_JSON);
    }

    // 2. model_specs/ directory candidate
    let model_specs_dir = dir.join("model_specs");
    if !model_specs_dir.exists() {
        let _ = fs::create_dir_all(&model_specs_dir);
    }
    let sub_spec = model_specs_dir.join("vieneu_v3_turbo.json");
    if !sub_spec.exists() {
        let _ = fs::write(&sub_spec, MODEL_SPEC_JSON);
    }

    // 3. config.json
    let config_path = dir.join("config.json");
    if !config_path.exists() {
        fs::write(&config_path, CONFIG_JSON)
            .context("Failed to write embedded config.json")?;
    }

    // 4. tokenizer_config.json
    let tok_config_path = dir.join("tokenizer_config.json");
    if !tok_config_path.exists() {
        fs::write(&tok_config_path, TOKENIZER_CONFIG_JSON)
            .context("Failed to write embedded tokenizer_config.json")?;
    }

    // 5. speech_tokenizer/config.json
    let speech_tok_dir = dir.join("speech_tokenizer");
    if !speech_tok_dir.exists() {
        let _ = fs::create_dir_all(&speech_tok_dir);
    }
    let speech_tok_config = speech_tok_dir.join("config.json");
    if !speech_tok_config.exists() {
        fs::write(&speech_tok_config, SPEECH_TOKENIZER_CONFIG_JSON)
            .context("Failed to write embedded speech_tokenizer/config.json")?;
    }

    Ok(())
}
