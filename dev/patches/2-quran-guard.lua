-- In-app check of the book style guard (dev only; dev/ is export-ignored).
-- KOReader userpatch, env-gated: does nothing unless KO_QGUARD is set.
-- Driven by dev/check_guard_in_app.sh, which reads the "qguard:" log line.
--   KO_QGUARD_WAIT    seconds to let the book open (default 8); the state is
--                     read after twice that, so a reopen has finished too
--   KO_QGUARD_NOPEEK  make the look inside the EPUB fail (forces the check
--                     after loading, the one that reopens the book)
--   KO_QGUARD_DO=off  then switch "Embedded Style" off as a reader would
if not os.getenv("KO_QGUARD") then return end
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Event = require("ui/event")
local wait = tonumber(os.getenv("KO_QGUARD_WAIT") or "") or 8

if os.getenv("KO_QGUARD_NOPEEK") then
    local ok, A = pcall(require, "ffi/archiver")
    if ok and type(A) == "table" and A.Reader then
        local orig = A.Reader.open
        A.Reader.open = function(self, path)
            if type(path) == "string" and path:lower():find("%.epub$") then return nil end
            return orig(self, path)
        end
    end
end

local function noticeShown()
    for _i, w in ipairs(UIManager._window_stack or {}) do
        local text = w.widget and w.widget.text
        if type(text) == "string" and text:find("needs its own style and fonts", 1, true) then
            return true
        end
    end
    return false
end

local function report(tag)
    local ui = require("apps/reader/readerui").instance
    if not (ui and ui.document) then
        logger.info("qguard:", tag, "no book open")
        return nil
    end
    local c = ui.document.configurable or {}
    local flag = ui.doc_settings and ui.doc_settings:readSetting("quran_style_guard")
    logger.info(string.format("qguard: %s css=%s fonts=%s quran=%s flag=%s notice=%s stale=%s page=%s",
        tag, tostring(c.embedded_css), tostring(c.embedded_fonts),
        tostring(ui.quran and ui.quran._is_quran_book or false),
        type(flag) == "table" and tostring(flag.state) or "none",
        noticeShown() and "yes" or "no",
        ui.document.isBuiltDomStale and tostring(ui.document:isBuiltDomStale()) or "?",
        tostring(ui.document.getCurrentPage and ui.document:getCurrentPage() or "?")))
    return ui
end

local function finish()
    local ui = require("apps/reader/readerui").instance
    if ui then ui:onClose() end      -- a proper close writes the book's settings
    UIManager:scheduleIn(1, function() UIManager:quit() end)
end

UIManager:scheduleIn(wait * 2, function()
    local ui = report("ready")
    if ui and os.getenv("KO_QGUARD_DO") == "off" then
        ui:handleEvent(Event:new("ToggleEmbeddedStyleSheet", false))
        UIManager:scheduleIn(wait, function()
            report("after-off")
            finish()
        end)
    else
        finish()
    end
end)
