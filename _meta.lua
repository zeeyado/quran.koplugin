local _ = require("gettext")
return {
    name = "quran",
    version = "0.1.0",
    fullname = _("Quran Helper"),
    description = _([[
Quran companion plugin for KOReader (early beta).

Designed around the Quran EPUB library from the quran-ebook project.
Features:
- Explorer: surah/juz library browser with per-ayah navigation,
  search, and reading-position restore
- Ayah card and quick panel: tap an ayah marker for translation,
  tafsir, word-by-word grammar, and cross-references
- Tafsir reader with multi-edition switching
- Per-instance word dictionary filtering and grammar/surah-overview
  lookups (StarDict packages)
- Roots browser (Lane), similar-ayah and thematic connections,
  phrase-occurrence views (QUL data packages)
- Juz/hizb-aware header and footer, Hafs/Warsh-aware numbering
- In-app downloads for books, dictionaries, and data packages]]),
}
