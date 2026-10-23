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
-- 0.4.6: card above slider / arrows; no 听 button
check("card anchored above whole panel + float", src:find("self:_progressCard(g, H - (m.stats_h + m.slider_h + m.pills_h + m.icon_h + U.px(20)) - m.float_d - U.px(20))", 1, true) ~= nil)
check("slider rect covers ‹ › (margin to margin)", src:find("self.slider_rect = rect(m.margin, y, W - 2 * m.margin, m.slider_h)", 1, true) ~= nil)
do -- geometry at PW5 (px == identity scale assumption irrelevant: same unit on both sides)
    local H, stats_h, slider_h, pills_h, icon_h, pad, float_d, gap20, ch, gap12 = 1648, 150, 110, 110, 140, 20, 96, 20, 150, 12
    local panel_y = H - (stats_h + slider_h + pills_h + icon_h + pad)
    local card_bottom = (panel_y - float_d - gap20 - ch - gap12) + ch
    local slider_top = panel_y + 16 + stats_h
    check("card bottom above slider top", card_bottom <= slider_top)
    check("card bottom above AI float top", card_bottom <= panel_y - float_d - gap20)
end
check("0.4.7: no 听 float button", not src:find('float%("听"') and not src:find("x_tts", 1, true))
check("0.4.7: AI float kept, at right edge", src:find('float("AI", x_ai', 1, true) ~= nil and src:find("local x_ai = W - m.margin - d\n", 1, true) ~= nil)
-- 0.4.8: classic 0.3.6 bars + progress circle + TOC sidebar
check("fmt_short", L.fmt_short(nil) == "—" and L.fmt_short(20) == "<1分" and L.fmt_short(300) == "余5分" and L.fmt_short(7200) == "余2时")
i = L.progress_info(40, 100, 52, { avg_time = 30 })
check("info exposes chapter/book secs", i.chapter_secs == 360 and i.book_secs == 1800)
check("TOC sidebar 80%", L.TOC_SIDEBAR_FRAC == 0.8)
local bld = src:match("function RM:_build%(%)(.-)\nend") or ""
check("_build uses classic bars only (no official panel/floats)", bld:find("_classicTopBar", 1, true) and bld:find("_classicBottomBar", 1, true)
    and not bld:find("self:_bottomBar", 1, true) and not bld:find("self:_topBar", 1, true))
