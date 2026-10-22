-- wereadshelf_data.lua — data layer for the "微信书架" tab.
--
-- Pure Lua: no KOReader UI requires at module level, so it can be unit
-- tested with luajit on a PC. Everything goes through the *live*
-- weread.koplugin instance (weread 1.6.0 public-ish methods), never through
-- private reimplementations of its storage format, so its account hashing,
-- download dir override and cover cache rules stay authoritative.
--
-- weread 1.6.0 references (tag v1.6.0, commit 1f4861d):
--   instance on FM/Reader : koreader frontend/apps/filemanager/filemanager.lua:418-425
--                           (registerModule(plugin_module.name, ...)) → ui.weread
--   login check            : weread/lib/settings.lua:257 is_api_configured()
--                           (shelf refresh requires api key: weread/ui/library.lua:151)
--   shelf cache            : weread/lib/library_db.lua:193 getShelf()  (SQLite
--                           <data_dir>/weread/library-<sha256(vid)[1..20]>.db, table books)
--                           accountKey(): library_db.lua:51 (nil when no user_vid)
--   book records           : weread/lib/settings.lua:245-258 get("books") →
--                           weread/lib/book_store.lua:124 load() (metadata.json +
--                           reading_state.json per book dir)
--   downloaded?            : weread/ui/cache.lua:373 bookRecordHasDownload(record)
--   cover thumbnail path   : weread/ui/library.lua:237 getShelfCoverCache() →
--                           weread/lib/cover_cache.lua:51 pathFor(book)
--                           (<data_dir>/weread/shelf-covers/<md5(cover url)>.thumb.png)
--   open downloaded book   : weread/ui/library.lua:1466 openBookForReading(book)
--   detail/download page   : weread/ui/library.lua:657 showBookRecord(book)
--   weread's own shelf     : weread/main.lua:33 openBookshelf()

local M = {}

-- Error codes returned as 2nd value of get_shelf().
M.ERR_NO_PLUGIN     = "no_plugin"       -- weread.koplugin not loaded/enabled
M.ERR_NOT_LOGGED_IN = "not_logged_in"   -- no api_key / no account vid
M.ERR_NO_CACHE      = "no_cache"        -- logged in, but shelf never synced
M.ERR_DB            = "db_unavailable"  -- library db could not be opened/read
M.ERR_NOT_FOUND     = "not_found"       -- open_book: id not on cached shelf

M.MESSAGES = {
    no_plugin      = "未找到微信读书插件（weread.koplugin）。\n请确认它已安装并在「插件管理」中启用。",
    not_logged_in  = "微信读书尚未登录。\n请先打开微信读书插件扫码登录。",
    no_cache       = "还没有书架缓存。\n请先打开一次微信读书插件的书架（联网），让它同步书架。",
    db_unavailable = "无法读取微信读书的书架缓存数据库。",
    not_found      = "书架缓存中找不到这本书，请刷新书架后重试。",
}

