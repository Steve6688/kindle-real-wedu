-- realweidu_readermenu.lua — official WeRead reading menu (0.4.3), e-ink light
-- theme, plus the 字体设置 panel, shown over KOReader's ReaderUI.
-- Everything it does goes through ReaderUI's own events/modules:
--   ToggleBookmark            apps/reader/modules/readerbookmark.lua:370, isPageBookmarked :423
--   ShowToc                   apps/reader/modules/readertoc.lua:806, getTocTitleOfCurrentPage :475
--   ShowSkimtoDialog          apps/reader/modules/readergoto.lua:124 (progress slider / go to)
--   ShowFlDialog              frontend/device/devicelistener.lua:194 (frontlight dialog)
--   ShowFulltextSearchInput   apps/reader/modules/readersearch.lua:294
--   SetFontSize/SetLineSpace/SetFontBaseWeight/SetFont  apps/reader/modules/readerfont.lua:203,212,221,283
--   SetPageHorizMargins       apps/reader/modules/readertypeset.lua:477
--   ToggleStyleTweak "paragraph_indent"  readerstyletweak.lua:735, ui/data/css_tweaks.lua:544
-- Values set through these events live in the document's configurable and are
-- saved to the book's sidecar by KOReader itself (persist across restarts).
local ButtonDialog    = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Event           = require("ui/event")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local Screen          = Device.screen

local U     = require("realweidu_ui")
local Logic = require("realweidu_logic")

local RM = InputContainer:extend{
    name = "realweidu_readermenu",
    ui = nil,              -- ReaderUI
    on_back = nil,         -- function() back to shelf
    weread = nil,          -- weread plugin instance (optional)
    font_open = false,
    sheet_open = false,    -- v0.3.6 阅读设置 bottom sheet (字号 / 亮度·暖光 / 翻页方式)
}
local Blitbuffer = require("ffi/blitbuffer")
local LABEL_GRAY = Blitbuffer.Color8(0x8C)
local PANEL_BG   = Blitbuffer.Color8(0xF0) -- light gray panel (e-ink)
local PILL_BG    = Blitbuffer.Color8(0xE0)
local TITLE_GRAY = Blitbuffer.Color8(0x99)
local FLOAT_BG   = Blitbuffer.Color8(0x55) -- dark float buttons

local function send_event(ui, name, ...) if ui then ui:handleEvent(Event:new(name, ...)) end end
local function place(group, w, x, y) w.overlap_offset = { x, y }; group[#group + 1] = w; return w end
local function rect(x, y, w, h) return Geom:new{ x = x, y = y, w = w, h = h } end

function RM:init()
    self.W, self.H = Screen:getWidth(), Screen:getHeight()
    self.dimen = rect(0, 0, self.W, self.H)
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    if Device:hasKeys() then self.key_events = { Close = { { "Back" } } } end
    self.m = {
        bar_h = math.max(U.px(130), 120), margin = U.px(40),
        icon = U.px(56), title_px = U.px(28),
        row_h = math.max(U.px(120), 120), circle = U.px(70), track_h = U.px(70),
        panel_title_h = math.max(U.px(110), 110), font_btn_h = U.px(85), font_pitch = math.max(U.px(120), 120),
        label_px = U.px(26), panel_title_px = U.px(36),
        -- 0.4.3 official panel
        panel_r = U.px(36), float_d = U.px(96), float_gap = U.px(20),
        stats_h = U.px(150), slider_h = U.px(110), pills_h = U.px(110), icon_h = U.px(140),
        panel_pad = U.px(36),
    }
    self:_build()
end

function RM:isRolling() return self.ui and self.ui.rolling ~= nil and self.ui.document and self.ui.document.configurable ~= nil end

-- 0.4.3 official reading menu ------------------------------------------------
-- Stats for the 3-column row: progress + ETA, reading time, notes.
function RM:_bookStats()
    local pct, eta_h, mins, notes = 0, nil, 0, 0
    local ui = self.ui
    if ui and ui.document then
        pcall(function()
            local cur = ui:getCurrentPage() or 1
            local total = ui.document:getPageCount() or 1
            if total > 0 then pct = math.floor(100 * cur / total + 0.5) end
        end)
        pcall(function()
            local ann = ui.annotation and ui.annotation.annotations
            if type(ann) == "table" then notes = #ann end
        end)
        pcall(function()
            local bm = ui.bookmark and ui.bookmark.bookmarks
            if notes == 0 and type(bm) == "table" then notes = #bm end
        end)
    end
    -- KOReader statistics plugin (if loaded)
    pcall(function()
        local st = ui.statistics
        if st and st.id_curr_book and st.getBookStat then
            local ok, data = pcall(st.getBookStat, st)
            if ok and type(data) == "table" and data.total_time_in_sec then
                mins = math.floor(data.total_time_in_sec / 60 + 0.5)
            end
        end
        if mins == 0 and st and st.data and st.data.total_time_in_sec then
            mins = math.floor(st.data.total_time_in_sec / 60 + 0.5)
        end
        -- ETA from avg page time when available
        if st and st.data and st.data.total_time_in_sec and st.data.total_read_pages
                and st.data.total_read_pages > 0 and ui.document then
            local left = (ui.document:getPageCount() or 0) - (ui:getCurrentPage() or 0)
            if left > 0 then
                local avg = st.data.total_time_in_sec / st.data.total_read_pages
                eta_h = math.max(1, math.floor(left * avg / 3600 + 0.5))
            end
        end
    end)
    if not eta_h and pct > 0 and pct < 100 and mins > 0 then
        eta_h = math.max(1, math.floor(mins * (100 - pct) / pct / 60 + 0.5))
    end
    return pct, eta_h, mins, notes
end

function RM:_chapterTitle()
    local chapter
    pcall(function() chapter = self.ui.toc:getTocTitleOfCurrentPage() end)
    local book = self.ui.doc_props and self.ui.doc_props.display_title or ""
    return Logic.reader_title(chapter, book) or ""
end

function RM:_progressFrac()
    local ui = self.ui
    if not (ui and ui.document) then return 0 end
    local cur, total = 1, 1
    pcall(function() cur = ui:getCurrentPage() or 1; total = ui.document:getPageCount() or 1 end)
    if total <= 1 then return 0 end
    return (cur - 1) / (total - 1)
end

-- Top: small gray chapter title only (official look).
function RM:_topBar(g)
    local m, W = self.m, self.W
    local title = self:_chapterTitle()
    local t = U.text(title, m.title_px, false, W - 2 * m.margin)
    t.fgcolor = TITLE_GRAY
    place(g, t, m.margin, U.px(28))
end

-- Floating round AI button above the panel (0.4.4: no 听/TTS).
function RM:_floatButtons(g, panel_y)
    local m, W = self.m, self.W
    local d = m.float_d
    local y = panel_y - d - U.px(20)
    local x_ai = W - m.margin - d
    local function float(label, x, enabled, fn)
        local txt = U.text(label, U.px(32), true)
        txt.fgcolor = U.WHITE
        if not enabled then txt.fgcolor = Blitbuffer.Color8(0xBB) end
        place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0,
            background = enabled and FLOAT_BG or Blitbuffer.Color8(0xAA),
            radius = math.floor(d / 2),
            CenterContainer:new{ dimen = Geom:new{ w = d, h = d }, txt } }, x, y)
        self:_hit(rect(x, y, d, d), fn)
    end
    float("AI", x_ai, self:_hasAI(), function() self:openAI() end)
