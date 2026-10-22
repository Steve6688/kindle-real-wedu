-- Offline tests for wereadshelf_data.lua. Run: luajit spec/test_shelf_data.lua
-- Uses the REAL weread v1.6.0 LibraryDB / BookStore / CoverCache / Crypto code
-- to write the mock cache, so the data layer is checked against weread's
-- actual on-disk format, not a guess.
local here = arg[0]:match("^(.*)/[^/]+$") or "."
local deps = here .. "/.deps"
package.path = table.concat({
    here .. "/../wereadshelf.koplugin/?.lua",
    deps .. "/weread/?.lua",
    deps .. "/kb/?.lua",
    deps .. "/kb/thirdparty/?.lua",
    deps .. "/?.lua",
    package.path,
}, ";")

local ffi = require("ffi")
ffi.loadlib = ffi.loadlib or function(name, ver) return ffi.load("lib" .. name .. ".so." .. ver) end
ffi.libc = ffi.libc or "gnu" -- field of KOReader's LuaJIT build, used by kb/ffi/posix_h.lua
package.loaded["logger"] = { info=function() end, warn=function() end, err=function() end, dbg=function() end }
local function sh_ok(cmd) local r = os.execute(cmd) return r == 0 or r == true end
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(path, field)
        local mode
        if sh_ok("test -d '" .. path .. "'") then mode = "directory"
        elseif sh_ok("test -f '" .. path .. "'") then mode = "file" end
        if not mode then return nil end
        local size = 0
        if mode == "file" then local f = io.open(path, "rb"); size = f:seek("end"); f:close() end
        local t = { mode = mode, size = size, modification = 0 }
        if field then return t[field] end
        return t
    end,
    mkdir = function(p) return sh_ok("mkdir -p '" .. p .. "'") end,
    dir = function() return function() return nil end end,
}

local LibraryDB  = require("weread.lib.library_db")
local BookStore  = require("weread.lib.book_store")
local CoverCache = require("weread.lib.cover_cache")
local Crypto     = require("weread.lib.crypto")
local Data       = require("wereadshelf_data")

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print("ok   " .. name)
    else fail = fail + 1; print("FAIL " .. name .. (extra and ("  -- " .. tostring(extra)) or "")) end
end

local root = os.tmpname(); os.remove(root); os.execute("mkdir -p " .. root)

-- Fake weread Settings exposing the subset weread itself uses (settings.lua:246-259)
local function make_settings(opts)
    local store = { account = { user_vid = opts.vid or "" }, api_key = opts.api_key or "", books = {} }
    local s = { data_dir = root .. "/weread", cache_dir = root .. "/weread/cache" }
    os.execute("mkdir -p " .. s.cache_dir)
    function s:get(key, default)
        if key == "books" then
            local out = {}
            for id, index in pairs(store.books) do out[id] = BookStore.load(self, id, index) end
            return out
        end
        local v = store[key]; if v == nil then return default end; return v
    end
    function s:is_api_configured() return store.api_key ~= "" end
    function s:_saveBook(id, book)
        local ok, index = BookStore.save(self, id, book); assert(ok, index); store.books[id] = index
    end
    return s
end

