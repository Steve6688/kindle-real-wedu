-- Smoke test for main.lua with stubbed KOReader modules (no SimpleUI: removed in 0.3.7) (not real UI).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../wereadshelf.koplugin/?.lua;" .. package.path
local shown, ticks, closed = {}, {}, {}
local function cls() local c = {}; c.__index = c
    function c:extend(t) t = t or {}; t.__index = t; return setmetatable(t, { __index = self }) end
    function c:new(t) t = t or {}; return setmetatable(t, { __index = self }) end
    return c end
package.loaded["ui/uimanager"] = { show = function(_, w) shown[#shown+1] = w end,
    close = function(_, w) closed[#closed+1] = w; if w and w.onCloseWidget then w:onCloseWidget() end end,
    nextTick = function(_, f) ticks[#ticks+1] = f end, askForRestart = function() _G.restart_asked = true end }
package.loaded["ui/widget/container/widgetcontainer"] = cls()
package.loaded["ui/widget/infomessage"] = cls()
package.loaded["ui/widget/confirmbox"] = cls()
package.loaded["ui/widget/menu"] = cls()
package.loaded["ui/widget/inputdialog"] = cls()
package.loaded["logger"] = { warn = print }
-- grid widget stub (real widget needs KOReader; covered by the box emulator run)
local Grid = cls()
function Grid:setKeyword(k) self.keyword = k end
function Grid:onCloseWidget() end
package.loaded["wereadshelf_grid"] = Grid
package.loaded["wereadshelf_ui"] = { icons_dir = "." }
local Pages = { Discover = cls(), Me = cls() }
function Pages.Me:refresh() self.refreshed = (self.refreshed or 0) + 1 end
package.loaded["wereadshelf_pages"] = Pages
local RMcls = cls()
package.loaded["wereadshelf_readermenu"] = RMcls
package.loaded["ui/widget/buttondialog"] = cls()
package.loaded["ui/event"] = { new = function(_, name, ...) return { name = name, args = { ... } } end }
local broadcast = {}
package.loaded["ui/uimanager"].broadcastEvent = function(_, ev) broadcast[#broadcast + 1] = ev end
package.loaded["ui/uimanager"].scheduleIn = function(_, _t, f) ticks[#ticks + 1] = f end
-- in-memory LuaSettings
local function mem_settings() local d = {}
    return { readSetting = function(_, k) return d[k] end, saveSetting = function(_, k, v) d[k] = v end,
        delSetting = function(_, k) d[k] = nil end, isTrue = function(_, k) return d[k] == true end,
        flush = function() end, _d = d } end
package.loaded["ui/elements/filemanager_menu_order"] = { main = { "history", "exit_menu" } }

local P = dofile(here .. "/../wereadshelf.koplugin/main.lua")
local S = mem_settings(); P._settings_override = S
local menu_items = {}
local inst = P:new{ ui = { menu = { registerToMainMenu = function(_, p) p:addToMainMenu(menu_items) end } }, path = "/x" }
inst:init(); for _, f in ipairs(ticks) do f() end
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
check("main menu has four focused actions", menu_items.wereadshelf ~= nil
    and #menu_items.wereadshelf.sub_item_table == 4
    and menu_items.wereadshelf.sub_item_table[4].text == "更多设置…"
    and menu_items.wereadshelf.sub_item_table[1].text == "打开 Real微读"
    and menu_items.wereadshelf.sub_item_table[2].text == "登录、同步与管理书架")
check("v0.3.5 default ON: fresh install startup opens Real微读 (no weread yet -> its notice)",
    #shown == 1 and tostring(shown[1].text):find("weread.koplugin") ~= nil)
check("v0.3.7 no SimpleUI writes / backups", S:readSetting("preset_backup") == nil and S:readSetting("landing_backup") == nil)
check("v0.3.7 no SimpleUI-only functions left", P.applyPreset == nil and P.registerSimpleUIStatic == nil and P.backToNative == nil)
check("v0.3.5 reader menu default ON", P.isOn("reader_menu"))
UIManager_stack = package.loaded["ui/uimanager"]
UIManager_stack._window_stack = { { widget = { name = "sui_homescreen" } } }
local before_top = #shown
check("stale SimpleUI Home Screen on top -> shelf re-raised", P.ensureOnTop() and #shown == before_top + 1)
UIManager_stack._window_stack = nil
check("v0.3.5 ☰ entry pinned first", package.loaded["ui/elements/filemanager_menu_order"].main[1] == "wereadshelf_enter")
-- no weread loaded -> friendly InfoMessage, no crash
P.showGrid()
check("no weread -> InfoMessage shown", shown[#shown] and tostring(shown[#shown].text):find("weread.koplugin") ~= nil)
P.showDiscover()
check("discover w/o weread -> InfoMessage", shown[#shown] and shown[#shown].text ~= nil)
-- logged-out weread -> ConfirmBox with login button
package.loaded["apps/filemanager/filemanager"] = { instance = { weread = {
    library_db = { accountKey = function() return nil end },
    settings = { is_api_configured = function() return false end },
    openBookshelf = function() end } } }
P.showGrid()
check("logged out -> ConfirmBox", shown[#shown] and shown[#shown].ok_text == "打开微信读书")
-- logged in with shelf -> grid
local calls = {}
local fm = package.loaded["apps/filemanager/filemanager"].instance
fm.weread = {
    library_db = { accountKey = function() return "k" end,
        getShelf = function() return { { bookId = "1", title = "T", author = "A", readUpdateTime = 5 },
                                       { bookId = "2", title = "U", author = "B", readUpdateTime = 9 } } end },
    settings = { is_api_configured = function() return true end, get = function() return {} end },
    openBookshelf = function() calls.shelf = true end,
    showBookRecord = function(_, b) _G.opened = b.bookId end,
    showSearch = function() calls.search = true end,
    searchWithUI = function(_, kw) calls.search_kw = kw end,
    showReadStats = function() calls.stats = true end }
check("direct weread management entry", P.openWereadManagement() and calls.shelf)
P.showGrid()
local g = shown[#shown]
check("grid shown with 2 books", g and g.books and #g.books == 2 and g.icons_dir == "/x/icons")
check("grid placeholder = first title", g.placeholder == "U" or g.placeholder == "T")
g.on_open(g.books[2])
check("tap cover -> open_book", _G.opened == g.books[2].bookId)
g.on_import(); check("导入 -> weread openBookshelf", calls.shelf)
-- BUG-07: 导入 failing inside weread -> error notice (via call_weread)
local orig_ob = fm.weread.openBookshelf
fm.weread.openBookshelf = function() error("db locked") end
g.on_import(); check("BUG-07 导入 error -> notice", tostring(shown[#shown].text):find("db locked") ~= nil)
fm.weread.openBookshelf = orig_ob
g.on_select(); check("选择 -> phase-2 notice", tostring(shown[#shown].text):find("二期") ~= nil)
-- re-tap 书架 tab while grid open: old one closed, page kept
g.page = 3
P.showGrid()
local g2 = shown[#shown]
check("re-tap closes old grid", closed[#closed] == g and g2 ~= g and g2.page == 3)
-- search dialog buttons
P.showSearchDialog(g2)
local dlg = shown[#shown]
dlg.getInputText = function() return "U" end
dlg.buttons[2][1].callback()
check("书架内筛选 -> grid keyword", g2.keyword == "U")
P.showSearchDialog(g2); dlg = shown[#shown]; dlg.getInputText = function() return "三体" end
dlg.buttons[2][2].callback()
check("微信读书搜索 -> weread searchWithUI", calls.search_kw == "三体")
calls.search = nil
P.showDiscover()
local dp = shown[#shown]
check("发现 page shown, grid closed", getmetatable(dp).__index == Pages.Discover and closed[#closed] == g2)
check("发现 entries only for existing weread methods", #dp.entries == 2) -- showSearch + openBookshelf in this stub
check("发现 recent from shelf", dp.books and #dp.books == 2)
dp.on_search(); check("发现 search -> weread showSearch", calls.search)
dp.on_open(dp.books[1]); check("发现 recent tap -> open_book", _G.opened == dp.books[1].bookId)
check("发现 has own bar nav callbacks", dp.on_nav_shelf and dp.on_nav_me)
-- 我 page
fm.weread.settings.get = function(_, k, d) if k == "account" then return { name = "小明" } end return d end
fm.weread.isNetworkOnline = function() return true end
fm.weread.runOnlineTask = function(_, _l, cb) cb(); return true end
fm.weread.client = { get_read_stats = function(_, mode)
    _G.stats_mode = mode
    return { totalReadTime = 3630, readStat = { { stat = "笔记", counts = "12条" } } } end }
P.showMe()
local mp = shown[#shown]
check("我 page shown, discover closed", getmetatable(mp).__index == Pages.Me and closed[#closed] == dp)
check("我 account name", mp.account_name == "小明")
check("v0.3.7 我 rows = all items directly (no 更多设置 level)", #mp.rows == 9 and mp.footer == "Real微读 0.3.7")
check("v0.3.6 我 does not hit the network on open", _G.stats_mode == nil)
local function find_btn(page, pat)
    for _, row in ipairs(page.rows) do if row.text:find(pat) then return { callback = row.fn, text = row.text, bold = row.bold } end end
end
local md = mp
check("我 keeps every feature", find_btn(md, "阅读时长统计") and find_btn(md, "我的笔记")
    and find_btn(md, "书架同步") and find_btn(md, "Real微读阅读菜单") and find_btn(md, "快速下载")
    and find_btn(md, "KOReader 设置") and find_btn(md, "退出到 Kindle") and find_btn(md, "返回 KOReader")
    and not find_btn(md, "更多设置") and not find_btn(md, "SimpleUI"))
check("last row = 返回 KOReader (bold)", mp.rows[9].text == "返回 KOReader" and mp.rows[9].bold)
local before_rows = mp.rows
find_btn(md, "Real微读阅读菜单").callback()
check("switch toggles and 我 rows update in place", mp.rows ~= before_rows and (mp.refreshed or 0) >= 1
    and mp.rows[5].text:find("　") == 1)
find_btn(mp, "Real微读阅读菜单").callback()
find_btn(md, "阅读时长统计").callback(); check("阅读时长统计 -> showReadStats", calls.stats)
find_btn(md, "我的笔记").callback(); check("我的笔记 -> honest notice", tostring(shown[#shown].text):find("没有") ~= nil)
find_btn(md, "刷新本周阅读").callback()
check("刷新本周阅读 -> weekly stats", _G.stats_mode == "weekly" and S:readSetting("stats_cache").week_min == 61
    and S:readSetting("stats_cache").notes == 12 and tostring(shown[#shown].text):find("61"))
-- BUG-04: refresh returning nil / raising -> failure reported, cache kept
local old_client = fm.weread.client
local got
fm.weread.client = { get_read_stats = function() return nil end }
P.refreshStats(fm.weread, function(good) got = good end, false)
check("BUG-04 nil stats -> failure", got == false)
fm.weread.client = { get_read_stats = function() error("HTTP 500") end }
P.refreshStats(fm.weread, function(good, err) got = { good, err } end, false)
check("BUG-04 error -> failure with reason", got[1] == false and tostring(got[2]):find("HTTP 500") ~= nil)
check("BUG-04 cache kept after failure", S:readSetting("stats_cache").week_min == 61)
fm.weread.client = old_client
-- active icon

P.exitToKindle(); check("exit to Kindle = KOReader Exit event", broadcast[#broadcast] and broadcast[#broadcast].name == "Exit")
-- reader hook
local zones
local rui = { document = {}, registerTouchZones = function(_, z) zones = z end }
S:saveSetting("reader_menu", true)
local rinst = P:new{ ui = rui, path = "/x" }; rinst:init()
check("reader: centre zone registered", zones and zones[1].id == "wereadshelf_menu_tap" and zones[1].overrides[1] == "tap_forward"
    and zones[1].screen_zone.ratio_x == 0.25 and zones[1].screen_zone.ratio_w == 0.5)
zones[1].handler()
check("reader: tap shows WeRead menu", getmetatable(shown[#shown]).__index == RMcls and shown[#shown].ui == rui)
S:saveSetting("reader_menu", false); zones = nil
P:new{ ui = rui, path = "/x" }:init()
check("reader: no hook when setting off", zones == nil)
-- v0.3.4 enter / exit
check("top-level menu entry 进入 Real微读", menu_items.wereadshelf_enter and menu_items.wereadshelf_enter.text == "进入 Real微读")
P.leaveToKOReader()
check("返回 KOReader pauses auto-enter for this session", not P.shouldAutoEnter())
ticks = {}; P:new{ ui = { menu = { registerToMainMenu = function() end } }, path = "/x" }:init()
local nshown = #shown; for _, f in ipairs(ticks) do f() end
check("paused: FM re-init does not open shelf", #shown == nshown)
local before = #shown; menu_items.wereadshelf_enter.callback()
check("menu entry re-enters shelf + clears pause", #shown == before + 1 and P.shouldAutoEnter())
ticks = {}; P:new{ ui = { menu = { registerToMainMenu = function() end } }, path = "/x" }:init()
nshown = #shown; for _, f in ipairs(ticks) do f() end
check("always on: FM init (start / book closed) opens shelf", #shown > nshown and shown[#shown].active_action_id == "wereadshelf_open")
local homed = false
local rui2 = { document = {}, onHome = function() homed = true end }
local ri2 = P:new{ ui = rui2, path = "/x" }
check("dispatcher event from reader closes book", ri2:onWeReadShelfOpen() and homed)
-- BUG-06: empty (but readable) shelf -> empty grid, not the 未同步 dialog
local orig_gs = fm.weread.library_db.getShelf
fm.weread.library_db.getShelf = function() return {} end
P.showGrid()
local eg = shown[#shown]
check("BUG-06 empty shelf -> grid with 0 books", eg and eg.books and #eg.books == 0 and eg.on_import ~= nil)
fm.weread.library_db.getShelf = orig_gs
print(string.format("\n%d checks, %d failed", n, fails)); print(fails == 0 and "smoke ok" or "smoke FAILED")
os.exit(fails == 0 and 0 or 1)
