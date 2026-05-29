//! Bilingual (EN/TR) text selection, shared by every Rust surface.
//!
//! Every user-facing string in the engine and CLI goes through
//! [`Language::text`] so we never ship a one-language string (project rule).
//! Detection honors an explicit `CONTEXTBAR_LANG=en|tr` override first, then
//! the standard locale env vars.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Language {
    En,
    Tr,
}

impl Language {
    /// Resolve the UI language: `CONTEXTBAR_LANG` override, else locale env.
    pub fn detect() -> Self {
        if let Ok(forced) = std::env::var("CONTEXTBAR_LANG") {
            let f = forced.trim().to_ascii_lowercase();
            if f.starts_with("tr") {
                return Self::Tr;
            }
            if f.starts_with("en") {
                return Self::En;
            }
        }
        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let Ok(value) = std::env::var(key) {
                if value.to_ascii_lowercase().starts_with("tr") {
                    return Self::Tr;
                }
                if !value.is_empty() {
                    return Self::En;
                }
            }
        }
        Self::En
    }

    /// Pick the English or Turkish variant.
    pub fn text(self, en: &'static str, tr: &'static str) -> &'static str {
        match self {
            Self::En => en,
            Self::Tr => tr,
        }
    }
}
