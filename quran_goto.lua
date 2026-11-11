--[[--
quran_goto.lua — the quick surah/ayah navigator dialog (D-R4-10, owner
shape call 2026-07-26: two picker columns, surah left / ayah right).

Structurally a DoubleSpinWidget (frontend/ui/widget/doublespinwidget.lua),
composed here directly because DoubleSpinWidget cannot host a value_table
column: the surah picker spins over label strings ("36 · Ya-Sin"), and the
ayah picker's max must re-clamp to the selected surah's count on every
surah change (the date-widget precedent). Ayah numbering is Hafs-canonical
(design invariant D8) — the go-to seam converts for Warsh books.

2026-11-10: a swipe up or down on a column now spins it (a flick = 1, a
medium swipe = 10, a long swipe = 50; up = onward, like the ▼ button).
Before, the dialog sat in a draggable container, so the swipe a reader
tries first dragged the whole box across the screen. The container is
kept (same layout) but made unmovable.

2026-11-10 (later): a tap on the surah name opens the full surah list
(owner: "a longer scrollable list" instead of typing a number). The
type-a-number prompt of 2026-07-27 is gone; the ayah number still takes
typed input, as every stock number picker does.
GPL-3.0.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local MovableContainer = require("ui/widget/container/movablecontainer")
local NumberPickerWidget = require("ui/widget/numberpickerwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

-- [goto-swipe] pure swipe helpers; the harness extracts this block by its
-- markers and runs it without any widget, so keep it free of upvalues.

-- Swipe length as a share of the screen height -> step size. Tune here.
local SWIPE_MEDIUM = 0.20   -- from this share up: 10
local SWIPE_LONG = 0.45     -- from this share up: 50

local function swipeStep(distance, screen_h)
    local share = (distance or 0) / math.max(1, screen_h or 1)
    if share >= SWIPE_LONG then return 50 end
    if share >= SWIPE_MEDIUM then return 10 end
    return 1
end

-- Move cur by delta inside 1..max. A step that would overshoot stops at
-- the end; a step taken while already AT an end loops to the other one
-- (the same loop a single tap makes).
local function stepClamped(cur, delta, max)
    if not max or max < 1 then return 1 end
    cur = cur or 1
    local to = cur + delta
    if to > max then
        return cur >= max and 1 or max
    elseif to < 1 then
        return cur <= 1 and max or 1
    end
    return to
end

-- Which column a swipe spins and where it lands: "surah"|"ayah", target.
-- nil = not ours (sideways or diagonal, or it started off the dialog).
-- The column is the one whose centre is nearest to where the finger
-- went down, so the gaps between the pickers count too and a mirrored
-- (right-to-left) interface needs no special case.
local function swipeTarget(self, ges)
    local dir = ges and ges.direction
    if dir ~= "north" and dir ~= "south" then return nil end
    local frame = self.widget_frame and self.widget_frame.dimen
    local pos = ges.pos
    if not (frame and pos) then return nil end
    if pos.x < frame.x or pos.x >= frame.x + frame.w
        or pos.y < frame.y or pos.y >= frame.y + frame.h then
        return nil
    end
    local sw, aw = self.surah_widget, self.ayah_widget
    if not (sw and aw and sw.dimen and aw.dimen) then return nil end
    local step = swipeStep(ges.distance, self.screen_height)
    local delta = dir == "north" and step or -step   -- up = onward
    local d_surah = math.abs(pos.x - (sw.dimen.x + sw.dimen.w / 2))
    local d_ayah = math.abs(pos.x - (aw.dimen.x + aw.dimen.w / 2))
    if d_surah <= d_ayah then
        local cur = select(2, sw:getValue())   -- value, index
        return "surah", stepClamped(cur, delta, #self.labels)
    end
    return "ayah", stepClamped(aw:getValue(), delta, aw.value_max)
end
-- [/goto-swipe]

-- [goto-list] the surah list's rows; pure, extracted by the harness.
-- One row per surah: the picker's own label, the ayah count on the right.
-- `current` is the surah the picker stands on; Menu draws that row bold.
local function surahListItems(labels, counts, current)
    local items = { current = current }
    for s = 1, #(labels or {}) do
        local n = counts and counts[s]
        items[s] = {
            text = labels[s],
            mandatory = n and tostring(n) or nil,
            surah = s,
        }
    end
    return items
end

-- Rows per page. Stock Menu draws a fixed 14 and stretches them, so a
-- tall phone screen gets huge rows; this gives it more rows instead
-- (the browser's rule: about 48dp a row, 14 to 22). A user's own
-- "items per page" setting wins.
local function listRowsPerPage(user_setting, screen_h, row_h)
    if user_setting then return user_setting end
    return math.min(22, math.max(14,
        math.floor((screen_h or 0) / math.max(1, row_h or 86))))
end
-- [/goto-list]

local GotoDialog = FocusManager:extend{
    title_text = "",
    title_face = Font:getFace("x_smalltfont"),
    labels = nil,     -- surah label strings, index 1..114
    counts = nil,     -- Hafs ayah count per surah, index 1..114
    surah = 1,        -- initial surah (1..114)
    ayah = 1,         -- initial ayah (clamped to the surah)
    surah_text = _("Surah"),
    ayah_text = _("Ayah"),
    cancel_text = _("Close"),
    ok_text = _("Go"),
    callback = nil,        -- function(surah, ayah)
    close_callback = nil,
}

function GotoDialog:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    -- Wider than DoubleSpinWidget's default: the surah column carries
    -- "114 · Al-Fatiha"-length labels.
    self.width = math.floor(math.min(self.screen_width, self.screen_height) * 0.9)
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ w = self.screen_width, h = self.screen_height },
            },
        }
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = Geom:new{ w = self.screen_width, h = self.screen_height },
            },
        }
    end
    self:update(self.surah, self.ayah)
