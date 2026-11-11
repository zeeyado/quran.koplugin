--[[--
quran_setup.lua: the setup checks. Each check can say whether it is done
and can do it, so the same code serves an automatic check, a row in the
Setup menu and, later, a guided first run (the shape of KOAssistant's
setup wizard: steps that know whether they are already set up).

Check 1, the book style guard (2026-11-11).

Our books need KOReader's "Embedded Style" and "Embedded Fonts" switched
on: the Quran text is only correct in the book's own font, and the layout
lives in the book's own stylesheet. KOReader has both on out of the box,
but a reader can make "off" the default for new books (a long-press in
the bottom menu). A Quran book opened for the first time then shows a
fallback font and a broken layout, while books opened earlier keep their
own saved "on" (found by the owner, 2026-11-10).

What the guard does, once per book:
  * Before the book is loaded (from the plugin's init, and again from
    KOReader's DocSettingsLoad event): if the book would open with the
    style or the fonts off and it is one of ours, both are set to on in
    the book's own settings. The first page is then already right and
    nothing is drawn twice. A book KOReader has opened before is
    recognised by its saved metadata; a new one by a look at the
    subject inside the EPUB file.
  * After the book is ready (ReaderReady): one of our books that could
    not be recognised that early is fixed now and opened again, so that
    KOReader builds its pages with the style on from the start.
  * Either way the reader is told once, and the book gets a mark in its
    own settings. From then on the guard never touches that book: a
    later manual "off" is the reader's choice.

"One of ours" is narrower than the plugin's book detection: a subject
that is exactly "Quran" (the line our builder writes), or a book the
detection knows by its structure alone. A book that merely mentions the
Quran in its subject or description is left to its reader.

The guard only ever switches things ON, only in the book's own settings,
and never changes the reader's defaults.

Check 2, gestures: the screen lives in quran_gestures.lua; this file only
gives it a row in the Setup menu.
GPL-3.0.
]]

local logger = require("logger")
local _ = require("gettext")

local M = {}

-- [style-guard] pure helpers; the harness extracts this block by its
-- markers and runs it without KOReader, so keep it free of upvalues.

-- KOReader's own per-book keys for the two switches (0 = off, 1 = on)
local STYLE_KEY = "copt_embedded_css"
local FONTS_KEY = "copt_embedded_fonts"
-- Our mark in the book's own settings: the guard has seen this book
local FLAG = "quran_style_guard"

-- The test the plugin's book detection applies to a loaded book's
-- metadata: subject or description holds "Quran" somewhere. Broad on
-- purpose there; too broad for changing a book's settings.
local function isQuranMeta(keywords, description)
    return (type(keywords) == "string" and keywords:find("Quran", 1, true) ~= nil)
        or (type(description) == "string" and description:find("Quran", 1, true) ~= nil)
end

-- One of OUR books by its metadata: a subject that is exactly "Quran",
-- the line our builder writes (crengine hands several subjects over one
-- per line). "Quranic studies" or a description that mentions the Quran
-- is somebody else's book, and its settings are not ours to change.
local function isOurSubject(keywords)
    if type(keywords) ~= "string" then return false end
    for line in keywords:gmatch("[^\n]+") do
        if line:match("^%s*(.-)%s*$") == "Quran" then return true end
    end
    return false
end

-- Ours, once the plugin's own detection has run: our subject line, or a
-- book the detection recognised by its structure alone (our older books
-- carry no subject and are known by their juz entries).
local function isOurBook(detected, keywords, description)
    if not detected then return false end
    return isOurSubject(keywords) or not isQuranMeta(keywords, description)
end

-- The value a switch will have when the book opens: the book's own saved
-- value, else the reader's default, else KOReader's stock value (on).
local function effective(saved, default)
    if saved ~= nil then return saved end
    if default ~= nil then return default end
    return 1
end

local function styleOn(css, fonts)
    return css == 1 and fonts == 1
end

-- The package file's path, from META-INF/container.xml
local function containerOpfPath(xml)
    if type(xml) ~= "string" then return nil end
    return xml:match('full%-path%s*=%s*"([^"]+)"') or xml:match("full%-path%s*=%s*'([^']+)'")
end

-- Subject(s) and description from a package file's text, in the two
-- fields crengine reports them in (keywords, description).
local function opfMeta(opf)
    if type(opf) ~= "string" then return nil, nil end
    local subjects = {}
    for s in opf:gmatch("<dc:subject[^>]*>(.-)</dc:subject>") do
        subjects[#subjects + 1] = s
    end
    local description = opf:match("<dc:description[^>]*>(.-)</dc:description>")
    return (#subjects > 0) and table.concat(subjects, "\n") or nil, description
end

-- What to do before a book is loaded.
--   "skip": nothing (guard off, a paged document, a book seen before, or
--           a book that will open with both switches on)
--   "fix":  one of ours and it would open with the style or fonts off
--   "peek": it would open with them off and KOReader holds no metadata
--           for it yet: look inside the file to see whether it is ours
-- o = { guard_on, paged, flag, saved_css, saved_fonts, default_css,
--       default_fonts, props }
local function earlyPlan(o)
    if not o.guard_on or o.paged or o.flag ~= nil then return "skip" end
    if styleOn(effective(o.saved_css, o.default_css),
               effective(o.saved_fonts, o.default_fonts)) then
        return "skip"
    end
    if type(o.props) == "table" then
        return isOurSubject(o.props.keywords) and "fix" or "skip"
    end
    return "peek"
end

-- What to do once the book is ready. `ours` = isOurBook(...) for it.
--   "notice": the guard fixed this book (before loading, or before the
--             reopen it asked for): tell the reader, once
--   "mark":   one of ours, first meeting, both switches on: remember it
--   "fix":    one of ours, first meeting, style or fonts off: switch on
--             and open the book again
--   "skip":   seen before, not ours, or the guard is off
local function readyPlan(flag, css, fonts, guard_on, ours)
    if type(flag) == "table" and flag.notice then return "notice" end
    if flag ~= nil or not ours then return "skip" end
    if styleOn(css, fonts) then return "mark" end
    return guard_on and "fix" or "skip"
end
-- [/style-guard]

--- The guard's own switch (Setup menu); on unless the reader turned it off.
local function guardOn(quran)
    return not (quran.settings and quran.settings:isFalse("style_guard"))
end

-- Subject and description of a book KOReader has never opened, read from
-- the EPUB file itself. Only called while the reader's defaults have the
-- style or the fonts off; any failure just means "not recognised" and the
-- check after loading takes over.
local function peekEpub(path)
    if type(path) ~= "string" or not path:lower():find("%.epub$") then return nil end
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok or type(Archiver) ~= "table" or not Archiver.Reader then return nil end
    local keywords, description, arc
    local done, err = pcall(function()
        arc = Archiver.Reader:new()
        if not arc:open(path) then
            arc = nil
            return
        end
        local opf_path, opf
        for entry in arc:iterate() do
            if entry.path == "META-INF/container.xml" then
                opf_path = containerOpfPath(arc:extractToMemory(entry.path))
                if not opf_path then break end
            elseif opf_path and entry.path == opf_path then
                opf = arc:extractToMemory(entry.path)
                break
            end
        end
        -- a package file listed before the container: go back for it
        if opf_path and not opf then opf = arc:extractToMemory(opf_path) end
        keywords, description = opfMeta(opf)
    end)
    -- the file is released on every path, a failed read included
    if arc then pcall(function() arc:close() end) end
    if not done then
        logger.info("quran.koplugin: style guard: could not look inside", path, tostring(err))
    end
    return keywords, description
end

--- Before the book is loaded: fix the book's own settings so its first
--- page is already drawn with its style on. Called twice on purpose, and
--- harmless the second time (the book then carries the mark):
---   * from the plugin's init, which KOReader runs when the book's
---     settings exist but nothing has read them yet;
---   * from KOReader's DocSettingsLoad event, as a second chance. That
---     event alone is not enough: KOReader's own "docsettingtweak" plugin
---     answers it and stops it, and on Kobo and Kindle that plugin comes
---     before ours, so the event never reaches us there.
function M.beforeLoad(quran, doc_settings, document)
    if not (doc_settings and document and document.file) then return end
    local G = rawget(_G, "G_reader_settings")   -- KOReader's global
    local plan = earlyPlan({
        guard_on = guardOn(quran),
        paged = (document.info and document.info.has_pages) and true or false,
        flag = doc_settings:readSetting(FLAG),
        saved_css = doc_settings:readSetting(STYLE_KEY),
        saved_fonts = doc_settings:readSetting(FONTS_KEY),
        default_css = G and G:readSetting(STYLE_KEY),
        default_fonts = G and G:readSetting(FONTS_KEY),
        props = doc_settings:readSetting("doc_props"),
    })
    if plan == "peek" then
        plan = isOurSubject((peekEpub(document.file))) and "fix" or "skip"
    end
    if plan ~= "fix" then return end
    doc_settings:saveSetting(STYLE_KEY, 1)
    doc_settings:saveSetting(FONTS_KEY, 1)
    doc_settings:saveSetting(FLAG, { state = "fixed", notice = true })
    -- A page cache built while the style was off would bring the old
    -- layout back; KOReader removes the same file when it resets a book.
    local cache = doc_settings:readSetting("cache_file_path")
    if type(cache) == "string" and cache ~= "" then os.remove(cache) end
    logger.info("quran.koplugin: style guard: embedded style and fonts switched on before loading", document.file)
end

local function showNotice()
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:nextTick(function()
        UIManager:show(InfoMessage:new{
            text = _("This Quran book needs its own style and fonts. They were off, so the Quran plugin switched them on for this book.")
                .. "\n\n" .. _("If you switch them off again (bottom menu, last tab), the plugin leaves it that way."),
        })
    end)
end

-- Books the guard has reopened by itself in this KOReader session: one
-- automatic reopen per book and session, whatever happens to the book's
-- settings file. A settings file that cannot be written can then never
-- turn into a reopen loop. (Kept outside this module's own table because
-- KOReader loads the module anew for every book.)
local function reopenedBooks()
    local t = package.loaded["quran_setup_reopened"]
    if type(t) ~= "table" then
        t = {}
        package.loaded["quran_setup_reopened"] = t
    end
    return t
end

--- Switch both on for the open book and open it again, so KOReader builds
--- its pages with the style on from the start. Used by the check after
--- loading (automatic = true) and by the Setup menu's row.
--- @return "reopening" (the book is about to be opened again), "saved"
--- (switched on in the book's settings; the page shows it at the next
--- opening) or false (no book)
function M.switchOn(quran, automatic)
    local ui = quran.ui
    local doc, doc_settings = ui and ui.document, ui and ui.doc_settings
    if not (doc and doc_settings and doc.configurable) then return false end
    doc.configurable.embedded_css = 1
    doc.configurable.embedded_fonts = 1
    doc_settings:saveSetting(STYLE_KEY, 1)
    doc_settings:saveSetting(FONTS_KEY, 1)
    doc_settings:saveSetting(FLAG, { state = "fixed", notice = true })
    local reopened = reopenedBooks()
    if type(ui.reloadDocument) ~= "function" or (automatic and reopened[doc.file]) then
        logger.info("quran.koplugin: style guard: embedded style and fonts switched on for the next opening", doc.file)
        return "saved"
    end
    reopened[doc.file] = true
    -- The page tree in memory (and its cache file) was built with the
    -- style off: drop the cache so the reopen parses the book afresh.
    pcall(function()
        if doc.hasCacheFile and doc:hasCacheFile() and doc.invalidateCacheFile then
            doc:invalidateCacheFile()
        end
    end)
    logger.info("quran.koplugin: style guard: embedded style and fonts switched on, reopening", doc.file)
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        -- still the same open book? (the reader may have left meanwhile)
        if ui.document == doc then ui:reloadDocument() end
    end)
    return "reopening"
end

--- Once the book is ready and the plugin knows what it is.
--- @return "reopening" when the book is about to be opened again; the
--- plugin then leaves the rest of its own start-up (a pending go-to, the
--- offer to restore old reading data) to the new opening.
function M.onReaderReady(quran)
    local ui = quran.ui
    local doc, doc_settings = ui and ui.document, ui and ui.doc_settings
    if not (doc and doc_settings and doc.configurable) then return nil end
    local flag = doc_settings:readSetting(FLAG)
    local props = type(ui.doc_props) == "table" and ui.doc_props or {}
    local plan = readyPlan(flag, doc.configurable.embedded_css, doc.configurable.embedded_fonts,
        guardOn(quran), isOurBook(quran._is_quran_book, props.keywords, props.description))
    if plan == "notice" then
        flag.notice = nil
        doc_settings:saveSetting(FLAG, flag)
        -- say it only if it is true (something else may have undone it)
        if styleOn(doc.configurable.embedded_css, doc.configurable.embedded_fonts) then
            showNotice()
        end
    elseif plan == "mark" then
        doc_settings:saveSetting(FLAG, { state = "ok" })
    elseif plan == "fix" then
        if M.switchOn(quran, true) == "reopening" then return "reopening" end
    end
    return nil
end

--- The open book's state for the Setup menu: "none" (no Quran book is
--- open), "on" or "off".
function M.styleState(quran)
    local doc = quran.ui and quran.ui.document
    if not (quran._is_quran_book and doc and doc.configurable) then return "none" end
    return styleOn(doc.configurable.embedded_css, doc.configurable.embedded_fonts) and "on" or "off"
end

-- ---------------------------------------------------------------------
-- The Setup menu (Quran menu > Setup)
-- ---------------------------------------------------------------------

local function gesturesModule(quran)
    if quran._gestures_mod == nil then
        local ok, mod = pcall(dofile, (quran.path or "") .. "/quran_gestures.lua")
        quran._gestures_mod = (ok and type(mod) == "table") and mod or false
        if not quran._gestures_mod then
            logger.info("quran.koplugin: quran_gestures.lua unavailable:", tostring(mod))
        end
    end
    return quran._gestures_mod or nil
end
M.gesturesModule = gesturesModule

--- The "Setup" row of the Quran menu, with its rows.
function M.menuItem(quran)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    return {
        text = _("Setup"),
        help_text = _("Checks that KOReader is set up for the Quran books: the book's own style and fonts, and gestures for the plugin's actions."),
        sub_item_table = {
            {
                text_func = function()
                    local state = M.styleState(quran)
                    if state == "on" then
                        return _("This book's style and fonts: on")
                    elseif state == "off" then
                        return _("This book's style and fonts: off (tap to switch on)")
                    end
                    return _("This book's style and fonts (open a Quran book)")
                end,
                help_text = _("A Quran book needs KOReader's \"Embedded Style\" and \"Embedded Fonts\" switched on (bottom menu, last tab). With them off, the Quran text shows in a fallback font and the layout breaks."),
                enabled_func = function() return M.styleState(quran) ~= "none" end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if M.styleState(quran) == "off" then
                        if touchmenu_instance and touchmenu_instance.closeMenu then
                            touchmenu_instance:closeMenu()
                        end
                        M.switchOn(quran)
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("This book's own style and fonts are on. Nothing to do."),
                        })
                    end
                end,
            },
            {
                text = _("Switch them on automatically"),
                help_text = _("When the plugin first meets a Quran book of this project with its style or fonts off, it switches both on for that book and tells you. It does this once per book and never changes your defaults for other books. Switch them off again and the plugin leaves that book alone."),
                checked_func = function() return guardOn(quran) end,
                callback = function()
                    quran.settings:saveSetting("style_guard", not guardOn(quran))
                    quran.settings:flush()
                end,
                separator = true,
            },
            {
                text_func = function()
                    local mod = gesturesModule(quran)
                    local n = mod and mod.boundCount(quran) or 0
                    if n == 0 then return _("Gestures: none set") end
                    return string.format(_("Gestures: %d set"), n)
                end,
                help_text = _("Give the plugin's actions (quick panel, go to ayah, Explorer and more) a gesture, or remove one. The same gestures also appear in KOReader's own gesture manager."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local mod = gesturesModule(quran)
                    if mod then
                        mod.showScreen(quran, function()
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end)
                    end
                end,
            },
        },
    }
end

return M
