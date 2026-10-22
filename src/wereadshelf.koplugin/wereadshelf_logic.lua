-- wereadshelf_logic.lua — pure helpers (no KOReader deps) for the reader menu,
-- font panel, discover and me pages. Unit-tested in spec/test_logic.lua.
local M = {}

-- Font panel sliders. Values are what KOReader's own events take:
--   SetFontSize(size)        apps/reader/modules/readerfont.lua:203 (clamped 12..255)
--   SetFontBaseWeight(w)     readerfont.lua:221 (creoptions.lua:596-602 uses -1..3)
--   SetLineSpace(percent)    readerfont.lua:212 (clamped 50..200)
--   SetPageHorizMargins{l,r} apps/reader/modules/readertypeset.lua:477
M.SLIDERS = {
    { id = "size",   label = "字号", lo = "小", hi = "大", event = "SetFontSize",
      steps = { 16, 18, 20, 22, 24, 26, 28, 30, 33, 36 } },
    { id = "weight", label = "字重", lo = "细", hi = "粗", event = "SetFontBaseWeight",
      steps = { -1, -0.5, 0, 0.5, 1, 1.5 },
      names = { "-1", "-½", "0", "+½", "+1", "+1½" } },
    { id = "line",   label = "行距", lo = "紧", hi = "松", event = "SetLineSpace",
      steps = { 80, 90, 100, 110, 120, 130, 140, 160 } },
    { id = "margin", label = "边距", lo = "小", hi = "大", event = "SetPageHorizMargins",
      steps = { 5, 10, 15, 20, 30, 40, 55 } },
}

-- Index of the step closest to value (ties -> lower).
function M.nearest_index(steps, value)
    value = tonumber(value)
    if not value then return 1 end
    local best, bd = 1, math.huge
    for i, v in ipairs(steps) do
        local d = math.abs(v - value)
        if d < bd then best, bd = i, d end
    end
    return best
end

function M.clamp_index(steps, i)
    if i < 1 then return 1 end
    if i > #steps then return #steps end
    return i
end

-- Map a tap x (relative to track start) to a step index.
function M.index_from_x(steps, x, track_w, diameter)
    local n = #steps
    if n <= 1 or track_w <= 0 then return 1 end
    diameter = diameter or 0
    local usable = track_w - diameter
    if usable <= 0 then return 1 end
    -- Use the same centres as knob_x; equal-width hit bins drift away
    -- from the visible stops, especially on narrow screens.
    return M.clamp_index(steps,
        math.floor((x - diameter / 2) / usable * (n - 1) + 0.5) + 1)
end

-- Knob centre x for index i on a track of width w with knob diameter d.
function M.knob_x(steps, i, w, d)
    local n = #steps
    if n <= 1 then return math.floor(d / 2) end
    local usable = w - d
    return math.floor(d / 2 + usable * (i - 1) / (n - 1) + 0.5)
end

function M.step_label(slider, i)
    if slider.names then return slider.names[i] end
    if slider.id == "size" then return tostring(slider.steps[i]) end
    return slider.label
end

-- Current value of each slider from a KOReader document configurable
-- (frontend/configurable.lua; keys from ui/data/creoptions.lua).
function M.read_values(conf)
    conf = conf or {}
    local hm = conf.h_page_margins
    return {
        size   = conf.font_size,
        weight = conf.font_base_weight or 0,
        line   = conf.line_spacing,
        margin = type(hm) == "table" and hm[1] or nil,
    }
end

-- Arguments for ui:handleEvent(Event:new(event, arg)).
function M.event_arg(slider, value)
    if slider.id == "margin" then return { value, value } end
    return value
end

-- Font buttons: up to 15 faces that are actually installed (cre.getFontFaces()),
-- preferring CJK faces; UI-SPEC: "没有的字体先隐藏".
M.PREFERRED = { "思源宋体", "Source Han Serif", "Noto Serif CJK", "思源黑体", "Source Han Sans",
    "Noto Sans CJK", "方正", "仓耳", "霞鹜", "LXGW", "汉仪", "兰亭", "楷", "宋", "黑", "圆" }
function M.pick_fonts(faces, max)
    max = max or 15
    local out, seen = {}, {}
    local function add(f) if not seen[f] and #out < max then seen[f] = true; out[#out + 1] = f end end
    for _, p in ipairs(M.PREFERRED) do
        for _, f in ipairs(faces or {}) do
            if f:find(p, 1, true) then add(f) end
        end
    end
    for _, f in ipairs(faces or {}) do
        if f:find("CJK", 1, true) or f:find("[\128-\255]") then add(f) end
    end
    return out
end

-- BUG-01: the face in use is always listed (first) and marked, even when it is
-- a Latin face filtered out by pick_fonts (CJK then comes from fallback).
-- Returns list, index_of_current (nil when current is unknown).
function M.font_list(faces, current, max)
    max = max or 15
    local list = M.pick_fonts(faces, max)
    if type(current) ~= "string" or current == "" then return list, nil end
    for i, f in ipairs(list) do if f == current then return list, i end end
    table.insert(list, 1, current)
    if #list > max then list[#list] = nil end
    return list, 1
