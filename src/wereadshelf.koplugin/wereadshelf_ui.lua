-- wereadshelf_ui.lua — small shared drawing helpers built on stock KOReader
-- widgets. Only black / white / #D9D9D9 (UI-SPEC v1 全局). No animation.
local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local IconWidget      = require("ui/widget/iconwidget")
local ImageWidget     = require("ui/widget/imagewidget")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Screen          = Device.screen

local U = {}
U.BLACK = Blitbuffer.COLOR_BLACK
U.WHITE = Blitbuffer.COLOR_WHITE
U.GRAY  = Blitbuffer.Color8(0xD9)

-- Screen-width scale vs PW5 reference (UI-SPEC numbers are PW5 px).
function U.k() return Screen:getWidth() / 1236 end
function U.px(v) return math.max(1, math.floor(v * U.k() + 0.5)) end

-- Font:getFace() multiplies by Screen:scaleBySize (frontend/ui/font.lua:276).
function U.face(px)
    local r = Screen:scaleBySize(1000) / 1000
    return Font:getFace("cfont", math.max(8, math.floor(px / r + 0.5)))
end

U.icons_dir = "."
function U.icon(name, size)
    return IconWidget:new{ file = U.icons_dir .. "/" .. name .. ".svg", width = size, height = size, alpha = true }
end

function U.text(t, px, bold, max_w)
    return TextWidget:new{ text = t or "", face = U.face(px), bold = bold, fgcolor = U.BLACK, max_width = max_w }
end

function U.textbox(t, px, w, h, bold, align)
    return TextBoxWidget:new{ text = t or "", face = U.face(px), bold = bold, width = w, height = h,
        height_overflow_show_ellipsis = h ~= nil, fgcolor = U.BLACK, alignment = align or "left" }
end

function U.hline(w, h, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = h or 1 }, background = color or U.BLACK }
end

function U.vline(h, w)
    return LineWidget:new{ dimen = Geom:new{ w = w or 1, h = h }, background = U.BLACK }
end

function U.hspan(w) return HorizontalSpan:new{ width = w } end

-- Real微读 bottom navigation (发现 / 书架 / 我, no arrows), drawn by every page;
-- keep it inside the plugin so the primary navigation never disappears.
function U.nav_height() return math.max(U.px(128), 112) end

function U.bottom_nav(active, width)
    width = width or Screen:getWidth()
    local h = U.nav_height()
    local tabs = {
        { id = "discover", label = "发现", icon = "tab_discover" },
        { id = "shelf", label = "书架", icon = "tab_shelf" },
        { id = "me", label = "我", icon = "tab_me" },
    }
    local cells = HorizontalGroup:new{ align = "top" }
    local base = math.floor(width / #tabs)
    for i, tab in ipairs(tabs) do
        local w = i == #tabs and (width - base * (i - 1)) or base
        local selected = tab.id == active
        local icon_name = tab.icon .. (selected and "_active" or "")
        local icon_size = U.px(48)
        local content = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = U.px(14) },
            U.icon(icon_name, icon_size),
            VerticalSpan:new{ width = U.px(5) },
            U.text(tab.label, U.px(25), selected),
        }
        cells[#cells + 1] = CenterContainer:new{ dimen = Geom:new{ w = w, h = h - 2 }, content }
    end
    return FrameContainer:new{
        bordersize = 1, padding = 0, margin = 0, color = U.BLACK, background = U.WHITE,
        width = width, height = h, cells,
    }
end

-- Pill search box (UI-SPEC 书架页搜索框).
function U.search_capsule(w, h, placeholder, font_px)
    local icon_sz = math.floor(font_px * 1.3)
    return FrameContainer:new{
        bordersize = math.max(2, U.px(2)), color = U.BLACK, background = U.WHITE,
        radius = math.floor(h / 2), padding = 0, margin = 0,
        LeftContainer:new{
            dimen = Geom:new{ w = w - 4, h = h - 4 },
            HorizontalGroup:new{ align = "center",
                U.hspan(math.floor(h * 0.35)), U.icon("search", icon_sz),
                U.hspan(math.floor(font_px * 0.5)),
                U.text(placeholder, font_px, false, w - h - icon_sz),
            },
        },
    }
end

-- Cover box w×h with 1px gray border; weread thumbnail or title placeholder.
-- Not put in KOReader's shared ImageCache (imagewidget.lua:41-50); callers
-- free() the tree on page change / close.
function U.cover(path, title, w, h, font_px)
    local iw, ih = w - 2, h - 2
    local inner
    if path then
        local ok, img = pcall(ImageWidget.new, ImageWidget, { file = path, width = iw, height = ih,
            stretch_limit_percentage = 10, file_do_cache = false })
        if ok then inner = img end
    end
    if not inner then
        inner = U.textbox(title, font_px, iw - 2 * math.floor(font_px * 0.6), nil, true, "center")
    end
    return FrameContainer:new{ bordersize = 1, color = U.GRAY, background = U.WHITE, padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = iw, h = ih }, inner } }
end

function U.inside(g, x, y)
    return g and x >= g.x and x < g.x + g.w and y >= g.y and y < g.y + g.h
end

-- Content area: the whole screen (the bottom bar is drawn by each page).
function U.content_area()
    return 0, Screen:getHeight()
end

return U
