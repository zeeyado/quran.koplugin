--[[--
The AYAH CARD (design D-R2-9; ND-19 organizer round 2026-07-27): the
default ayah long-press surface — an organizer-style launcher panel in
the quick panel's koassistant-QS pattern: titled dialog with an X close
(no Close cell) and a gear opening a sort/enable organizer, rows
persisted per user (quran_card_order / quran_card_show_<id> via the
shared surface machinery in quran_actions). The card's SHAPE stays
stable page to page (D-R3-5): rows never vary with marked state or
counts — zero-count connection rows render disabled, not hidden; only
the user's own organizer choices change the roster. Connection rows
land the per-kind browser LIST screen, never a single connection
directly — siblings are never lost (D-R3-12). Per-resource reading
rows: Translations · Tafsir · Grammar · I'rab (its own button since
ND-19; routed like tafsir, follows the Dictionary-windows routing).
Every row opens an EXISTING surface (Reader, browser screens): the
card renders no content of its own. (The M2 Similar quick-view popup
lived here for one day — R4 build ④ — and was rolled back by owner
judgment 2026-07-18; the dense browser landing is D-R4-6.)
--]]

local logger = require("logger")
local _ = require("gettext")

local M = {}

-- Canonical card item order (ids frozen; labels in cardSpec).
M.CARD_ORDER = {
    "translations", "tafsir", "grammar", "irab", "word_grammar",
    "similar", "themes", "phrases", "topics",
    "figures", "narrative", "ayah_page",
}

