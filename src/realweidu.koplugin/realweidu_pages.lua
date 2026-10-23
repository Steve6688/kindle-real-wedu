-- realweidu_pages.lua — 「发现」and「我」full-screen tab pages.
-- Each page draws Real微读's own bottom bar (realweidu_ui.bottom_nav).
-- Content is only what
-- weread 1.6.0 really provides; see main.lua for the data sources.
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup   = require("ui/widget/verticalgroup")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local UIManager       = require("ui/uimanager")
local Screen          = Device.screen

local U     = require("realweidu_ui")
local Logic = require("realweidu_logic")

local function place(g, w, x, y) w.overlap_offset = { x, y }; g[#g + 1] = w; return w end
local function rect(x, y, w, h) return Geom:new{ x = x, y = y, w = w, h = h } end

local Page = InputContainer:extend{ covers_fullscreen = true }

function Page:init()
    self.W = Screen:getWidth()
    self.top, self.avail = U.content_area()
    self.own_nav = true -- v0.3.7: Real微读 always draws its own bar
    self.nav_h = self.own_nav and U.nav_height() or 0
    self.avail = self.avail - self.nav_h
    self.dimen = rect(0, 0, self.W, Screen:getHeight())
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    if Device:hasKeys() then self.key_events = { Close = { { "Back" } } } end
    self.frame = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = self.W, height = self.top + self.avail + self.nav_h, U.hspan(0) }
    self[1] = self.frame
    self:refresh(true)
end

function Page:refresh(no_dirty)
    if self.frame[1] and self.frame[1].free then self.frame[1]:free() end
    self.hits = {}
    self.row_rects = {}
    local g = OverlapGroup:new{ dimen = Geom:new{ w = self.W, h = self.avail + self.nav_h } }
    self:build(g)
    self.g = g -- 0.6.4: kept for layout/bounds checks
    if self.own_nav then
        -- 0.3.3-style bar: 〈 发现 书架 我 〉 (arrows inactive on these pages)
        place(g, U.bottom_nav(self.nav_active, self.W, false, false), 0, self.avail)
        self:hit(rect(0, self.avail, self.W, self.nav_h), function(p)
            local slot = U.NAV_SLOTS[U.nav_slot(p.x, self.W)]
            if slot == "discover" and self.on_nav_discover then self.on_nav_discover()
            elseif slot == "shelf" and self.on_nav_shelf then self.on_nav_shelf()
            elseif slot == "me" and self.on_nav_me then self.on_nav_me() end
        end)
    end
    -- status line on top, content below (taps are translated by self.top)
    self.frame[1] = VerticalGroup:new{ align = "left", U.status_bar(self.W), g }
    if not no_dirty then UIManager:setDirty(self, "ui") end
end