end

function RM:_hasAI()
    -- No built-in AI; dictionary is the closest substitute when available.
    return self.ui and self.ui.dictionary ~= nil
end

function RM:openAI()
    if self.ui and self.ui.dictionary then
        self:close()
        send_event(self.ui, "ShowDictionaryLookup")
    else
        UIManager:show(require("ui/widget/infomessage"):new{ text = "本机没有 AI 功能；可在 KOReader 安装词典作替代。", timeout = 2 })
    end
end

-- Bottom official panel (rounded light gray).
function RM:_bottomBar(g)
    local m, W, H = self.m, self.W, self.H
    local panel_h = m.stats_h + m.slider_h + m.pills_h + m.icon_h + U.px(20)
    local y0 = H - panel_h
    self.panel_rect = rect(0, y0, W, panel_h)
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = PANEL_BG,
        radius = m.panel_r, width = W, height = panel_h, U.hspan(0) }, 0, y0)
    self:_floatButtons(g, y0)
    local y = y0 + U.px(16)
    -- stats row
    local pct, eta_h, mins, notes = self:_bookStats()
    local cols = {
        { tostring(pct) .. "%", eta_h and ("约 " .. eta_h .. " 小时后读完") or "阅读进度" },
        { tostring(mins) .. " 分钟", "阅读时长" },
        { tostring(notes) .. " 条", "笔记" },
    }
    local cw = math.floor(W / 3)
    for i, c in ipairs(cols) do
        local big = U.text(c[1], U.px(44), true)
        local sm = U.text(c[2], U.px(24)); sm.fgcolor = LABEL_GRAY
        local cx = (i - 1) * cw
        place(g, CenterContainer:new{ dimen = Geom:new{ w = cw, h = U.px(70) }, big }, cx, y)
        place(g, CenterContainer:new{ dimen = Geom:new{ w = cw, h = U.px(50) }, sm }, cx, y + U.px(70))
        if i < 3 then place(g, U.vline(U.px(80), 1), cx + cw, y + U.px(20)) end
    end
    y = y + m.stats_h
    -- chapter progress slider with ‹ ›
    local chev = U.px(64)
    local track_x = m.margin + chev + U.px(12)
    local track_w = W - 2 * (m.margin + chev + U.px(12))
    local track_h = U.px(8)
    local ty = y + math.floor((m.slider_h - track_h) / 2)
    local left = U.text("‹", U.px(48), true)
    local right = U.text("›", U.px(48), true)
    place(g, CenterContainer:new{ dimen = Geom:new{ w = chev, h = m.slider_h }, left }, m.margin, y)
    place(g, CenterContainer:new{ dimen = Geom:new{ w = chev, h = m.slider_h }, right }, W - m.margin - chev, y)
    self:_hit(rect(m.margin, y, chev, m.slider_h), function() self:prevChapter() end)
    self:_hit(rect(W - m.margin - chev, y, chev, m.slider_h), function() self:nextChapter() end)
    place(g, FrameContainer:new{ bordersize = 0, background = Blitbuffer.Color8(0xCC),
        radius = 4, padding = 0, margin = 0, width = track_w, height = track_h, U.hspan(0) }, track_x, ty)
    local frac = self:_progressFrac()
    local fill = math.max(U.px(8), math.floor(track_w * frac))
    place(g, FrameContainer:new{ bordersize = 0, background = U.BLACK,
        radius = 4, padding = 0, margin = 0, width = fill, height = track_h, U.hspan(0) }, track_x, ty)
    local kd = U.px(36)
    place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = U.WHITE,
        radius = math.floor(kd / 2), padding = 0, margin = 0, width = kd, height = kd, U.hspan(0) },
        track_x + fill - math.floor(kd / 2), y + math.floor((m.slider_h - kd) / 2))
    self:_hit(rect(track_x, y, track_w, m.slider_h), function(pos)
        local f = math.max(0, math.min(1, (pos.x - track_x) / track_w))
        self:gotoFrac(f)
    end)
    y = y + m.slider_h
    -- two pill buttons
    local pw = math.floor((W - 2 * m.margin - U.px(24)) / 2)
    local ph = U.px(80)
    local py = y + math.floor((m.pills_h - ph) / 2)
    local function pill(text, x, fn)
        local t = U.text(text, U.px(30))
        place(g, FrameContainer:new{ bordersize = 0, background = PILL_BG, radius = math.floor(ph / 2),
            padding = 0, margin = 0, CenterContainer:new{ dimen = Geom:new{ w = pw, h = ph }, t } }, x, py)
        self:_hit(rect(x, py, pw, ph), fn)
    end
    pill("阅读明细", m.margin, function() self:openReadingDetail() end)
    local auto_on = false
    pcall(function()
        local G = rawget(_G, "G_reader_settings")
        auto_on = G and G:isTrue("autoturn_enabled")
    end)
    pill(auto_on and "关闭自动翻页" or "开启自动翻页", m.margin + pw + U.px(24), function() self:toggleAutoTurn() end)
    y = y + m.pills_h
    -- icon bar: ☰  compass  center-dot  sun  A
    local icons = {
        { draw = "toc",     fn = function() self:showTocSheet() end },
        { draw = "compass", fn = function() self:showBookmarks() end }, -- closest: 书签/跳转
        { draw = "dot",     fn = function() self:showProgress() end },  -- official center control = progress/jump
        { draw = "sun",     fn = function() self:showBrightnessPanel() end },
        { draw = "A",       fn = function() self:toggleFont() end },
    }
    for i, b in ipairs(icons) do
        local x, sw = Logic.slot(W, #icons, i)
        self:_drawIcon(g, b.draw, x, y, sw, m.icon_h)
        self:_hit(rect(x, y, sw, m.icon_h), b.fn)
    end
end

function RM:_drawIcon(g, kind, x, y, sw, h)
    if kind == "toc" then
        local t = U.text("☰", U.px(44))
        place(g, CenterContainer:new{ dimen = Geom:new{ w = sw, h = h }, t }, x, y)
    elseif kind == "compass" then
        -- compass: circle + diagonal needle (e-ink)
        local d = U.px(52)
        local cx = x + math.floor((sw - d) / 2)
        local cy = y + math.floor((h - d) / 2)
        place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = U.WHITE,
            radius = math.floor(d / 2), padding = 0, margin = 0, width = d, height = d, U.hspan(0) }, cx, cy)
        place(g, U.hline(math.floor(d * 0.55), 2), cx + math.floor(d * 0.22), cy + math.floor(d / 2) - 1)
        place(g, U.vline(math.floor(d * 0.55), 2), cx + math.floor(d / 2) - 1, cy + math.floor(d * 0.22))
    elseif kind == "dot" then
        -- official: filled center dot on a short horizontal line
        local line_w = U.px(56)
        local line_h = U.px(4)
        local d = U.px(28)
        local lx = x + math.floor((sw - line_w) / 2)
        local ly = y + math.floor(h / 2) - math.floor(line_h / 2)
        place(g, FrameContainer:new{ bordersize = 0, background = Blitbuffer.Color8(0xBB),
            radius = 2, padding = 0, margin = 0, width = line_w, height = line_h, U.hspan(0) }, lx, ly)
        place(g, FrameContainer:new{ bordersize = 0, background = U.BLACK,
            radius = math.floor(d / 2), padding = 0, margin = 0, width = d, height = d, U.hspan(0) },
            x + math.floor((sw - d) / 2), y + math.floor((h - d) / 2))
    elseif kind == "sun" then
        local t = U.text("☀", U.px(40))
        place(g, CenterContainer:new{ dimen = Geom:new{ w = sw, h = h }, t }, x, y)
    elseif kind == "A" then
        -- 0.4.2 layout: rm_font / rm_font_active SVG icons (do not restyle)
        local name = self.font_open and "rm_font_active" or "rm_font"
        place(g, CenterContainer:new{ dimen = Geom:new{ w = sw, h = h },
            U.icon(name, self.m.icon) }, x, y)
    end
