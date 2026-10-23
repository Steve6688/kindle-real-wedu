-- Smoke test for main.lua with stubbed KOReader modules (no SimpleUI: removed in 0.3.7) (not real UI).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
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
package.loaded["logger"] = { warn = print, info = function() end, dbg = function() end }
-- grid widget stub (real widget needs KOReader; covered by the box emulator run)
local Grid = cls()
function Grid:setKeyword(k) self.keyword = k end
function Grid:onCloseWidget() end
package.loaded["realweidu_grid"] = Grid
package.loaded["realweidu_ui"] = { icons_dir = "." }
local Pages = { Discover = cls(), Me = cls() }
function Pages.Me:refresh() self.refreshed = (self.refreshed or 0) + 1 end
package.loaded["realweidu_pages"] = Pages
local RMcls = cls()
package.loaded["realweidu_readermenu"] = RMcls
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

-- embedded weread stub (the real module needs KOReader; covered by the emulator run)
local WR = cls()
function WR:getMainMenuItems() return { { text = "扫码登录" }, { text = "书架" }, { text = "公众号" } } end
package.loaded["rweread.plugin"] = WR
local P = dofile(here .. "/../realweidu.koplugin/main.lua")
local S = mem_settings(); P._settings_override = S
local menu_items = {}
local inst = P:new{ ui = { menu = { registerToMainMenu = function(_, p) p:addToMainMenu(menu_items) end } }, path = "/x" }
inst:init(); for _, f in ipairs(ticks) do f() end
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
check("main menu has four focused actions", menu_items.realweidu ~= nil
    and #menu_items.realweidu.sub_item_table == 5
    and menu_items.realweidu.sub_item_table[4].text == "阅读设置…"
    and menu_items.realweidu.sub_item_table[1].text == "打开 Real微读"
    and menu_items.realweidu.sub_item_table[2].text == "登录与同步书架")
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
check("v0.3.5 ☰ entry pinned first", package.loaded["ui/elements/filemanager_menu_order"].main[1] == "realweidu_enter")
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
check("v0.3.8 我 = 0.3.3 look: 数据卡 + 5 rows + 返回 KOReader", mp.show_stats == true and #mp.rows == 6
    and mp.rows[1].text == "阅读时长统计" and mp.rows[2].text == "我的笔记" and mp.rows[3].text == "书架同步"
    and mp.rows[4].text == "阅读设置" and mp.rows[5].text == "退出到 Kindle" and not mp.rows[5].bold
    and mp.rows[6].text == "返回 KOReader" and mp.footer == nil)
check("v0.3.8 我 refreshes weekly stats on open (0.3.3, silent offline)", _G.stats_mode == "weekly"
    and mp.stats and mp.stats.week_min == 61)
local function find_btn(page, pat)
    for _, row in ipairs(page.rows) do if row.text:find(pat) then return { callback = row.fn, text = row.text, bold = row.bold } end end
