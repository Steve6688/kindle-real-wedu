-- 0.4.5: middle round button = progress % + remaining time (chapter / book).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
local L = require("realweidu_logic")
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end

-- progress calc
check("pct 1/100", L.progress_pct(1, 100) == 1)
check("pct 37/100", L.progress_pct(37, 100) == 37)
check("pct last page = 100", L.progress_pct(250, 250) == 100)
check("pct rounds", L.progress_pct(1, 3) == 33 and L.progress_pct(2, 3) == 67)
check("pct clamps", L.progress_pct(0, 10) == 10 and L.progress_pct(99, 10) == 100)
check("pct unknown", L.progress_pct(nil, 10) == nil and L.progress_pct(3, 0) == nil and L.progress_pct(3, nil) == nil)
-- avg page time
local a, s = L.avg_page_secs({ avg_time = 45 }); check("avg from statistics avg_time", a == 45 and s == "stats")
a, s = L.avg_page_secs({ total_time_in_sec = 600, total_read_pages = 20 }); check("avg from book totals", a == 30 and s == "stats")
a, s = L.avg_page_secs({ avg_time = 0, total_time_in_sec = 0, total_read_pages = 0 }); check("zero stats -> default", a == 60 and s == "default")
a, s = L.avg_page_secs(nil); check("no stats -> default 1 page/min", a == 60 and s == "default")
a = L.avg_page_secs(nil, 2); check("custom default ppm", a == 30)
check("ppm 0 -> unknown", L.avg_page_secs(nil, 0) == nil)
-- pages left
check("book left", L.pages_left_book(40, 100) == 60 and L.pages_left_book(100, 100) == 0)
check("chapter left via next chapter", L.pages_left_chapter(40, 100, 52) == 12)
check("last chapter -> book end", L.pages_left_chapter(90, 100, nil) == 10)
check("bogus next chapter -> book end", L.pages_left_chapter(90, 100, 80) == 10)
-- formatting
check("fmt nil -> —", L.fmt_duration(nil) == "—")
check("fmt NaN -> —", L.fmt_duration(0/0) == "—")
check("fmt 0", L.fmt_duration(0) == "0分钟")
check("fmt <1min", L.fmt_duration(20) == "不到1分钟")
check("fmt mins", L.fmt_duration(12 * 60) == "12分钟")
check("fmt hours", L.fmt_duration(2 * 3600) == "2小时")
check("fmt h+m", L.fmt_duration(2 * 3600 + 10 * 60) == "2小时10分钟")
-- full info: per chapter / per book
local i = L.progress_info(40, 100, 52, { avg_time = 30 })
check("info pct", i.pct == 40 and i.pct_text == "40%")
check("info chapter 12p*30s=6min", i.chapter_text == "6分钟")
check("info book 60p*30s=30min", i.book_text == "30分钟")
check("info source stats", i.source == "stats")
i = L.progress_info(40, 100, 52, nil)
check("no-stats fallback chapter 12min", i.chapter_text == "12分钟" and i.source == "default")
check("no-stats fallback book 1h", i.book_text == "1小时")
i = L.progress_info(nil, nil, nil, nil)
check("unknown doc -> all —", i.pct_text == "—" and i.chapter_text == "—" and i.book_text == "—")
-- source-level: menu wiring
local f = io.open(here .. "/../realweidu.koplugin/realweidu_readermenu.lua"); local src = f:read("*a"); f:close()
check("middle button uses pct + card", src:find('draw = "pct",%s+fn = function%(%) self:toggleProgressCard%(%)') ~= nil)
check("card uses partial ui refresh", src:find('self.progress_open = not self.progress_open\n    self:refresh%("ui"%)') ~= nil)
check("reads KOReader statistics", src:find("ui.statistics") ~= nil and src:find("avg_time = st.avg_time", 1, true) ~= nil)
check("A button untouched", src:find('local name = self.font_open and "rm_font_active" or "rm_font"', 1, true) ~= nil)
local blk = (src:match("%-%- 0%.4%.5 middle button(.-)function RM:showProgress") or ""):gsub("%-%-[^\n]*", "")
check("card adds no animation/TTS code", #blk > 0 and not blk:find("[Aa]nimat") and not blk:find("TTS") and not blk:find("ReadAloud"))
print(string.format("\n%d checks, %d failed", n, fails)); os.exit(fails == 0 and 0 or 1)
