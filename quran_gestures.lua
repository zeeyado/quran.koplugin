--[[--
quran_gestures.lua: gestures for the plugin's actions, set inside the
plugin (Quran menu > Setup > Gestures).

Two parts:
  * The picker: every gesture slot KOReader's Gestures plugin has, in
    KOReader's own sections. A free slot is assigned on a tap. A taken
    slot shows what holds it and asks before it is replaced (the slot's
    other actions are removed: this picker gives a gesture one action,
    KOReader's own gesture manager stacks). A slot that already holds
    the action offers Remove.
  * The screen: each of the plugin's actions with the gestures it has
    now, wherever they were set (here or in KOReader's gesture manager).

A write goes through the live Gestures plugin when it is loaded (it
applies at once: KOReader registers every gesture zone at start and
reads the action table when a gesture fires), else through gestures.lua
(it applies once that plugin runs again, after a restart).

Modelled on KOAssistant's gesture picker and Gestures screen (same
maintainer; koassistant/ui/gesture_picker.lua as of 2026-11-11). Added
here: what KOReader does not offer in a mode is not offered either (two
top corner taps and one corner long-press are reader-only, as are double
taps; two-finger gestures need a multitouch screen; double taps and
multiswipes need their KOReader switch).

The slot ids, sections and words are a copy of gestures.koplugin's
section_titles, section_items and gestures_list (file-local there, not
reachable from a plugin; read from KOReader v2026.07.2-83). The harness
checks the copy against the installed KOReader's file when it is present.
GPL-3.0.
]]

local logger = require("logger")
local _ = require("gettext")

local M = {}

-- The multiswipes as KOReader draws them (symbols, not words; no _())
local MULTISWIPES = {
    { "multiswipe_west_east", "⬅ ➡" }, { "multiswipe_east_west", "➡ ⬅" },
    { "multiswipe_north_east", "⬆ ➡" }, { "multiswipe_north_west", "⬆ ⬅" },
    { "multiswipe_north_south", "⬆ ⬇" }, { "multiswipe_east_north", "➡ ⬆" },
    { "multiswipe_west_north", "⬅ ⬆" }, { "multiswipe_east_south", "➡ ⬇" },
    { "multiswipe_south_north", "⬇ ⬆" }, { "multiswipe_south_east", "⬇ ➡" },
    { "multiswipe_south_west", "⬇ ⬅" }, { "multiswipe_west_south", "⬅ ⬇" },
    { "multiswipe_north_south_north", "⬆ ⬇ ⬆" }, { "multiswipe_south_north_south", "⬇ ⬆ ⬇" },
    { "multiswipe_west_east_west", "⬅ ➡ ⬅" }, { "multiswipe_east_west_east", "➡ ⬅ ➡" },
    { "multiswipe_south_west_north", "⬇ ⬅ ⬆" }, { "multiswipe_north_east_south", "⬆ ➡ ⬇" },
    { "multiswipe_north_west_south", "⬆ ⬅ ⬇" }, { "multiswipe_west_south_east", "⬅ ⬇ ➡" },
    { "multiswipe_west_north_east", "⬅ ⬆ ➡" }, { "multiswipe_east_south_west", "➡ ⬇ ⬅" },
    { "multiswipe_east_north_west", "➡ ⬆ ⬅" }, { "multiswipe_south_east_north", "⬇ ➡ ⬆" },
    { "multiswipe_east_north_west_east", "➡ ⬆ ⬅ ➡" }, { "multiswipe_south_east_north_south", "⬇ ➡ ⬆ ⬇" },
    { "multiswipe_east_south_west_north", "➡ ⬇ ⬅ ⬆" }, { "multiswipe_west_south_east_north", "⬅ ⬇ ➡ ⬆" },
    { "multiswipe_south_east_north_west", "⬇ ➡ ⬆ ⬅" }, { "multiswipe_south_west_north_east", "⬇ ⬅ ⬆ ➡" },
    { "multiswipe_southeast_northeast", "⬊ ⬈" }, { "multiswipe_northeast_southeast", "⬈ ⬊" },
    { "multiswipe_northwest_southwest_northwest", "⬉ ⬋ ⬉" },
    { "multiswipe_southeast_southwest_northwest", "⬊ ⬋ ⬉" },
    { "multiswipe_southeast_northeast_northwest", "⬊ ⬈ ⬉" },
}

-- { id, label, reader_only } rows -> slot tables
local function slots(list)
    local out = {}
    for _i, s in ipairs(list) do
        out[#out + 1] = { id = s[1], label = s[2], reader_only = s[3] or nil }
    end
    return out
end

local multiswipe_slots = {}
for _i, m in ipairs(MULTISWIPES) do
    multiswipe_slots[#multiswipe_slots + 1] = {
        id = m[1], label = string.format(_("Multiswipe %s"), m[2]) }
end

--- KOReader's sections, in its order, each with its slots.
---   reader_only    (section or slot): KOReader does not offer it in the
---                  file browser
---   multitouch     needs a multitouch screen
---   enable_setting the G_reader_settings switch that must be on
---   off_setting    the switch that turns it off while on or unset
---   ignore_setting the switch that makes KOReader ignore it while on
M.SECTIONS = {
    { key = "tap_corner", label = _("Tap corner"), slots = slots({
        { "tap_top_left_corner", _("Tap top-left corner"), true },
        { "tap_top_right_corner", _("Tap top-right corner"), true },
        { "tap_left_bottom_corner", _("Tap bottom-left corner") },
        { "tap_right_bottom_corner", _("Tap bottom-right corner") },
    }) },
    { key = "hold_corner", label = _("Long-press on corner"),
      ignore_setting = "ignore_hold_corners", slots = slots({
        { "hold_top_left_corner", _("Long-press top-left corner"), true },
        { "hold_top_right_corner", _("Long-press top-right corner") },
        { "hold_bottom_left_corner", _("Long-press bottom-left corner") },
        { "hold_bottom_right_corner", _("Long-press bottom-right corner") },
    }) },
    { key = "one_finger_swipe", label = _("One-finger swipe"), slots = slots({
        { "short_diagonal_swipe", _("Short diagonal swipe") },
        { "one_finger_swipe_left_edge_down", _("Swipe down the left edge") },
        { "one_finger_swipe_left_edge_up", _("Swipe up the left edge") },
        { "one_finger_swipe_right_edge_down", _("Swipe down the right edge") },
        { "one_finger_swipe_right_edge_up", _("Swipe up the right edge") },
        { "one_finger_swipe_top_edge_right", _("Swipe right along the top edge") },
        { "one_finger_swipe_top_edge_left", _("Swipe left along the top edge") },
        { "one_finger_swipe_bottom_edge_right", _("Swipe right along the bottom edge") },
        { "one_finger_swipe_bottom_edge_left", _("Swipe left along the bottom edge") },
    }) },
    { key = "double_tap", label = _("Double tap"), reader_only = true,
      off_setting = "disable_double_tap", slots = slots({
        { "double_tap_left_side", _("Double-tap left side") },
        { "double_tap_right_side", _("Double-tap right side") },
        { "double_tap_top_left_corner", _("Double-tap top-left corner") },
        { "double_tap_top_right_corner", _("Double-tap top-right corner") },
        { "double_tap_bottom_left_corner", _("Double-tap bottom-left corner") },
        { "double_tap_bottom_right_corner", _("Double-tap bottom-right corner") },
    }) },
    { key = "two_finger_tap", label = _("Two-finger tap corner"), multitouch = true, slots = slots({
        { "two_finger_tap_top_left_corner", _("Two-finger tap top-left corner") },
        { "two_finger_tap_top_right_corner", _("Two-finger tap top-right corner") },
        { "two_finger_tap_bottom_left_corner", _("Two-finger tap bottom-left corner") },
        { "two_finger_tap_bottom_right_corner", _("Two-finger tap bottom-right corner") },
    }) },
    { key = "two_finger_swipe", label = _("Two-finger swipe"), multitouch = true, slots = slots({
        { "two_finger_swipe_east", _("Two-finger swipe east") },
        { "two_finger_swipe_west", _("Two-finger swipe west") },
        { "two_finger_swipe_south", _("Two-finger swipe south") },
        { "two_finger_swipe_north", _("Two-finger swipe north") },
        { "two_finger_swipe_northeast", _("Two-finger swipe northeast") },
        { "two_finger_swipe_northwest", _("Two-finger swipe northwest") },
        { "two_finger_swipe_southeast", _("Two-finger swipe southeast") },
        { "two_finger_swipe_southwest", _("Two-finger swipe southwest") },
    }) },
    { key = "spread_and_pinch", label = _("Spread and pinch"), multitouch = true, slots = slots({
        { "spread_gesture", _("Spread") },
        { "pinch_gesture", _("Pinch") },
    }) },
    { key = "two_finger_rotation", label = _("Two-finger rotation"), multitouch = true, slots = slots({
        { "rotate_cw", _("Rotate clockwise") },
        { "rotate_ccw", _("Rotate counterclockwise") },
    }) },
    { key = "multiswipes", label = _("Multiswipes"),
      enable_setting = "multiswipes_enabled", slots = multiswipe_slots },
}

--- The plugin's gesture actions, in display order. The ids and the
--- reader/file-browser reach mirror quran_actions.lua's registrations
--- (a "general" action works in both); the harness keeps the two in step.
M.ACTIONS = {
    { id = "quran_quick_panel", title = _("Quick panel"), reader = true, fm = true },
    { id = "quran_goto_ayah", title = _("Go to ayah"), reader = true, fm = true },
    { id = "quran_browser", title = _("Explorer"), reader = true, fm = true },
    { id = "quran_ayah_lookup", title = _("Current ayah lookup"), reader = true },
    { id = "quran_surah_overview", title = _("Surah overview"), reader = true },
    { id = "quran_toggle_header", title = _("Toggle header bar"), reader = true },
    { id = "quran_toggle_juz_footer", title = _("Toggle juz in footer"), reader = true },
}

local BY_ID = {}
do
    local order = 0
    for _i, section in ipairs(M.SECTIONS) do
        for _j, slot in ipairs(section.slots) do
            order = order + 1
            BY_ID[slot.id] = { section = section, slot = slot, order = order }
        end
    end
end

--- The section a slot id belongs to (nil for an id this copy does not know).
function M.sectionOf(slot_id)
    local hit = BY_ID[slot_id]
    return hit and hit.section or nil
end

--- A slot's words, or the raw id made readable for a slot this copy does
--- not know (a newer KOReader's gesture, bound in its own manager).
function M.slotLabel(slot_id)
    local hit = BY_ID[slot_id]
    if hit then return hit.slot.label end
    return (tostring(slot_id):gsub("_", " "))
end

--- The mode a gestures section key stands for, in words.
function M.modeLabel(section_key)
    return section_key == "gesture_fm" and _("in the file browser") or _("in books")
end

-- Free or taken: nil or an empty table is free; the `settings` subtable
-- never counts as an action.
local function slotState(entry)
    if entry == nil or (type(entry) == "table" and next(entry) == nil) then return "free", 0 end
    local n = 0
    if type(entry) == "table" then
        for k in pairs(entry) do
            if k ~= "settings" then n = n + 1 end
        end
    end
    if n == 0 then return "free", 0 end
    return "taken", n
end
M.slotState = slotState

--- Whether a slot exists in a mode at all (three are reader-only).
function M.slotUsable(slot, section_key)
    return not (slot.reader_only and section_key == "gesture_fm")
end

--- Why a whole section cannot be used in a mode, or nil when it can.
--- env = { multitouch = boolean, isTrue = function(key),
---         nilOrTrue = function(key) } (the last two read G_reader_settings)
--- @return nil | "reader_only" | "no_multitouch" | "off"
function M.sectionBlock(section, section_key, env)
    env = env or {}
    if section.reader_only and section_key == "gesture_fm" then return "reader_only" end
    if section.multitouch and env.multitouch == false then return "no_multitouch" end
    if section.enable_setting and not (env.isTrue and env.isTrue(section.enable_setting)) then
        return "off"
    end
    if section.off_setting and (not env.nilOrTrue or env.nilOrTrue(section.off_setting)) then
        return "off"
    end
    return nil
end

--- How many of a section's slots are free in one mode's data, of those
--- the mode has. Pure.
--- @return number free, number total
function M.freeCount(section, mode_data, section_key)
    local free, total = 0, 0
    for _i, slot in ipairs(section.slots) do
        if M.slotUsable(slot, section_key) then
            total = total + 1
            if slotState((mode_data or {})[slot.id]) == "free" then free = free + 1 end
        end
    end
    return free, total
end

--- What a tap on a slot does for this action: "free" assigns, "mine"
--- offers Remove, "taken" asks before replacing. Pure.
function M.plan(entry, action_id)
    if slotState(entry) == "free" then return "free" end
    if type(entry) == "table" and entry[action_id] then return "mine" end
    return "taken"
end

--- The words for what holds a slot: describe(entry) (the Dispatcher's
--- menu text), "taken" when it cannot say. Pure.
function M.holder(entry, describe)
    if type(describe) == "function" then
        local ok, text = pcall(describe, entry)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return _("taken")
end

--- Every slot that holds an action, in both modes, in a steady order: by
--- mode, then in the picker's own order (tap corners first, multiswipes
--- last); an unknown slot id last, by name. Pure.
--- @return table { { section = "gesture_reader"|"gesture_fm", slot = id }, ... }
function M.bindingsFor(data, action_id)
    local out = {}
    for _i, section_key in ipairs({ "gesture_reader", "gesture_fm" }) do
        local section = (data or {})[section_key]
        if type(section) == "table" then
            for slot, entry in pairs(section) do
                if type(entry) == "table" and entry[action_id] then
                    out[#out + 1] = { section = section_key, slot = slot }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.section ~= b.section then return a.section > b.section end   -- books first
        local oa = BY_ID[a.slot] and BY_ID[a.slot].order or math.huge
        local ob = BY_ID[b.slot] and BY_ID[b.slot].order or math.huge
        if oa ~= ob then return oa < ob end
        return a.slot < b.slot
    end)
    return out
end

--- Every bound action id that starts with `prefix` and is not in the set
--- `except`, sorted: bindings left behind by an action that no longer
--- exists (KOReader's gesture manager shows them as "Unknown item"). Pure.
function M.boundIds(data, prefix, except)
    local seen, out = {}, {}
    for _i, section_key in ipairs({ "gesture_reader", "gesture_fm" }) do
        local section = (data or {})[section_key]
        if type(section) == "table" then
            for _j, entry in pairs(section) do
                if type(entry) == "table" then
                    for id in pairs(entry) do
                        if type(id) == "string" and id ~= "settings"
                            and id:sub(1, #prefix) == prefix
                            and not (except and except[id]) and not seen[id] then
                            seen[id] = true
                            out[#out + 1] = id
                        end
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

--- One action's bindings in words: "Tap bottom-right corner (in books), …"
--- or nil when it has none. A gesture held in both modes is named once.
--- Pure.
function M.bindingsText(data, action_id)
    local list = M.bindingsFor(data, action_id)
    if #list == 0 then return nil end
    local modes = {}
    for _i, b in ipairs(list) do modes[b.slot] = (modes[b.slot] or 0) + 1 end
    local parts, named = {}, {}
    for _i, b in ipairs(list) do
        if not named[b.slot] then
            named[b.slot] = true
            local where = modes[b.slot] > 1 and _("in books and in the file browser")
                or M.modeLabel(b.section)
            parts[#parts + 1] = string.format(_("%s (%s)"), M.slotLabel(b.slot), where)
        end
    end
    return table.concat(parts, ", ")
end

--- The one-tap offer: the quick panel on the bottom-right corner tap, in
--- every mode where that corner is free. Only while none of the plugin's
--- actions has a gesture (after that the reader has their own layout).
--- Pure. @return table { { section, slot, action }, ... } (may be empty)
function M.suggestion(data)
    for _i, act in ipairs(M.ACTIONS) do
        if #M.bindingsFor(data, act.id) > 0 then return {} end
    end
    local out = {}
    for _i, section_key in ipairs({ "gesture_reader", "gesture_fm" }) do
        if slotState(((data or {})[section_key] or {}).tap_right_bottom_corner) == "free" then
            out[#out + 1] = { section = section_key, slot = "tap_right_bottom_corner",
                              action = "quran_quick_panel" }
        end
    end
    return out
end

-- ---------------------------------------------------------------------
-- The live side: KOReader's gesture data and the writes
-- ---------------------------------------------------------------------

--- KOReader's gesture data: the live Gestures plugin's settings object
--- when it is loaded (a write applies at once; the object is shared by the
--- reader and the file browser), else gestures.lua opened here (a write
--- then needs a restart).
--- @return table data, table|nil live (the Gestures instance), table settings
function M.access(quran)
    local ges = quran and quran.ui and quran.ui.gestures
    if ges and ges.settings and ges.settings.data then
        return ges.settings.data, ges, ges.settings
    end
    local DataStorage = require("datastorage")
    local LuaSettings = require("luasettings")
    local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/gestures.lua")
    settings.data = settings.data or {}
    return settings.data, nil, settings
end

--- Whether KOReader has any gesture data yet (its Gestures plugin ran once).
function M.ready(data)
    return type(data) == "table" and next(data) ~= nil
end

--- How many of the plugin's actions have at least one gesture.
function M.boundCount(quran)
    local ok, data = pcall(M.access, quran)
    if not ok then return 0 end
    local n = 0
    for _i, act in ipairs(M.ACTIONS) do
        if #M.bindingsFor(data, act.id) > 0 then n = n + 1 end
    end
    return n
end

local function describeEntry(entry)
    local Dispatcher = require("dispatcher")
    return Dispatcher:menuTextFunc(entry)
end

--- Bind action_id to a slot (the slot's other actions are removed: one
--- action per gesture here).
--- @return string "live" (applies now) | "restart"
function M.assign(quran, section_key, slot, action_id)
    local data, live, settings = M.access(quran)
    data[section_key] = data[section_key] or {}
    data[section_key][slot] = { [action_id] = true }
    -- Re-point the fire-time table in case the section table was created
    -- fresh (normally the same reference, a no-op)
    if live and live.ges_mode then live.gestures = data[live.ges_mode] end
    settings:flush()
    logger.dbg("quran.koplugin: gestures: assigned", action_id, "to", slot, "in", section_key,
        live and "live" or "after a restart")
    return live and "live" or "restart"
end

--- Remove action_id from a slot, as KOReader's own uncheck does (its
--- order table trimmed too). A slot left with nothing goes back to nil,
--- so a tap that used to fall through (to a page turn, say) does again.
--- @return string "live" | "restart"
function M.remove(quran, section_key, slot, action_id)
    local data, live, settings = M.access(quran)
    local sec = data[section_key]
    local entry = sec and sec[slot]
    if type(entry) ~= "table" then return live and "live" or "restart" end
    entry[action_id] = nil
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and type(Dispatcher) == "table" and Dispatcher._removeFromOrder then
        pcall(Dispatcher._removeFromOrder, sec, slot, action_id)
    end
    if slotState(entry) == "free" then sec[slot] = nil end
    if live and live.ges_mode then live.gestures = data[live.ges_mode] end
    settings:flush()
    logger.dbg("quran.koplugin: gestures: removed", action_id, "from", slot, "in", section_key,
        live and "live" or "after a restart")
    return live and "live" or "restart"
end

-- ---------------------------------------------------------------------
-- The picker
-- ---------------------------------------------------------------------

-- What the device and KOReader's switches allow, for sectionBlock
local function liveEnv()
    local G = rawget(_G, "G_reader_settings")   -- KOReader's global
    local multitouch = true
    local ok, Device = pcall(require, "device")
    if ok and type(Device) == "table" and type(Device.hasMultitouch) == "function" then
        multitouch = Device:hasMultitouch() and true or false
    end
    return {
        multitouch = multitouch,
        isTrue = function(key) return G ~= nil and G:isTrue(key) end,
        nilOrTrue = function(key) return G == nil or G:nilOrTrue(key) end,
    }
end

local BLOCK_TEXT = {
    reader_only = _("%s (only in books)"),
    no_multitouch = _("%s (needs a multitouch screen)"),
    off = _("%s (off in KOReader's gesture settings)"),
}

--- The picker. opts = { quran, action_id, action_label, section_key
--- ("gesture_reader" | "gesture_fm"), on_done(slot_id | nil, how)
--- (how = "live" | "restart" | "removed"), on_cancel() }. Exactly one of
--- the two callbacks runs, once.
function M.show(opts)
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local ConfirmBox = require("ui/widget/confirmbox")
    local quran = opts.quran
    local action_id = opts.action_id
    local section_key = opts.section_key or "gesture_reader"
    local label = opts.action_label or action_id
    local finished = false
    local function finish(fn, ...)
        if finished then return end
        finished = true
        if fn then fn(...) end
    end
    local function cancel() finish(opts.on_cancel) end
    local function done(slot, how) finish(opts.on_done, slot, how) end

    local data, live = M.access(quran)
    local mode_data = data[section_key] or {}
    local env = liveEnv()
    local where = live and _("A pick starts working right away.")
        or _("KOReader's gesture plugin is not running here. A pick is saved and works once that plugin runs.")
    local head = string.format(_("%s (%s)"), label, M.modeLabel(section_key))

    local sections_dialog
    local function showSection(section)
        if sections_dialog then UIManager:close(sections_dialog); sections_dialog = nil end
        local dialog
        local function back()
            if dialog then UIManager:close(dialog); dialog = nil end
            M.show(opts)
        end
        local buttons = {}
        for _i, slot in ipairs(section.slots) do
            if M.slotUsable(slot, section_key) then
                local entry = mode_data[slot.id]
                local plan = M.plan(entry, action_id)
                local text = slot.label
                if plan == "mine" then
                    text = string.format(_("%s (this one)"), slot.label)
                elseif plan == "taken" then
                    text = string.format(_("%s: %s"), slot.label, M.holder(entry, describeEntry))
                end
                buttons[#buttons + 1] = {{ text = text, callback = function()
                    UIManager:close(dialog); dialog = nil
                    if plan == "free" then
                        done(slot.id, M.assign(quran, section_key, slot.id, action_id))
                    elseif plan == "mine" then
                        UIManager:show(ConfirmBox:new{
                            text = string.format(_("Remove %s from %s?"), label, slot.label),
                            ok_text = _("Remove"),
                            ok_callback = function()
                                M.remove(quran, section_key, slot.id, action_id)
                                done(nil, "removed")
                            end,
                            cancel_callback = function() M.show(opts) end,
                        })
                    else
                        UIManager:show(ConfirmBox:new{
                            text = string.format(_("Replace %s on %s with %s?"),
                                    M.holder(entry, describeEntry), slot.label, label)
                                .. "\n" .. _("The gesture then does only this. What it did before is taken off it."),
                            ok_text = _("Replace"),
                            ok_callback = function()
                                done(slot.id, M.assign(quran, section_key, slot.id, action_id))
                            end,
                            cancel_callback = function() M.show(opts) end,
                        })
                    end
                end }}
            end
        end
        buttons[#buttons + 1] = {{ text = _("Back"), id = "close", callback = back }}
        local title = head .. "\n" .. section.label .. "\n" .. where
        if section.ignore_setting and env.isTrue(section.ignore_setting) then
            title = title .. "\n" .. _("KOReader ignores corner long-presses while its \"Ignore long-press on corners\" setting is on (Taps and gestures).")
        end
        dialog = ButtonDialog:new{ title = title, buttons = buttons, tap_close_callback = back }
        UIManager:show(dialog)
    end

    local buttons = {}
    for _i, section in ipairs(M.SECTIONS) do
        local block = M.sectionBlock(section, section_key, env)
        local text
        if block then
            text = string.format(BLOCK_TEXT[block], section.label)
        else
            local free, total = M.freeCount(section, mode_data, section_key)
            text = string.format(_("%s: %d of %d free"), section.label, free, total)
        end
        buttons[#buttons + 1] = {{ text = text, enabled = block == nil,
            callback = function() showSection(section) end }}
    end
    buttons[#buttons + 1] = {{ text = _("Cancel"), id = "close", callback = function()
        if sections_dialog then UIManager:close(sections_dialog); sections_dialog = nil end
        cancel()
    end }}
    sections_dialog = ButtonDialog:new{
        title = head .. "\n"
            .. _("Pick a gesture. A gesture in use shows what holds it; it can be replaced.")
            .. "\n" .. where,
        buttons = buttons,
        tap_close_callback = function() sections_dialog = nil; cancel() end,
    }
    UIManager:show(sections_dialog)
end

-- ---------------------------------------------------------------------
-- The screen (Quran menu > Setup > Gestures)
-- ---------------------------------------------------------------------

local function notify(text)
    local UIManager = require("ui/uimanager")
    local Notification = require("ui/widget/notification")
    UIManager:show(Notification:new{ text = text, timeout = 2 })
end

--- One action's gestures: a Remove row per binding, then "Add a gesture"
--- per mode the action works in.
function M.showActionDialog(quran, act, on_close)
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local data = M.access(quran)
    local dialog
    local function back()
        if dialog then UIManager:close(dialog); dialog = nil end
        M.showScreen(quran, on_close)
    end
    local buttons = {}
    for _i, b in ipairs(M.bindingsFor(data, act.id)) do
        local binding = b
        buttons[#buttons + 1] = {{
            text = string.format(_("Remove: %s (%s)"), M.slotLabel(binding.slot), M.modeLabel(binding.section)),
            callback = function()
                local how = M.remove(quran, binding.section, binding.slot, act.id)
                notify(how == "live" and _("Gesture removed.") or _("Gesture removed (saved for when KOReader's gesture plugin runs)."))
                back()
            end,
        }}
    end
    local modes = {}
    if act.reader then modes[#modes + 1] = "gesture_reader" end
    if act.fm then modes[#modes + 1] = "gesture_fm" end
    for _i, section_key in ipairs(modes) do
        local key = section_key
        buttons[#buttons + 1] = {{
            text = string.format(_("Add a gesture (%s)…"), M.modeLabel(key)),
            callback = function()
                if dialog then UIManager:close(dialog); dialog = nil end
                M.show({
                    quran = quran, action_id = act.id, action_label = act.title, section_key = key,
                    on_done = function(slot, how)
                        if slot then
                            notify(string.format(how == "live" and _("Gesture assigned: %s")
                                or _("Gesture saved: %s (works once KOReader's gesture plugin runs)"), M.slotLabel(slot)))
                        end
                        M.showScreen(quran, on_close)
                    end,
                    on_cancel = function() M.showActionDialog(quran, act, on_close) end,
                })
            end,
        }}
    end
    buttons[#buttons + 1] = {{ text = _("Back"), id = "close", callback = back }}
    dialog = ButtonDialog:new{
        title = string.format(_("Gestures for: %s"), act.title),
        buttons = buttons,
        tap_close_callback = back,
    }
    UIManager:show(dialog)
end

--- Every gesture action of the plugin with the gestures it has now; a
--- tap opens the action's own dialog. on_close runs when the screen is
--- left (the Setup menu refreshes its row).
function M.showScreen(quran, on_close)
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local data, live = M.access(quran)
    local dialog
    local function close()
        if dialog then UIManager:close(dialog); dialog = nil end
        if on_close then on_close() end
    end
    if not M.ready(data) then
        -- gestures.lua has never been written (KOReader's Gestures plugin
        -- never ran): do not invent its file; point at KOReader's own screen
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("KOReader's gesture data is not ready yet. Set gestures in KOReader's own menu (gear icon, Taps and gestures, Gesture manager); the Quran actions are listed there."),
            dismiss_callback = on_close,
        })
        return
    end
    local buttons = {}
    local offer = M.suggestion(data)
    if #offer > 0 then
        buttons[#buttons + 1] = {{
            text = string.format(_("Quick start: %s opens the quick panel"),
                M.slotLabel(offer[1].slot)),
            callback = function()
                local how = "live"
                for _i, o in ipairs(offer) do
                    how = M.assign(quran, o.section, o.slot, o.action)
                end
                notify(string.format(how == "live" and _("Gesture assigned: %s")
                    or _("Gesture saved: %s (works once KOReader's gesture plugin runs)"), M.slotLabel(offer[1].slot)))
                if dialog then UIManager:close(dialog); dialog = nil end
                M.showScreen(quran, on_close)
            end,
        }}
    end
    local known = {}
    local function row(act)
        buttons[#buttons + 1] = {{
            text = string.format(_("%s: %s"), act.title, M.bindingsText(data, act.id) or _("not set")),
            callback = function()
                if dialog then UIManager:close(dialog); dialog = nil end
                M.showActionDialog(quran, act, on_close)
            end,
        }}
    end
    for _i, act in ipairs(M.ACTIONS) do
        known[act.id] = true
        row(act)
    end
    -- a gesture still bound to a Quran action that no longer exists (an
    -- older plugin's id): listed so it can be removed
    for _i, dead_id in ipairs(M.boundIds(data, "quran_", known)) do
        row({ id = dead_id, title = _("An action that no longer exists") })
    end
    buttons[#buttons + 1] = {{ text = _("Close"), id = "close", callback = close }}
    local title = _("Gestures") .. "\n"
    if live then
        title = title .. _("Tap an action to give it a gesture or remove one. Changes apply at once.")
    else
        title = title .. _("Tap an action to give it a gesture or remove one. KOReader's gesture plugin is not running here, so a change is saved and works once that plugin runs (after a restart).")
    end
    dialog = ButtonDialog:new{ title = title, buttons = buttons, tap_close_callback = close }
    UIManager:show(dialog)
end

return M