end
local md = mp
-- 阅读设置 dialog: switches incl. 快速下载 and 流畅翻页
find_btn(md, "阅读设置").callback()
local sd = shown[#shown]
local function dbtn(dlg, pat) for _, row in ipairs(dlg.buttons) do if row[1].text:find(pat) then return row[1] end end end
check("阅读设置 dialog keeps switches", sd.title == "阅读设置" and dbtn(sd, "Real微读阅读菜单") and dbtn(sd, "快速下载")
    and dbtn(sd, "流畅翻页") and not dbtn(sd, "KOReader 设置") and not dbtn(sd, "SimpleUI"))
check("switches default ON (✓)", dbtn(sd, "快速下载").text:find("✓") == 1 and dbtn(sd, "流畅翻页").text:find("✓") == 1)
dbtn(sd, "快速下载").callback()
check("快速下载 toggles off and is saved", S:readSetting("fast_download") == false)
P.toggleSetting("fast_download")
check("快速下载 back on", P.isOn("fast_download"))
find_btn(md, "阅读时长统计").callback(); check("阅读时长统计 -> showReadStats", calls.stats)
find_btn(md, "我的笔记").callback(); check("我的笔记 -> honest notice", tostring(shown[#shown].text):find("没有") ~= nil)
_G.stats_mode = nil
mp.on_refresh_stats()
check("数据卡 tap -> weekly stats", _G.stats_mode == "weekly" and S:readSetting("stats_cache").week_min == 61
    and S:readSetting("stats_cache").notes == 12)
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

-- v0.3.8: every weread 「书架」 entry -> Real微读's shelf
local W = { library_db = fm.weread.library_db, settings = fm.weread.settings, shelf_view = "OLD",
    showShelfView = function() _G.weread_list_shown = true end,
    showBookshelf = function() _G.weread_list_shown = true end,
    refreshBookshelf = function(self_w) _G.synced = true; self_w:showShelfView("books") end,
    refreshLoginMenu = function() end }
W.openBookshelf = function(self_w) return self_w:showBookshelf() end
check("redirect installs once", P.redirectWereadShelf(W) and not P.redirectWereadShelf(W))
local function run_ticks() local t = ticks; ticks = {}; for _, f in ipairs(t) do f() end end
ticks = {}; _G.weread_list_shown = nil
local ns = #shown; W:openBookshelf(); run_ticks()
check("weread openBookshelf -> Real微读 grid, not weread list", not _G.weread_list_shown and shown[#shown].books ~= nil and #shown > ns)
_G.weread_list_shown = nil; W:showShelfView("books", nil, "OLDVIEW"); run_ticks()
check("weread showShelfView(books) (after sync/refresh) -> Real微读 grid + old view closed",
    not _G.weread_list_shown and (function() for _, c in ipairs(closed) do if c == "OLDVIEW" then return true end end end)()
    and shown[#shown].books ~= nil)
_G.weread_list_shown = nil; W:showShelfView("public_account")
check("public-account list is not a 书架: stays weread's", _G.weread_list_shown == true)
-- empty cache -> weread sync (login if needed), result into Real微读
local orig_shelf = W.library_db
W.library_db = { getShelf = function() return {} end, accountKey = function() return "k" end }
_G.synced, _G.weread_list_shown = nil, nil; W:showBookshelf(); run_ticks()
check("no cache yet -> weread sync, then Real微读 shelf", _G.synced and not _G.weread_list_shown)
W.library_db = orig_shelf
-- in a book: 书架 (end-of-book dialog / gesture) closes the book first
local homed2 = false
package.loaded["apps/reader/readerui"] = { instance = { document = {}, onHome = function() homed2 = true end } }
W:showBookshelf(); run_ticks()
check("in a book: weread 书架 -> close book (FM re-init shows Real微读)", homed2)
package.loaded["apps/reader/readerui"] = nil
-- grid 导入 / 我 书架同步 / discover 刷新 -> sync -> Real微读
fm.weread.refreshBookshelf = function() _G.synced2 = (_G.synced2 or 0) + 1 end
fm.weread._wrs_redirect = nil
fm.weread.showShelfView = function() _G.weread_list_shown = true end
P.showGrid(); local gg = shown[#shown]; gg.on_import()
find_btn(md, "书架同步").callback()
check("导入 and 书架同步 -> weread sync (result shown in Real微读)", _G.synced2 == 2)
check("fm weread instance patched by showGrid", fm.weread._wrs_redirect == true)
-- after QR login -> shelf fetched and shown in Real微读
local W2 = { library_db = { accountKey = function() return _G.logged and "k" or nil end, getShelf = function() return {} end },
    settings = { is_api_configured = function() return _G.logged == true end },
    showShelfView = function() end, showBookshelf = function() end,
    refreshBookshelf = function() _G.login_synced = true end, refreshLoginMenu = function() end }
P.redirectWereadShelf(W2); ticks = {}
_G.logged = true; W2:refreshLoginMenu(); run_ticks()
check("after login -> shelf sync into Real微读", _G.login_synced == true)
-- v0.3.8 流畅翻页
local RV = {}; package.loaded["apps/reader/modules/readerview"] = RV
RV.onPageChangeAnimation = function() _G.animated = true end
_G.G_reader_settings = { readSetting = function() return nil end, isTrue = function() return false end }
local UIM = package.loaded["ui/uimanager"]; UIM.FULL_REFRESH_COUNT = 6
check("流畅翻页 default on", P.applySmoothTurns() == true)
_G.animated = nil; RV.onPageChangeAnimation()
check("流畅翻页: no page-turn animation", not _G.animated)
check("流畅翻页: full refresh every 12 pages (default 6)", UIM.FULL_REFRESH_COUNT == 12)
P.toggleSetting("smooth_turns")
RV.onPageChangeAnimation()
check("流畅翻页 off restores KOReader behaviour", _G.animated and UIM.FULL_REFRESH_COUNT == 6)
P.toggleSetting("smooth_turns")
_G.G_reader_settings = { readSetting = function(_, k) if k == "full_refresh_count" then return 3 end end, isTrue = function() return false end }
P.toggleSetting("smooth_turns"); P.toggleSetting("smooth_turns")
check("流畅翻页 keeps a user-chosen refresh rate", UIM.FULL_REFRESH_COUNT ~= 12 or UIM._wrs_orig_rate == nil)
_G.G_reader_settings = nil
-- 0.4.0: one plugin — embedded weread attached, a separate weread.koplugin detached + disabled
do
    local foreign = { name = "weread" }
    local reg = { foreign, "other" }
    local saved = {}
    _G.G_reader_settings = { readSetting = function(_, k) return saved[k] end, saveSetting = function(_, k, v) saved[k] = v end,
        flush = function() end, isTrue = function() return false end }
    local ui2 = { foreign, weread = foreign, menu = { registered_widgets = reg }, active_widgets = {} }
    ui2.registerModule = function(self_u, name, m) self_u[name] = m; table.insert(self_u, m) end
    local inst2 = P.attachWeread(ui2)
    check("embedded weread attached as ui.weread", inst2 and ui2.weread == inst2 and inst2._real_embedded and inst2.real_shelf_redirect)
    check("separate weread.koplugin removed from events + menu", ui2[1] ~= foreign and reg[1] == "other" and #reg == 1)
    check("separate weread.koplugin disabled for next start", saved.plugins_disabled and saved.plugins_disabled.weread == true)
    check("attach is idempotent", P.attachWeread(ui2) == inst2)
    local mi = {}
    local pi = P:new{ ui = { weread = inst2 } }
    pi:addToMainMenu(mi)
    local sub = mi.realweidu.sub_item_table[5]
    check("☰ single Real微读 entry with weread functions folded in", mi.weread == nil and sub.text == "微信读书功能"
        and #sub.sub_item_table_func() == 3)
    ticks = {}; inst2.real_shelf_redirect(); local nb = #shown; for _, f in ipairs(ticks) do f() end
    check("embedded 书架 redirect -> Real微读 grid", #shown > nb)
    _G.G_reader_settings = nil
end
-- 0.4.1: rename migration wereadshelf -> realweidu
do
    local saved = { plugins_disabled = { weread = true } }
    local G = { data = { wereadshelf_last_tab = "me", other = 1 }, readSetting = function(self, k) return self.data[k] end,
        saveSetting = function(self, k, v) self.data[k] = v end, flush = function() end }
    G.data.plugins_disabled = saved.plugins_disabled
    P.migrate(G, nil)
    check("G_reader_settings wereadshelf_* -> realweidu_*", G.data.realweidu_last_tab == "me" and G.data.wereadshelf_last_tab == nil and G.data.other == 1)
    check("old wereadshelf.koplugin disabled, weread stays disabled", G.data.plugins_disabled.wereadshelf == true and G.data.plugins_disabled.weread == true)
    local g = { gesture_fm = { tap_left = { wereadshelf_open = true }, swipe = { realweidu_open = true } } }
    P._rename_ids(g)
    check("gesture action ids migrated", g.gesture_fm.tap_left.realweidu_open == true and g.gesture_fm.tap_left.wereadshelf_open == nil and g.gesture_fm.swipe.realweidu_open)
end
-- 0.4.2 device feedback
do
    local rows = P.meRows()
    local ex; for _, r in ipairs(rows) do if r.text == "退出到 Kindle" then ex = r end end
    check("退出到 Kindle row is normal weight", ex and not ex.bold)
    local has_ko = false
    for _, it in ipairs(P.settingsItems()) do if it.text:find("KOReader 设置", 1, true) then has_ko = true end end
    check("阅读设置 has no 「KOReader 设置」 row", not has_ko and #P.settingsItems() == 3)
    local U = package.loaded["ui/uimanager"]
    local closed, quit = {}, false
    local oc, oq = U.close, U.quit
    U.close = function(_, w) closed[#closed + 1] = w end
    U.quit = function() quit = true end
    U._window_stack = { { widget = { name = "notice" } } }
    ticks = {}; broadcast = {}
    P.showGrid(); P.exitToKindle()
    for _, f in ipairs(ticks) do f() end
    check("退出到 Kindle: closes our pages, broadcasts Exit, then quits KOReader",
        #closed >= 1 and broadcast[#broadcast] and broadcast[#broadcast].name == "Exit" and quit and not P.shouldAutoEnter())
    U.close, U.quit, U._window_stack = oc, oq, nil
    P._exiting = nil; package.loaded["realweidu_data"]._paused = false
    -- stats: 阅读时长统计 calls the embedded weread's showReadStats
    local called = false
    local fake = { library_db = {}, showReadStats = function() called = true end }
    local saved_fm = package.loaded["apps/filemanager/filemanager"]
    local saved_rui = package.loaded["apps/reader/readerui"]
    package.loaded["apps/reader/readerui"] = nil
    package.loaded["apps/filemanager/filemanager"] = { instance = { weread = fake } }
    for _, r in ipairs(P.meRows()) do if r.text == "阅读时长统计" then r.fn() end end
    check("阅读时长统计 -> weread:showReadStats", called)
    package.loaded["apps/filemanager/filemanager"] = saved_fm
    package.loaded["apps/reader/readerui"] = saved_rui
    -- no stale module names anywhere in the plugin (0.4.0 merge / 0.4.1 rename)
    local stale = {}
    local root = here .. "/../realweidu.koplugin"
    for f in io.popen('find "' .. root .. '" -name "*.lua"'):lines() do
        local n = 0
        for line in io.lines(f) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if (code:find('"weread%.lib%.') or code:find('"weread%.ui%.') or code:find('"wereadshelf_'))
                and not code:find('"rweread%.') and not line:find("LEGACY") and not code:find('or package.loaded%["weread')
                and not code:find('or L%["weread') and not code:find('"wereadshelf_open", {', 1, true) then
                stale[#stale + 1] = f:match("[^/]+$") .. ":" .. n
            end
        end
    end
    check("no stale weread.* / wereadshelf_* module names (" .. table.concat(stale, ",") .. ")", #stale == 0)
end
-- 0.4.3 reading menu + progress sync dialog (source-level; full UI needs KOReader)
do
    local src = assert(io.open(here .. "/../realweidu.koplugin/realweidu_readermenu.lua")):read("*a")
    check("reading menu has official panel pieces", src:find("阅读明细", 1, true) and src:find("开启自动翻页", 1, true)
        and src:find("showTocSheet", 1, true) and src:find('kind == "dot"', 1, true)
        and src:find('float("AI"', 1, true) and src:find("syncThoughts", 1, true)
        and src:find('rm_font_active', 1, true) and src:find("_fontIconBar", 1, true)
        and src:find('self:refresh("full")', 1, true))
    check("TOC is left 80% sidebar dismissable outside (0.4.8)", src:find("local PW = math.floor(W * Logic.TOC_SIDEBAR_FRAC)", 1, true)
        and src:find("tap outside dismisses TOC", 1, true))
    local ps = assert(io.open(here .. "/../realweidu.koplugin/rweread/ui/progress_sync_dialog.lua")):read("*a")
    check("progress sync dialog has 3 choices", ps:find("Use WeRead progress", 1, true)
        and ps:find("Use local progress", 1, true) and ps:find('"Cancel"', 1, true)
        and ps:find("ButtonDialog", 1, true))
    local i18n = assert(io.open(here .. "/../realweidu.koplugin/rweread/lib/i18n.lua")):read("*a")
    check("progress sync Chinese labels", i18n:find("使用微信读书进度", 1, true)
        and i18n:find("使用本地进度", 1, true) and i18n:find('["Cancel"] = "取消"', 1, true))
end
P.exitToKindle(); check("exit to Kindle = KOReader Exit event", broadcast[#broadcast] and broadcast[#broadcast].name == "Exit")
-- reader hook
local zones
local rui = { document = {}, registerTouchZones = function(_, z) zones = z end }
S:saveSetting("reader_menu", true)
local rinst = P:new{ ui = rui, path = "/x" }; rinst:init()
check("reader: centre zone registered", zones and zones[1].id == "realweidu_menu_tap" and zones[1].overrides[1] == "tap_forward"
    and zones[1].screen_zone.ratio_x == 0.25 and zones[1].screen_zone.ratio_w == 0.5)
zones[1].handler()
check("reader: 查词模式 zone registered, off -> passes through", zones[2] and zones[2].id == "realweidu_lookup_tap"
    and zones[2].handler({ pos = { x = 600, y = 800 } }) == false)
-- 0.5.1: 查词模式 stores only English words in vocabulary builder
do
    local seen = {}
    local vs = { enabled = false }
    local gd = { vocabulary_builder = vs, realweidu_lookup_mode = true }
    local oldG, oldDev = rawget(_G, "G_reader_settings"), package.loaded["device"]
    _G.G_reader_settings = { readSetting = function(_, k) return gd[k] end, isTrue = function(_, k) return gd[k] == true end,
        saveSetting = function(_, k, v) gd[k] = v end }
    package.loaded["device"] = oldDev or { screen = { getWidth = function() return 1236 end } }
    local cur = "serendipity"
    rui.view = { screenToPageTransform = function(_, p) return p end }
    rui.document.getWordFromPosition = function() return { word = cur } end
    rui.dictionary = { onLookupWord = function(_, w) seen[#seen + 1] = { w = w, en = vs.enabled } end }
    local W = require("device").screen:getWidth()
    local g = { pos = { x = math.floor(W / 2), y = 800 } }
    check("0.5.1 lookup: english word -> vocab enabled during lookup, restored", zones[2].handler(g) == true
        and seen[1] and seen[1].w == "serendipity" and seen[1].en == true and vs.enabled == false)
    cur = "李善德"
    check("0.5.1 lookup: chinese word -> dictionary shown, vocab NOT enabled", zones[2].handler(g) == true
        and seen[2] and seen[2].w == "李善德" and seen[2].en == false and vs.enabled == false)
    vs.enabled = true
    check("0.5.1 lookup: chinese word with vocab globally on -> suppressed then restored", zones[2].handler(g) == true
        and seen[3].en == false and vs.enabled == true)
    _G.G_reader_settings = oldG; package.loaded["device"] = oldDev; rui.view = nil; rui.dictionary = nil; rui.document.getWordFromPosition = nil
end
check("reader: tap shows WeRead menu", getmetatable(shown[#shown]).__index == RMcls and shown[#shown].ui == rui)
S:saveSetting("reader_menu", false); zones = nil
P:new{ ui = rui, path = "/x" }:init()
check("reader: no hook when setting off", zones == nil)
-- v0.3.4 enter / exit
check("top-level menu entry 进入 Real微读", menu_items.realweidu_enter and menu_items.realweidu_enter.text == "进入 Real微读")
P.leaveToKOReader()
check("返回 KOReader pauses auto-enter for this session", not P.shouldAutoEnter())
ticks = {}; P:new{ ui = { menu = { registerToMainMenu = function() end } }, path = "/x" }:init()
local nshown = #shown; for _, f in ipairs(ticks) do f() end
check("paused: FM re-init does not open shelf", #shown == nshown)
local before = #shown; menu_items.realweidu_enter.callback()
check("menu entry re-enters shelf + clears pause", #shown == before + 1 and P.shouldAutoEnter())
ticks = {}; P:new{ ui = { menu = { registerToMainMenu = function() end } }, path = "/x" }:init()
nshown = #shown; for _, f in ipairs(ticks) do f() end
check("always on: FM init (start / book closed) opens shelf", #shown > nshown and shown[#shown].active_action_id == "realweidu_open")
local homed = false
local rui2 = { document = {}, onHome = function() homed = true end }
local ri2 = P:new{ ui = rui2, path = "/x" }
check("dispatcher event from reader closes book", ri2:onRealWeiduOpen() and homed)
-- BUG-06: empty (but readable) shelf -> empty grid, not the 未同步 dialog
local orig_gs = fm.weread.library_db.getShelf
fm.weread.library_db.getShelf = function() return {} end
P.showGrid()
local eg = shown[#shown]
check("BUG-06 empty shelf -> grid with 0 books", eg and eg.books and #eg.books == 0 and eg.on_import ~= nil)
fm.weread.library_db.getShelf = orig_gs
print(string.format("\n%d checks, %d failed", n, fails)); print(fails == 0 and "smoke ok" or "smoke FAILED")
os.exit(fails == 0 and 0 or 1)