--- The card's surface spec for the shared organizer machinery
-- (quran_actions._surfOrder & co.). default returns a COPY — the
-- move helper mutates the list it gets before persisting it.
function M.cardSpec()
    return {
        prefix = "quran_card",
        title = _("Ayah card items"),
        default = function()
            local t = {}
            for _i, id in ipairs(M.CARD_ORDER) do t[#t + 1] = id end
            return t
        end,
        labels = function()
            return {
                translations = _("Translations"),
                tafsir = _("Tafsir"),
                grammar = _("Grammar"),
                irab = _("I'rab"),
                word_grammar = _("Word grammar (MASAQ)"),
                similar = _("Similar ayahs"),
                themes = _("Themes"),
                phrases = _("Repeated phrases"),
                topics = _("Topics"),
                figures = _("Figures"),
                narrative = _("Narrative context"),
                ayah_page = _("Ayah page"),
            }
        end,
    }
end

--- Show the card for surah:hafs (ayah in the Hafs data key space, D8).
-- Returns true, or false when no launcher context exists (caller falls
-- back to the resources popup).
function M.show(quran, surah, hafs)
    local UIManager = require("ui/uimanager")
    local actions = quran._actionsModule and quran:_actionsModule()
    if not (actions and actions.showBrowser) then return false end
    local qul = quran._qulModule and quran:_qulModule()
    local conn = qul and qul.ensureDb and qul.ensureDb(quran)
    -- DA-7 connections package (characters / stories / semantic pairs)
    local cx = quran._connectionsModule and quran:_connectionsModule()
    local cxconn = cx and cx.ensureDb and cx.ensureDb(quran)
    local reader = quran._readerModule and quran:_readerModule()
    local qt = quran._textModule and quran:_textModule()
    local text_conn = qt and qt.ensureDb and qt.ensureDb(quran)

    local name = quran.surahName and quran:surahName(surah)
        or tostring(surah)

    local dialog
    local function close_then(fn)
        return function()
            UIManager:close(dialog)
            quran._ayah_card = nil
            fn()
        end
    end
    -- land a browser screen (the card is a launcher — design D-R2-9)
    local function inBrowser(fn)
        return close_then(function()
            actions.showBrowser(quran, function(browser)
                local q2 = browser.qulModule and browser:qulModule()
                if q2 then fn(browser, q2) end
            end)
        end)
    end

    local sim_min = (qul and qul.similarMinScore
        and qul.similarMinScore(quran)) or 80
    local counts = (conn and qul.countsFor
        and qul.countsFor(conn, surah, hafs, sim_min)) or {}
    -- semantic pairs beyond the wording list join the Similar count
    -- (the union shown by qul.showSimilar's two labeled sections)
    local sem_extra = 0
    if cxconn then
        local wording = (conn and qul.similarFor
            and qul.similarFor(conn, surah, hafs, sim_min)) or {}
        sem_extra = #cx.diffPairs(
            cx.semanticFor(cxconn, surah, hafs, cx.semanticFloor(quran)),
            wording)
    end

    -- R3-F16: reading rows only when their resource actually resolves —
    -- dead buttons on fresh installs taught the lesson. Connection rows
    -- with live counts render ALWAYS when their package is present,
    -- zero counts disabled (stable card, D-R3-5); each lands the
    -- per-kind browser list (D-R3-12).
    local res = actions.detectResources and actions.detectResources(quran)
    local can_reader = quran.canReaderTafsir and quran:canReaderTafsir()
    local function connBtn(n, label, fn)
        return {
            text = string.format("%s (%d)", label, n or 0),
            enabled = (n or 0) > 0,
            callback = inBrowser(fn),
        }
    end
    local function cxBtn(n, label, fn)
        return {
            text = string.format("%s (%d)", label, n or 0),
            enabled = (n or 0) > 0,
            callback = close_then(function()
                actions.showBrowser(quran, function(browser)
                    local c2 = browser.connectionsModule
                        and browser:connectionsModule()
                    if c2 then fn(browser, c2) end
                end)
            end),
        }
    end

    -- id -> build() -> button def, or nil when the row's resource is
    -- absent (availability; the organizer setting is checked separately)
    local build = {}
    build.translations = function()
        if not (text_conn and reader and reader.showAyah) then return end
        return { text = _("Translations"),
            callback = close_then(function()
                reader.showAyah(quran, surah, hafs, { explore = true })
            end) }
    end
    build.tafsir = function()
        if not (res and res.tafsir and res.tafsir[1] and can_reader) then return end
        return { text = _("Tafsir"),
            callback = close_then(function()
                quran:openTafsirReader(surah, hafs, { explore = true })
            end) }
    end
    build.grammar = function()
        if not (res and res.grammar and can_reader) then return end
        return { text = _("Grammar"),
            callback = close_then(function()
                quran:openTafsirReader(surah, hafs,
                    { dict = res.grammar, explore = true })
            end) }
    end
    -- ND-19: I'rab as its own per-resource button — same reader route
    -- as tafsir/grammar; round-8 routing applies (normal Dictionary-
    -- windows radio, not the grammar popup-lock)
    build.irab = function()
        if not (res and res.irab and can_reader) then return end
        return { text = _("I'rab"),
            callback = close_then(function()
                quran:openTafsirReader(surah, hafs,
                    { dict = res.irab, explore = true })
            end) }
    end
    -- ND-27 slice 1: MASAQ's per-ayah word list as a first-class card
    -- row (same G2 source-tagged label as the ayah page's); lands the
    -- browser surface masaq.showAyah — package-gated like the browser
    -- row, never a dead button (R3-F16)
    build.word_grammar = function()
        local masaq = quran._masaqModule and quran:_masaqModule()
        local okm, mconn = pcall(function()
            return masaq and masaq.ensureDb
                and (select(1, masaq.ensureDb(quran))) or nil
        end)
        if not (okm and mconn) then return end
        return { text = _("Word grammar (MASAQ)"),
            callback = close_then(function()
                actions.showBrowser(quran, function(browser)
                    local m2 = browser.masaqModule and browser:masaqModule()
                    if m2 then m2.showAyah(browser, surah, hafs) end
                end)
            end) }
    end
    build.similar = function()
        local n
        if conn then
            n = (counts.similar or 0) + sem_extra
        elseif cxconn then
            -- no qul package: the semantic tier still feeds the same
            -- Similar list (qul.showSimilar renders both layers from
            -- whatever is installed)
            n = sem_extra
        else
            return
        end
        return connBtn(n, _("Similar ayahs"), function(b, q2)
            q2.showSimilar(b, surah, hafs)
        end)
    end
    build.themes = function()
        if not conn then return end
        return connBtn(counts.themes, _("Themes"), function(b, q2)
            q2.showThemesFor(b, surah, hafs)
        end)
    end
    build.phrases = function()
        if not conn then return end
        return connBtn(counts.phrases, _("Repeated phrases"), function(b, q2)
            q2.showMutashabihat(b, surah, hafs)
        end)
    end
    build.topics = function()
        if not conn then return end
        return connBtn(counts.topics, _("Topics"), function(b, q2)
            q2.showTopicsFor(b, surah, hafs)
        end)
    end
    build.figures = function()
        if not cxconn then return end
        return cxBtn(#cx.figuresAt(cxconn, surah, hafs), _("Figures"),
            function(b, c2) c2.showFiguresAt(b, surah, hafs) end)
    end
    build.narrative = function()
        if not cxconn then return end
        return cxBtn(#cx.unitsContaining(cxconn, surah, hafs), _("Narrative context"),
            function(b, c2) c2.showStoryContext(b, surah, hafs) end)
    end
    build.ayah_page = function()
        return { text = _("Ayah page") .. " \226\134\146",
            callback = close_then(function()
                quran:openBrowserAtAyah(surah, hafs)
            end) }
    end

    -- User-organized roster (shared surface machinery); graceful when
    -- the helpers or settings are unavailable: default order, all on.
    local spec = M.cardSpec()
    local surf = (actions._surfOrder and quran.settings) and actions or nil
    local order = surf and surf._surfOrder(quran, spec) or M.CARD_ORDER
    local flat = {}
    for _i, id in ipairs(order) do
        if (not surf or surf._surfEnabled(quran, spec, id)) and build[id] then
            local btn = build[id]()
            if btn then
                btn.font_bold = false
                flat[#flat + 1] = btn
            end
        end
    end
    if #flat == 0 then
        -- everything hidden/unavailable: keep the ayah-page door
        local btn = build.ayah_page()
        btn.font_bold = false
        flat[1] = btn
    end

    -- the quick panel's grid idiom: one continuous 2-per-row grid
    -- (R3-F13), a lone last cell only on odd counts
    local buttons = {}
    local titled = actions._panelDialogClass and actions._panelDialogClass(quran)
    if not titled then
        -- fallback dialog has no X title bar: keep the Close cell
        table.insert(flat, { text = _("Close"), font_bold = false,
            callback = function()
                UIManager:close(dialog)
                quran._ayah_card = nil
            end })
    end
    for i = 1, #flat, 2 do
        if flat[i + 1] then buttons[#buttons + 1] = { flat[i], flat[i + 1] }
        else buttons[#buttons + 1] = { flat[i] } end
    end

    local title = string.format("%s %d:%d", name, surah, hafs)
    if titled then
        -- koassistant-QS pattern (ND-19): X close in the title bar,
        -- gear opens the card organizer directly (one option only —
        -- no intermediate menu like the panel's align entry)
        dialog = titled:new{
            title = title,
            buttons = buttons,
            left_icon_tap_callback = function()
                UIManager:close(dialog)
                quran._ayah_card = nil
                actions.showSurfOrganizer(quran, spec, function()
                    M.show(quran, surah, hafs)   -- reopen, fresh roster
                end)
            end,
            close_callback = function() quran._ayah_card = nil end,
        }
    else
        local ButtonDialog = require("ui/widget/buttondialog")
        dialog = ButtonDialog:new{
            title = title,
            title_align = "center",
            buttons = buttons,
            tap_close_callback = function() quran._ayah_card = nil end,
        }
    end
    quran._ayah_card = dialog
    UIManager:show(dialog)
    logger.dbg("quran.koplugin: ayah card", surah, hafs)
    return true
end

logger.dbg("quran.koplugin: quran_ayahpopup loaded")

return M
