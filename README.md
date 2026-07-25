# Quran (`quran.koplugin`)

A Quran companion plugin for [KOReader](https://github.com/koreader/koreader),
built around the Quran EPUB library from the
[quran-ebook](https://github.com/zeeyado/quran-ebook) project.

> **Status: early beta (v0.1.x), work in progress.**
> This plugin just moved out of the quran-ebook monorepo into its own repo
> and restarted its version numbering. It is functional and in daily use,
> but menus, settings, and features are still being reshaped, and there is
> **no packaged release yet**: installing from this repo is for testers.
> If you previously installed a `1.x` (or `9.x` test) build, the version
> restart means the self-updater will not offer `0.x`: delete the old
> `quran.koplugin/` folder once and install fresh.

## What it does

- **Explorer**: a Quran library browser with surahs, juz', and per-ayah
  navigation, search, and reading-position restore.
- **Ayah card & quick panel**: tap an ayah marker for the translation,
  tafsir, word-by-word grammar, and cross-references.
- **Tafsir reader** with multi-edition switching.
- **Word dictionary filtering**: dictionary popups automatically show the
  entry for the exact word at the current ayah position.
- **Grammar, surah-overview, and tafsir lookups** from StarDict packages.
- **Roots browser** (Lane's Lexicon), **similar-ayah and thematic
  connections**, and **phrase-occurrence views** (QUL data packages).
- **Juz'/hizb-aware header and footer**, Hafs/Warsh-aware ayah numbering.
- **Library & assets**: in-app downloads for books, dictionaries, and
  data packages.

## Install (testers)

1. Download this repo as ZIP (green **Code** button → Download ZIP) and
   unzip.
2. Rename the unzipped folder to exactly `quran.koplugin` (strip any
   `-main` suffix) and place it inside KOReader's `plugins/` folder:

| Platform | Path |
|----------|------|
| Android | `/sdcard/koreader/plugins/` |
| Kobo | `/mnt/onboard/.adds/koreader/plugins/` |
| Kindle | `/mnt/us/koreader/plugins/` |
| Desktop (Linux) | `~/.config/koreader/plugins/` |
| Desktop (macOS) | `~/Library/Application Support/koreader/plugins/` |

The structure must be `plugins/quran.koplugin/main.lua` (no nested
folder).

3. Restart KOReader, open a Quran book, and go to Top Menu → Tool icon →
   **Quran**.
4. Get books and companion assets from **Library & assets** (in the Quran
   Explorer, the quick panel, or the plugin menu): the EPUBs, StarDict
   dictionaries, and data packages install from there, no manual
   unzipping.

The EPUBs themselves (and manual asset ZIPs, as a fallback) live on the
[quran-ebook releases page](https://github.com/zeeyado/quran-ebook/releases).

One KOReader setting the plugin needs for footer juz' display:
Status bar → Status bar items → check **External content**.

## Feedback

Beta feedback is what this phase is for. Please
[open an issue](../../issues) for anything: crashes, popups showing the
wrong entry, navigation dead-ends, confusing menus/labels, or layout
problems on your device (mention device + KOReader version).

## Development

Repo root **is** the plugin (KOReader zipball convention). Dev tooling
lives in [`dev/`](dev/): test harness, CI, and the headless screenshot
rig. See [`dev/README.md`](dev/README.md). The plugin's asset builders
(dictionaries, data packages) live in the
[quran-ebook](https://github.com/zeeyado/quran-ebook) repo.

## License

[GPL-3.0](LICENSE). Data and font credits are listed in the
[quran-ebook README](https://github.com/zeeyado/quran-ebook#credits).
