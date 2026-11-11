# Dev tooling

Everything in `dev/` is excluded from the GitHub zipball via
`.gitattributes export-ignore`: only the plugin's runtime files ship.

## Helper harness

`dev/check_plugin_helpers.lua` is the plugin's test suite: it extracts
code **live** from the plugin sources (so tested code can't drift from
shipped code) and runs behavioral pins against mocked KOReader modules.
It must end with `ALL HELPER TESTS PASS`.

Run from the repo root:

```zsh
# Full run (macOS, KOReader installed, quran-ebook as sister checkout):
/Applications/KOReader.app/Contents/koreader/luajit dev/check_plugin_helpers.lua

# Anywhere with a stock LuaJIT (KOReader-native and real-db sections
# self-skip; this is what CI runs):
luajit dev/check_plugin_helpers.lua
```

Path resolution (all auto-detected, override via env):

| Env | Default | Provides |
|-----|---------|----------|
| `QURAN_PLUGIN_DIR` | `.` (repo root) | the plugin sources under test |
| `QURAN_EBOOK_DIR` | `../quran-ebook` | `data/*.sqlite` + `output/` build artifacts for the real-db round trips (skip when absent) |
| `KOREADER_DIR` | `/Applications/KOReader.app/Contents/koreader` | sqlite binding + CREngine for the real-document tests (skip when absent) |

Full run on the reference setup: 2203 tests (2026-11-11). Stock-luajit
run without KOReader/data: 1664 tests + skips, still authoritative for
everything that ran.

CI (`.github/workflows/check.yml`) parse-checks every Lua file and runs
the harness on stock LuaJIT.

## Headless screenshots (macOS)

KOReader can screenshot itself, so no screen-recording permission is needed.
`dev/patches/2-quran-shot.lua` is a KOReader
[userpatch](https://github.com/koreader/koreader/wiki/User-patches),
env-gated on `KO_MECHTEST`, that opens a plugin surface and captures it.

```zsh
KOHOME=/tmp/kohome            # isolated profile, never your real one
BOOK=/tmp/kobooks/book.epub   # a COPY of the book, never the original:
                              # KOReader writes the book's settings folder
                              # (book.sdr) next to the book it opens
mkdir -p $KOHOME/patches $KOHOME/plugins
ln -sfn "$(pwd)" $KOHOME/plugins/quran.koplugin
cp dev/patches/2-quran-shot.lua $KOHOME/patches/
# data packages (optional, for connection/text surfaces):
#   cp <quran-ebook>/data/{qul,text}-v1.sqlite $KOHOME/data/quran/
KO_HOME=$KOHOME KO_MECHTEST=1 KO_MECHTEST_MODE=panel \
  KO_MECHTEST_OUT=$PWD/shot.png \
  EMULATE_READER_W=1100 EMULATE_READER_H=1500 \
  SDL_VIDEODRIVER=dummy \
  /Applications/KOReader.app/Contents/MacOS/koreader $BOOK
```

`SDL_VIDEODRIVER=dummy` runs it without a window (the screenshot comes
from KOReader's own frame buffer); leave it out to watch the run.

Modes: `panel · goto · card · popup · browser · themes · themeflow ·
uap · phrases · similar · surahhub · dictindex · getbooks · marker ·
markertap · translations` (markertap drives the real patched onGotoLink;
layer via `KO_MECHTEST_MARKER`, "off" must show nothing; translations
takes `KO_MECHTEST_TRANSINDEX` = a built index.json injected as the
manifest and `KO_MECHTEST_TRANSLANG` to drill into one language). Gotchas: the book path must be
**absolute** (a
relative path silently opens the file manager); the first run of a fresh
KO_HOME shows a one-time color-rendering popup: run twice and use the
second shot.

## In-app check of the book style guard (macOS)

The style guard (`quran_setup.lua`) depends on the order in which KOReader
opens a book, which the harness can only imitate. This script runs the
real thing:

```zsh
dev/check_guard_in_app.sh            # about three and a half minutes
```

It starts the installed KOReader eleven times with throwaway profiles,
with no window, on copies of two sample books of the sister repo
(`../quran-ebook/tests/`; pass two EPUBs to use others), and checks the
log line that `dev/patches/2-quran-guard.lua` writes: a new book fixed
before loading, a silent second opening, a manual "off" respected, the
fix after loading with its single reopen, a waiting go-to that survives
that reopen, the guard's own switch, a book saved as off fixed from its
metadata, another book untouched, stock defaults only remembered. It
must end `ALL GUARD RUNS PASS`. Your real KOReader profile is never read
or written.

Plugin order matters and the script covers both orders. KOReader calls
plugins in the order of their folder paths, and its own `docsettingtweak`
plugin answers the `DocSettingsLoad` event and stops it there. On Kobo and
Kindle this plugin sits in KOReader's own `plugins/` folder and comes
after it, so the event never arrives; on macOS and Android the path is
absolute and comes first. That is why the guard also runs from the
plugin's `init`. Most runs use a plugin path that sorts like the e-reader
case; one uses the desktop order.

## Release / packaging

None yet (beta). Asset packages (dicts, data) are built by quran-ebook's
`tools/` and published to this repo's asset bucket. When the first
packaged release is cut: add the updates-manager fields (`update_url` +
version) to `_meta.lua`, and only then add the `koreader-plugin` GitHub
topic (it makes the repo discoverable/installable via appstore.koplugin;
that is the "promoted" switch).
