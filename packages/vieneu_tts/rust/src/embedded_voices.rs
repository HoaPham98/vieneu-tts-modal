use std::fs;
use std::path::{Path, PathBuf};

pub struct VoiceData {
    pub id: &'static str,
    pub ref_codes: &'static str,
    pub speaker_emb: &'static str,
}

macro_rules! voice {
    ($id:ident, $path:expr) => {
        VoiceData {
            id: stringify!($id),
            ref_codes: include_str!(concat!("../../../preset_voices/", $path, "/ref_codes.txt")),
            speaker_emb: include_str!(concat!("../../../preset_voices/", $path, "/speaker.emb.txt")),
        }
    };
}

pub static VOICES: &[VoiceData] = &[
    voice!(minh_quan_pro, "minh_quan_pro"),
    voice!(ngoc_huyen, "ngoc_huyen"),
    voice!(mai_anh, "mai_anh"),
    voice!(thuy_dung, "thuy_dung"),
    voice!(quang_son, "quang_son"),
    voice!(ngoc_tran, "ngoc_tran"),
    voice!(anh_khoi, "anh_khoi"),
    voice!(truc_ly, "truc_ly"),
    voice!(adam_bua, "adam_bua"),
    voice!(thien_tam_duc, "thien_tam_duc"),
    voice!(minh_duc, "minh_duc"),
    voice!(pham_tuyen, "pham_tuyen"),
    voice!(thai_son, "thai_son"),
    voice!(xuan_vinh, "xuan_vinh"),
    voice!(thanh_binh, "thanh_binh"),
    voice!(ngoc_linh, "ngoc_linh"),
    voice!(doan_trang, "doan_trang"),
    voice!(thuc_doan, "thuc_doan"),
    voice!(minh_triet, "minh_triet"),
    voice!(my_duyen, "my_duyen"),
    voice!(quynh_anh, "quynh_anh"),
    voice!(duc_tri, "duc_tri"),
    voice!(kim_thanh, "kim_thanh"),
    voice!(adam, "adam"),
    voice!(manh_dung, "manh_dung"),
];

/// Resolves a voice ID to its embedded reference codes and speaker embedding data.
pub fn get_voice_data(voice_id: &str) -> &'static VoiceData {
    let clean = voice_id.trim().to_lowercase();
    for v in VOICES {
        if v.id == clean {
            return v;
        }
    }
    // Default fallback: minh_quan_pro
    &VOICES[0]
}

/// Ensures the reference codes and speaker embedding text files are written to [cache_dir],
/// returning the paths to (ref_codes_file, speaker_embedding_file).
pub fn ensure_voice_files(voice_id: &str, cache_dir: &Path) -> std::io::Result<(PathBuf, PathBuf)> {
    let voice = get_voice_data(voice_id);
    let voice_dir = cache_dir.join("voices").join(voice.id);
    fs::create_dir_all(&voice_dir)?;

    let codes_path = voice_dir.join("ref_codes.txt");
    let emb_path = voice_dir.join("speaker.emb.txt");

    if !codes_path.exists() {
        fs::write(&codes_path, voice.ref_codes)?;
    }
    if !emb_path.exists() {
        fs::write(&emb_path, voice.speaker_emb)?;
    }

    Ok((codes_path, emb_path))
}
