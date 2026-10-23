-- 0.6.2 realweidu_rank: parse / tabs / 换一批
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
local R = require("realweidu_rank")
local n, failed = 0, 0
local function check(name, ok) n = n + 1; if not ok then failed = failed + 1 end; print((ok and "ok   " or "FAIL ") .. name) end
local data = { books = { { bookInfo = { bookId = 123, title = "三体", author = "刘慈欣", cover = "https://x/s_1.jpg" }, newRating = 950 },
    { bookInfo = { title = "no id" } }, { bookId = "9", title = "flat" } } }
local l = R.parse(data)
check("parse bookInfo + flat, skips no-id", #l == 2 and l[1].bookId == "123" and l[1].title == "三体" and l[2].bookId == "9")
check("parse bad input", #R.parse(nil) == 0 and #R.parse({}) == 0)
check("url per tab", R.url("rising", 20):find("bookListInCategory/rising?maxIndex=20", 1, true) ~= nil)
check("tabs 神作榜 潜力榜", R.TABS[1].name == "神作榜" and R.TABS[2].name == "潜力榜")
local client = { get_text = function(_, url) return url:find("hot_search") and "REC" or "RANK" end,
    json_decode = function(_, t)
        local b = {}
        for i = 1, (t == "REC" and 10 or 6) do b[i] = { bookInfo = { bookId = t .. i, title = t .. i } } end
        return { books = b } end,
    get_binary = function() return nil end }
local ok = R.load(client, "/tmp/rw_rank_test", true)
local top = R.rank_books()
check("load rank top 5", ok and #top == 5 and top[1].bookId == "RANK1")
check("first batch 5", #R.batch() == 5 and R.batch()[1].bookId == "REC1")
check("换一批 -> next 5 (no fetch)", R.next_batch() == false and R.batch()[1].bookId == "REC6")
check("换一批 past end -> fetch next page", R.next_batch() == true and R.rec_offset == 10)
R.set_tab(2); check("switch tab", R.tab == 2 and #R.rank_books() == 0)
R.load(client, "/tmp/rw_rank_test"); check("tab 2 loaded", #R.rank_books() == 5)
check("fetch error surfaces", (function()
    local c = { get_text = function() return nil, 403 end }
    local b, e = R.fetch(c, "rising", 0); return b == nil and e == "HTTP 403" end)())
-- 0.6.4: home = selected tab only (5 covers) + 为你推荐 5
R.lists = {}; R.tab = 3; R.rec_page = 0; R.rec_offset = 0
R.load_all(client, "/tmp/rw_rank_test", true)
check("load_all fetches selected tab + rec only", R.any_loaded() and R.list(3) and not R.list(1) and #R.batch() == 5)
check("rank row = 5 books", #R.rank_books() == 5)
print(string.format("\n%d checks, %d failed", n, failed))
os.exit(failed == 0 and 0 or 1)
