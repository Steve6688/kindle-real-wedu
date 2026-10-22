-- Smoke test for main.lua with stubbed KOReader/SimpleUI modules (not real UI).
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
-- SimpleUI stubs
local reg = {}
package.loaded["features/sui_quickactions"] = { register = function(d) reg[d.id] = d end,
    isRegistered = function(id) return reg[id] ~= nil end }
local invalidated = false
local store = { simpleui_bar_tabs = { "home", "history" }, simpleui_bar_mode = "both" }
local Store = { get = function(_, k) return store[k] end, set = function(_, k, v) store[k] = v end,
    del = function(_, k) store[k] = nil end }
package.loaded["infra/sui_store"] = Store
package.loaded["infra/sui_config"] = { invalidateTabsCache = function() invalidated = true end,
    saveTabConfig = function(t) _G.tabs_writes = (_G.tabs_writes or 0) + 1; store.simpleui_bar_tabs = t end,
    saveNavbarMode = function(m) _G.mode_writes = (_G.mode_writes or 0) + 1; store.simpleui_bar_mode = m end }
local bi = {}
package.loaded["ui/elements/filemanager_menu_order"] = { main = { "history", "exit_menu" } }
package.loaded["infra/sui_core"] = { BarInjection = { register = function(d) bi[d.id] = d end } }

local P = dofile(here .. "/../wereadshelf.koplugin/main.lua")
local S = mem_settings(); P._settings_override = S
local menu_items = {}
local inst = P:new{ ui = { menu = { registerToMainMenu = function(_, p) p:addToMainMenu(menu_items) end } }, path = "/x" }
inst:init(); for _, f in ipairs(ticks) do f() end
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
check("QA shelf registered (id kept from v0.1)", reg.wereadshelf_open ~= nil and reg.wereadshelf_open.is_in_place)
check("QA discover + me registered", reg.wereadshelf_discover ~= nil and reg.wereadshelf_me ~= nil)
check("tabs cache invalidated", invalidated)
check("BarInjection registered for grid", bi.wereadshelf_grid and bi.wereadshelf_grid.widget_name == "wereadshelf_grid"
    and bi.wereadshelf_grid.active_action_id == "wereadshelf_open" and bi.wereadshelf_grid.is_pageable == true)
check("shelf icon outline when grid closed", reg.wereadshelf_open.get_icon("wereadshelf_open") == "/x/icons/tab_shelf.svg")
check("main menu has four focused actions", menu_items.wereadshelf ~= nil
    and #menu_items.wereadshelf.sub_item_table == 4
    and menu_items.wereadshelf.sub_item_table[4].text == "更多设置…"
    and menu_items.wereadshelf.sub_item_table[1].text == "打开 Real微读"
    and menu_items.wereadshelf.sub_item_table[2].text == "登录、同步与管理书架")
