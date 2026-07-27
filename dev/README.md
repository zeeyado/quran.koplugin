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

Full run on the reference setup: 1360 tests. Stock-luajit run without
KOReader/data: ~944 tests + skips, still authoritative for everything
that ran.

CI (`.github/workflows/check.yml`) parse-checks every Lua file and runs
the harness on stock LuaJIT.

## Headless screenshots (macOS)

KOReader can screenshot itself, so no screen-recording permission is needed.
`dev/patches/2-quran-shot.lua` is a KOReader
[userpatch](https://github.com/koreader/koreader/wiki/User-patches),
env-gated on `KO_MECHTEST`, that opens a plugin surface and captures it.

```zsh
KOHOME=/tmp/kohome            # isolated profile, never your real one
mkdir -p $KOHOME/patches $KOHOME/plugins
ln -sfn "$(pwd)" $KOHOME/plugins/quran.koplugin
cp dev/patches/2-quran-shot.lua $KOHOME/patches/
# data packages (optional, for connection/text surfaces):
#   cp <quran-ebook>/data/{qul,text}-v1.sqlite $KOHOME/data/quran/
KO_HOME=$KOHOME KO_MECHTEST=1 KO_MECHTEST_MODE=panel \
  KO_MECHTEST_OUT=$PWD/shot.png \
  EMULATE_READER_W=1100 EMULATE_READER_H=1500 \
  /Applications/KOReader.app/Contents/MacOS/koreader /ABSOLUTE/path/to/book.epub
```

Modes: `panel · goto · card · popup · browser · themes · themeflow ·
uap · phrases · similar · surahhub`. Gotchas: the book path must be
**absolute** (a
relative path silently opens the file manager); the first run of a fresh
KO_HOME shows a one-time color-rendering popup: run twice and use the
second shot.

## Release / packaging

None yet (beta). Asset packages (dicts, data) are built by quran-ebook's
`tools/` and published to this repo's asset bucket. When the first
packaged release is cut: add the updates-manager fields (`update_url` +
version) to `_meta.lua`, and only then add the `koreader-plugin` GitHub
topic (it makes the repo discoverable/installable via appstore.koplugin;
that is the "promoted" switch).