end

-- 0.4.2-style thin icon strip under the font panel (not the tall official panel).
function RM:_fontIconBar(g)
    local m, W, H = self.m, self.W, self.H
    local y = H - m.bar_h
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = W, height = m.bar_h, U.hspan(0) }, 0, y)
    place(g, U.hline(W, 1), 0, y)
    local icons = {
        { draw = "toc",     fn = function() self:showTocSheet() end },
        { draw = "compass", fn = function() self:showBookmarks() end },
        { draw = "dot",     fn = function() self:showProgress() end },
        { draw = "sun",     fn = function() self:showBrightnessPanel() end },
        { draw = "A",       fn = function() self:toggleFont() end },
    }
    for i, b in ipairs(icons) do
        local x, sw = Logic.slot(W, #icons, i)
        self:_drawIcon(g, b.draw, x, y, sw, m.bar_h)
        self:_hit(rect(x, y, sw, m.bar_h), b.fn)
    end
end

-- font panel ---------------------------------------------------------------------
function RM:_slider(g, s, value, x0, y, w)
    local m = self.m
    local steps = s.steps
    local idx = Logic.nearest_index(steps, value)
    local cy = y + math.floor((m.row_h - m.circle) / 2)
    -- − and + circles (1.5px border -> 2px)
    local function circle(sym, cx)
        place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = U.WHITE,
            radius = math.floor(m.circle / 2), padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = m.circle - 4, h = m.circle - 4 }, U.text(sym, U.px(40), true) } },
            cx, cy)
    end
    circle("−", x0)
    circle("+", x0 + w - m.circle)
    local tx = x0 + m.circle + U.px(16)
    local tw = w - 2 * (m.circle + U.px(16))
    local ty = y + math.floor((m.row_h - m.track_h) / 2)
    local r = math.floor(m.track_h / 2)
    place(g, FrameContainer:new{ bordersize = 0, background = U.GRAY, radius = r, padding = 0, margin = 0,
        width = tw, height = m.track_h, U.hspan(0) }, tx, ty)
    local kx = Logic.knob_x(steps, idx, tw, m.track_h)
    place(g, FrameContainer:new{ bordersize = 0, background = U.BLACK, radius = r, padding = 0, margin = 0,
        width = kx + r, height = m.track_h, U.hspan(0) }, tx, ty)
    for i = 2, idx do -- ticks on the filled part
        local lx = Logic.knob_x(steps, i, tw, m.track_h) - math.floor((Logic.knob_x(steps, 2, tw, m.track_h) - Logic.knob_x(steps, 1, tw, m.track_h)) / 2)
        if lx > r and lx < kx - r then
            place(g, U.hline(1, math.floor(m.track_h * 0.6), U.WHITE), tx + lx, ty + math.floor(m.track_h * 0.2))
        end
    end
    -- end labels: lo on black (white text impossible with TextWidget fgcolor? use white)
    local lo = U.text(s.lo, m.label_px, true); lo.fgcolor = U.WHITE
    place(g, lo, tx + U.px(20), ty + math.floor((m.track_h - lo:getSize().h) / 2))
    local hi = U.text(s.hi, m.label_px, true)
    place(g, hi, tx + tw - U.px(20) - hi:getSize().w, ty + math.floor((m.track_h - hi:getSize().h) / 2))
    -- knob
    local kd = m.track_h - U.px(6)
    place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = U.WHITE,
        radius = math.floor(kd / 2), padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = kd - 4, h = kd - 4 },
            U.text(Logic.step_label(s, idx), U.px(24), true, kd - 6) } },
        tx + kx - math.floor(kd / 2), ty + U.px(3))
    -- hit areas: full row height (>=120)
    self:_hit(rect(x0 - U.px(25), y, m.circle + U.px(40), m.row_h), function() self:setStep(s, idx - 1) end)
    self:_hit(rect(x0 + w - m.circle - U.px(15), y, m.circle + U.px(40), m.row_h), function() self:setStep(s, idx + 1) end)
    self:_hit(rect(tx, y, tw, m.row_h), function(pos) self:setStep(s, Logic.index_from_x(steps, pos.x - tx, tw, m.track_h)) end)