-- hit rects are given in content coordinates; taps arrive in screen coordinates
function Page:hit(r, fn) self.hits[#self.hits + 1] = { r = r, fn = fn } end
function Page:onTap(_, ges)
    local p = ges and ges.pos
    if not p then return end
    if U.is_shot_tap(p.x, p.y, self.W) then U.take_screenshot(0.2); return true end -- 0.6.3
    local y = p.y - self.top
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if U.inside(h.r, p.x, y) then h.fn({ x = p.x, y = y }); return true end
    end
end
function Page:onClose() UIManager:close(self); return true end
function Page:onCloseWidget() if self.frame and self.frame[1] and self.frame[1].free then self.frame[1]:free() end end

-- list row with bottom 1px line and › (UI-SPEC v1.1 我的页列表 / 发现页入口)
function Page.row_h() return math.max(U.px(120), 120) end

function Page:row(g, y, text, fn, bold)
    local m = U.px(45)
    local h = Page.row_h()
    local t = U.text(text, U.px(34), bold)
    place(g, t, m, y + math.floor((h - t:getSize().h) / 2))
    local ic = U.px(44)
    place(g, U.icon("chevron_right", ic), self.W - m - ic, y + math.floor((h - ic) / 2))
    place(g, U.hline(self.W - 2 * m, 1), m, y + h - 1)
    self:hit(rect(0, y, self.W, h), fn)
    self.row_rects = self.row_rects or {}
    self.row_rects[text] = rect(0, y, self.W, h)
    return y + h
end

-- BUG-05: rows that do not fit are paged ("‹ 上一页" / "更多 ›" rows) instead
-- of being dropped, so 「退出到 Kindle」 can never disappear.
function Page:rows_paged(g, y, list, key)
    local n, h = #list, Page.row_h()
    local fit = math.floor((self.avail - y) / h)
    local first, last, has_prev, has_next = Logic.page_rows(n, fit, self[key] or 0)
    self._paged = self._paged or {}
    self._paged[key] = { n = n, fit = fit, first = first, last = last }
    for i = first, last do
        local r = list[i]
        y = self:row(g, y, r.text, r.fn, r.bold)
    end
    if has_prev or has_next then
        y = self:nav_row(g, y,
            has_prev and function() self[key] = Logic.prev_offset(n, fit, first - 1); self:refresh() end,
            has_next and function() self[key] = last; self:refresh() end)
    end
    return y
end

-- NEW-03: one nav row, text-only arrows (no extra chevron icon); each half is
-- its own >=120px-tall tap target.
function Page:nav_row(g, y, on_prev, on_next)
    local m, h, half = U.px(45), Page.row_h(), math.floor(self.W / 2)
    if on_prev then
        local t = U.text("‹ 上一页", U.px(34), true)
        place(g, t, m, y + math.floor((h - t:getSize().h) / 2))
        self:hit(rect(0, y, half, h), on_prev)
    end
    if on_next then
        local t = U.text("下一页 ›", U.px(34), true)
        place(g, t, self.W - m - t:getSize().w, y + math.floor((h - t:getSize().h) / 2))
        self:hit(rect(half, y, self.W - half, h), on_next)
    end
    place(g, U.hline(self.W - 2 * m, 1), m, y + h - 1)
    return y + h
end

-------------------------------------------------------------------------------
-- 发现
-------------------------------------------------------------------------------
local Discover = Page:extend{
    name = "realweidu_discover",
    nav_active = "discover",
    books = nil,          -- Data.get_shelf() list (may be empty)
    on_search = nil, on_open = nil, on_all = nil,
    entries = nil,        -- { {text=, fn=}, ... } weread entries that exist
}

function Discover:build(g)
    local W, m = self.W, U.px(45)
    local y = U.px(24) -- 0.6.3: no search capsule here; the space goes to the rankings
    -- 最近阅读: 4 covers + 「全部 ›」 cell (UI-SPEC v1.1)
    local recent = Logic.recent(self.books, 4)
    local title = U.text("最近阅读", U.px(40), true)
    place(g, title, m, y + U.px(10)); y = y + math.max(U.px(90), title:getSize().h + U.px(20))
    -- 0.6.5: one grid for all three rows
    local name_px = U.px(26)
    local name_h = math.floor(name_px * 1.45)
    local row_extra = U.px(8) + name_h
    local fixed = y + Discover.TAB_H() + Discover.HDR_H() + 3 * row_extra
    local G = Logic.home_grid(W, m, self.avail, fixed, 3, 4, U.px(20), U.px(30))
    self.grid, self.name_px = G, name_px
    local cw, ch = G.cw, G.ch
    self.recent_rects = {}
    if #recent == 0 then
        local t = U.text("还没有阅读记录。去书架打开一本书吧。", U.px(30))
        place(g, t, m, y + math.floor((ch - t:getSize().h) / 2))
    else
        for i, b in ipairs(recent) do
            local x = G.xs[i]
            place(g, U.cover(b.cover, b.title, cw, ch, U.px(24)), x, y)
            place(g, U.textbox(b.title, name_px, cw, name_h, true), x, y + ch + U.px(8))
            self.recent_rects[i] = rect(x, y, cw, ch)
            self:hit(rect(x, y, cw, ch + row_extra), function() if self.on_open then self.on_open(b) end end)
        end
        local x = G.xs[5]
        place(g, FrameContainer:new{ bordersize = 1, color = U.GRAY, background = U.WHITE, padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = cw - 2, h = ch - 2 }, U.text("全部 ›", U.px(32), true) } }, x, y)
        self.recent_rects[5] = rect(x, y, cw, ch)
        self:hit(rect(x, y, cw, ch + row_extra), function() if self.on_all then self.on_all() end end)
    end
    y = y + ch + row_extra + G.vgap
    self:build_weread(g, y)
end
function Discover.TAB_H() return math.max(U.px(84), 84) end
function Discover.HDR_H() return math.max(U.px(80), 80) end

