-- realweidu_ui.lua — small shared drawing helpers built on stock KOReader
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

-- 0.3.3 look, drawn by Real微读 itself (SimpleUI is gone since 0.3.7):
-- a thin top status line (time left, battery right) and an icon-only bottom
-- bar ‹ 发现 书架 我 › with a hairline on top and a thick marker over the
-- active tab. Arrows are black when that page direction exists, else gray.
U.MID_GRAY = Blitbuffer.Color8(0x99)
function U.status_h() return U.px(82) end
function U.nav_height() return U.px(226) end
U.NAV_SLOTS = { "prev", "discover", "shelf", "me", "next" }
local function nav_margin() return U.px(47) end
-- slot index (1..5) for an x coordinate
function U.nav_slot(x, width)
    width = width or Screen:getWidth()
    local m = nav_margin()
    local sw = (width - 2 * m) / 5
    local i = math.floor((x - m) / sw) + 1
    return math.max(1, math.min(5, i))
end

function U.status_bar(width)
    width = width or Screen:getWidth()
    local h = U.status_h()
    local m = nav_margin()
    local t = U.text(os.date("%H:%M"), U.px(34))
    local pct
    pcall(function()
        local p = Device.getPowerDevice and Device:getPowerDevice()
        pct = p and p.getCapacity and p:getCapacity()
    end)
    local right = HorizontalGroup:new{ align = "center" }
    -- 0.6.3 global screenshot button (tap the right part of the status line)
    right[#right + 1] = U.text("截屏", U.px(30), true)
    right[#right + 1] = U.hspan(U.px(40))
    -- small upright battery glyph (black body, cap on top)
    local bw, bh = U.px(18), U.px(30)
    right[#right + 1] = VerticalGroup:new{ align = "center", U.hline(U.px(8), U.px(4)), U.hline(bw, bh) }
    right[#right + 1] = U.hspan(U.px(6))
    right[#right + 1] = U.text((pct and tostring(math.floor(pct)) or "—") .. "%", U.px(34))
    local rw = right:getSize().w
    local row = HorizontalGroup:new{ align = "center",
        U.hspan(m), t, U.hspan(math.max(0, width - 2 * m - t:getSize().w - rw)), right, U.hspan(m) }
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = h }, row }
end

-- active: "discover" | "shelf" | "me"; has_prev / has_next tint the arrows.
function U.bottom_nav(active, width, has_prev, has_next)
    width = width or Screen:getWidth()
    local h = U.nav_height()
    local m = nav_margin()
    local sw = math.floor((width - 2 * m) / 5)
    local line_w = width - 2 * m
    local cells = HorizontalGroup:new{ align = "center", U.hspan(m) }
    local drop = U.px(70) -- 0.6.3: icons sit lower (less blank space under them)
    local cell_h = h - U.px(10) - drop
    for _, id in ipairs(U.NAV_SLOTS) do
        local content
        if id == "prev" or id == "next" then
            local w = U.text(id == "prev" and "〈" or "〉", U.px(60))
            w.fgcolor = ((id == "prev" and has_prev) or (id == "next" and has_next)) and U.BLACK or U.MID_GRAY
            content = w
        else
            content = U.icon("tab_" .. id .. (id == active and "_active" or ""), U.px(80))
        end
        cells[#cells + 1] = CenterContainer:new{ dimen = Geom:new{ w = sw, h = cell_h }, content }
    end
    -- marker row: hairline across, thick bar under the active slot
    local idx = ({ discover = 2, shelf = 3, me = 4 })[active]
    local marker = HorizontalGroup:new{ align = "top", U.hspan(m) }
    if idx then
        local before = (idx - 1) * sw
        marker[#marker + 1] = U.hline(before, 2)
        marker[#marker + 1] = U.hline(sw, U.px(8))
        marker[#marker + 1] = U.hline(line_w - before - sw, 2)
    else
        marker[#marker + 1] = U.hline(line_w, 2)
    end
    return FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = width, height = h,
        VerticalGroup:new{ align = "left",
            FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, height = U.px(10), width = width, marker },
            VerticalSpan:new{ width = drop },
            cells,
        },
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

-- Content area below the status line (the bottom bar is drawn by each page).
-- 0.6.3 global screenshot: status-line right half (home pages) / 「截屏」 in the reader bar.
function U.is_shot_tap(x, y, width)
    return y ~= nil and x ~= nil and y < U.status_h() and x >= math.floor((width or Screen:getWidth()) * 0.55)
end
function U.take_screenshot(delay)
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(delay or 0.6, function() -- let the tapped menu close / repaint first
        local inst
        pcall(function() inst = require("apps/reader/readerui").instance end)
        if not inst then pcall(function() inst = require("apps/filemanager/filemanager").instance end) end
        if inst and inst.screenshot and inst.screenshot.onScreenshot then
            local ok = pcall(inst.screenshot.onScreenshot, inst.screenshot)
            if ok then return end
        end
        local dir = require("datastorage"):getDataDir() .. "/screenshots"
        os.execute("mkdir -p '" .. dir .. "'")
        local f = os.date(dir .. "/realweidu_%Y-%m-%d_%H%M%S.png")
        Screen:shot(f)
        UIManager:show(require("ui/widget/infomessage"):new{ text = "截屏已保存：" .. f, timeout = 3 })
    end)
    U.last_shot_request = os.time()
end

function U.content_area()
    local top = U.status_h()
    return top, Screen:getHeight() - top
end

return U