end

function RM:_fontPanel(g)
    local m, W, H = self.m, self.W, self.H
    local faces, cur_i = self:_faces()
    local font_rows = math.ceil(#faces / 5)
    local panel_h = m.panel_title_h + #Logic.SLIDERS * m.row_h + font_rows * m.font_pitch + U.px(20)
    local y0 = H - m.bar_h - panel_h
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = W, height = panel_h, U.hspan(0) }, 0, y0)
    place(g, U.hline(W, 1), 0, y0)
    self.panel_rect = rect(0, y0, W, panel_h)
    -- title + 首行缩进 capsule
    local t = U.text("字体设置", m.panel_title_px, true)
    place(g, t, m.margin, y0 + math.floor((m.panel_title_h - t:getSize().h) / 2))
    local indent_on = false
    pcall(function() indent_on = self.ui.styletweak:isTweakEnabled("paragraph_indent") and true or false end)
    local cap_txt = U.text(Logic.indent_label(indent_on), U.px(30), true)
    local cw, ch = cap_txt:getSize().w + U.px(40), U.px(64)
    if indent_on then cap_txt.fgcolor = U.WHITE end
    place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = indent_on and U.BLACK or U.WHITE,
        radius = math.floor(ch / 2), padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch - 4 }, cap_txt } },
        W - m.margin - cw, y0 + math.floor((m.panel_title_h - ch) / 2))
    self:_hit(rect(W - m.margin - cw - U.px(20), y0, cw + U.px(40), m.panel_title_h), function() self:toggleIndent() end)
    -- sliders
    local values = Logic.read_values(self.ui.document.configurable)
    local y = y0 + m.panel_title_h
    for _, s in ipairs(Logic.SLIDERS) do
        self:_slider(g, s, values[s.id], m.margin, y, W - 2 * m.margin)
        y = y + m.row_h
    end
    -- 5-column font buttons (gray, radius 12; selected black w/ white text)
    local gap = U.px(18)
    local bw = math.floor((W - 2 * m.margin - 4 * gap) / 5)
    for i, face in ipairs(faces) do
        local r, c = math.floor((i - 1) / 5), (i - 1) % 5
        local x = m.margin + c * (bw + gap)
        local by = y + r * m.font_pitch + math.floor((m.font_pitch - m.font_btn_h) / 2)
        local sel = i == cur_i
        local lbl = U.text(Logic.font_label(face), U.px(28), sel, bw - U.px(12))
        if sel then lbl.fgcolor = U.WHITE end
        place(g, FrameContainer:new{ bordersize = 0, background = sel and U.BLACK or U.GRAY, radius = U.px(12),
            padding = 0, margin = 0, CenterContainer:new{ dimen = Geom:new{ w = bw, h = m.font_btn_h }, lbl } }, x, by)
        self:_hit(rect(x, y + r * m.font_pitch, bw, m.font_pitch), function() self:setFont(face) end)
    end
