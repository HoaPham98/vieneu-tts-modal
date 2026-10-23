use std::fs;
use std::path::{Path, PathBuf};

pub struct VoiceData {
    pub id: &'static str,
    /// Natural display name shown in the public catalog (e.g. "Mai Anh").
    pub name: &'static str,
    pub ref_codes: &'static str,
    pub speaker_emb: &'static str,
}

macro_rules! voice {
    ($id:ident, $name:expr, $path:expr) => {
        VoiceData {
            id: stringify!($id),
            name: $name,
            ref_codes: include_str!(concat!("../../../../preset_voices/", $path, "/ref_codes.txt")),
            speaker_emb: include_str!(concat!("../../../../preset_voices/", $path, "/speaker.emb.txt")),
        }
    };
}

pub static VOICES: &[VoiceData] = &[
    voice!(minh_quan_pro, "Minh Quân Pro", "minh_quan_pro"),
    voice!(ngoc_huyen, "Ngọc Huyền", "ngoc_huyen"),
    voice!(mai_anh, "Mai Anh", "mai_anh"),
    voice!(thuy_dung, "Thùy Dung", "thuy_dung"),
    voice!(quang_son, "Quang Sơn", "quang_son"),
    voice!(ngoc_tran, "Ngọc Trân", "ngoc_tran"),
    voice!(anh_khoi, "Anh Khôi", "anh_khoi"),
    voice!(truc_ly, "Trúc Ly", "truc_ly"),
    voice!(adam_bua, "Adam bựa", "adam_bua"),
    voice!(thien_tam_duc, "Thiền Tâm Đức", "thien_tam_duc"),
    voice!(minh_duc, "Minh Đức", "minh_duc"),
    voice!(pham_tuyen, "Phạm Tuyên", "pham_tuyen"),
    voice!(thai_son, "Thái Sơn", "thai_son"),
    voice!(xuan_vinh, "Xuân Vĩnh", "xuan_vinh"),
    voice!(thanh_binh, "Thanh Bình", "thanh_binh"),
    voice!(ngoc_linh, "Ngọc Linh", "ngoc_linh"),
    voice!(doan_trang, "Đoan Trang", "doan_trang"),
    voice!(thuc_doan, "Thục Đoan", "thuc_doan"),
    voice!(minh_triet, "Minh Triết", "minh_triet"),
    voice!(my_duyen, "Mỹ Duyên", "my_duyen"),
    voice!(quynh_anh, "Quỳnh Anh", "quynh_anh"),
    voice!(duc_tri, "Đức Trí", "duc_tri"),
    voice!(kim_thanh, "Kim Thanh", "kim_thanh"),
    voice!(adam, "Adam", "adam"),
    voice!(manh_dung, "Mạnh Dũng", "manh_dung"),
];

/// Folds a Vietnamese character to its unaccented ASCII base form.
fn fold_char(c: char) -> Option<char> {
    let folded = match c {
        'a' | 'à' | 'á' | 'ạ' | 'ả' | 'ã' | 'â' | 'ầ' | 'ấ' | 'ậ' | 'ẩ' | 'ẫ' | 'ă' | 'ằ' | 'ắ'
        | 'ặ' | 'ẳ' | 'ẵ' => 'a',
        'e' | 'è' | 'é' | 'ẹ' | 'ẻ' | 'ẽ' | 'ê' | 'ề' | 'ế' | 'ệ' | 'ể' | 'ễ' => 'e',
        'i' | 'ì' | 'í' | 'ị' | 'ỉ' | 'ĩ' => 'i',
        'o' | 'ò' | 'ó' | 'ọ' | 'ỏ' | 'õ' | 'ô' | 'ồ' | 'ố' | 'ộ' | 'ổ' | 'ỗ' | 'ơ' | 'ờ' | 'ớ'
        | 'ợ' | 'ở' | 'ỡ' => 'o',
        'u' | 'ù' | 'ú' | 'ụ' | 'ủ' | 'ũ' | 'ư' | 'ừ' | 'ứ' | 'ự' | 'ử' | 'ữ' => 'u',
        'y' | 'ỳ' | 'ý' | 'ỵ' | 'ỷ' | 'ỹ' => 'y',
        'd' | 'đ' => 'd',
        _ => return c.is_ascii_alphanumeric().then_some(c),
    };
    Some(folded)
}

