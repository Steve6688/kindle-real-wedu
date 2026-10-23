-- realweidu_logic.lua — pure helpers (no KOReader deps) for the reader menu,
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

-- 0.4.5 middle progress button ------------------------------------------------
M.DEFAULT_PAGES_PER_MIN = 1   -- fallback when KOReader has no reading stats
M.UNKNOWN = "—"
M.TOC_SIDEBAR_FRAC = 0.5  -- 0.6.3: TOC sidebar = 50% width; right half = tap-to-close

-- Percent read (0..100, integer) from current page and page count; nil if unknown.
function M.progress_pct(cur, total)
    if type(cur) ~= "number" or type(total) ~= "number" or total <= 0 then return nil end
    if cur < 1 then cur = 1 elseif cur > total then cur = total end
    return math.floor(100 * cur / total + 0.5)
end

-- Average seconds per page. stats = { avg_time=, total_time_in_sec=, total_read_pages= }.
-- Returns secs, source ("stats"|"default").
function M.avg_page_secs(stats, default_ppm)
    if type(stats) == "table" then
        local a = tonumber(stats.avg_time)
        if a and a > 0 then return a, "stats" end
        local t, n = tonumber(stats.total_time_in_sec), tonumber(stats.total_read_pages)
        if t and n and t > 0 and n > 0 then return t / n, "stats" end
    end
    local ppm = tonumber(default_ppm) or M.DEFAULT_PAGES_PER_MIN
    if ppm <= 0 then return nil end
    return 60 / ppm, "default"
end

-- Pages left in the book / in the chapter (next_chapter_page = first page of next chapter or nil).
function M.pages_left_book(cur, total)
    if type(cur) ~= "number" or type(total) ~= "number" or total <= 0 then return nil end
    return math.max(0, total - cur)
end
function M.pages_left_chapter(cur, total, next_chapter_page)
    if type(cur) ~= "number" then return nil end
    if type(next_chapter_page) == "number" and next_chapter_page > cur then
        return next_chapter_page - cur
    end
    return M.pages_left_book(cur, total)
end

function M.remaining_secs(pages_left, avg)
    if type(pages_left) ~= "number" or type(avg) ~= "number" or avg <= 0 then return nil end
    return pages_left * avg
end

-- "—" | "不到1分钟" | "N分钟" | "H小时" | "H小时M分钟"
function M.fmt_duration(secs)
    if type(secs) ~= "number" or secs ~= secs or secs < 0 then return M.UNKNOWN end
    if secs == 0 then return "0分钟" end
    local mins = math.floor(secs / 60 + 0.5)
    if mins < 1 then return "不到1分钟" end
    if mins < 60 then return mins .. "分钟" end
    local h, mm = math.floor(mins / 60), mins % 60
    return mm == 0 and (h .. "小时") or (h .. "小时" .. mm .. "分钟")
end

-- 0.4.9 TOC sidebar pagination -------------------------------------------------
-- rows_per_page(avail_h, row_h) >= 1
function M.toc_rows_per_page(avail_h, row_h)
    if type(avail_h) ~= "number" or type(row_h) ~= "number" or row_h <= 0 then return 1 end
    return math.max(1, math.floor(avail_h / row_h))
end
function M.toc_page_count(n, per)
    if type(n) ~= "number" or n <= 0 then return 1 end
    return math.max(1, math.ceil(n / per))
end
-- index (1-based) of the chapter containing page `cur` in a toc of { page = } entries; 1 if none
function M.toc_current_index(toc, cur)
    local idx = 1
    if type(toc) ~= "table" or type(cur) ~= "number" then return idx end
    for i, ch in ipairs(toc) do
        if type(ch.page) == "number" and ch.page <= cur then idx = i end
    end
    return idx
end
function M.toc_page_of(index, per) return math.max(1, math.ceil((index or 1) / per)) end
function M.toc_clamp_page(p, count) return math.max(1, math.min(count, p or 1)) end
-- first/last entry indices shown on page p
function M.toc_page_range(p, per, n)
    local first = (p - 1) * per + 1
    return first, math.min(n, first + per - 1)
end
-- KOReader list convention: swipe up (finger moves north) = next page, south = previous.
function M.toc_swipe_delta(direction)
    if direction == "north" or direction == "west" then return 1 end
    if direction == "south" or direction == "east" then return -1 end
    return 0
end

-- 0.5.0 查词模式 ----------------------------------------------------------------
M.LOOKUP_SETTING = "realweidu_lookup_mode"  -- G_reader_settings key (persisted)
M.LOOKUP_EDGE = 0.12                        -- left/right strips that still turn pages
-- "lookup" when the tap should look up a word, "pass" to leave it to page turn / menu.
function M.lookup_tap_action(on, x, w, edge)
    if not on or type(x) ~= "number" or type(w) ~= "number" or w <= 0 then return "pass" end
    local e = math.floor(w * (edge or M.LOOKUP_EDGE))
    if x < e or x >= w - e then return "pass" end
    return "lookup"
end

