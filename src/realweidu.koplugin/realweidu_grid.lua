-- realweidu_grid.lua — full-screen 4-column cover grid "书架" page.
-- Built only from stock KOReader widgets (frontend/ui/widget/*); own bottom bar.
-- Paging: page / page_num, onNextPage / onPrevPage / onGotoPage (swipes, page keys).
-- E-ink: no animation, only black / white / #D9D9D9, whole-page flips.
local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local IconWidget      = require("ui/widget/iconwidget")
local ImageWidget     = require("ui/widget/imagewidget")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local logger          = require("logger")
local Screen          = Device.screen

local Layout = require("realweidu_layout")
local U      = require("realweidu_ui")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY  = Blitbuffer.Color8(0xD9) -- UI-SPEC: the single gray, controls only

-- Font:getFace() multiplies size by Screen:scaleBySize (frontend/ui/font.lua:276);
-- convert our pixel sizes back so the rendered glyph height matches UI-SPEC px.
local function face(px)
    local r = Screen:scaleBySize(1000) / 1000
    return Font:getFace("cfont", math.max(8, math.floor(px / r + 0.5)))
end

local ShelfGrid = InputContainer:extend{
    name = "realweidu_grid",       -- BarInjection matches on this name
    covers_fullscreen = true,
    books = nil,                     -- from Data.get_shelf()
    icons_dir = nil,
    on_open = nil,                   -- function(book)
    on_import = nil,                 -- function()
    on_select = nil,                 -- function()
    on_search = nil,                 -- function(grid) -> shows search dialog
    on_discover = nil,
    on_shelf = nil,
    on_me = nil,
    keyword = nil,                   -- active local filter
    page = 1,
    page_num = 1,
}

function ShelfGrid:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.all_books = self.books or {}
    self.shown = Layout.filter(self.all_books, self.keyword)
    -- 0.3.8: 0.3.3 look — status line on top, Real微读's own bottom bar.
    local top, avail = U.content_area()
    self.content_top = top
    self.own_nav = true
    self.nav_h = self.own_nav and U.nav_height() or 0
    self.avail_h = avail - self.nav_h
    self.L = Layout.compute{ screen_w = Screen:getWidth(), avail_h = self.avail_h }
    self.page_num = Layout.page_count(#self.shown, self.L.per_page)
    self.page = Layout.clamp_page(self.page, #self.shown, self.L.per_page)

    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    if Device:hasKeys() then
        self.key_events = {
            NextPage = { { Device.input and Device.input.group and Device.input.group.PgFwd or "RPgFwd" } },
            PrevPage = { { Device.input and Device.input.group and Device.input.group.PgBack or "RPgBack" } },
            Close    = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
        }
    end
    self:_build()
end

-- Header -------------------------------------------------------------------

function ShelfGrid:_icon(name, size)
    return IconWidget:new{ file = self.icons_dir .. "/" .. name .. ".svg",
        width = size, height = size, alpha = true }
end

function ShelfGrid:_buildHeader()
    local L = self.L
    local placeholder = self.keyword and self.keyword ~= "" and ("筛选：" .. self.keyword)
        or (self.placeholder or "搜索书架或微信读书")
    local icon_sz = math.floor(L.search_font * 1.3)
    local capsule = FrameContainer:new{
        bordersize = math.max(2, math.floor(2 * L.k + 0.5)), color = BLACK, background = WHITE,
        radius = math.floor(L.search_h / 2), padding = 0, margin = 0,
        LeftContainer:new{
            dimen = Geom:new{ w = L.search_w - 4, h = L.search_h - 4 },
            HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = math.floor(L.search_h * 0.35) },
                self:_icon("search", icon_sz),
                HorizontalSpan:new{ width = math.floor(L.search_font * 0.5) },
                TextWidget:new{ text = placeholder, face = face(L.search_font), fgcolor = BLACK,
                    max_width = L.search_w - L.search_h - icon_sz },
            },
        },
    }
    local function action(icon, label)
        return HorizontalGroup:new{ align = "center",
            self:_icon(icon, L.action_font),
            HorizontalSpan:new{ width = math.floor(L.action_font * 0.25) },
            TextWidget:new{ text = label, face = face(L.action_font), fgcolor = BLACK },
        }
    end
    -- 0.6.2: 「导入」「选择」 replaced by one 「刷新书架」 (sync with WeRead)
    local imp = action("refresh", "刷新书架")
    local title = TextWidget:new{ text = self.title or "书架", face = face(L.title_font), bold = true, fgcolor = BLACK }
    local gap = math.floor(L.action_font * 1.2)
    local right_w = imp:getSize().w
    local row_inner_w = Screen:getWidth() - 2 * L.margin
    local title_row = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = L.margin },
        LeftContainer:new{ dimen = Geom:new{ w = row_inner_w - right_w, h = L.title_row_h }, title },
        imp,
    }
    -- hit rectangles (screen coords) for the header controls; full row height
    -- so each target is >= 120 px tall.
    local y0 = self.content_top
    local imp_w = imp:getSize().w
    local right_x = L.margin + row_inner_w - right_w
    local pad = math.floor(gap / 2)
    self.hit_search = Geom:new{ x = L.margin, y = y0 + L.search_top, w = L.search_w, h = L.search_h }
    local ty = y0 + L.search_top + L.search_h
    self.hit_import = Geom:new{ x = right_x - pad, y = ty, w = math.max(imp_w + 2 * pad, L.title_row_h), h = L.title_row_h }
    self.hit_select = nil
    return VerticalGroup:new{ align = "left",
        VerticalSpan:new{ width = L.search_top },
        HorizontalGroup:new{ HorizontalSpan:new{ width = L.margin }, capsule },
        title_row,
    }
end

-- Grid -----------------------------------------------------------------------

function ShelfGrid:_buildCover(book)
    local L = self.L
    local inner_w, inner_h = L.cover_w - 2, L.cover_h - 2
    local inner
    if book.cover then
        local ok, w = pcall(ImageWidget.new, ImageWidget, {
            file = book.cover,
            width = inner_w, height = inner_h,
            -- thumbs are 2:3 like the box; stretch only if close, else fit
            stretch_limit_percentage = 10,
            -- Do not put covers in KOReader's shared 8 MiB ImageCache
            -- (imagewidget.lua:41-50): it also holds UI icons. We free the
            -- page's blitbuffers ourselves on every flip / close.
            file_do_cache = false,
        })
        if ok and w then inner = w else logger.warn("realweidu: cover failed", book.cover, w) end
    end
    if not inner then
        -- placeholder: white box with the title centred (no gray text)
        inner = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            TextBoxWidget:new{ text = book.title or "", face = face(L.name_font), bold = true,
                width = inner_w - 2 * math.floor(L.name_font * 0.6), alignment = "center",
                fgcolor = BLACK, height = inner_h - L.name_font * 2, height_adjust = true,
                height_overflow_show_ellipsis = true },
        }
    end
    return FrameContainer:new{ bordersize = 1, color = GRAY, background = WHITE,
        padding = 0, margin = 0, radius = 0,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, inner } }
end

function ShelfGrid:_buildCell(book)
    local L = self.L
    -- 0.6.1 边下边读: one-line title + a progress line in the same box height
    local okS, Stream = pcall(require, "realweidu_stream")
    local label = okS and book.bookId and Stream.shelf_label(book.bookId) or nil
    if label then
        return VerticalGroup:new{ align = "left",
            self:_buildCover(book),
            VerticalSpan:new{ width = L.name_gap },
            TextBoxWidget:new{ text = book.title or "", face = face(L.name_font), bold = true,
                width = L.cover_w, height = L.name_line_h, height_overflow_show_ellipsis = true,
                fgcolor = BLACK, alignment = "left" },
            TextBoxWidget:new{ text = label, face = face(math.floor(L.name_font * 0.85)),
                width = L.cover_w, height = L.name_h - L.name_line_h, height_overflow_show_ellipsis = true,
                fgcolor = BLACK, alignment = "left" },
        }
    end
    return VerticalGroup:new{ align = "left",
        self:_buildCover(book),
        VerticalSpan:new{ width = L.name_gap },
        TextBoxWidget:new{ text = book.title or "", face = face(L.name_font), bold = true,
            width = L.cover_w, height = L.name_h, height_overflow_show_ellipsis = true,
            fgcolor = BLACK, alignment = "left" },
    }
end

function ShelfGrid:_buildGrid()
    local L = self.L
    local items = Layout.page_slice(self.shown, self.page, L.per_page)
    self.page_items = items
    local og = OverlapGroup:new{ dimen = Geom:new{ w = Screen:getWidth(), h = L.grid_h } }
    if #items == 0 then
        local msg = (self.keyword and self.keyword ~= "") and ("书架中没有匹配「" .. self.keyword .. "」的书")
            or "书架为空。点右上「刷新书架」同步微信读书书架。"
        og[1] = CenterContainer:new{ dimen = Geom:new{ w = Screen:getWidth(), h = math.floor(L.grid_h / 2) },
            TextWidget:new{ text = msg, face = face(L.name_font), fgcolor = BLACK } }
        return og
    end
    for i, book in ipairs(items) do
        local x, y = Layout.cell_pos(L, i)
        local cell = self:_buildCell(book)
        cell.overlap_offset = { x, y }
        og[#og + 1] = cell
    end
    return og
end

function ShelfGrid:_buildBody()
    self.grid_top = self.content_top + self.L.header_h
    local body = VerticalGroup:new{ align = "left",
        U.status_bar(Screen:getWidth()),
        self:_buildHeader(),
        self:_buildGrid(),
    }
    if self.own_nav then
        body[#body + 1] = U.bottom_nav("shelf", Screen:getWidth(), self.page > 1, self.page < self.page_num)
        self.nav_top = self.content_top + self.avail_h
    end
    return body
end

-- self[1] is a stable white frame; on page flips we only replace its child.
function ShelfGrid:_build()
    self.frame = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0, background = WHITE,
        width = Screen:getWidth(), height = self.content_top + self.avail_h + self.nav_h,
        self:_buildBody(),
    }
    self[1] = self.frame
end

-- Repaint after a page flip / filter: full-page "ui" refresh, no animation.
function ShelfGrid:_refresh()
    if self.frame[1] then self.frame[1]:free() end -- release cover blitbuffers now
    self.frame[1] = self:_buildBody()
    self:_syncBar()
    UIManager:setDirty(self, "ui")
end

function ShelfGrid:_syncBar() end -- arrows are redrawn with the page (see _buildBody)

-- Paging API (keys + swipes) ---------------------------------

function ShelfGrid:onGotoPage(p)
    p = Layout.clamp_page(p, #self.shown, self.L.per_page)
    if p == self.page then return true end
    self.page = p
    self:_refresh()
    return true
end
function ShelfGrid:onNextPage() return self:onGotoPage(self.page + 1) end
function ShelfGrid:onPrevPage() return self:onGotoPage(self.page - 1) end

function ShelfGrid:setKeyword(kw)
    self.keyword = (kw and kw ~= "") and kw or nil
    self.shown = Layout.filter(self.all_books, self.keyword)
    self.page_num = Layout.page_count(#self.shown, self.L.per_page)
    self.page = 1
    self:_refresh()
end

function ShelfGrid:onSwipe(_, ges)
    local d = ges and ges.direction
    if d == "west" or d == "north" then return self:onNextPage()
    elseif d == "east" or d == "south" then return self:onPrevPage() end
end

local function inside(g, x, y)
    return g and x >= g.x and x < g.x + g.w and y >= g.y and y < g.y + g.h
end

function ShelfGrid:onTap(_, ges)
    local pos = ges and ges.pos
    if not pos then return end
    if self.own_nav and pos.y >= self.nav_top then
        local slot = U.NAV_SLOTS[U.nav_slot(pos.x, Screen:getWidth())]
        if slot == "prev" then self:onPrevPage()
        elseif slot == "next" then self:onNextPage()
        elseif slot == "discover" then if self.on_discover then self.on_discover() end
        elseif slot == "shelf" then if self.on_shelf then self.on_shelf() end
        elseif slot == "me" then if self.on_me then self.on_me() end end
        return true
    end
    if inside(self.hit_search, pos.x, pos.y) then
        if self.on_search then self.on_search(self) end
        return true
    end
    if inside(self.hit_import, pos.x, pos.y) then
        if self.on_import then self.on_import(self) end
        return true
    end
    if inside(self.hit_select, pos.x, pos.y) then
        if self.on_select then self.on_select(self) end
        return true
    end
    local i = Layout.hit(self.L, pos.x, pos.y - self.grid_top, #(self.page_items or {}))
    if i and self.on_open then
        self.on_open(self.page_items[i], self)
        return true
    end
end

function ShelfGrid:onClose()
    UIManager:close(self)
    return true
end

function ShelfGrid:onCloseWidget()
    -- free cover blitbuffers immediately (512 MB device)
    if self.frame and self.frame[1] then self.frame[1]:free() end
end

return ShelfGrid