local function safe(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil, a
end

-- Locate the live weread plugin instance. `env` lets tests inject fakes.
function M.find_weread(env)
    env = env or {}
    if env.weread then return env.weread end
    local loaded = env.loaded or package.loaded
    for _i, key in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local cls = loaded[key]
        local inst = type(cls) == "table" and cls.instance or nil
        local w = type(inst) == "table" and inst.weread or nil
        if type(w) == "table" and type(w.library_db) == "table" then
            return w
        end
    end
    return nil
end

function M.is_logged_in(weread)
    if not weread or not weread.settings then return false end
    local api_ok = safe(function() return weread.settings:is_api_configured() end)
    if not api_ok then return false end
    local key = safe(function() return weread.library_db:accountKey() end)
    return key ~= nil
end

local function file_exists(path)
    if type(path) ~= "string" or path == "" then return false end
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

-- Fallback identical in spirit to weread/ui/cache.lua:373.
local function record_has_download(weread, record)
    if type(record) ~= "table" then return false end
    if type(weread.bookRecordHasDownload) == "function" then
        local v = safe(weread.bookRecordHasDownload, weread, record)
        return v == true
    end
    if file_exists(record.cached_full_book) or file_exists(record.cached_file) then
        return true
    end
    for _uid, path in pairs(record.cached_chapters or {}) do
        if file_exists(path) then return true end
    end
    return false
end

-- Fallback when weread's lazy require("weread.lib.cover_cache")
-- (library.lua:239) cannot resolve at runtime: rebuild the same path rule
-- (cover_cache.lua:35, 45-55) with weread's already-loaded Crypto module
-- (required at top level by library_db.lua:6).
local function cover_path_fallback(weread, book)
    local url = type(book) == "table" and book.cover or nil
    if type(url) ~= "string" or url == "" then return nil end
    local Crypto = M._crypto or package.loaded["weread.lib.crypto"]
    local settings = weread.settings or {}
    local base = settings.data_dir or settings.cache_dir
    if type(Crypto) ~= "table" or type(Crypto.md5_hex) ~= "function" or not base then return nil end
    local key = safe(Crypto.md5_hex, url)
    if type(key) ~= "string" then return nil end
    local path = base .. "/shelf-covers/" .. key .. ".thumb.png"
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end") or 0
    f:close()
    return size >= 16 and path or nil -- MIN_IMAGE_BYTES, cover_cache.lua:11
end

local function cover_path(weread, book)
    if type(weread.getShelfCoverCache) == "function" then
        local cache = safe(weread.getShelfCoverCache, weread)
        if type(cache) == "table" and type(cache.pathFor) == "function" then
            local path = safe(cache.pathFor, cache, book)
            return type(path) == "string" and path or nil
        end
    end
    return cover_path_fallback(weread, book)
end

-- Progress in percent 0..100 or nil when unknown.
-- The /shelf/sync payload carries no progress (docs/weread-api-reference.md:263-283);
-- weread stores it on the book record (library.lua:721, book_store.lua:22 "progress").
local function progress_of(book, record)
    local p = type(record) == "table" and tonumber(record.progress) or nil
    if p == nil then p = tonumber(book.progress) end
    if p == nil and tonumber(book.finishReading) == 1 then p = 100 end
    if p == nil then return nil end
    return math.max(0, math.min(100, p))
end

local function normalize(weread, book, saved)
    local id = book.bookId or book.book_id
    if id == nil then return nil end
    id = tostring(id)
    local record = saved[id]
    return {
        bookId     = id,
        title      = type(book.title) == "string" and book.title or id,
        author     = type(book.author) == "string" and book.author or "",
        cover      = cover_path(weread, book),          -- local path or nil
        progress   = progress_of(book, record),         -- 0..100 or nil
        finished   = tonumber(book.finishReading) == 1,
        downloaded = record_has_download(weread, record),
        last_read  = tonumber(book.readUpdateTime) or 0, -- unix seconds, 0 = unknown
        is_mp      = id:match("^MP_WXS_") ~= nil,       -- 公众号 (library_db.lua:149)
        _raw       = book,
    }
end

-- Returns list, nil  |  nil, err_code
-- opts.include_mp (default false): include 公众号 entries.
-- opts.allow_empty (BUG-06): a readable but empty shelf returns {} instead of
-- ERR_NO_CACHE, so the grid can show an empty shelf with search / 导入.
function M.get_shelf(weread, opts)
    opts = opts or {}
    if not weread then return nil, M.ERR_NO_PLUGIN end
    if not M.is_logged_in(weread) then return nil, M.ERR_NOT_LOGGED_IN end
    local books, err = safe(function() return weread.library_db:getShelf() end)
    if books == nil then
        -- getShelf() returns nil when the db cannot be opened or queried.
        return nil, err and M.ERR_DB or M.ERR_DB
    end
    if type(books) ~= "table" then return nil, M.ERR_NO_CACHE end
    if #books == 0 then
        if opts.allow_empty then return {} end
        return nil, M.ERR_NO_CACHE
    end
    local saved = safe(function() return weread.settings:get("books", {}) end) or {}
    local out = {}
    for _i, book in ipairs(books) do
        if type(book) == "table" then
            local item = normalize(weread, book, saved)
            if item and (opts.include_mp or not item.is_mp) then
                out[#out + 1] = item
            end
        end
    end
    -- weread default sort "time_desc" (settings.lua:95, library.lua:573-576)
    for i, item in ipairs(out) do item._pos = i end
    table.sort(out, function(a, b)
        if a.last_read ~= b.last_read then return a.last_read > b.last_read end
        return a._pos < b._pos
    end)
    for _i, item in ipairs(out) do item._pos = nil end
    if #out == 0 and not opts.allow_empty then return nil, M.ERR_NO_CACHE end
    return out
end

-- Decide what open_book would do, without doing it (testable).
-- Returns action ("read"|"detail"), payload  |  nil, err_code
function M.plan_open(weread, book_id)
    if not weread then return nil, M.ERR_NO_PLUGIN end
    if not M.is_logged_in(weread) then return nil, M.ERR_NOT_LOGGED_IN end
    book_id = tostring(book_id or "")
    local books = safe(function() return weread.library_db:getShelf() end)
    if type(books) ~= "table" then return nil, M.ERR_DB end
    local shelf_book
    for _i, b in ipairs(books) do
        if tostring(b.bookId or b.book_id) == book_id then shelf_book = b break end
    end
    if not shelf_book then return nil, M.ERR_NOT_FOUND end
    local saved = safe(function() return weread.settings:get("books", {}) end) or {}
    local record = saved[book_id]
    if not book_id:match("^MP_WXS_") and record_has_download(weread, record) then
        return "read", record
    end
    return "detail", shelf_book
end

-- Perform the open. Must run on the UI thread inside KOReader.
-- Returns true | false, err_code
function M.open_book(weread, book_id)
    local action, payload = M.plan_open(weread, book_id)
    if not action then return false, payload end
    if action == "read" and type(weread.openBookForReading) == "function" then
        local ok, opened = pcall(weread.openBookForReading, weread, payload)
        if ok and opened then return true end
        -- fall through to the detail page (it offers download/read buttons)
        local books = safe(function() return weread.library_db:getShelf() end) or {}
        for _i, b in ipairs(books) do
            if tostring(b.bookId or b.book_id) == tostring(book_id) then payload = b break end
        end
    end
    if type(weread.showBookRecord) ~= "function" then return false, M.ERR_NO_PLUGIN end
    local ok, err = pcall(weread.showBookRecord, weread, payload)
    if not ok then return false, tostring(err) end
    return true
end

-- Text helpers for the list UI.
function M.format_mandatory(item, now_date_fn)
    local parts = {}
    if item.downloaded then parts[#parts + 1] = "✓" end
    if item.finished then
        parts[#parts + 1] = "读完"
    elseif item.progress then
        parts[#parts + 1] = string.format("%d%%", math.floor(item.progress + 0.5))
    end
    if item.last_read and item.last_read > 0 then
        parts[#parts + 1] = (now_date_fn or os.date)("%m-%d", item.last_read)
    end
    return table.concat(parts, "  ")
end

function M.format_text(item)
    if item.author ~= "" then return item.title .. " — " .. item.author end
    return item.title
end

return M