-- 0.5.1: only English words (Latin letters, inner/outer apostrophe or hyphen) go to the
-- vocabulary builder in 查词模式; Chinese / other non-Latin selections are not stored.
function M.is_english_word(s)
    if type(s) ~= "string" then return false end
    s = s:gsub("\226\128\153", "'"):gsub("\226\128\152", "'"):match("^%s*(.-)%s*$")
    if s == "" or #s > 64 then return false end
    if not s:match("^[A-Za-z'%-]+$") then return false end
    return s:find("[A-Za-z]") ~= nil
end

-- Compact form for inside the circle: "—" | "<1分" | "N分" | "N时" (rounded hours >= 60 min)
function M.fmt_short(secs)
    if type(secs) ~= "number" or secs ~= secs or secs < 0 then return M.UNKNOWN end
    local mins = math.floor(secs / 60 + 0.5)
    if secs > 0 and mins < 1 then return "<1分" end
    if mins < 60 then return "余" .. mins .. "分" end
    return "余" .. math.floor(mins / 60 + 0.5) .. "时"
end

-- Everything the middle button shows. Any field may be "—".
function M.progress_info(cur, total, next_chapter_page, stats, default_ppm)
    local pct = M.progress_pct(cur, total)
    local avg, src = M.avg_page_secs(stats, default_ppm)
    return {
        pct = pct, pct_text = pct and (pct .. "%") or M.UNKNOWN,
        chapter_text = M.fmt_duration(M.remaining_secs(M.pages_left_chapter(cur, total, next_chapter_page), avg)),
        book_text = M.fmt_duration(M.remaining_secs(M.pages_left_book(cur, total), avg)),
        chapter_secs = M.remaining_secs(M.pages_left_chapter(cur, total, next_chapter_page), avg),
        book_secs = M.remaining_secs(M.pages_left_book(cur, total), avg),
        source = src,
    }
end

-- 0.6.2 「同步进度」 confirm text
function M.sync_progress_text(local_pct, remote_pct, err)
    local function f(v) return v and (string.format("%.1f", v):gsub("%.0$", "") .. "%") or "未知" end
    local t = "本地进度：" .. f(local_pct) .. "\n微信读书进度：" .. f(remote_pct)
    if err then t = t .. "\n（读取微信读书进度失败：" .. err .. "）" end
    return t .. "\n\n同步后将按微信读书的规则对齐两端进度。确定同步？"
end
-- 0.6.3 light slider fraction, clamped so the knob never leaves the track
function M.light_frac(v, lo, hi)
    v, lo, hi = tonumber(v), tonumber(lo), tonumber(hi)
    if not v or not lo or not hi or hi <= lo then return 0 end
    return math.max(0, math.min(1, (v - lo) / (hi - lo)))
end
-- 0.6.5: ONE cover grid for all three home rows (最近阅读 / ranking / 为你推荐):
-- same width, same gap, edges flush with both margins. `fixed` = all
-- non-cover height of the page, `rows` = cover rows, `slots` = vertical gaps.
function M.home_grid(W, m, avail, fixed, rows, slots, min_gap, min_col_gap)
    local inner = W - 2 * m
    local cw = math.floor((inner - 4 * min_col_gap) / 5)
    local ch = math.floor(cw * 280 / 200)
    local fit = math.floor((avail - fixed - slots * min_gap) / rows)
    if fit < ch then ch = fit; cw = math.min(cw, math.floor(ch * 200 / 280)) end
    cw = cw - ((cw - inner) % 4)          -- (inner - cw) % 4 == 0: integer gap, identical steps
    ch = math.min(ch, math.floor(cw * 280 / 200))
    local gap = math.floor((inner - 5 * cw) / 4)
    local xs = {}
    for i = 1, 5 do xs[i] = m + (i - 1) * (cw + gap) end
    local vgap = math.max(min_gap, math.floor((avail - fixed - rows * ch) / slots))
    return { cw = cw, ch = ch, gap = gap, xs = xs, vgap = vgap }
end

-- 0.6.6: vertical rhythm below 最近阅读. `left` = height from the bottom of the
-- 最近阅读 titles to the nav bar. Both section gaps (previous titles' bottom ->
-- next section's title text top) are the same S; the rest is fixed.
-- t = { tab_h, tab_off (label top inside the tab row), inner (tabs -> covers),
--       row (cover + title height), hdr_h, hdr_off (为你推荐 text top), pad (bottom) }
function M.home_sections(left, t)
    local used = t.tab_h + t.inner + t.row + t.hdr_h + t.row + t.pad
    local S = math.floor((left - used + t.tab_off + t.hdr_off) / 2)
    local tabs_y = S - t.tab_off
    local rank_y = tabs_y + t.tab_h + t.inner
    local hdr_y = rank_y + t.row + S - t.hdr_off
    local rec_y = hdr_y + t.hdr_h
    return { S = S, tabs_y = tabs_y, rank_y = rank_y, hdr_y = hdr_y, rec_y = rec_y, bottom = rec_y + t.row }
end

return M
