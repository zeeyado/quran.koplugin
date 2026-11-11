#!/bin/zsh
# In-app check of the book style guard (quran_setup.lua). macOS.
#
# Runs the installed KOReader eleven times with throwaway profiles, with no
# window, on COPIES of two books, and checks what the guard did each time.
# Nothing in your real KOReader profile is read or written, and the books
# you pass are never opened in place (KOReader writes a book's settings
# folder next to the book it opens).
#
# usage:  dev/check_guard_in_app.sh [quran-book.epub] [other-book.epub]
# env:    KOREADER_APP   the koreader launcher (default: the macOS app)
#         KO_QGUARD_WAIT seconds to let a book open (default 8; raise it on
#                        a slow machine)
# The defaults are two sample books of the sister repo (../quran-ebook/tests).
# Takes about three and a half minutes. Ends with "ALL GUARD RUNS PASS" or
# exits 1.
#
# Plugin order matters here. KOReader calls plugins in the order of their
# folder paths, and its own "docsettingtweak" plugin answers the
# DocSettingsLoad event and stops it. On Kobo and Kindle our plugin sits in
# KOReader's own plugins folder and comes AFTER that plugin; on macOS and
# Android it sits under an absolute path and comes BEFORE it. Most runs
# below use a path that sorts like the e-reader case; one uses the other.

set -u
PLUGIN=${0:A:h:h}
KO=${KOREADER_APP:-/Applications/KOReader.app/Contents/MacOS/koreader}
KODIR=${KO:A:h:h}/koreader          # KOReader's own folder, its working directory
QBOOK=${1:-$PLUGIN/../quran-ebook/tests/quran_hafs-indopak_nastaleeq_word-inline_ar-en-hilali-khan.epub}
OBOOK=${2:-$PLUGIN/../quran-ebook/tests/test_qcf_fatiha.epub}
WAIT=${KO_QGUARD_WAIT:-8}

for f in "$KO" "$KODIR/plugins/docsettingtweak.koplugin" "$QBOOK" "$OBOOK"; do
    if [[ ! -e $f ]]; then print -u2 "missing: $f"; exit 2; fi
done

T=$(mktemp -d "${TMPDIR:-/tmp}/quran-guard.XXXXXX")
T=${T:A}
print "scratch folder: $T"