end

-- Round 19 (queued round 15): grayed prev/next NEIGHBOR PREVIEW — the
-- picker-wheel look. Stock builds the spinner as [▲][space][value]
-- [space][▼]; the spaces become fixed-size DIM rows showing what ▲/▼
-- would land on (reading order: previous above, next below). The
-- neighbor rows sit in fixed-dimen boxes so spins never re-layout the
-- group; structure-guarded, so a stock layout change just renders the
-- plain picker. neighbor_text(picker, dir) -> label (dir 1 = the ▲
-- target, -1 = the ▼ target).
local function attachNeighbors(picker, neighbor_text)
    local frame = picker.frame
    local center = frame and frame[1]
    local vg = center and center[1]
    if not (vg and #vg == 5 and picker.text_value) then return end
    local face = Font:getFace("cfont", 17)
    local function mk()
        return TextWidget:new{
            text = " ",
            face = face,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = picker.width,
        }
    end
    local up_txt, down_txt = mk(), mk()
    local function refresh()
        up_txt:setText(neighbor_text(picker, 1) or " ")
        down_txt:setText(neighbor_text(picker, -1) or " ")
    end
    refresh()
    local function boxed(w)
        return CenterContainer:new{
            dimen = Geom:new{ w = picker.width, h = w:getSize().h },
            w,
        }
    end
    local group = VerticalGroup:new{
        align = "center",
        vg[1], boxed(up_txt), vg[3], boxed(down_txt), vg[5],
    }
    picker.frame = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.default,
        CenterContainer:new{
            align = "center",
            dimen = Geom:new{
                w = group:getSize().w,
                h = group:getSize().h,
            },
            group,
        },
    }
    picker.dimen = picker.frame:getSize()
    picker[1] = picker.frame
    -- ayah spins update in place (no dialog rebuild): refresh the
    -- neighbors alongside the stock center update
    local orig_update = picker.update
    picker.update = function(p, ...)
        orig_update(p, ...)
        refresh()
        UIManager:setDirty(p.show_parent, function()
            return "ui", p.dimen
        end)
    end
end

