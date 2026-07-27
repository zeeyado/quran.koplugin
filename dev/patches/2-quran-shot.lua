-- Headless screenshot rig (dev only — never ships; dev/ is export-ignored).
-- KOReader userpatch, env-gated: does nothing unless KO_MECHTEST is set.
-- Opens a plugin surface (KO_MECHTEST_MODE) and screenshots it to
-- KO_MECHTEST_OUT, then quits. See dev/README.md for the run recipe.
if not os.getenv("KO_MECHTEST") then return end
local UIManager = require("ui/uimanager")
local logger = require("logger")
UIManager:scheduleIn(12, function()
    local mode = os.getenv("KO_MECHTEST_MODE") or "panel"
    logger.info("mechtest: firing mode", mode)
    local function withBrowser(fn)
        local ui = require("apps/reader/readerui").instance
        local q = ui and ui.quran
        local actions = q and q._actionsModule and q:_actionsModule()
        if actions then actions.showBrowser(q, fn) end
    end
    if mode == "panel" then
        UIManager:broadcastEvent(require("ui/event"):new("QuranQuickPanel"))
    elseif mode == "goto" then
        UIManager:broadcastEvent(require("ui/event"):new("QuranGotoAyah"))
    elseif mode == "browser" then withBrowser()
    elseif mode == "surahhub" then
        withBrowser(function(b)
            local si, st = b:buildSurahItems(2)
            b:navigateForward(st, si)
        end)
    elseif mode == "uap" then
        withBrowser(function(b) b:showPosition() end)
    elseif mode == "themes" then
        withBrowser(function(b)
            local qul = b:qulModule(); if qul then qul.showThemesBrowse(b) end
        end)
    elseif mode == "phrases" then
        withBrowser(function(b)
            local qul = b:qulModule(); if qul then qul.showMutashabihat(b, 2, 23) end
        end)
    elseif mode == "similar" then
        withBrowser(function(b)
            local qul = b:qulModule(); if qul then qul.showSimilar(b, 1, 1) end
        end)
    elseif mode == "popup" then
        -- ND-25: the kind-partitioned ayah popup (auto → tafsir ring)
        local ui = require("apps/reader/readerui").instance
        local q = ui and ui.quran
        if q then q:openAyahPopup(2, 255) end
    elseif mode == "dictindex" then
        -- ND-25 P3: the Dictionaries index
        withBrowser(function(b) b:showDictIndex() end)
    else  -- card
        local ui = require("apps/reader/readerui").instance
        local q = ui and ui.quran
        local ap = q and q._ayahPopupModule and q:_ayahPopupModule()
        if ap then logger.info("mechtest: card", ap.show(q, 2, 255)) end
    end
    UIManager:scheduleIn(4, function()
        require("device").screen:shot(os.getenv("KO_MECHTEST_OUT"))
        UIManager:quit()
    end)
end)