check("v0.3.5 default ON: fresh install startup opens Real微读 (no weread yet -> its notice)",
    #shown == 1 and tostring(shown[1].text):find("weread.koplugin") ~= nil)
check("v0.3.5 first run sets SimpleUI bar once, with backup", S:readSetting("setup_done") == true
    and store.simpleui_bar_tabs[2] == "wereadshelf_open" and S:readSetting("preset_backup").simpleui_bar_mode == "both")
check("v0.3.5 reader menu default ON", P.isOn("reader_menu"))
check("v0.3.5 SimpleUI landing handed to us (close target + onboarding)", store.simpleui_hs_book_close_target == "library"
    and store.simpleui_onboarding_done == true and S:readSetting("landing_backup")._saved)
UIManager_stack = package.loaded["ui/uimanager"]
UIManager_stack._window_stack = { { widget = { name = "sui_homescreen" } } }
local before_top = #shown
check("v0.3.5 shelf re-raised over SimpleUI Home Screen", P.ensureOnTop() and #shown == before_top + 1)
UIManager_stack._window_stack = nil
P.restoreLandingDefaults()
check("v0.3.5 landing restore", store.simpleui_hs_book_close_target == nil and store.simpleui_onboarding_done == nil)
P.restorePreset() -- back to the user's original bar for the tests below
check("v0.3.5 ☰ entry pinned first", package.loaded["ui/elements/filemanager_menu_order"].main[1] == "wereadshelf_enter")
-- no weread loaded -> friendly InfoMessage, no crash
reg.wereadshelf_open.execute({})
check("no weread -> InfoMessage shown", shown[#shown] and tostring(shown[#shown].text):find("weread.koplugin") ~= nil)
reg.wereadshelf_discover.execute({})
check("discover w/o weread -> InfoMessage", shown[#shown] and shown[#shown].text ~= nil)
check("BarInjection for discover/me pages", bi.wereadshelf_discover and bi.wereadshelf_discover.active_action_id == "wereadshelf_discover"
    and bi.wereadshelf_me and bi.wereadshelf_me.is_pageable == false)
-- logged-out weread -> ConfirmBox with login button
package.loaded["apps/filemanager/filemanager"] = { instance = { weread = {
    library_db = { accountKey = function() return nil end },
    settings = { is_api_configured = function() return false end },
    openBookshelf = function() end } } }
reg.wereadshelf_open.execute({})
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
reg.wereadshelf_open.execute({})
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
reg.wereadshelf_open.execute({})
local g2 = shown[#shown]
check("shelf icon solid while grid open", reg.wereadshelf_open.get_icon("x") == "/x/icons/tab_shelf_active.svg"
    and reg.wereadshelf_me.get_icon("x") == "/x/icons/tab_me.svg")
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
reg.wereadshelf_discover.execute({})
local dp = shown[#shown]
check("发现 page shown, grid closed", getmetatable(dp).__index == Pages.Discover and closed[#closed] == g2)
check("发现 entries only for existing weread methods", #dp.entries == 2) -- showSearch + openBookshelf in this stub
check("发现 recent from shelf", dp.books and #dp.books == 2)
dp.on_search(); check("发现 search -> weread showSearch", calls.search)
dp.on_open(dp.books[1]); check("发现 recent tap -> open_book", _G.opened == dp.books[1].bookId)
check("发现 icon solid", reg.wereadshelf_discover.get_icon("x") == "/x/icons/tab_discover_active.svg")
-- 我 page
fm.weread.settings.get = function(_, k, d) if k == "account" then return { name = "小明" } end return d end
fm.weread.isNetworkOnline = function() return true end
fm.weread.runOnlineTask = function(_, _l, cb) cb(); return true end
fm.weread.client = { get_read_stats = function(_, mode)
    _G.stats_mode = mode
    return { totalReadTime = 3630, readStat = { { stat = "笔记", counts = "12条" } } } end }
reg.wereadshelf_me.execute({})
local mp = shown[#shown]
check("我 page shown, discover closed", getmetatable(mp).__index == Pages.Me and closed[#closed] == dp)
check("我 account name", mp.account_name == "小明")
check("v0.3.6 我 = header + 更多设置 + 返回 KOReader only", #mp.rows == 2 and mp.rows[1].text == "更多设置"
    and mp.rows[2].text == "返回 KOReader" and not mp.show_stats and mp.footer == "Real微读 0.3.6")
check("v0.3.6 我 does not hit the network on open", _G.stats_mode == nil)
mp.rows[1].fn()
local md = shown[#shown]
local function find_btn(dlg, pat)
    for _, row in ipairs(dlg.buttons) do if row[1].text:find(pat) then return row[1] end end
end
check("更多设置 keeps every feature", md.title == "更多设置" and find_btn(md, "阅读时长统计") and find_btn(md, "我的笔记")
    and find_btn(md, "书架同步") and find_btn(md, "Real微读阅读菜单") and find_btn(md, "快速下载")
    and find_btn(md, "KOReader 设置") and find_btn(md, "恢复 SimpleUI") and find_btn(md, "退出到 Kindle"))
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
check("我 icon solid, shelf outline", reg.wereadshelf_me.get_icon("x") == "/x/icons/tab_me_active.svg"
    and reg.wereadshelf_open.get_icon("x") == "/x/icons/tab_shelf.svg")
-- active icon

-- preset apply / restore
check("preset apply ok", P.applyPreset())
check("preset tabs", store.simpleui_bar_tabs[1] == "wereadshelf_discover" and store.simpleui_bar_tabs[2] == "wereadshelf_open"
    and store.simpleui_bar_tabs[3] == "wereadshelf_me" and #store.simpleui_bar_tabs == 3)
check("v0.3.6 preset icons-only, no ‹ › arrows", store.simpleui_bar_mode == "icons" and store.simpleui_bar_navpager_enabled == false)
P.applyPreset() -- second apply must not overwrite the original backup
check("backup kept original", S:readSetting("preset_backup").simpleui_bar_mode == "both")
check("restore ok", P.restorePreset())
check("restored tabs/mode", store.simpleui_bar_tabs[1] == "home" and store.simpleui_bar_mode == "both"
    and store.simpleui_bar_navpager_enabled == nil)
check("restore twice -> error", not P.restorePreset())
-- SimpleUI prunes our tab ids before we register; restore logic
local T = P.tabsToRestore
check("restore: nothing of ours -> nil", T({ "home", "history" }, { "home", "history" }) == nil)
check("restore: not pruned -> nil", T({ "wereadshelf_open", "home" }, { "wereadshelf_open", "home" }) == nil)
local r = T({ "wereadshelf_discover", "wereadshelf_open", "wereadshelf_me" }, {})
check("restore: pruned -> original order", r and #r == 3 and r[1] == "wereadshelf_discover" and r[3] == "wereadshelf_me")
local r2 = T({ "home", "wereadshelf_open", "other_plugin_qa" }, { "home" }, function(id) return id == "home" end)
check("restore: keeps only valid foreign ids", r2 and #r2 == 2 and r2[2] == "wereadshelf_open")
check("restore: no snapshot -> nil", T(nil, {}) == nil)
-- 微信读书模式 / 一键回原生
S:saveSetting("reader_menu", false); S:saveSetting("open_on_start", false)
store.simpleui_bar_tabs = { "home", "history" }; store.simpleui_bar_mode = "both"; store.simpleui_bar_navpager_enabled = nil
check("wechat mode ok", P.applyWeChatMode())
check("wechat mode sets tabs + reader menu", store.simpleui_bar_tabs[2] == "wereadshelf_open" and S:isTrue("reader_menu") and S:isTrue("open_on_start"))
local okn = P.backToNative()
check("back to native restores SimpleUI", okn and store.simpleui_bar_tabs[1] == "home" and store.simpleui_bar_mode == "both"
    and store.simpleui_bar_navpager_enabled == nil)
check("back to native turns our switches off", not S:isTrue("reader_menu") and not S:isTrue("open_on_start"))
-- BUG-02: no backup -> refuse, change nothing, no restart prompt
S:saveSetting("open_on_start", true); S:saveSetting("reader_menu", true); _G.restart_asked = nil
local okb, why = P.backToNative()
check("BUG-02 no backup -> false + reason", okb == false and tostring(why):find("没有可恢复的备份") ~= nil)
check("BUG-02 no backup -> user switches untouched", S:isTrue("open_on_start") and S:isTrue("reader_menu"))
P.confirmBackToNative()
shown[#shown].ok_callback()
check("BUG-02 restore w/o backup -> notice, no restart", not _G.restart_asked
    and tostring(shown[#shown].text):find("没有可恢复的备份") ~= nil)
S:saveSetting("reader_menu", false)
P.applyWeChatMode(); P.confirmBackToNative(); shown[#shown].ok_callback()
check("BUG-02 with backup -> restored + restart asked", _G.restart_asked and store.simpleui_bar_tabs[1] == "home")
-- BUG-03: apply and restore both use SimpleUI setters; no aliasing of our constant
_G.tabs_writes, _G.mode_writes = 0, 0
P.applyPreset()
local applied = store.simpleui_bar_tabs
applied[1] = "mutated_by_simpleui"
P.restorePreset()
check("BUG-03 apply+restore go through saveTabConfig/saveNavbarMode", _G.tabs_writes == 2 and _G.mode_writes == 2)
P.applyPreset()
check("BUG-03 PRESET constant not aliased", store.simpleui_bar_tabs[1] == "wereadshelf_discover" and store.simpleui_bar_tabs ~= applied)
store.simpleui_bar_tabs[1] = "x"
check("BUG-03 backup not aliased to live store", S:readSetting("preset_backup").simpleui_bar_tabs[1] == "home")
P.restorePreset()
check("BUG-03 restore round-trip exact", store.simpleui_bar_tabs[1] == "home" and store.simpleui_bar_tabs[2] == "history"
    and store.simpleui_bar_mode == "both" and store.simpleui_bar_navpager_enabled == nil)
-- BUG-03: original nil mode -> deleted, not left as "icons"
store.simpleui_bar_mode = nil; P.applyPreset(); P.restorePreset()
check("BUG-03 nil original mode restored to nil", store.simpleui_bar_mode == nil)
store.simpleui_bar_mode = "both"
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
-- v0.3.6 nav migration for 0.3.5 installs
S:saveSetting("setup_done", true); S:delSetting("nav_036"); store.simpleui_bar_navpager_enabled = true
check("v0.3.6 migration turns ‹ › off once", P.migrateNav036() and store.simpleui_bar_navpager_enabled == false
    and not P.migrateNav036())
-- BUG-06: empty (but readable) shelf -> empty grid, not the 未同步 dialog
local orig_gs = fm.weread.library_db.getShelf
fm.weread.library_db.getShelf = function() return {} end
P.showGrid()
local eg = shown[#shown]
check("BUG-06 empty shelf -> grid with 0 books", eg and eg.books and #eg.books == 0 and eg.on_import ~= nil)
fm.weread.library_db.getShelf = orig_gs
print(string.format("\n%d checks, %d failed", n, fails)); print(fails == 0 and "smoke ok" or "smoke FAILED")
os.exit(fails == 0 and 0 or 1)
