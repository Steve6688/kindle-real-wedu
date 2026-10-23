-- realweidu_rank.lua (0.6.2) — 发现 「微信读书」 section: WeRead rankings
-- (神作榜 / 潜力榜 / 飙升榜 / 新书榜 / 总榜, switchable) and a 4-book
-- 「为你推荐」 row with 「换一批」. Data: weread.qq.com/web/bookListInCategory
-- (the public list the WeRead web app uses), fetched with weread's own client
-- (its cookies); covers are cached under <cache>/realweidu_covers/.
local M = {
    TABS = {
        { id = "newrating_publish",           name = "神作榜" },
        { id = "newrating_potential_publish", name = "潜力榜" },
        { id = "rising",                      name = "飙升榜" },
        { id = "newbook",                     name = "新书榜" },
        { id = "all",                         name = "总榜" },
    },
    RECOMMEND = "hot_search",   -- 「为你推荐」 source list
    RANK_N = 5, REC_N = 5, -- 0.6.4: one row of 5 covers each
    tab = 1, rec_offset = 0,
    lists = {},                 -- [category] = { books, t }
    deps = {},
}

function M.url(category, max_index)
    return "https://weread.qq.com/web/bookListInCategory/" .. category
        .. "?maxIndex=" .. tostring(max_index or 0) .. "&rank=1"
end

-- Response -> { {bookId=, title=, author=, cover=, rating=}, ... }
function M.parse(data)
    local out = {}
    if type(data) ~= "table" then return out end
    for _, e in ipairs(data.books or {}) do
        local b = type(e) == "table" and (e.bookInfo or e) or nil
        if type(b) == "table" and b.bookId then
            out[#out + 1] = { bookId = tostring(b.bookId), title = b.title or "", author = b.author or "",
                cover = b.cover, rating = tonumber(e.newRating or b.newRating) }
        end
    end
    return out
end

function M.cover_path(dir, url)
    if type(url) ~= "string" or url == "" then return nil end
    local h = 0
    for i = 1, #url do h = (h * 31 + url:byte(i)) % 4294967296 end
    return string.format("%s/%08x.jpg", dir, h)
end

local function exists(p) local f = p and io.open(p, "rb"); if f then f:close(); return true end end

-- Network (run inside weread:runOnlineTask). Returns list or nil, err.
function M.fetch(client, category, max_index)
    local text, code = client:get_text(M.url(category, max_index), { accept = "application/json, text/plain, */*" })
    if type(text) ~= "string" then return nil, "HTTP " .. tostring(code) end
    local ok, data = pcall(client.json_decode, client, text)
    if not ok or type(data) ~= "table" then return nil, "bad json" end
    if data.errcode and tonumber(data.errcode) ~= 0 then return nil, tostring(data.errmsg or data.errcode) end
    return M.parse(data)
end

function M.fetch_covers(client, books, dir)
    os.execute("mkdir -p '" .. dir .. "'")
    for _, b in ipairs(books) do
        local p = M.cover_path(dir, b.cover)
        if p and not exists(p) then
            local url = b.cover:gsub("/s_", "/t6_")
            pcall(function()
                local data = client:get_binary(url)
                if type(data) == "string" and #data > 100 then
                    local f = io.open(p, "wb"); if f then f:write(data); f:close() end
                end
            end)
        end
        if p and exists(p) then b.cover_file = p end
    end
end

-- Load the current tab + the recommendation list (cached for the session).
function M.load(client, dir, force)
    local errs = {}
    local function get(cat, idx, key)
        key = key or cat
        if M.lists[key] and not force then return M.lists[key].books end
        local books, err = M.fetch(client, cat, idx)
        if books then M.lists[key] = { books = books } else errs[#errs + 1] = err end
        return books
    end
    local rank = get(M.TABS[M.tab].id, 0)
    if rank then
        local top = {}
        for i = 1, math.min(M.RANK_N, #rank) do top[i] = rank[i] end
        M.fetch_covers(client, top, dir)
    end
    local rec = get(M.RECOMMEND, M.rec_offset, M.RECOMMEND .. ":" .. M.rec_offset)
    if rec then M.fetch_covers(client, M.batch(rec), dir) end
    return #errs == 0, errs[1]
end

function M.rank_books()
    local l = M.lists[M.TABS[M.tab].id]
    local out = {}
    for i = 1, math.min(M.RANK_N, l and #l.books or 0) do out[i] = l.books[i] end
    return out, l ~= nil
end

-- The 4 recommended books shown now; 「换一批」 moves through the list and
-- fetches the next page when the current one runs out.
M.rec_page = 0
function M.batch(list)
    list = list or (M.lists[M.RECOMMEND .. ":" .. M.rec_offset] or {}).books or {}
    local out = {}
    local start = M.rec_page * M.REC_N
    for i = 1, M.REC_N do out[i] = list[start + i] end
    return out
end

function M.next_batch()
    local list = (M.lists[M.RECOMMEND .. ":" .. M.rec_offset] or {}).books or {}
    M.rec_page = M.rec_page + 1
    if (M.rec_page + 1) * M.REC_N > #list then
        M.rec_offset = (#list > 0 and M.rec_offset < 200) and (M.rec_offset + #list) or 0
        M.rec_page = 0
        return true -- needs a fetch
    end
    return false
end

function M.set_tab(i) if M.TABS[i] then M.tab = i end end

-- 0.6.3 home layout: every ranking is one row of 4 covers; 「换一批」 shifts all rows.
M.ROW_N, M.shift = 4, 0
function M.list(i)
    local t = M.TABS[i]
    local l = t and M.lists[t.id]
    return l and l.books or nil
end
function M.row_books(i)
    local l = M.list(i) or {}
    local out = {}
    if #l == 0 then return out end
    local pages = math.max(1, math.floor(#l / M.ROW_N))
    local start = (M.shift % pages) * M.ROW_N
    for k = 1, M.ROW_N do out[k] = l[start + k] end
    return out
end
function M.shift_rows() M.shift = M.shift + 1 end
-- 0.6.4: home shows only the selected tab + 为你推荐 again -> load just those
function M.load_all(client, dir, force) return M.load(client, dir, force) end
function M.load_every_tab(client, dir, force)
    local first_err
    for i, t in ipairs(M.TABS) do
        if force or not M.lists[t.id] then
            local books, err = M.fetch(client, t.id, 0)
            if books then M.lists[t.id] = { books = books } else first_err = first_err or err end
        end
        local row = M.row_books(i)
        if #row > 0 then M.fetch_covers(client, row, dir) end
    end
    return first_err == nil, first_err
end
function M.any_loaded()
    return M.lists[M.TABS[M.tab].id] ~= nil
end

return M