-- 0.6.4: 「微信读书」 block = ranking tabs, ONE row of 5 covers of the selected
-- ranking, then 「为你推荐」 (+ 换一批) with ONE row of 5 covers. Same 5-column
-- grid as 最近阅读; leftover height is split evenly between the rows.
function Discover:cover_row(g, y, books, cw, ch, name_px, empty_text)
    local W, m = self.W, U.px(45)
    local name_h = math.floor(name_px * 1.45)
    if #books == 0 then
        place(g, U.text(empty_text, U.px(30)), m, y + math.floor((ch - U.px(30)) / 2))
    end
    self.cover_rects = self.cover_rects or {}
    for i = 1, math.min(5, #books) do
        local b = books[i]
        local x = self.grid.xs[i] -- 0.6.5: shared grid
        place(g, U.cover(b.cover_file, b.title, cw, ch, U.px(24)), x, y)
        place(g, U.textbox(b.title, name_px, cw, name_h, true), x, y + ch + U.px(8))
        self.cover_rects[#self.cover_rects + 1] = rect(x, y, cw, ch) -- cover box (layout checks)
        self:hit(rect(x, y, cw, ch + U.px(8) + name_h), function() if self.on_book then self.on_book(b) end end)
    end
    return y + ch + U.px(8) + name_h
end

function Discover:build_weread(g, y)
    local W, m = self.W, U.px(45)
    local R = self.rank
    if not R then return y end
    self.cover_rects = {}
    -- tabs (the block's header): bold + underline on the selected one
    local tab_h = Discover.TAB_H()
    local tw = math.floor((W - 2 * m) / #R.TABS)
    self.tab_rects = {}
    for i, tab in ipairs(R.TABS) do
        local x = m + (i - 1) * tw
        local on = i == R.tab
        local lbl = U.text(tab.name, U.px(34), on)
        place(g, lbl, x + math.floor((tw - lbl:getSize().w) / 2), y + math.floor((tab_h - lbl:getSize().h) / 2))
        if on then place(g, U.hline(math.floor(tw * 0.5), U.px(6)), x + math.floor(tw * 0.25), y + tab_h - U.px(6)) end
        self.tab_rects[i] = rect(x, y, tw, tab_h)
        self:hit(self.tab_rects[i], function()
            -- tap another tab: switch the row; tap the selected tab again: whole ranking
            if on and self.on_rank then self.on_rank(i) elseif self.on_tab then self.on_tab(i) end
        end)
    end
    y = y + tab_h
    place(g, U.hline(W - 2 * m, 1), m, y)
    local G = self.grid
    local cw, ch, vgap = G.cw, G.ch, G.vgap
    local name_px = self.name_px
    local hdr_h = Discover.HDR_H()
    self.rank_layout = { ch = ch, cw = cw, vgap = vgap }
    y = y + vgap
    local books, loaded = R.rank_books()
    local empty = self.rank_error and ("榜单加载失败（点此重试）") or (loaded and "暂无榜单数据" or "正在加载榜单…")
    local ry = y
    y = self:cover_row(g, y, books, cw, ch, name_px, empty)
    if #books == 0 then
        self:hit(rect(0, ry, W, ch), function() if self.on_reload then self.on_reload() end end)
    end
    y = y + vgap
    -- 为你推荐 + 换一批
    local rt = U.text("为你推荐", U.px(36), true)
    place(g, rt, m, y + math.floor((hdr_h - rt:getSize().h) / 2))
    local sw = U.text("换一批 ↻", U.px(32), true)
    local swx = W - m - sw:getSize().w
    place(g, sw, swx, y + math.floor((hdr_h - sw:getSize().h) / 2))
    self.more_rect = rect(swx - U.px(40), y, sw:getSize().w + U.px(40) + m, hdr_h)
    self:hit(self.more_rect, function() if self.on_more then self.on_more() end end)
    y = y + hdr_h
    y = self:cover_row(g, y, R.batch(), cw, ch, name_px, loaded and "暂无推荐" or "正在加载推荐…")
    self.weread_bottom = y
    return y
end

-------------------------------------------------------------------------------
-- 0.6.3 one ranking, full list (paged rows)
-------------------------------------------------------------------------------
local RankList = Page:extend{
    name = "realweidu_ranklist",
    nav_active = "discover",
    title = nil, books = nil, on_book = nil, on_back = nil,
}

function RankList:build(g)
    local W, m = self.W, U.px(45)
    local y = U.px(24)
    local t = U.text("‹ " .. (self.title or "榜单"), U.px(40), true)
    place(g, t, m, y + U.px(10))
    self:hit(rect(0, y, W, U.px(100)), function() if self.on_back then self.on_back() end end)
    y = y + U.px(110)
    place(g, U.hline(W - 2 * m, 1), m, y - 1)
    local rows = {}
    for i, b in ipairs(self.books or {}) do
        rows[i] = { text = i .. "  " .. (b.title or "") .. ((b.author or "") ~= "" and ("  ·  " .. b.author) or ""),
            fn = function() if self.on_book then self.on_book(b) end end }
    end
    if #rows == 0 then place(g, U.text("暂无数据", U.px(30)), m, y + U.px(20)); return end
    self:rows_paged(g, y, rows, "_row_offset")
end

-------------------------------------------------------------------------------
-- 我
-------------------------------------------------------------------------------
local Me = Page:extend{
    name = "realweidu_me",
    nav_active = "me",
    account_name = nil,
    stats = nil,          -- { week_min=, finished=, notes=, note_text= }
    rows = nil,           -- { {text=, fn=, bold=}, ... }
}

function Me:build(g)
    local W, m = self.W, U.px(45)
    local y = U.px(40)
    local d = U.px(140)
    place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = U.WHITE, radius = math.floor(d / 2),
        padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = d - 4, h = d - 4 }, U.text(Logic.initial(self.account_name), U.px(60), true) } },
        m, y)
    local nick = U.text(self.account_name ~= "" and self.account_name or "未登录", U.px(44), true, W - 3 * m - d)
    local sub = U.text(self.account_sub or "微信读书账号", U.px(28))
    local tx = m + d + U.px(36)
    local th = nick:getSize().h + U.px(10) + sub:getSize().h
    place(g, nick, tx, y + math.floor((d - th) / 2))
    place(g, sub, tx, y + math.floor((d - th) / 2) + nick:getSize().h + U.px(10))
    y = y + d + U.px(50)
    -- v0.3.6 (ENTRY-MIN): 「我」 = account header + 2 rows; the stats card
    -- moved to 更多设置 → 阅读时长统计. Kept behind show_stats for reuse.
    if not self.show_stats then
        y = y + U.px(32)
        place(g, U.hline(W - 2 * m, 2), m, y - 2)
        y = self:rows_paged(g, y, self.rows or {}, "_row_offset")
        if self.footer then
            local f = U.text(self.footer, U.px(26))
            place(g, f, math.floor((W - f:getSize().w) / 2), self.avail - U.px(80))
        end
        return
    end
    -- 数据卡: 3 equal cells, 1px vertical separators, no fill
    local s = self.stats or {}
    local cells = {
        { Logic.fmt_num(s.week_min), "本周阅读（分钟）" },
        { Logic.fmt_num(s.finished), "读完（本）" },
        { Logic.fmt_num(s.notes),    "笔记（条）" },
    }
    local cw = math.floor((W - 2 * m) / 3)
    local card_h = math.max(U.px(180), 150)
    for i, c in ipairs(cells) do
        local x = m + (i - 1) * cw
        local big = U.text(c[1], U.px(56), true)
        local lab = U.text(c[2], U.px(28))
        local hh = big:getSize().h + U.px(8) + lab:getSize().h
        local yy = y + math.floor((card_h - hh) / 2)
        place(g, big, x + math.floor((cw - big:getSize().w) / 2), yy)
        place(g, lab, x + math.floor((cw - lab:getSize().w) / 2), yy + big:getSize().h + U.px(8))
        if i > 1 then place(g, U.vline(math.floor(card_h * 0.6)), x, y + math.floor(card_h * 0.2)) end
    end
    self:hit(rect(m, y, W - 2 * m, card_h), function() if self.on_refresh_stats then self.on_refresh_stats() end end)
    y = y + card_h
    if s.hint then
        local t = U.text(s.hint, U.px(24))
        place(g, t, m, y); y = y + t:getSize().h
    end
    y = y + U.px(30)
    place(g, U.hline(W - 2 * m, 1), m, y - 1)
    y = self:rows_paged(g, y, self.rows or {}, "_row_offset")
end

return { Discover = Discover, Me = Me, Page = Page, RankList = RankList }
