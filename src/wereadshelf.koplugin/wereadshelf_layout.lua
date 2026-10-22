-- wereadshelf_layout.lua — pure layout + pagination math for the 4-column
-- cover grid (no KOReader deps; unit-tested in spec/test_layout.lua).
-- Reference values are UI-SPEC v1 numbers measured for PW5 (1236 px wide);
-- they are scaled linearly by screen_w / 1236 on other screens.
local M = {}

M.REF_W = 1236
M.SPEC = {
    margin       = 45,   -- left/right page margin
    col_gap      = 45,   -- gap between columns
    cols         = 4,
    cover_ratio  = 3 / 2,     -- h / w: UI-SPEC "封面 2:3（约 260×360）"; weread thumbs are 300×450 (cover_cache.lua:12-13), so 2:3 avoids distortion
    search_top   = 24,   -- space above the search capsule
    search_h     = 115,
    search_font  = 30,
    title_row_h  = 120,  -- "书架" row; also the tap height of 导入/选择 (>=110)
    title_font   = 52,
    action_font  = 36,
    name_gap     = 12,   -- cover -> book title
    name_font    = 32,
    name_lines   = 2,
    line_factor  = 1.4,  -- line box per text line (TextBoxWidget adds ~30% leading)
    row_gap      = 30,
    min_touch    = 120,  -- UI-SPEC says >=110; task asks >=120
}

local function floor(x) return math.floor(x + 1e-9) end

-- opts: { screen_w, avail_h } (avail_h = height between SimpleUI top inset
-- and bottom bar). Returns a table of integer pixel metrics.
function M.compute(opts)
    local S = M.SPEC
    local sw = assert(opts.screen_w, "screen_w")
    local ah = assert(opts.avail_h, "avail_h")
    local k = sw / M.REF_W
    local L = { k = k, cols = S.cols }
    local function px(v) return math.max(1, floor(v * k)) end
    L.margin      = px(S.margin)
    L.col_gap     = px(S.col_gap)
    L.search_top  = px(S.search_top)
    L.search_h    = math.max(px(S.search_h), S.min_touch)
    L.search_w    = sw - 2 * L.margin
    L.search_font = px(S.search_font)
    L.title_row_h = math.max(px(S.title_row_h), S.min_touch)
    L.title_font  = px(S.title_font)
    L.action_font = px(S.action_font)
    L.name_font   = px(S.name_font)
    L.name_gap    = px(S.name_gap)
    L.row_gap     = px(S.row_gap)
    L.cover_w     = floor((sw - 2 * L.margin - (S.cols - 1) * L.col_gap) / S.cols)
    L.cover_h     = floor(L.cover_w * S.cover_ratio)
    L.name_line_h = floor(L.name_font * S.line_factor)
    L.name_h      = L.name_line_h * S.name_lines
    L.cell_w      = L.cover_w
    L.cell_h      = L.cover_h + L.name_gap + L.name_h
    L.header_h    = L.search_top + L.search_h + L.title_row_h
    L.grid_h      = math.max(0, ah - L.header_h)
    L.rows        = math.max(1, floor((L.grid_h + L.row_gap) / (L.cell_h + L.row_gap)))
    L.per_page    = L.cols * L.rows
    -- leftover horizontal pixels from flooring go to the right margin
    L.grid_w      = S.cols * L.cover_w + (S.cols - 1) * L.col_gap
    return L
end

-- Top-left of cell #i (1-based, within a page), relative to the grid origin.
function M.cell_pos(L, i)
    local idx = i - 1
    local r, c = floor(idx / L.cols), idx % L.cols
    return L.margin + c * (L.cover_w + L.col_gap), r * (L.cell_h + L.row_gap), r + 1, c + 1
end

function M.page_count(n, per_page)
    if n <= 0 then return 1 end
    return math.ceil(n / per_page)
end

function M.clamp_page(page, n, per_page)
    local pc = M.page_count(n, per_page)
    page = tonumber(page) or 1
    if page < 1 then return 1 end
    if page > pc then return pc end
    return floor(page)
end

-- Items of `list` on `page` (1-based), plus first/last absolute index.
function M.page_slice(list, page, per_page)
    page = M.clamp_page(page, #list, per_page)
    local first = (page - 1) * per_page + 1
    local last = math.min(#list, first + per_page - 1)
    local out = {}
    for i = first, last do out[#out + 1] = list[i] end
    return out, first, last, page
end

-- Page that contains absolute item index idx (to keep position after refilter).
function M.page_of(idx, per_page)
    if not idx or idx < 1 then return 1 end
    return floor((idx - 1) / per_page) + 1
end

-- Case-insensitive plain substring filter on title/author (local search).
function M.filter(list, keyword)
    if type(keyword) ~= "string" then return list end
    keyword = keyword:gsub("^%s+", ""):gsub("%s+$", "")
    if keyword == "" then return list end
    local kw = keyword:lower()
    local out = {}
    for _, b in ipairs(list) do
        local t = (b.title or ""):lower()
        local a = (b.author or ""):lower()
        if t:find(kw, 1, true) or a:find(kw, 1, true) then out[#out + 1] = b end
    end
    return out
end

-- Tap hit-test: x,y relative to grid origin -> cell index on page, or nil
-- (gaps between cells are not hits).
function M.hit(L, x, y, count)
    if x < L.margin or y < 0 then return nil end
    local cx = x - L.margin
    local c = floor(cx / (L.cover_w + L.col_gap))
    if c >= L.cols or cx - c * (L.cover_w + L.col_gap) > L.cover_w then return nil end
    local r = floor(y / (L.cell_h + L.row_gap))
    if r >= L.rows or y - r * (L.cell_h + L.row_gap) > L.cell_h then return nil end
    local i = r * L.cols + c + 1
    if count and i > count then return nil end
    return i
end

return M