local cb = src:match("function RM:_classicBottomBar(.-)\nend") or ""
check("classic bar draws no floats", #cb > 0 and not cb:find("_floatButtons", 1, true))
check("bottom = ← ≡ progress -o- A", src:find('{ icon = "rm_back",       fn = "back" },\n    { icon = "rm_toc",        fn = "showTocSheet" }, %-%- 0.4.8: left sidebar TOC\n    { icon = "progress",      fn = "toggleProgressCard" }') ~= nil
    and src:find('{ icon = "rm_brightness", fn = "showClassicBrightness" },\n    { icon = "rm_font",       fn = "toggleFont" },', 1, true) ~= nil)
local tb = src:match("function RM:_classicTopBar(.-)\nend") or ""
check("top = ‹ title | bookmark | more", tb:find("back_chevron", 1, true) and tb:find("bookmark_active", 1, true) and tb:find('U.icon("more"', 1, true))
check("TOC tap outside sidebar closes", src:find("tap outside dismisses TOC", 1, true) and src:find("self.toc_rect = rect(0, 0, PW, H)", 1, true))
do local W, H, bar = 1236, 1648, 130; local card_y = H - bar - 150 - 12
   check("card sits above bottom bar", card_y + 150 <= H - bar) end
-- 0.4.9: TOC sidebar pagination with a 100-chapter TOC
do
    local toc = {}; for k = 1, 100 do toc[k] = { title = "第" .. k .. "章", page = k * 5 } end
    local per = L.toc_rows_per_page(1648 - 120 - 110, 88)
    check("rows per page at PW5 = 16", per == 16)
    local count = L.toc_page_count(#toc, per)
    check("100 chapters -> 7 pages", count == 7)
    check("rows_per_page never 0", L.toc_rows_per_page(10, 88) == 1 and L.toc_rows_per_page(nil, 88) == 1)
    check("empty toc -> 1 page", L.toc_page_count(0, per) == 1)
    local idx = L.toc_current_index(toc, 252)
    check("current chapter index (page 252 -> ch 50)", idx == 50)
    check("opens on current chapter's page", L.toc_page_of(idx, per) == 4)
    local f, l = L.toc_page_range(4, per, #toc)
    check("page 4 shows 49..64 incl. current", f == 49 and l == 64 and idx >= f and idx <= l)
    f, l = L.toc_page_range(7, per, #toc)
    check("last page 97..100", f == 97 and l == 100)
    check("swipe up = next, down = prev", L.toc_swipe_delta("north") == 1 and L.toc_swipe_delta("south") == -1)
    check("swipe left = next, right = prev", L.toc_swipe_delta("west") == 1 and L.toc_swipe_delta("east") == -1)
    check("diagonal/unknown no-op", L.toc_swipe_delta("northeast") == 0 and L.toc_swipe_delta(nil) == 0)
    check("clamp at ends", L.toc_clamp_page(0, 7) == 1 and L.toc_clamp_page(8, 7) == 7)
    -- walk all pages by swiping: every chapter reachable exactly once
    local seen, p = {}, 1
    for _ = 1, 20 do
        local a, b = L.toc_page_range(p, per, #toc); for k = a, b do seen[k] = (seen[k] or 0) + 1 end
        local np = L.toc_clamp_page(p + L.toc_swipe_delta("north"), count); if np == p then break end; p = np
    end
    local ok = true; for k = 1, 100 do if seen[k] ~= 1 then ok = false end end
    check("swiping through reaches all 100 chapters once", ok)
    check("menu registers Swipe gesture", src:find('Swipe = { GestureRange:new{ ges = "swipe"', 1, true) ~= nil)
    check("onSwipe pages TOC", src:find("function RM:onSwipe", 1, true) and src:find("self:tocTurn(d)", 1, true))
    check("footer ‹ 上一页 n/m 下一页 ›", src:find('"‹ 上一页"', 1, true) and src:find('"下一页 ›"', 1, true) and src:find('self.toc_page .. " / " .. count', 1, true))
    check("open resets to current chapter page", src:find("self.toc_page = nil %-%- reopen on the current chapter's page") ~= nil)
    check("right blank strip still closes", src:find("tap outside dismisses TOC", 1, true) ~= nil)
end
-- 0.5.0: 生词本 entry in ⋯ menu, other buttons unchanged
do
    local more = src:match("function RM:showMore%(%)(.-)\nend\n") or ""
    check("⋯ menu has 生词本", more:find('item("生词本", function() self:openVocabBuilder() end)', 1, true) ~= nil)
    local n_items = select(2, more:gsub("\n%s+item%(", ""))
    local others = true
    for _, t in ipairs({ "书签列表", "下载并匹配划线/想法", "搜索全书", "书籍详情", "刷新屏幕", "KOReader 原生菜单", "添加书签" }) do
        if not more:find(t, 1, true) then others = false end
    end
    check("⋯ menu keeps the other 7 items (+生词本 +查词模式 = 9)", n_items == 9 and others)
    check("opens KOReader vocabbuilder", src:find('send(self.ui, "ShowVocabBuilder")', 1, true) ~= nil and src:find("self.ui.vocabbuilder", 1, true) ~= nil)
    check("graceful when plugin disabled", src:find("生词本插件未启用", 1, true) ~= nil)
    check("bottom bar unchanged", src:find('{ icon = "rm_brightness", fn = "showClassicBrightness" },\n    { icon = "rm_font",       fn = "toggleFont" },', 1, true) ~= nil)
end
-- 0.5.0: 查词模式
do
    local E = L.LOOKUP_EDGE
    check("edge strip default 12%", E == 0.12)
    check("off -> always pass (tap-to-turn unchanged)", L.lookup_tap_action(false, 618, 1236) == "pass" and L.lookup_tap_action(nil, 618, 1236) == "pass")
    check("on, centre -> lookup", L.lookup_tap_action(true, 618, 1236) == "lookup")
    check("on, left strip -> pass", L.lookup_tap_action(true, 0, 1236) == "pass" and L.lookup_tap_action(true, 147, 1236) == "pass")
    check("on, right strip -> pass", L.lookup_tap_action(true, 1235, 1236) == "pass" and L.lookup_tap_action(true, 1236 - 148, 1236) == "pass")
    check("on, just inside strips -> lookup", L.lookup_tap_action(true, 148, 1236) == "lookup" and L.lookup_tap_action(true, 1236 - 149, 1236) == "lookup")
    check("bad input -> pass", L.lookup_tap_action(true, nil, 1236) == "pass" and L.lookup_tap_action(true, 5, 0) == "pass")
    local more = src:match("function RM:showMore%(%)(.-)\nend\n") or ""
    check("⋯ menu has 查词模式 toggle", more:find("查词模式：开", 1, true) and more:find("查词模式：关", 1, true) and more:find("self:toggleLookupMode()", 1, true))
    check("toggle persists in G_reader_settings", src:find("G:saveSetting(Logic.LOOKUP_SETTING, on)", 1, true) ~= nil and L.LOOKUP_SETTING == "realweidu_lookup_mode")
    local f = io.open(here .. "/../realweidu.koplugin/main.lua"); local msrc = f:read("*a"); f:close()
    check("reader registers lookup tap zone overriding page turn", msrc:find('id = "realweidu_lookup_tap"', 1, true) and msrc:find('"tap_forward", "tap_backward"', 1, true))
    check("lookup handler uses zone helper + dictionary", msrc:find("Logic.lookup_tap_action(RealWeidu.lookupModeOn()", 1, true) and msrc:find("ui.dictionary.onLookupWord", 1, true))
    check("no word -> falls through", msrc:find("no word: page turn / menu", 1, true) ~= nil)
    check("auto-add: vocabbuilder enabled only during lookup", msrc:find("vs.enabled = english; restore = true", 1, true) and msrc:find("if restore then vs.enabled = prev end", 1, true))
    check("bottom bar still unchanged", src:find('{ icon = "rm_brightness", fn = "showClassicBrightness" },', 1, true) ~= nil)
end
-- 0.5.1: 查词模式 only stores English words in the vocabulary builder
do
    local W = L.is_english_word
    check("english words accepted", W("serendipity") and W("Hello") and W("  word\n") and W("don't") and W("don\226\128\153t") and W("well-known") and W("o'clock"))
    check("chinese rejected", not W("李善德") and not W("和尚") and not W("佛"))
    check("mixed / non-Latin rejected", not W("hello世界") and not W("café") and not W("Привет") and not W("こんにちは") and not W("123") and not W("x2"))
    check("empty / punctuation / bad input rejected", not W("") and not W("   ") and not W("'") and not W("--") and not W(nil) and not W(42) and not W("two words"))
    local f = io.open(here .. "/../realweidu.koplugin/main.lua"); local msrc = f:read("*a"); f:close()
    check("lookup gates vocab on is_english_word", msrc:find("local english = Logic.is_english_word(text)", 1, true) ~= nil)
    check("vocab enabled flag forced to english-ness and restored", msrc:find("vs.enabled = english; restore = true", 1, true) and msrc:find("if restore then vs.enabled = prev end", 1, true))
    check("fallback WordLookedUp only for english", msrc:find('if english and type(vs) ~= "table" and ui.vocabbuilder then', 1, true) ~= nil)
    local meta = io.open(here .. "/../realweidu.koplugin/_meta.lua"):read("*a")
    check("version 0.5.1", meta:find('"0.5.1"', 1, true) and msrc:find('RealWeidu.VERSION = "0.5.1"', 1, true))
end
print(string.format("\n%d checks, %d failed", n, fails)); os.exit(fails == 0 and 0 or 1)
