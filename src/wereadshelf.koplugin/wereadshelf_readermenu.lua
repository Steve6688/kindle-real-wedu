-- wereadshelf_readermenu.lua — WeRead-style reading menu (top bar + 5-icon
-- bottom bar) and the 字体设置 panel, shown over KOReader's ReaderUI.
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

local U     = require("wereadshelf_ui")
local Logic = require("wereadshelf_logic")

local RM = InputContainer:extend{
    name = "wereadshelf_readermenu",
    ui = nil,              -- ReaderUI
    on_back = nil,         -- function() back to shelf
    weread = nil,          -- weread plugin instance (optional)
    font_open = false,
}

local function place(group, w, x, y) w.overlap_offset = { x, y }; group[#group + 1] = w; return w end
local function rect(x, y, w, h) return Geom:new{ x = x, y = y, w = w, h = h } end

function RM:init()
    self.W, self.H = Screen:getWidth(), Screen:getHeight()
    self.dimen = rect(0, 0, self.W, self.H)
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    if Device:hasKeys() then self.key_events = { Close = { { "Back" } } } end
    self.m = {
        bar_h = math.max(U.px(130), 120), margin = U.px(45),
        icon = U.px(64), title_px = U.px(32),
        row_h = math.max(U.px(120), 120), circle = U.px(70), track_h = U.px(70),
        panel_title_h = math.max(U.px(110), 110), font_btn_h = U.px(85), font_pitch = math.max(U.px(120), 120),
        label_px = U.px(26), panel_title_px = U.px(36),
    }
    self:_build()
end

function RM:isRolling() return self.ui and self.ui.rolling ~= nil and self.ui.document and self.ui.document.configurable ~= nil end

-- top bar ---------------------------------------------------------------------
function RM:_topBar(g)
    local m, W = self.m, self.W
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = W, height = m.bar_h, U.hspan(0) }, 0, 0)
    place(g, U.hline(W, 1), 0, m.bar_h - 1)
    local chapter
    pcall(function() chapter = self.ui.toc:getTocTitleOfCurrentPage() end)
    local book = self.ui.doc_props and self.ui.doc_props.display_title or ""
    local title = Logic.reader_title(chapter, book)
    local right_w = 2 * m.bar_h
    local back = HorizontalGroup:new{ align = "center",
        U.icon("back_chevron", math.floor(m.icon * 0.6)), U.hspan(U.px(12)),
        U.text(title, m.title_px, false, W - 2 * m.margin - right_w - m.icon) }
    place(g, LeftContainer:new{ dimen = Geom:new{ w = W - right_w, h = m.bar_h },
        HorizontalGroup:new{ U.hspan(m.margin), back } }, 0, 0)
    local marked = false
    pcall(function() marked = self.ui.bookmark:isPageBookmarked() end)
    local bx = W - right_w
    place(g, CenterContainer:new{ dimen = Geom:new{ w = m.bar_h, h = m.bar_h },
        U.icon(marked and "bookmark_active" or "bookmark", m.icon) }, bx, 0)
    place(g, CenterContainer:new{ dimen = Geom:new{ w = m.bar_h, h = m.bar_h }, U.icon("more", m.icon) }, bx + m.bar_h, 0)
    self:_hit(rect(0, 0, bx, m.bar_h), function() self:back() end)
    self:_hit(rect(bx, 0, m.bar_h, m.bar_h), function() self:toggleBookmark() end)
    self:_hit(rect(bx + m.bar_h, 0, m.bar_h, m.bar_h), function() self:showMore() end)
end

-- bottom bar --------------------------------------------------------------------
RM.BOTTOM = {
    { icon = "rm_back",       fn = "back" },
    { icon = "rm_toc",        fn = "showToc" },
    { icon = "tab_discover",  fn = "showProgress" }, -- 指南针 = 进度/跳页 (UI-SPEC, CEO 定)
    { icon = "rm_brightness", fn = "showBrightness" },
    { icon = "rm_font",       fn = "toggleFont" },
}

function RM:_bottomBar(g)
    local m, W, H = self.m, self.W, self.H
    local y = H - m.bar_h
    place(g, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = U.WHITE,
        width = W, height = m.bar_h, U.hspan(0) }, 0, y)
    place(g, U.hline(W, 1), 0, y)
    for i, b in ipairs(RM.BOTTOM) do
        local x, sw = Logic.slot(W, #RM.BOTTOM, i)
        local name = b.icon
        if b.fn == "toggleFont" and self.font_open then name = "rm_font_active" end
        place(g, CenterContainer:new{ dimen = Geom:new{ w = sw, h = m.bar_h }, U.icon(name, m.icon) }, x, y)
        self:_hit(rect(x, y, sw, m.bar_h), function() self[b.fn](self) end)
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

function RM:_build()
    if self[1] then self[1]:free() end
    self.hits = {}
    self.panel_rect = nil
    local g = OverlapGroup:new{ dimen = Geom:new{ w = self.W, h = self.H } }
    -- UI-SPEC/ref 05-font: the font panel is shown without the top bar.
    if not self.font_open then self:_topBar(g) end
    if self.font_open then self:_fontPanel(g) end
    self:_bottomBar(g)
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
    if self.font_open and not U.inside(self.panel_rect, p.x, p.y) then
        self.font_open = false
        self:refresh("full")
        return true
    end
    self:close()
    return true
end

function RM:close()
    UIManager:close(self, "full") -- 刷新规则：关菜单一次全屏刷新
end
function RM:onClose() self:close(); return true end
function RM:onCloseWidget() if self[1] then self[1]:free() end end

-- actions -------------------------------------------------------------------------
local function send(ui, name, ...) if ui then ui:handleEvent(Event:new(name, ...)) end end

function RM:back()
    self:close()
    if self.on_back then self.on_back() end
end
function RM:showToc() self:close(); send(self.ui, "ShowToc") end
function RM:showProgress() self:close(); send(self.ui, "ShowSkimtoDialog") end
function RM:showBrightness()
    self:close()
    if Device:hasFrontlight() then
        UIManager:broadcastEvent(Event:new("ShowFlDialog"))
    else
        UIManager:show(require("ui/widget/infomessage"):new{ text = "此设备没有前光。" })
    end
end
function RM:toggleFont()
    if not self:isRolling() then
        -- PDF/DjVu/CBZ: no reflowable font settings; open KOReader's own bottom config instead
        self:close(); send(self.ui, "ShowConfigMenu"); return
    end
    self.font_open = not self.font_open
    self:refresh("full")
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
    if not ok then logger.warn("wereadshelf: font panel", s.event, e) end
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
