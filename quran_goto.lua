--[[--
quran_goto.lua — the quick surah/ayah navigator dialog (D-R4-10, owner
shape call 2026-07-26: two picker columns, surah left / ayah right).

Structurally a DoubleSpinWidget (frontend/ui/widget/doublespinwidget.lua),
composed here directly because DoubleSpinWidget cannot host a value_table
column: the surah picker spins over label strings ("36 · Ya-Sin"), and the
ayah picker's max must re-clamp to the selected surah's count on every
surah change (the date-widget precedent). Ayah numbering is Hafs-canonical
(design invariant D8) — the go-to seam converts for Warsh books.
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
    end
    self:update(self.surah, self.ayah)
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
    -- is exposed as text_value — hook it to a surah-number prompt.
    self.surah_widget.text_value.callback = function()
        self:promptSurah()
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
    self.movable = MovableContainer:new{
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

--- Center-tap on the surah column: type the surah number directly
-- (1-114, clamped); the ayah resets to 1 like any surah change.
function GotoDialog:promptSurah()
    local InputDialog = require("ui/widget/inputdialog")
    local input
    input = InputDialog:new{
        title = _("Surah number (1-114)"),
        input_type = "number",
        buttons = { {
            {
                text = self.cancel_text,
                id = "close",
                callback = function() UIManager:close(input) end,
            },
            {
                text = _("OK"),
                is_enter_default = true,
                callback = function()
                    local n = tonumber(input:getInputText())
                    UIManager:close(input)
                    if n then
                        n = math.floor(n)
                        if n < 1 then n = 1 elseif n > 114 then n = 114 end
                        self:update(n, 1)
                    end
                end,
            },
        } },
    }
    UIManager:show(input)
    input:onShowKeyboard()
end

function GotoDialog:onCloseWidget()
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