end

function RM:_faces()
    if not self._face_cache then
        local faces = {}
        pcall(function()
            local cre = require("document/credocument"):engineInit() -- as readerfont.lua does
            faces = cre.getFontFaces() or {}
        end)
        self._face_cache = faces
    end
    -- current face: ReaderFont.font_face (readerfont.lua, set by onSetFont)
    local current = self.ui and self.ui.font and self.ui.font.font_face
    return Logic.font_list(self._face_cache, current, 15)
end

function RM:_hit(r, fn) self.hits[#self.hits + 1] = { r = r, fn = fn } end

-- 阅读设置 bottom sheet (UI-LAYOUT-0.3.5 §2) --------------------------------
-- Page-turn modes map onto KOReader's own switches (ui/elements/page_turns.lua,
-- read at gesture time by readerrolling.lua:371,555 / readerpaging.lua):
--   点击 = taps + swipes (KOReader default), 滑动 = swipes only, 按键 = keys only.
RM.TURN_MODES = {
    { id = "tap",   label = "点击", tap = true,  swipe = true },
    { id = "swipe", label = "滑动", tap = false, swipe = true },
    { id = "key",   label = "按键", tap = false, swipe = false, needs_keys = true },
}
function RM.turnModes()
    local out = {}
    for _, t in ipairs(RM.TURN_MODES) do
        if not t.needs_keys or (Device.hasKeys and Device:hasKeys()) then out[#out + 1] = t end
    end
    return out
end
function RM.currentTurnMode()
    local G = rawget(_G, "G_reader_settings")
    local tap = not (G and G:isTrue("page_turns_disable_tap"))
    local swipe = not (G and G:isTrue("page_turns_disable_swipe"))
    if tap then return "tap" elseif swipe then return "swipe" else return "key" end
end
function RM:setTurnMode(id)
    local G = rawget(_G, "G_reader_settings")
    for _, t in ipairs(RM.TURN_MODES) do
        if t.id == id and G then
            G:saveSetting("page_turns_disable_tap", not t.tap)
            G:saveSetting("page_turns_disable_swipe", not t.swipe)
        end
    end
    self:refresh("ui")
end

local function powerd() return Device.getPowerDevice and Device:getPowerDevice() end
function RM:lightValues()
    local p = powerd()
    local v = { has_fl = Device.hasFrontlight and Device:hasFrontlight() or false,
        has_warm = Device.hasNaturalLight and Device:hasNaturalLight() or false }
    if p then
        pcall(function()
            v.min, v.max = p.fl_min or 0, p.fl_max or 100
            v.fl = p:frontlightIntensity()
            if v.has_warm then v.wmin, v.wmax, v.warm = p.fl_warmth_min or 0, p.fl_warmth_max or 100, p:frontlightWarmth() end
        end)
    end
    return v
end
function RM:setLight(kind, frac)
    local p, v = powerd(), self:lightValues()
    if not p then return end
    frac = math.max(0, math.min(1, frac))
    pcall(function()
        if kind == "fl" and v.has_fl then p:setIntensity(math.floor(v.min + frac * (v.max - v.min) + 0.5))
        elseif kind == "warm" and v.has_warm then p:setWarmth(math.floor(v.wmin + frac * (v.wmax - v.wmin) + 0.5)) end
    end)
    self:refresh("ui")
end
function RM:fontSize()
    local c = self.ui and self.ui.document and self.ui.document.configurable
    return c and tonumber(c.font_size) or nil
end
function RM:bumpFont(d)
    local f = self:fontSize()
    if not f then return end
    send_event(self.ui, "SetFontSize", math.max(12, math.min(72, f + d)))
    self:refresh("ui")
end

function RM:_sheet(g)
    local W, H = self.W, self.H
    local pad, gap = U.px(64), U.px(24)
    -- rows: pad-top 40 + title 96 + 字号 160 + 光 2×130 + 翻页 160 + 更多 112 + 4 gaps + 24 bottom
    local sheet_h = U.px(40 + 96 + 160 + 260 + 160 + 112 + 4 * 24 + 24)
    local y0 = H - sheet_h
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = W, height = sheet_h, U.hspan(0) }, 0, y0)
    place(g, U.hline(W, 2), 0, y0)
    self.panel_rect = rect(0, y0, W, sheet_h)
    local function label(t, x, y, h)
        local w = U.text(t, U.px(34)); w.fgcolor = LABEL_GRAY
        place(g, w, x, y + math.floor((h - w:getSize().h) / 2)); return w
    end
    local function button(t, x, y, w, h, selected, fn, px)
        local txt = U.text(t, px or U.px(36), selected)
        if selected then txt.fgcolor = U.WHITE end
        place(g, FrameContainer:new{ bordersize = 2, color = U.BLACK, background = selected and U.BLACK or U.WHITE,
            radius = U.px(12), padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = w - 4, h = h - 4 }, txt } }, x, y)
        if fn then self:_hit(rect(x, y, w, h), fn) end
    end
    local y = y0 + U.px(40)
    -- title + 完成
    local th = U.px(96)
    local t = U.text("阅读设置", U.px(40), true)
    place(g, t, pad, y + math.floor((th - t:getSize().h) / 2))
    local done = U.text("完成", U.px(36))
    place(g, done, W - pad - done:getSize().w, y + math.floor((th - done:getSize().h) / 2))
    self:_hit(rect(W - pad - U.px(128), y, U.px(128) + pad, th), function() self:closeSheet() end)
    y = y + th + gap
    -- 字号
    local rh = U.px(160)
    label("字号", pad, y, rh)
    local bw, bh = U.px(120), U.px(96)
    local by = y + math.floor((rh - bh) / 2)
    local num_w = U.px(140)
    local x_plus = W - pad - bw
    local x_num = x_plus - num_w
    local x_minus = x_num - bw
    local f = self:fontSize()
    button("A−", x_minus, by, bw, bh, false, function() self:bumpFont(-1) end)
    local nt = U.text(f and tostring(math.floor(f + 0.5)) or "—", U.px(44), true)
    place(g, nt, x_num + math.floor((num_w - nt:getSize().w) / 2), by + math.floor((bh - nt:getSize().h) / 2))
    button("A+", x_plus, by, bw, bh, false, function() self:bumpFont(1) end)
    y = y + rh + gap
    -- 亮度 / 暖光
    local lv = self:lightValues()
    local function lightrow(name, kind, enabled, frac, value_txt)
        local h = U.px(130)
        label(name, pad, y, h)
        local tx, tw = pad + U.px(150), W - 2 * pad - U.px(150) - U.px(110)
        local ty = y + math.floor((h - U.px(8)) / 2)
        place(g, FrameContainer:new{ bordersize = 0, background = U.GRAY, padding = 0, margin = 0,
            width = tw, height = U.px(8), U.hspan(0) }, tx, ty)
        if enabled then
            local fx = math.floor(tw * (frac or 0))
            if fx > 0 then
                place(g, FrameContainer:new{ bordersize = 0, background = U.BLACK, padding = 0, margin = 0,
                    width = fx, height = U.px(8), U.hspan(0) }, tx, ty)
            end
            local kd = U.px(48)
            place(g, FrameContainer:new{ bordersize = 0, background = U.BLACK, radius = math.floor(kd / 2),
                padding = 0, margin = 0, width = kd, height = kd, U.hspan(0) },
                tx + fx - math.floor(kd / 2), y + math.floor((h - kd) / 2))
            self:_hit(rect(tx - U.px(30), y, tw + U.px(60), h), function(pos) self:setLight(kind, (pos.x - tx) / tw) end)
        end
        local vt = U.text(value_txt, U.px(32)); if not enabled then vt.fgcolor = LABEL_GRAY end
        place(g, vt, W - pad - vt:getSize().w, y + math.floor((h - vt:getSize().h) / 2))
        y = y + h
    end
    local function frac(v, lo, hi) if not v or not lo or not hi or hi <= lo then return 0 end return (v - lo) / (hi - lo) end
    lightrow("亮度", "fl", lv.has_fl and lv.fl ~= nil, frac(lv.fl, lv.min, lv.max), lv.has_fl and tostring(lv.fl or "—") or "无")
    lightrow("暖光", "warm", lv.has_warm and lv.warm ~= nil, frac(lv.warm, lv.wmin, lv.wmax),
        lv.has_warm and tostring(lv.warm or "—") or "不支持")
    y = y + gap
    -- 翻页方式
    label("翻页方式", pad, y, rh)
    local modes = RM.turnModes()
    local seg_w = math.max(U.px(240), math.floor((W - 2 * pad - U.px(200)) / #modes))
    local sx = W - pad - seg_w * #modes
    local cur = RM.currentTurnMode()
    for i, md in ipairs(modes) do
        button(md.label, sx + (i - 1) * seg_w, y + math.floor((rh - bh) / 2), seg_w, bh,
            md.id == cur, function() self:setTurnMode(md.id) end)
    end
    y = y + rh + gap
    -- 更多设置 ›
    local mh = U.px(112)
    local mt = U.text("更多设置", U.px(34))
    place(g, mt, pad, y + math.floor((mh - mt:getSize().h) / 2))
    local ar = U.text("›", U.px(34)); ar.fgcolor = LABEL_GRAY
    place(g, ar, W - pad - ar:getSize().w, y + math.floor((mh - ar:getSize().h) / 2))
    self:_hit(rect(0, y, W, mh), function() self:showMoreReading() end)
end

function RM:openSheet() self.sheet_open = true; self.font_open = false; self:refresh("ui") end
function RM:closeSheet() self.sheet_open = false; self:refresh("ui") end

-- 「更多设置」 inside a book: everything that is not 字号 / 光 / 翻页.
function RM:showMoreReading()
    local dlg
    local function item(text, fn) return { { text = text, align = "left", callback = function() UIManager:close(dlg); fn() end } } end
    dlg = ButtonDialog:new{
        title = "更多设置",
        buttons = {
            item("字体、粗细、行距、边距、缩进", function()
                if self:isRolling() then self.sheet_open = false; self.font_open = true; self:refresh("ui")
                else self:close(); send_event(self.ui, "ShowConfigMenu") end end),
            item("目录", function() self:showToc() end),
            item("书签与笔记", function() self:close(); send_event(self.ui, "ShowBookmark") end),
            item("进度跳转", function() self:showProgress() end),
            item("搜索全书", function() self:close(); send_event(self.ui, "ShowFulltextSearchInput") end),
            item("KOReader 阅读设置（刷新频率、旋转等）", function() self:close(); send_event(self.ui, "ShowMenu") end),
            { { text = "关闭", callback = function() UIManager:close(dlg) end } },
        },
    }
    UIManager:show(dlg)
end

function RM:_build()
    if self[1] then self[1]:free() end
    self.hits = {}
    self.panel_rect = nil
    self.toc_rect = nil
    local g = OverlapGroup:new{ dimen = Geom:new{ w = self.W, h = self.H } }
    if self.toc_open then
        self:_tocSheet(g)
    elseif self.sheet_open then
        self:_sheet(g)
    elseif self.font_open then
        -- 0.4.2: font panel above a thin icon bar (A = rm_font_active)
        self:_fontPanel(g)
        self:_fontIconBar(g)
    else
        self:_topBar(g)
        self:_bottomBar(g)
    end
    self[1] = g
end

function RM:refresh(mode)
    self:_build()
    UIManager:setDirty(self, mode or "ui")
end

function RM:onTap(_, ges)
    local p = ges and ges.pos
    if not p then return true end
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if U.inside(h.r, p.x, p.y) then h.fn(p); return true end
    end
    if self.toc_open then
        if not (self.toc_rect and U.inside(self.toc_rect, p.x, p.y)) then
            self.toc_open = false; self:close(); return true -- tap outside dismisses TOC
        end
        return true
    end
    if self.sheet_open and self.panel_rect and not U.inside(self.panel_rect, p.x, p.y) then
        self:close(); return true
    end
    if self.font_open and self.panel_rect and not U.inside(self.panel_rect, p.x, p.y) then
        self.font_open = false
        self:refresh("full") -- 0.4.2 font panel dismiss
        return true
    end
    -- tapping the uncovered page dismisses the reading menu (partial)
    self:close(); return true
end

function RM:close()
    -- font panel (0.4.2) full; everything else partial (0.4.3 snappy dismiss)
    UIManager:close(self, self.font_open and "full" or "ui")
end
function RM:onClose() self:close(); return true end
function RM:onCloseWidget() if self[1] then self[1]:free() end end

-- actions -------------------------------------------------------------------------
local function send(ui, name, ...) if ui then ui:handleEvent(Event:new(name, ...)) end end

function RM:back()
    self:close()
    if self.on_back then self.on_back() end
end
function RM:showToc() self:showTocSheet() end
function RM:showProgress() self:close(); send(self.ui, "ShowSkimtoDialog") end
function RM:showBrightness() self:showBrightnessPanel() end
function RM:showBrightnessPanel()
    -- Prefer in-menu brightness sheet when device has frontlight; else KOReader dialog.
    if Device:hasFrontlight() then
        self.sheet_open = true; self.font_open = false; self.toc_open = false
        self:refresh("ui"); return
    end
    self:close()
    UIManager:broadcastEvent(Event:new("ShowFlDialog"))
end
function RM:toggleFont()
    -- 0.4.2: 「A」 opens/closes 字体设置 with a full refresh
    if not self:isRolling() then
        self:close(); send(self.ui, "ShowConfigMenu"); return
    end
    self.font_open = not self.font_open
    self.sheet_open = false; self.toc_open = false
    self:refresh("full")
end

function RM:prevChapter()
    local toc = self.ui and self.ui.toc
    if not toc then return end
    local cur = self.ui:getCurrentPage()
    local prev
    pcall(function() prev = toc:getPreviousChapter(cur) end)
    if prev then send(self.ui, "GotoPage", prev); self:refresh("ui") end
end
function RM:nextChapter()
    local toc = self.ui and self.ui.toc
    if not toc then return end
    local cur = self.ui:getCurrentPage()
    local nxt
    pcall(function() nxt = toc:getNextChapter(cur) end)
    if nxt then send(self.ui, "GotoPage", nxt); self:refresh("ui") end
end
function RM:gotoFrac(f)
    local doc = self.ui and self.ui.document
    if not doc then return end
    local total = 1
    pcall(function() total = doc:getPageCount() or 1 end)
    local page = math.max(1, math.min(total, math.floor(f * (total - 1) + 1.5)))
    send(self.ui, "GotoPage", page)
    self:refresh("ui")
end

function RM:openReadingDetail()
    self:close()
    -- Prefer weread reading stats for this book; else KOReader statistics
    local w = self.weread
    if w and type(w.showReadStats) == "function" then pcall(w.showReadStats, w); return end
    send(self.ui, "ShowBookStat")
end

function RM:toggleAutoTurn()
    local G = rawget(_G, "G_reader_settings")
    local at = self.ui and self.ui.autoturn
    if at and type(at.onMenuHold) == "function" then
        -- open autoturn's own config (seconds picker)
        self:close(); pcall(function()
            -- flip via settings + restart schedule
            local on = G and G:isTrue("autoturn_enabled")
            if on then
                G:makeFalse("autoturn_enabled"); at.enabled = false
                if at._unschedule then at:_unschedule() end
            else
                if not G:readSetting("autoturn_timeout_seconds") then
                    G:saveSetting("autoturn_timeout_seconds", 30)
                end
                at.autoturn_sec = G:readSetting("autoturn_timeout_seconds", 30)
                G:makeTrue("autoturn_enabled"); at.enabled = true
                if at._start then at:_start() end
            end
        end)
        self:refresh("ui"); return
    end
    if G then
        if G:isTrue("autoturn_enabled") then G:makeFalse("autoturn_enabled")
        else
            if not G:readSetting("autoturn_timeout_seconds") then G:saveSetting("autoturn_timeout_seconds", 30) end
            G:makeTrue("autoturn_enabled")
        end
    end
    self:refresh("ui")
end

function RM:showBookmarks()
    self:close(); send(self.ui, "ShowBookmark")
end

-- Half-screen TOC sheet (0.4.3): covers ~55% of the page; tap outside dismisses.
function RM:showTocSheet()
    self.toc_open = true; self.font_open = false; self.sheet_open = false
    self:refresh("ui")
end

function RM:_tocSheet(g)
    local m, W, H = self.m, self.W, self.H
    local sheet_h = math.floor(H * 0.55)
    local y0 = H - sheet_h
    self.toc_rect = rect(0, y0, W, sheet_h)
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = PANEL_BG,
        radius = m.panel_r, width = W, height = sheet_h, U.hspan(0) }, 0, y0)
    local title = U.text("目录", U.px(40), true)
    place(g, title, m.margin, y0 + U.px(28))
    local close = U.text("关闭", U.px(30)); close.fgcolor = LABEL_GRAY
    place(g, close, W - m.margin - close:getSize().w, y0 + U.px(32))
    self:_hit(rect(W - m.margin - U.px(120), y0, U.px(120) + m.margin, U.px(80)), function()
        self.toc_open = false; self:close()
    end)
    -- chapters
    local toc, cur = {}, 1
    pcall(function() toc = self.ui.toc.toc or self.ui.document:getToc() or {} end)
    pcall(function() cur = self.ui:getCurrentPage() end)
    local row_h = U.px(88)
    local y = y0 + U.px(100)
    local max_rows = math.floor((sheet_h - U.px(120)) / row_h)
    -- start near current chapter
    local start = 1
    for i, ch in ipairs(toc) do
        if ch.page and ch.page <= cur then start = i end
    end
    start = math.max(1, math.min(start - 2, #toc - max_rows + 1))
    if start < 1 then start = 1 end
    local shown = 0
    for i = start, #toc do
        if shown >= max_rows then break end
        local ch = toc[i]
        local label = (ch.title or ("第 " .. i .. " 章"))
        local active = ch.page and cur >= ch.page and (not toc[i + 1] or cur < (toc[i + 1].page or 1e9))
        local t = U.text(label, U.px(30), active, W - 2 * m.margin - U.px(80))
        if not active then t.fgcolor = LABEL_GRAY end
        place(g, t, m.margin, y + math.floor((row_h - t:getSize().h) / 2))
        local pg = U.text(tostring(ch.page or ""), U.px(26)); pg.fgcolor = LABEL_GRAY
        place(g, pg, W - m.margin - pg:getSize().w, y + math.floor((row_h - pg:getSize().h) / 2))
        place(g, U.hline(W - 2 * m.margin, 1), m.margin, y + row_h - 1)
        local page = ch.page
        self:_hit(rect(0, y, W, row_h), function()
            self.toc_open = false; self:close()
            if page then send(self.ui, "GotoPage", page) end
        end)
        y = y + row_h; shown = shown + 1
    end
    if #toc == 0 then
        local empty = U.text("本书没有目录", U.px(30)); empty.fgcolor = LABEL_GRAY
        place(g, empty, m.margin, y0 + U.px(160))
    end
end

-- 想法: download + match via weread's annotation sync (existing APIs).
function RM:syncThoughts()
    self:close()
    local w = self.weread
    if not w then
        UIManager:show(require("ui/widget/infomessage"):new{ text = "微信读书模块未加载。", timeout = 2 }); return
    end
    -- weread's unified annotation sync: download underlines/thoughts and match to chapters
    if type(w.startUnifiedAnnotationSync) == "function" then
        local ok, e = pcall(w.startUnifiedAnnotationSync, w, {})
        if not ok then
            logger.warn("realweidu: thoughts sync", e)
            UIManager:show(require("ui/widget/infomessage"):new{ text = "划线/想法同步失败：" .. tostring(e), timeout = 3 })
        end
        return
    end
    if type(w.chooseAnnotationChapters) == "function" then
        pcall(w.chooseAnnotationChapters, w); return
    end
    UIManager:show(require("ui/widget/infomessage"):new{
        text = "划线/想法同步入口不可用。可在 ☰ Real微读 → 微信读书功能 里操作。", timeout = 3 })
end
function RM:toggleBookmark()
    send(self.ui, "ToggleBookmark")
    self:refresh("ui")
end
function RM:toggleIndent()
    pcall(function() self.ui.styletweak:onToggleStyleTweak("paragraph_indent", nil, true) end)
    self:refresh("ui")
end
function RM:setStep(s, i)
    i = Logic.clamp_index(s.steps, i)
    local v = s.steps[i]
    local conf = self.ui.document.configurable
    if s.id == "margin" then
        conf.h_page_margins = { v, v } -- persisted by ReaderConfig with the other configurables
    end
    local ok, e = pcall(send, self.ui, s.event, Logic.event_arg(s, v))
    if not ok then logger.warn("realweidu: font panel", s.event, e) end
    self:refresh("ui")
end
function RM:setFont(face)
    send(self.ui, "SetFont", face)
    self:refresh("ui")
end

function RM:showMore()
    local dlg
    local marked = false
    pcall(function() marked = self.ui.bookmark:isPageBookmarked() end)
    local function item(text, fn) return { { text = text, callback = function() UIManager:close(dlg); fn() end } } end
    local weread = self.weread
    dlg = ButtonDialog:new{
        title = "更多",
        buttons = {
            item(marked and "删除书签" or "添加书签", function() self:toggleBookmark() end),
            item("书签列表", function() self:close(); send(self.ui, "ShowBookmark") end),
            item("下载并匹配划线/想法", function() self:syncThoughts() end),
            item("搜索全书", function() self:close(); send(self.ui, "ShowFulltextSearchInput") end),
            item("书籍详情", function()
                self:close()
                -- weread/ui/library.lua:1768 for WeRead books; KOReader book info otherwise
                if weread and type(weread.showCurrentBookDetails) == "function"
                        and pcall(weread.showCurrentBookDetails, weread) then return end
                send(self.ui, "ShowBookInfo")
            end),
            item("刷新屏幕", function() self:close(); UIManager:setDirty(nil, "full") end),
            item("KOReader 原生菜单", function() self:close(); send(self.ui, "ShowMenu") end),
        },
    }
    UIManager:show(dlg)
end

return RM
