--[[--
quran_marker.lua — the ND-26 marker-tap layer (route decided 2026-07-27:
marker-as-anchor; override decided same day: a setting, default defer).

The EPUBs wrap every non-noteref ayah marker in a SELF-HREF anchor
(class ayah-mark-link, href #ayah-S-A) — inert everywhere else. The
ReaderLink.onGotoLink patch in main.lua spots those hrefs on the RAW
xpointer with a SUFFIX match, so the CREngine _doc_fragment_N_ prefix
saga never applies (we swallow the navigation, we never resolve it),
and opens the popup here: a bare bottom-anchored scroll-only window
(KOReader's own FootnoteWidget — exactly the baked footnote-popup feel)
with a Settings-chosen ayah-keyed layer. TAP only: long-press stays the
dictionary machinery. Baked interactive books (ayah-noteref → endnote
popups) keep their own popup unless the override setting is ON
(maximal-EPUB posture: default defer, flip per session).

Marker anchors are intercepted EVEN when the layer is Off (the tap is
swallowed, nothing shown): left to KOReader, the self-href trips the
stock footnote heuristic (the marker text is a bare number, detection
flag 0x0400) and pops the whole ayah block up as a "footnote" —
observed on device 2026-07-27. The EPUB CSS also carries -cr-hint:
noteref-ignore on the anchor class for non-plugin KOReader, but old
anchored builds only have this guard.
GPL-3.0.
]]

local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local M = {}

-- What a marker tap opens (setting quran_marker_tap; default off =
-- stock behavior, the anchor stays a harmless self-jump).
M.MODES = {
    { value = "off", label = _("Off (marker taps do nothing)") },
    { value = "translation", label = _("Translation") },
    { value = "tafsir", label = _("Preferred tafsir") },
    { value = "card", label = _("Ayah card") },
}

function M.mode(quran)
    local v = quran.settings and quran.settings:readSetting("quran_marker_tap")
    for _i, m in ipairs(M.MODES) do
        if m.value == v then return v end
    end
    return "off"
end

--- Whether the plugin layer also overrides BAKED noteref popups
-- (interactive books). Default DEFER: the book's own popup wins.
function M.overrideBaked(quran)
    return (quran.settings and quran.settings:isTrue("quran_marker_override"))
        or false
end

--- Parse a RAW internal href/xpointer into (kind, surah, ayah).
-- kind "mark" = an ayah-mark-link self-href (#ayah-S-A, with or
-- without a CREngine fragment prefix); kind "note" = a baked endnote
-- noteref target (…#trans-S-A / …#tafsir-S-A). nil = not ours.
-- Suffix-matched: endnote back-links do not exist in the EPUBs, so the
-- only in-book hrefs ending in these shapes are the marker anchors and
-- the baked noterefs.
function M.parseHref(href)
    if type(href) ~= "string" then return end
    local s, a = href:match("ayah%-(%d+)%-(%d+)$")
    if s then return "mark", tonumber(s), tonumber(a) end
    s, a = href:match("trans%-(%d+)%-(%d+)$")
    if not s then
        s, a = href:match("tafsir%-(%d+)%-(%d+)$")
    end
    if s then return "note", tonumber(s), tonumber(a) end
end

--- Whether the onGotoLink patch should intercept this href. Returns
-- kind, surah, ayah or nil. Marker anchors ("mark") are ALWAYS ours on
-- a quran book — even with the layer Off the tap must be swallowed
-- (show() does nothing then), or the stock footnote heuristic pops the
-- ayah block up. Baked noterefs ("note") stay the book's own popup
-- unless the layer is on AND the override setting captures them.
function M.wants(quran, href)
    local kind, s, a = M.parseHref(href)
    if not kind then return end
    if kind == "note" then
        if M.mode(quran) == "off" then return end
        if not M.overrideBaked(quran) then return end
    end
    return kind, s, a
end

local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--- The popup HTML for a content layer; nil = nothing available (the
-- caller shows the honest notification). surah/hafs are Hafs-numbered
-- (data keys, design invariant D8).
function M.contentHtml(quran, mode, surah, hafs)
    local name = quran.surahName and quran:surahName(surah)
        or tostring(surah)
    -- plain divs, NOT <section>/<title>: FootnoteWidget's stock CSS
    -- inlines section titles into the body (footnote-shaped markup)
    local head = string.format("<div><b>%s %d:%d</b></div>",
        esc(name), surah, hafs)
    if mode == "translation" then
        -- ALL enabled roster translations, in roster order, each
        -- labeled ABOVE its text (a trailing label hid below the fold
        -- on long ayahs, and with several entries it was ambiguous)
        local qt = quran._textModule and quran:_textModule()
        local conn = qt and qt.ensureDb and qt.ensureDb(quran)
        if not conn then return end
        local ts = qt.enabledTranslations(quran, conn, surah, hafs)
        if not ts or #ts == 0 then return end
        local parts = { "<div>", head }
        for i, t in ipairs(ts) do
            parts[#parts + 1] = string.format(
                '<div%s><i>%s</i></div><div>%s</div>',
                i > 1 and ' style="margin-top: 0.4em"' or "",
                esc(t.name), esc(t.text))
        end
        parts[#parts + 1] = "</div>"
        return table.concat(parts)
    elseif mode == "tafsir" then
        -- preferred tafsir → the single installed one; needs the
        -- headless fetch (pre-rawSdcv KOReader gets the notification)
        local actions = quran._actionsModule and quran:_actionsModule()
        local res = actions and actions.detectResources
            and actions.detectResources(quran)
        local tafsirs = res and res.tafsir or {}
        if #tafsirs == 0 or not quran._rawDefinition then return end
        local dict = tafsirs[1]
        local preferred = quran.settings
            and quran.settings:readSetting("preferred_tafsir")
        for _i, n in ipairs(tafsirs) do
            if n == preferred then dict = n break end
        end
        local keys = quran._ayahDictKeys and quran:_ayahDictKeys(surah, hafs)
            or { string.format("%d:%d", surah, hafs) }
        local ok, def = pcall(function()
            return quran:_rawDefinition(dict, keys)
        end)
        if not (ok and def) then return end
        if quran._stripEntryHeader then
            def = quran:_stripEntryHeader(def)
        end
        return string.format("<div>%s<div><i>%s</i></div>%s</div>",
            head, esc(dict), def)
    end
end

--- Open the marker popup for a tapped anchor. surah/book_ayah come in
-- BOOK numbering (the ids are baked per riwayah); converted to Hafs
-- for every data lookup. Returns true (the tap is handled).
function M.show(quran, surah, book_ayah)
    local mode = M.mode(quran)
    logger.info("quran.koplugin: marker tap", surah, book_ayah, mode)
    if mode == "off" then
        return true  -- swallowed: the self-jump is pointless and the
                      -- stock footnote heuristic must never see it
    end
    local hafs = quran._warshToHafs
        and quran:_warshToHafs(surah, book_ayah) or book_ayah
    if mode == "card" then
        local ap = quran._ayahPopupModule and quran:_ayahPopupModule()
        if not (ap and ap.show and ap.show(quran, surah, hafs)) then
            quran:openAyahPopup(surah, hafs)
        end
        return true
    end
    local html = M.contentHtml(quran, mode, surah, hafs)
    if not html then
        local Notification = require("ui/widget/notification")
        UIManager:show(Notification:new{
            text = _("Marker layer: no content available for this ayah."),
        })
        return true
    end
    local FootnoteWidget = require("ui/widget/footnotewidget")
    local Screen = require("device").screen
    local doc = quran.ui and quran.ui.document
    local popup
    popup = FootnoteWidget:new{
        html = html,
        doc_font_name = quran.ui and quran.ui.font
            and quran.ui.font.font_face or nil,
        doc_font_size = doc and doc.configurable
            and Screen:scaleBySize(doc.configurable.font_size) or nil,
        doc_margins = doc and doc.getPageMargins
            and doc:getPageMargins() or nil,
        -- ReaderUI as the event dialog, exactly like stock footnote
        -- popups: scroll redraws target it (nil = crash on the second
        -- page, scrollhtmlwidget.lua:182, device 2026-07-27) and
        -- hold-release routes LookupWord/LookupWikipedia through it
        -- (the native selection = dictionary-popup behavior)
        dialog = quran.ui and (quran.ui.dialog or quran.ui) or nil,
        on_tap_close_callback = function() end,
    }
    quran._marker_popup = popup
    UIManager:show(popup)
    return true
end

return M