function GotoDialog:update(surah, ayah)
    local prev_movable_offset = self.movable and self.movable:getMovedOffset()
    local max = self.counts[surah] or 1
    if ayah > max then ayah = max end
    if ayah < 1 then ayah = 1 end
    self.layout = {}
    -- Both pickers spin INVERTED from stock (owner 2026-07-27): ▼ =
    -- next, ▲ = previous — reading order, like turning pages. Stock ▲
    -- applies +value_step, so negative steps flip both tap and hold.
    -- Both columns WRAP (loop past the ends).
    self.surah_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.width * 0.42),
        value_table = self.labels,
        value_index = surah,
        wrap = true,
        value_step = -1,
        value_hold_step = -10,
    }
    local labels = self.labels
    attachNeighbors(self.surah_widget, function(p, dir)
        local t = (p.value_index or 1) + dir * (p.value_step or 1)
        if t < 1 then t = 114 elseif t > 114 then t = 1 end
        return labels[t]
    end)
    self:mergeLayoutInHorizontal(self.surah_widget)
    self.ayah_widget = NumberPickerWidget:new{
        show_parent = self,
        precision = "%1d",
        value = ayah,
        value_min = 1,
        value_max = max,
        wrap = true,
        value_step = -1,
        value_hold_step = -10,
    }
    attachNeighbors(self.ayah_widget, function(p, dir)
        local t = (p.value or 1) + dir * (p.value_step or 1)
        local hi = p.value_max or 1
        if t < 1 then t = hi elseif t > hi then t = 1 end
        return tostring(t)
    end)
    self:mergeLayoutInHorizontal(self.ayah_widget)
    -- Surah change RESETS the ayah column to 1 (owner 2026-07-27: a
    -- new surah starts at its first ayah) and re-clamps its max:
    -- rebuild both (the DoubleSpinWidget idiom — pickers carry
    -- min/max at :new time).
    self.surah_widget.picker_updated_callback = function(_value, value_index)
        self:update(value_index, 1)
    end
    -- The surah VALUE is tappable like the ayah number (owner
    -- 2026-07-27): stock only wires center-tap input for numeric
    -- pickers (value_table columns get none), but the center Button
    -- is exposed as text_value. It opens the full surah list (owner
    -- 2026-11-10; before, a type-the-number prompt).
    self.surah_widget.text_value.callback = function()
        self:showSurahList()
    end

    local text_max_width = math.floor(0.95 * self.width / 2)
    local surah_group = VerticalGroup:new{
        align = "center",
        TextWidget:new{
            text = self.surah_text,
            face = self.title_face,
            max_width = text_max_width,
        },
        self.surah_widget,
    }
    local ayah_group = VerticalGroup:new{
        align = "center",
        TextWidget:new{
            text = self.ayah_text,
            face = self.title_face,
            max_width = text_max_width,
        },
        self.ayah_widget,
    }
    local widget_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = math.floor(self.width * 0.58),
                h = surah_group:getSize().h,
            },
            surah_group,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = math.floor(self.width * 0.42),
                h = ayah_group:getSize().h,
            },
            ayah_group,
        },
    }

    local title_bar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title_text,
        title_shrink_font_to_fit = true,
        show_parent = self,
    }

    local button_table = ButtonTable:new{
        width = self.width - 2 * Size.padding.default,
        buttons = { {
            {
                text = self.cancel_text,
                callback = function() self:onClose() end,
            },
            {
                text = self.ok_text,
                callback = function()
                    local _v, s = self.surah_widget:getValue()
                    local a = self.ayah_widget:getValue()
                    self:onClose()
                    if self.callback then self.callback(s, a) end
                end,
            },
        } },
        zero_sep = true,
        show_parent = self,
    }
    self:mergeLayoutInVertical(button_table)

    self.widget_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_bar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = widget_group:getSize().h + 4 * Size.padding.large,
                },
                widget_group,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = button_table:getSize().h,
                },
                button_table,
            },
        },
    }
    -- unmovable: a swipe spins a column (onSwipe) instead of dragging
    -- the box; the container stays so the layout is unchanged
    self.movable = MovableContainer:new{
        unmovable = true,
        self.widget_frame,
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        self.movable,
    }
    if prev_movable_offset then
        self.movable:setMovedOffset(prev_movable_offset)
    end
    self:refocusWidget()
    UIManager:setDirty(self, function()
        return "ui", self.widget_frame.dimen
    end)
end

--- Center-tap on the surah column: the full surah list. It opens on
-- the page that holds the current surah (drawn bold); a tap picks one
-- and the ayah resets to 1, like any surah change. Closing the list
-- without picking leaves the dialog as it was.
function GotoDialog:showSurahList()
    local Menu = require("ui/widget/menu")
    local cur = select(2, self.surah_widget:getValue())   -- value, index
    local items = surahListItems(self.labels, self.counts, cur)
    local reader_settings = rawget(_G, "G_reader_settings")   -- KOReader's global
    local menu
    menu = Menu:new{
        title = self.surah_text,
        item_table = items,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        width = self.screen_width,
        height = self.screen_height,
        single_line = true,
        items_font_size = 18,
        items_mandatory_font_size = 14,
        items_per_page = listRowsPerPage(
            reader_settings and reader_settings:readSetting("items_per_page"),
            self.screen_height,
            Screen.scaleBySize and Screen:scaleBySize(48)),
    }
    menu.onMenuSelect = function(_menu, item)
        UIManager:close(menu)
        self.surah_list = nil
        if item and item.surah then self:update(item.surah, 1) end
        return true
    end
    menu.close_callback = function() self.surah_list = nil end
    menu:switchItemTable(nil, items, cur)   -- turn to the current surah's page
    self.surah_list = menu
    UIManager:show(menu)
end

function GotoDialog:onCloseWidget()
    -- a dialog torn down from outside (book closed) takes its list along
    if self.surah_list then
        UIManager:close(self.surah_list)
        self.surah_list = nil
    end
    UIManager:setDirty(nil, function()
        return "ui", self.widget_frame.dimen
    end)
end

function GotoDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.widget_frame.dimen
    end)
    return true
end

--- A vertical swipe on a column spins it by the swipe's length. Every
-- swipe on this dialog is consumed, so none reaches the page beneath.
function GotoDialog:onSwipe(_arg, ges)
    local column, to = swipeTarget(self, ges)
    if column == "surah" then
        local cur = select(2, self.surah_widget:getValue())
        if to ~= cur then self:update(to, 1) end   -- a new surah starts at ayah 1
    elseif column == "ayah" then
        local aw = self.ayah_widget
        if to ~= aw:getValue() then
            aw.value = to
            aw:update()   -- in place; also refreshes the neighbor preview
        end
    end
    return true
end

function GotoDialog:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.widget_frame.dimen) then
        self:onClose()
    end
    return true
end

function GotoDialog:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

return GotoDialog