/// Normalizes a user-provided voice identifier for comparison.
///
/// Lowercases, folds Vietnamese diacritics, and drops every separator so that
/// preset IDs (`minh_quan_pro`) and display names (`Minh Quân Pro`) collapse to
/// the same key (`minhquanpro`).
pub fn normalize_voice_key(voice: &str) -> String {
    voice
        .trim()
        .to_lowercase()
        .chars()
        .filter_map(fold_char)
        .collect()
}

/// Resolves a voice identifier or display name to its embedded reference codes
/// and speaker embedding data, falling back to `minh_quan_pro` when unknown.
pub fn get_voice_data(voice_id: &str) -> &'static VoiceData {
    let key = normalize_voice_key(voice_id);
    if !key.is_empty() {
        for v in VOICES {
            if normalize_voice_key(v.id) == key || normalize_voice_key(v.name) == key {
                return v;
            }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_voice_by_preset_id() {
        assert_eq!(get_voice_data("mai_anh").id, "mai_anh");
        assert_eq!(get_voice_data("minh_quan_pro").id, "minh_quan_pro");
        assert_eq!(get_voice_data("ngoc_huyen").id, "ngoc_huyen");
    }

    #[test]
    fn resolves_voice_by_display_name() {
        assert_eq!(get_voice_data("Mai Anh").id, "mai_anh");
        assert_eq!(get_voice_data("Minh Quân Pro").id, "minh_quan_pro");
        assert_eq!(get_voice_data("Adam bựa").id, "adam_bua");
        assert_eq!(get_voice_data("Thiền Tâm Đức").id, "thien_tam_duc");
    }

    #[test]
    fn resolution_is_case_insensitive_and_whitespace_tolerant() {
        assert_eq!(get_voice_data("MAI_ANH").id, "mai_anh");
        assert_eq!(get_voice_data("  mai anh  ").id, "mai_anh");
        assert_eq!(get_voice_data("MaiAnh").id, "mai_anh");
        assert_eq!(get_voice_data("mAi AnH").id, "mai_anh");
    }

    #[test]
    fn resolves_diacritic_insensitive_input() {
        assert_eq!(get_voice_data("mai anh").id, "mai_anh");
        assert_eq!(get_voice_data("minh quan pro").id, "minh_quan_pro");
        assert_eq!(get_voice_data("thien tam duc").id, "thien_tam_duc");
        assert_eq!(get_voice_data("thuy dung").id, "thuy_dung");
    }

    #[test]
    fn falls_back_to_default_for_unknown_voice() {
        assert_eq!(get_voice_data("khong_ton_tai").id, "minh_quan_pro");
        assert_eq!(get_voice_data("").id, "minh_quan_pro");
        assert_eq!(get_voice_data("   ").id, "minh_quan_pro");
        assert_eq!(get_voice_data("unrecognized voice name").id, "minh_quan_pro");
    }

    #[test]
    fn every_preset_resolves_from_its_own_id_and_name() {
        for v in VOICES {
            assert_eq!(get_voice_data(v.id).id, v.id, "id {} did not resolve", v.id);
            assert_eq!(get_voice_data(v.name).id, v.id, "name {} did not resolve", v.name);
        }
    }

    #[test]
    fn normalizes_ids_and_display_names_to_the_same_key() {
        assert_eq!(normalize_voice_key("Mai Anh"), normalize_voice_key("mai_anh"));
        assert_eq!(
            normalize_voice_key("Minh Quân Pro"),
            normalize_voice_key("minh_quan_pro")
        );
    }
}