# One throwaway profile per kind of reader.
#   name      folder under $T
#   order     "ereader": our plugin is reached through a path that starts
#             inside KOReader's own plugins folder, so it is called after
#             docsettingtweak, as on Kobo and Kindle
#             "desktop": an absolute path, called before it
#   settings  extra lines for settings.reader.lua
make_profile() {
    local name=$1 order=$2 settings=$3
    local home=$T/$name plugins
    mkdir -p $home/patches $home/plugins $home/settings
    ln -sfn $PLUGIN $home/plugins/quran.koplugin
    cp $PLUGIN/dev/patches/2-quran-guard.lua $home/patches/
    if [[ $order == ereader ]]; then
        local parts=( ${(s:/:)KODIR} )
        local up=$(printf '../%.0s' {1..$(( ${#parts} + 2 ))})
        plugins="plugins/docsettingtweak.koplugin/${up}${home#/}/plugins/"
    else
        plugins="$home/plugins/"
    fi
    print -r -- "return {
$settings    [\"extra_plugin_paths\"] = { \"$plugins\" },
}" > $home/settings.reader.lua
}
OFF='    ["copt_embedded_css"] = 0,
    ["copt_embedded_fonts"] = 0,
'
make_profile off ereader "$OFF"          # defaults off, e-reader plugin order
make_profile off_desktop desktop "$OFF"  # defaults off, desktop plugin order
make_profile stock ereader ''            # stock KOReader defaults

fails=0
run() {   # label, profile, book copy, wanted log patterns ("!pattern" = must NOT appear); env in RUN_ENV
    local label=$1 profile=$2 book=$3; shift 3
    local log=$T/$label.log
    ( cd $T && env KO_HOME=$T/$profile KO_QGUARD=1 KO_QGUARD_WAIT=$WAIT ${=RUN_ENV:-} \
        EMULATE_READER_W=1100 EMULATE_READER_H=1500 SDL_VIDEODRIVER=dummy \
        perl -e 'alarm shift; exec @ARGV' $(( WAIT * 6 + 40 )) $KO $book > $log 2>&1 )
    local ok=1 want
    for want in "$@"; do
        if [[ $want == !* ]]; then
            grep -q -- "${want#!}" $log && ok=0
        else
            grep -q -- "$want" $log || ok=0
        fi
    done
    if (( ok )); then
        print "ok    $label"
    else
        print "FAIL  $label"
        grep -- "qguard:\|style guard\|Looking for plugins" $log | sed 's/^/        /'
        print "        wanted: $*"
        fails=$(( fails + 1 ))
    fi
}
plugin_settings() {   # profile, content of the plugin's own settings file
    print -r -- "return { $2 }" > $T/$1/settings/quran.lua
}

mkdir -p $T/books
for name in new late goto saved_off stock desktop; do cp $QBOOK $T/books/$name.epub; done
cp $OBOOK $T/books/other.epub

BEFORE="style guard: embedded style and fonts switched on before loading"
REOPEN="style guard: embedded style and fonts switched on, reopening"
FIXED="qguard: ready css=1 fonts=1 quran=true flag=fixed notice=yes stale=false"

# 1. a Quran book never opened, defaults off: fixed before it is loaded,
#    although docsettingtweak stops the DocSettingsLoad event before us
RUN_ENV= run 1_new_book_fixed_before_loading off $T/books/new.epub "$BEFORE" "!$REOPEN" "$FIXED"

# 2. the same book again: nothing happens, no notice
RUN_ENV= run 2_second_opening_is_silent off $T/books/new.epub \
    "!style guard:" "qguard: ready css=1 fonts=1 quran=true flag=fixed notice=no"

# 3. the reader switches the style off by hand; the next opening respects it
RUN_ENV="KO_QGUARD_DO=off" run 3a_reader_switches_off off $T/books/new.epub "qguard: after-off css=0"
RUN_ENV= run 3b_manual_off_is_respected off $T/books/new.epub \
    "!style guard:" "qguard: ready css=0 fonts=1 quran=true flag=fixed notice=no"

# 4. the file cannot be looked into: fixed after loading, and reopened once
RUN_ENV="KO_QGUARD_NOPEEK=1" run 4_fixed_after_loading_and_reopened off $T/books/late.epub \
    "$REOPEN" "!$BEFORE" "$FIXED"

# 5. the same, with a go-to waiting (as when a book is opened from the
#    file browser's Quran Explorer): the reopened book must still go there
plugin_settings off '["quran_pending_goto"] = { 2, 255 },'
#    (KOReader's log puts a space after the last value, hence " *$")
RUN_ENV="KO_QGUARD_NOPEEK=1" run 5_pending_goto_survives_the_reopen off $T/books/goto.epub \
    "$REOPEN" "$FIXED" "!$FIXED page=1 *\$"
plugin_settings off ''

# 6. a book opened once while the guard was switched off (saved as off,
#    like a book opened before the plugin had the guard), then opened
#    with the guard on: fixed from its saved metadata
plugin_settings off '["style_guard"] = false,'
RUN_ENV= run 6a_guard_switched_off_does_nothing off $T/books/saved_off.epub \
    "!style guard:" "qguard: ready css=0 fonts=0 quran=true flag=none notice=no"
plugin_settings off ''
RUN_ENV= run 6b_saved_off_book_fixed_from_its_metadata off $T/books/saved_off.epub \
    "$BEFORE" "!$REOPEN" "$FIXED"

# 7. a book that is not a Quran: untouched
RUN_ENV= run 7_other_book_untouched off $T/books/other.epub \
    "!style guard:" "qguard: ready css=0 fonts=0 quran=false flag=none notice=no"

# 8. stock KOReader defaults: only remembered
RUN_ENV= run 8_stock_defaults_only_remembered stock $T/books/stock.epub \
    "!style guard:" "qguard: ready css=1 fonts=1 quran=true flag=ok notice=no"

# 9. the desktop plugin order (our plugin before docsettingtweak)
RUN_ENV= run 9_desktop_plugin_order off_desktop $T/books/desktop.epub "$BEFORE" "!$REOPEN" "$FIXED"

if (( fails == 0 )); then
    print "ALL GUARD RUNS PASS"
    rm -rf $T
else
    print "$fails run(s) failed; logs kept in $T"
    exit 1
fi