end

-- Short button label (BUG-01: "Noto Sans CJK SC" was cut to "Noto Sans CJ…").
-- Known CJK families get their usual Chinese name plus the region tag
-- (NEW-02: SC / TC / HK / JP / KR stay distinguishable); other names only
-- lose a trailing "Regular".
M.FONT_NAMES = {
    { "Noto Serif CJK", "思源宋体" }, { "Source Han Serif", "思源宋体" },
    { "Noto Sans CJK", "思源黑体" }, { "Source Han Sans", "思源黑体" },
    { "LXGW WenKai", "霞鹜文楷" }, { "Droid Sans Fallback", "Droid 黑体" },
}
M.REGIONS = { "SC", "TC", "HC", "HK", "JP", "KR", "CN", "TW", "J", "K" }
function M.font_label(face)
    if type(face) ~= "string" then return "" end
    for _, p in ipairs(M.FONT_NAMES) do
        local s, e = face:find(p[1], 1, true)
        if s then
            local rest = face:sub(e + 1)
            -- NEW-04: keep what follows (region, weight...), drop only "Regular"
            rest = rest:gsub("[ %-]Regular$", ""):gsub("^[ %-]+", ""):gsub("%-", " ")
            return rest ~= "" and (p[2] .. " " .. rest) or p[2]
        end
    end
    return (face:gsub("[ %-]Regular$", ""))
end

-- BUG-08: the switch is KOReader's paragraph_indent style tweak, which forces
-- an indent; it cannot tell whether the book's own CSS already indents.
function M.indent_label(on) return (on and "✓ " or "") .. "强制首行缩进" end

-- BUG-05 / NEW-01: list rows that do not fit are paged instead of dropped.
-- n rows, `fit` row slots, `offset` = index of first row shown (0-based).
-- When paging, ONE nav row (‹ 上一页 | 下一页 ›) takes one slot, so a page
-- never uses more than `fit` slots (fit >= 2). fit <= 1 cannot hold a row
-- plus navigation; then 1 row + nav row are drawn (documented limit).
-- Returns first, last (1-based, inclusive), has_prev, has_next.
function M.page_rows(n, fit, offset)
    offset = math.max(0, math.min(offset or 0, math.max(n - 1, 0)))
    fit = math.max(fit or 0, 1)
    if offset == 0 and n <= fit then return 1, n, false, false end
    local slots = math.max(fit - 1, 1)
    local last = math.min(n, offset + slots)
    return offset + 1, last, offset > 0, last < n
end
-- slots a page actually uses (rows + nav row)
function M.page_slots(n, fit, offset)
    local f, l, p, nx = M.page_rows(n, fit, offset)
    return (l - f + 1) + ((p or nx) and 1 or 0)
end
function M.next_offset(n, fit, offset)
    local _, last = M.page_rows(n, fit, offset)
    return last
end
function M.prev_offset(n, fit, offset)
    -- walk forward from 0 to find the page start before `offset`
    local o, prev = 0, 0
    while o < offset do
        prev = o
        local _, last = M.page_rows(n, fit, o)
        if last <= o then break end
        o = last
    end
    return prev
end

-- Discover page: most recently read books (shelf items from Data.get_shelf,
-- already sorted by last_read desc); only those with a known read time.
function M.recent(books, n)
    local out = {}
    for _, b in ipairs(books or {}) do
        if #out >= n then break end
        if (b.last_read or 0) > 0 then out[#out + 1] = b end
    end
    return out
end

-- Me page numbers ----------------------------------------------------------
function M.count_finished(books)
    local n = 0
    for _, b in ipairs(books or {}) do if b.finished then n = n + 1 end end
    return n
end

function M.minutes(seconds)
    seconds = tonumber(seconds)
    if not seconds then return nil end
    return math.floor(seconds / 60 + 0.5)
end

-- /readdata/detail "readStat" chips {stat="笔记", counts="12条"}
-- (weread/lib/read_stats.lua:189-201). Returns the number or nil.
function M.notes_from_summary(raw)
    local list = type(raw) == "table" and raw.readStat or nil
    if type(list) ~= "table" then return nil end
    for _, item in ipairs(list) do
        if type(item) == "table" and type(item.stat) == "string" and item.stat:find("笔记", 1, true) then
            return tonumber(tostring(item.counts or ""):match("%d+"))
        end
    end
    return nil
end

function M.fmt_num(v) return v == nil and "—" or tostring(v) end

-- First character (UTF-8 aware) for the avatar placeholder.
function M.initial(name)
    if type(name) ~= "string" or name == "" then return "我" end
    return name:match("^[%z\1-\127\194-\244][\128-\191]*") or "我"
end

-- Reader top bar title: chapter title if any, else book title, single line.
function M.reader_title(chapter, book)
    local t = (type(chapter) == "string" and chapter ~= "") and chapter or book
    if type(t) ~= "string" then return "" end
    return (t:gsub("%s+", " "))
end

-- 5 equal slots across width w: returns x of slot i and slot width.
function M.slot(w, n, i)
    local sw = math.floor(w / n)
    return (i - 1) * sw, sw
end

return M