local function make_weread(settings)
    local w = { settings = settings, library_db = LibraryDB:new(settings), calls = {} }
    local cc = CoverCache:new(settings)
    function w:getShelfCoverCache() return cc end
    function w:openBookForReading(book) self.calls[#self.calls+1] = {"read", book.book_id}; return true end
    function w:showBookRecord(book) self.calls[#self.calls+1] = {"detail", book.bookId or book.book_id} end
    function w:openBookshelf() end
    return w
end

-- 1. no plugin
local l, e = Data.get_shelf(nil)
check("no plugin -> ERR_NO_PLUGIN", l == nil and e == Data.ERR_NO_PLUGIN)
check("find_weread with empty package.loaded -> nil", Data.find_weread({ loaded = {} }) == nil)
check("find_weread FM instance", Data.find_weread({ loaded = {
    ["apps/filemanager/filemanager"] = { instance = { weread = { library_db = {} } } } } }) ~= nil)

-- 2. not logged in (no api key / no vid)
local w0 = make_weread(make_settings{ vid = "", api_key = "" })
l, e = Data.get_shelf(w0)
check("not logged in -> ERR_NOT_LOGGED_IN", l == nil and e == Data.ERR_NOT_LOGGED_IN, e)
local w0b = make_weread(make_settings{ vid = "123", api_key = "" })
check("vid but no api key -> not logged in", select(2, Data.get_shelf(w0b)) == Data.ERR_NOT_LOGGED_IN)

-- 3. logged in, never synced -> empty db
local settings = make_settings{ vid = "424242", api_key = "k" }
local w = make_weread(settings)
l, e = Data.get_shelf(w)
check("logged in, no cache -> ERR_NO_CACHE", l == nil and e == Data.ERR_NO_CACHE, e)
-- BUG-06: same empty shelf with allow_empty -> {} (grid shows empty shelf)
local le, ee = Data.get_shelf(w, { allow_empty = true })
check("BUG-06 empty shelf + allow_empty -> {}", type(le) == "table" and #le == 0 and ee == nil, ee)
local ok_open, e2 = Data.open_book(w, "1")
check("open_book on empty cache -> not_found", ok_open == false and e2 == Data.ERR_NOT_FOUND, e2)

-- 4. populate with weread's own writer (library.lua:181 cacheShelf)
local shelf = {
    { bookId = "100", title = "三体", author = "刘慈欣", cover = "https://cdn/a.jpg", readUpdateTime = 1700000000, finishReading = 0 },
    { bookId = "200", title = "活着", author = "余华", cover = "https://cdn/b.jpg", readUpdateTime = 1800000000, finishReading = 1 },
    { bookId = "300", title = "未下载", author = "", readUpdateTime = 0 },
    { bookId = "MP_WXS_1", title = "某公众号", author = "公众号" },
}
check("cacheShelf (real weread code) succeeded", LibraryDB.cacheShelf(w.library_db, shelf, {}))
local dbpath = w.library_db:databasePath()
check("db file at <data_dir>/library-<20hex>.db", dbpath and dbpath:match("/weread/library%-%x+%.db$") and #dbpath:match("library%-(%x+)%.db") == 20, dbpath)

-- book 100: downloaded full epub + progress 37.4; book 300: record but missing file
local epub = settings.cache_dir .. "/100/book.epub"
os.execute("mkdir -p " .. settings.cache_dir .. "/100"); local f = io.open(epub, "wb"); f:write("x"); f:close()
settings:_saveBook("100", { book_id = "100", title = "三体", cached_full_book = epub, progress = 37.4 })
settings:_saveBook("300", { book_id = "300", cached_chapters = { ["1"] = settings.cache_dir .. "/300/gone.html" } })
-- cover thumbnail for book 100 at weread's cache key (cover_cache.lua:45-55)
local cdir = settings.data_dir .. "/shelf-covers"; os.execute("mkdir -p " .. cdir)
local thumb = cdir .. "/" .. Crypto.md5_hex("https://cdn/a.jpg") .. ".thumb.png"
f = io.open(thumb, "wb"); f:write(string.rep("P", 64)); f:close()

l, e = Data.get_shelf(w)
check("get_shelf returns list", type(l) == "table", e)
check("MP excluded by default -> 3 books", l and #l == 3, l and #l)
check("sorted by readUpdateTime desc", l and l[1].bookId == "200" and l[2].bookId == "100" and l[3].bookId == "300")
local by = {}; for _, b in ipairs(l or {}) do by[b.bookId] = b end
check("title/author", by["100"].title == "三体" and by["100"].author == "刘慈欣")
check("cover local path found", by["100"].cover == thumb, by["100"].cover)
check("cover nil when no thumb", by["200"].cover == nil)
check("progress from reading_state.json", math.abs((by["100"].progress or -1) - 37.4) < 1e-9, by["100"].progress)
check("finished -> progress 100", by["200"].progress == 100 and by["200"].finished)
check("unknown progress -> nil", by["300"].progress == nil)
check("downloaded true for existing epub", by["100"].downloaded == true)
check("downloaded false when file missing", by["300"].downloaded == false)
check("downloaded false w/o record", by["200"].downloaded == false)
check("last_read", by["200"].last_read == 1800000000 and by["300"].last_read == 0)
local lm = Data.get_shelf(w, { include_mp = true })
check("include_mp -> 4", lm and #lm == 4)
check("format_mandatory", Data.format_mandatory(by["100"], function() return "11-14" end) == "✓  37%  11-14",
      Data.format_mandatory(by["100"], function() return "11-14" end))
check("format_text no author", Data.format_text(by["300"]) == "未下载")

-- 5. open_book routing
check("open downloaded -> openBookForReading", Data.open_book(w, "100") == true and w.calls[#w.calls][1] == "read")
check("open not downloaded -> showBookRecord", Data.open_book(w, "200") == true and w.calls[#w.calls][1] == "detail" and w.calls[#w.calls][2] == "200")
check("open MP -> showBookRecord", Data.open_book(w, "MP_WXS_1") == true and w.calls[#w.calls][1] == "detail")
check("open unknown id -> not_found", select(2, Data.open_book(w, "999")) == Data.ERR_NOT_FOUND)
w.openBookForReading = function() return false end
check("read returns false -> falls back to detail", Data.open_book(w, "100") == true and w.calls[#w.calls][1] == "detail")

-- 6. robustness: throwing library_db / corrupt db
local wb = make_weread(settings); wb.library_db = setmetatable({ getShelf = function() error("boom") end }, { __index = w.library_db })
check("getShelf throws -> ERR_DB, no crash", select(2, Data.get_shelf(wb)) == Data.ERR_DB)
local wc = make_weread(settings)
local s2 = make_settings{ vid = "999", api_key = "k" }; local wcorrupt = make_weread(s2)
local p2 = wcorrupt.library_db:databasePath(); f = io.open(p2, "wb"); f:write("not a sqlite db at all, garbage garbage"); f:close()
local r1, r2 = Data.get_shelf(wcorrupt)
check("corrupt db file -> error code, no crash", r1 == nil and (r2 == Data.ERR_DB or r2 == Data.ERR_NO_CACHE), r2)
local wnocov = make_weread(settings); wnocov.getShelfCoverCache = function() error("no cover module") end
local saved_crypto = package.loaded["weread.lib.crypto"]; package.loaded["weread.lib.crypto"] = nil
local ln = Data.get_shelf(wnocov)
package.loaded["weread.lib.crypto"] = saved_crypto
check("cover cache error, no crypto -> cover nil, list still ok", ln and #ln == 3 and ln[2].cover == nil)
Data._crypto = Crypto
ln = Data.get_shelf(wnocov)
check("cover cache error -> fallback path via Crypto.md5_hex", ln and ln[2].cover == thumb, ln and ln[2].cover)
Data._crypto = nil

os.execute("rm -rf " .. root)
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
