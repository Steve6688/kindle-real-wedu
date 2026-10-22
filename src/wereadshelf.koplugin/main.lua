-- wereadshelf.koplugin — "Real微读": standalone WeRead-style home for KOReader
-- (发现 / 书架 / 我 with its own bottom bar) + 4-column cover grid, backed by
-- weread.koplugin's local shelf cache. Does not modify weread files and does
-- not need (or touch) SimpleUI (removed in 0.3.7).
--
-- weread 1.6.0 entry points used (public methods on the plugin instance,
-- mixed in at weread main.lua:222-233):
--   openBookshelf()   main.lua:33
--   showSearch()      weread/ui/library.lua:1640   (online WeRead search dialog)
--   searchWithUI(kw)  weread/ui/library.lua:1673
--   showReadStats()   weread/ui/read_report.lua:238 (reading statistics)

local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage     = require("ui/widget/infomessage")
local Menu            = require("ui/widget/menu")
local logger          = require("logger")

-- Must be required at top level: KOReader only puts the plugin dir on
-- package.path while dofile()'ing main.lua (frontend/pluginloader.lua:242-244).
local Data   = require("wereadshelf_data")
local FastDL = require("wereadshelf_fastdl")
local Layout = require("wereadshelf_layout")
local ShelfGrid -- lazy (pulls in UI widgets)

local QA_ID       = "wereadshelf_open"     -- 书架 (tab id)
local QA_DISCOVER = "wereadshelf_discover" -- 发现
local QA_ME       = "wereadshelf_me"       -- 我

local WeReadShelf = WidgetContainer:extend{
    name = "wereadshelf",
    is_doc_only = false,
}

-- Plugin dir from this file's path (main.lua is dofile()'d by
-- frontend/pluginloader.lua:244, so the chunk source is its full path).
local plugin_dir = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$")

local function info(text)
    UIManager:show(InfoMessage:new{ text = text })
end

-- Own settings file (only written by explicit menu actions).
local _settings
local function settings()
    if not _settings then
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        _settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/wereadshelf.lua")
    end
    return _settings
end
WeReadShelf._settings_override = nil -- tests
local function S() return WeReadShelf._settings_override or settings() end
-- v0.3.5: reader menu defaults to ON; only an explicit false turns it off.
local function on(key) return S():readSetting(key) ~= false end
WeReadShelf.isOn = on
WeReadShelf.ENTER_TEXT = "进入 Real微读"
WeReadShelf.VERSION = "0.3.7"

-- Put 「进入 Real微读」 at the top of KOReader's ☰ (main) menu tab instead of
-- after Exit (items missing from the order table are appended at the end).
local function pin_menu_entry()
    for _, mod in ipairs({ "ui/elements/filemanager_menu_order", "ui/elements/reader_menu_order" }) do
        local ok, order = pcall(require, mod)
        if ok and type(order) == "table" and type(order.main) == "table" then
            local has = false
            for _, k in ipairs(order.main) do if k == "wereadshelf_enter" then has = true end end
            if not has then table.insert(order.main, 1, "wereadshelf_enter") end
        end
    end
end

local current_grid, current_page, active_tab
local close_pages, ui_icons, call_weread -- defined further below

function WeReadShelf:init()
    plugin_dir = self.path or plugin_dir
    pin_menu_entry()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    -- Reading menu (opt-in setting "reader_menu"; on with 微信读书模式).
    if self.ui and self.ui.document and on("reader_menu") then
        self:hookReader()
    end
    -- v0.3.5: Real微读 is always on (no toggle, no setup step). Every time the file manager comes up (KOReader start *and* after a book
    -- is closed — ReaderUI:onClose/onHome rebuild the FileManager, which
    -- re-inits plugins) we put the shelf on top, so the user never lands on
    -- the file browser screen. 「返回 KOReader」 pauses this for the
    -- current session only (Data._paused); any re-entry clears the pause.
    local in_fm = self.ui and not self.ui.document
    if in_fm then
        Data._startup_done = true
        if WeReadShelf.shouldAutoEnter() then
            UIManager:nextTick(function() WeReadShelf.showGrid() end)
            if UIManager.scheduleIn then
                UIManager:scheduleIn(1.5, function() WeReadShelf.ensureOnTop() end)
            end
        end
    end
    self:onDispatcherRegisterActions()
    -- v0.3.6 faster weread downloads (default ON; 更多设置 → 快速下载).
    if on("fast_download") then
        local ok, e = pcall(FastDL.install)
        if not ok then logger.warn("wereadshelf: fast download not installed:", e) end
    end
end

function WeReadShelf.shouldAutoEnter()
    return not Data._paused -- 返回 KOReader pauses only until next start / re-entry
end

-- Something (e.g. a stale SimpleUI Home Screen) may still be shown after our first
-- tick; check again shortly and bring the shelf back to the front.
local function is_ours(w)
    return w and (w.name == "wereadshelf_grid" or w.name == "wereadshelf_discover" or w.name == "wereadshelf_me")
end
function WeReadShelf.ensureOnTop()
    if Data._paused then return false end
    local RUI = package.loaded["apps/reader/readerui"]
    if RUI and RUI.instance then return false end -- a book is open: never cover it
    local st = UIManager._window_stack
    local top = type(st) == "table" and st[#st] and st[#st].widget
    if type(top) ~= "table" or is_ours(top) then return false end
    local nm = tostring(top.name or "")
    if nm == "filemanager" or nm == "homescreen" or nm:find("^sui_") then
        WeReadShelf.showGrid(); return true
    end
    return false
end

-- Gesture / dispatcher action: 「打开 Real微读」 (assignable in KOReader
-- 设置 → 手势管理, also usable from profiles / QuickMenu).
function WeReadShelf:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or type(Dispatcher) ~= "table" or type(Dispatcher.registerAction) ~= "function" then return end
    pcall(Dispatcher.registerAction, Dispatcher, "wereadshelf_open", {
        category = "none", event = "WeReadShelfOpen", title = "打开 Real微读", general = true,
    })
end

function WeReadShelf:onWeReadShelfOpen()
    WeReadShelf.enter(self.ui)
    return true
end

-- One-tap entry from plain KOReader (main-menu item, gesture, tab tap).
-- In the reader it closes the book first (to the file manager), then shows
-- the shelf.
function WeReadShelf.enter(ui)
    Data._paused = false
    if ui and ui.document and type(ui.onHome) == "function" then
        local ok = pcall(ui.onHome, ui)
        if ok and not WeReadShelf.shouldAutoEnter() then
            UIManager:scheduleIn(0.3, function() WeReadShelf.showGrid() end)
        end
        return
    end
    return WeReadShelf.showGrid()
end

-- 「返回 KOReader」: close our pages, stay in KOReader's file browser for this
-- session. Settings are untouched; the mode comes back on next start, after
-- re-entry via menu / gesture, or by tapping a bottom-bar tab.
function WeReadShelf.leaveToKOReader()
    Data._paused = true
    close_pages()
    info("已返回 KOReader。\n再次进入：KOReader 菜单 ☰ 第一项「进入 Real微读」，或手势「打开 Real微读」；下次启动自动进入。")
end

function WeReadShelf:addToMainMenu(menu_items)
    -- v0.3.4: one obvious top-level entry (first page of the KOReader menu).
    local ui = self.ui
    menu_items.wereadshelf_enter = {
        text = WeReadShelf.ENTER_TEXT,
        sorting_hint = "main",
        callback = function() WeReadShelf.enter(ui) end,
    }
    menu_items.wereadshelf = {
        text = "Real微读",
        sorting_hint = "tools",
        sub_item_table = {
            { text = "打开 Real微读", callback = function() WeReadShelf.showGrid() end },
            {
                text = "登录、同步与管理书架",
                callback = function() WeReadShelf.openWereadManagement() end,
                separator = true,
            },
            {
                text = "阅读时使用 Real微读菜单",
                checked_func = function() return on("reader_menu") end,
                callback = function() WeReadShelf.toggleSetting("reader_menu") end,
            },
            { text = "更多设置…", callback = function() WeReadShelf.showMoreSettings() end },
        },
    }
end

-- Direct route for account, login, sync and shelf management. The weread
-- plugin owns these flows; Real微读 simply opens them without another menu hop.
function WeReadShelf.openWereadManagement()
    local weread = Data.find_weread()
    if weread and type(weread.openBookshelf) == "function" then
        local ok, err = pcall(weread.openBookshelf, weread)
        if ok then return true end
        info("微信读书打开失败：" .. tostring(err))
        return false
    end
    info("未找到 weread.koplugin，请先安装或启用微信读书插件。")
    return false
end

function WeReadShelf.toggleSetting(key)
    S():saveSetting(key, not on(key)); S():flush()
    if current_page and active_tab == QA_ME and current_page.refresh then
        current_page.rows = WeReadShelf.moreSettingsItems() -- update ✓ marks in place
        pcall(current_page.refresh, current_page)
    end
    if key == "reader_menu" then info("已保存，下次打开书时生效。") end
end

-- Same as KOReader's own 退出 (frontend/ui/elements/common_exit_menu_table.lua:8-19);
-- on Kindle the launcher then returns to the native home screen.
function WeReadShelf.exitToKindle()
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("Exit"))
end

function WeReadShelf.confirmExitToKindle()
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = "退出 KOReader，返回 Kindle 主界面？",
        ok_text = "退出",
        ok_callback = function() WeReadShelf.exitToKindle() end,
    })
end

-- Older names kept for callers; the same items are the 「我」 rows.
function WeReadShelf.showSettingsDialog() return WeReadShelf.showMoreSettings() end

-- 「我」 rows (0.3.7). Also offered as a dialog for the KOReader tools menu.
function WeReadShelf.moreSettingsItems()
    local weread = Data.find_weread()
    local function mark(k) return on(k) and "✓ " or "　" end
    return {
        { text = "阅读时长统计", fn = function() call_weread("showReadStats") end },
        { text = "我的笔记", fn = function()
            info("weread 1.6.0 没有「全部笔记」列表接口。\n打开一本书后：阅读菜单「更多」→ 书签列表，"
                .. "或 weread 菜单「划线和想法管理」查看该书笔记。") end },
        { text = "书架同步 · 登录与管理", fn = function() WeReadShelf.openWereadManagement() end },
        { text = "刷新本周阅读数据", fn = function()
            if not WeReadShelf.refreshStats(weread, function(good)
                local c = WeReadShelf.statsCache()
                info(good and ("本周阅读 " .. tostring(c.week_min or 0) .. " 分钟") or "刷新失败（未联网或服务器无数据）")
            end, false) then info(Data.MESSAGES[Data.ERR_NO_PLUGIN]) end
        end },
        { text = mark("reader_menu") .. "Real微读阅读菜单", fn = function() WeReadShelf.toggleSetting("reader_menu") end },
        { text = mark("fast_download") .. "快速下载（3 章并行）", fn = function()
            WeReadShelf.toggleSetting("fast_download")
            info("已保存，重启 KOReader 后生效。") end },
        { text = "KOReader 设置（完整菜单）", fn = function() WeReadShelf.openKOReaderMenu() end },
        { text = "退出到 Kindle…", fn = function() WeReadShelf.confirmExitToKindle() end },
        { text = "返回 KOReader", bold = true, fn = function() WeReadShelf.leaveToKOReader() end },
    }
end

function WeReadShelf.showMoreSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local buttons = {}
    for _, it in ipairs(WeReadShelf.moreSettingsItems()) do
        buttons[#buttons + 1] = { { text = it.text, align = "left", callback = function() UIManager:close(dlg); it.fn() end } }
    end
    buttons[#buttons + 1] = { { text = "关闭", callback = function() UIManager:close(dlg) end } }
    dlg = ButtonDialog:new{ title = "更多设置", buttons = buttons }
    UIManager:show(dlg)
    return dlg
end

-- KOReader's own full menu, on top of the file manager (our pages close).
function WeReadShelf.openKOReaderMenu()
    Data._paused = true
    close_pages()
    local FM = package.loaded["apps/filemanager/filemanager"]
    local fm = FM and FM.instance
    if fm and fm.menu and type(fm.menu.onShowMenu) == "function" then
        UIManager:nextTick(function() pcall(fm.menu.onShowMenu, fm.menu) end)
    end
end

-- Reader integration -----------------------------------------------------------
-- A centre tap zone that takes priority over page turning (tap_forward /
-- tap_backward, apps/reader/modules/readerrolling.lua:367-377,
-- readerpaging.lua:106-116). KOReader's own top/bottom menu zones
-- (readermenu.lua:100-163) are left untouched as a fallback.
WeReadShelf.CENTER_ZONE = { ratio_x = 0.25, ratio_y = 0.25, ratio_w = 0.5, ratio_h = 0.5 }

function WeReadShelf:hookReader()
    local ui = self.ui
    if not (ui and type(ui.registerTouchZones) == "function") then return end
    ui:registerTouchZones({ {
        id = "wereadshelf_menu_tap",
        ges = "tap",
        screen_zone = WeReadShelf.CENTER_ZONE,
        overrides = { "tap_forward", "tap_backward" },
        handler = function() return WeReadShelf.showReaderMenu(ui) end,
    } })
end

function WeReadShelf.showReaderMenu(ui)
    ui_icons()
    local RM = require("wereadshelf_readermenu")
    local weread = Data.find_weread()
    local menu = RM:new{
        ui = ui, weread = weread,
        on_back = function()
            -- ReaderUI:onHome closes the book and shows the file manager
            -- (apps/reader/readerui.lua:929-933); then open our shelf on top.
            -- FM init re-opens the shelf itself when the mode is on.
            Data._paused = false
            local ok = pcall(ui.onHome, ui)
            if ok and not WeReadShelf.shouldAutoEnter() then
                UIManager:scheduleIn(0.3, function() WeReadShelf.showGrid() end)
            end
        end,
    }
    UIManager:show(menu, "full") -- 刷新规则：打开菜单一次全屏刷新
    return true
end

-- Conventional launcher name.
function WeReadShelf:launch() WeReadShelf.showGrid() end

-- Public API -----------------------------------------------------------

function WeReadShelf.get_shelf(opts)
    return Data.get_shelf(Data.find_weread(), opts)
end

function WeReadShelf.open_book(book_id)
    return Data.open_book(Data.find_weread(), book_id)
end

-- Shared error handling -------------------------------------------------

local function show_error(weread, err)
    local msg = Data.MESSAGES[err] or tostring(err)
    if weread and (err == Data.ERR_NOT_LOGGED_IN or err == Data.ERR_NO_CACHE)
            and type(weread.openBookshelf) == "function" then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = msg,
            ok_text = "打开微信读书",
            ok_callback = function()
                -- weread/main.lua:33 — triggers QR login if needed (common.lua:182)
                pcall(weread.openBookshelf, weread)
            end,
        })
    else
        info(msg)
    end
end

call_weread = function(method, ...)
    local weread = Data.find_weread()
    if not weread then info(Data.MESSAGES[Data.ERR_NO_PLUGIN]); return false end
    if type(weread[method]) ~= "function" then
        info("当前 weread 版本没有此入口（" .. method .. "）")
        return false
    end
    local ok, e = pcall(weread[method], weread, ...)
    if not ok then logger.warn("wereadshelf:", method, e); info("打开失败：" .. tostring(e)) end
    return ok
end

-- Pages ------------------------------------------------------------------------

ui_icons = function()
    local U = require("wereadshelf_ui")
    U.icons_dir = (plugin_dir or ".") .. "/icons"
    return U
end

-- Only one of our tab pages is open at a time (tab switching replaces it).
close_pages = function(except)
    if current_page and current_page ~= except then UIManager:close(current_page); current_page = nil end
    if current_grid and current_grid ~= except then UIManager:close(current_grid); current_grid = nil end
end

local function show_page(page, tab)
    local orig = page.onCloseWidget
    page.onCloseWidget = function(w)
        if current_page == w then current_page = nil end
        if active_tab == tab and current_page == nil and current_grid == nil then active_tab = nil end
        if orig then return orig(w) end
    end
    Data._paused = false
    current_page = page
    active_tab = tab
    UIManager:show(page, "full") -- 刷新规则：切换 Tab 一次全屏刷新
    return page
end

-- 发现: search (weread showSearch, library.lua:1640), 最近阅读 from the local
-- shelf cache, and the WeRead entries weread 1.6.0 really has. weread has no
-- recommendation / ranking / category API (only /store/search, /shelf/sync,
-- /book/info, /review/list, /readdata/detail ... in weread/lib/client.lua),
-- so 「为你推荐」 is hidden as UI-SPEC v1.1 asks when data is unavailable.
function WeReadShelf.showDiscover()
    local weread = Data.find_weread()
    if not weread then info(Data.MESSAGES[Data.ERR_NO_PLUGIN]); return end
    local books = Data.get_shelf(weread) or {}
    ui_icons()
    close_pages()
    local Pages = require("wereadshelf_pages")
    local entries = {}
    local function add(text, method, ...)
        if type(weread[method]) == "function" then
            local args = { ... }
            entries[#entries + 1] = { text = text, fn = function() call_weread(method, unpack(args)) end }
        end
    end
    add("搜索书城（书名 / 作者）", "showSearch")          -- library.lua:1640
    add("公众号文章", "showMPShelfPage")                   -- library.lua:1003
    add("微信读书收藏", "showWereadCollection")            -- menu.lua:787
    add("刷新 / 管理书架", "openBookshelf")                 -- main.lua:33
    local page = Pages.Discover:new{
        books = books, entries = entries,
        on_nav_discover = function() WeReadShelf.showDiscover() end,
        on_nav_shelf = function() WeReadShelf.showGrid() end,
        on_nav_me = function() WeReadShelf.showMe() end,
        on_search = function() call_weread("showSearch") end,
        on_open = function(b)
            local ok, e = Data.open_book(weread, b.bookId)
            if not ok then info(Data.MESSAGES[e] or ("打开失败：" .. tostring(e))) end
        end,
        on_all = function() WeReadShelf.showGrid() end,
    }
    return show_page(page, QA_DISCOVER)
end

-- 我: account name (weread settings "account", qr_login.lua:288-293), 本周阅读
-- (weread client:get_read_stats("weekly"), client.lua:680 -> totalReadTime),
-- 读完 = finished books on the cached shelf, 笔记 = readStat chip if the
-- server sends one (read_stats.lua:189-201), else "—".
function WeReadShelf.statsCache() return S():readSetting("stats_cache") or {} end

function WeReadShelf.refreshStats(weread, on_done, silent)
    if not weread or type(weread.runOnlineTask) ~= "function" or type(weread.client) ~= "table" then return false end
    local Logic = require("wereadshelf_logic")
    return weread:runOnlineTask("阅读统计", function()
        local ok, raw = pcall(weread.client.get_read_stats, weread.client, "weekly")
        local good = ok and type(raw) == "table" -- BUG-04: nil / non-table is a failure too
        if good then
            local c = { week_min = Logic.minutes(raw.totalReadTime), notes = Logic.notes_from_summary(raw), at = os.time() }
            S():saveSetting("stats_cache", c); S():flush()
        else
            logger.warn("wereadshelf: weekly stats failed:", raw)
        end
        if on_done then on_done(good, not ok and raw or nil) end
    end, 0.1, { silent_offline = silent })
end

function WeReadShelf.showMe()
    local weread = Data.find_weread()
    if not weread then info(Data.MESSAGES[Data.ERR_NO_PLUGIN]); return end
    local Logic = require("wereadshelf_logic")
    ui_icons()
    close_pages()
    local account = {}
    pcall(function() account = weread.settings:get("account", {}) or {} end)
    local books = Data.get_shelf(weread) or {}
    local function stats()
        local c = WeReadShelf.statsCache()
        local hint
        if c.at then hint = "本周阅读更新于 " .. os.date("%m-%d %H:%M", c.at) .. "，点数据卡刷新"
        else hint = "点数据卡联网获取本周阅读" end
        return { week_min = c.week_min, finished = Logic.count_finished(books), notes = c.notes, hint = hint }
    end
    local Pages = require("wereadshelf_pages")
    local page
    page = Pages.Me:new{
        account_name = Data.is_logged_in(weread) and (account.name or "") or "",
        stats = stats(),
        account_sub = Data.is_logged_in(weread) and "已登录 · 微信读书" or "未登录",
        footer = "Real微读 " .. (WeReadShelf.VERSION or ""),
        -- v0.3.7: every item sits directly on 「我」 (no 更多设置 level)
        rows = WeReadShelf.moreSettingsItems(),
        on_nav_discover = function() WeReadShelf.showDiscover() end,
        on_nav_shelf = function() WeReadShelf.showGrid() end,
        on_nav_me = function() WeReadShelf.showMe() end,
        on_refresh_stats = function()
            WeReadShelf.refreshStats(weread, function(good, err)
                if page then page.stats = stats(); page:refresh() end
                if not good then
                    info("本周阅读刷新失败" .. (err and ("：" .. tostring(err)) or "（服务器没有返回数据）")
                        .. "。\n页面上是上次的数据。")
                end
            end, false)
        end,
    }
    show_page(page, QA_ME)
    return page
end

-- Grid ---------------------------------------------------------------------

function WeReadShelf.showSearchDialog(grid)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = "搜索",
        input = grid.keyword or "",
        input_hint = "书名或作者",
        buttons = { {
            { text = "取消", id = "close", callback = function() UIManager:close(dialog) end },
            { text = "清除筛选", callback = function()
                UIManager:close(dialog); grid:setKeyword(nil) end },
        }, {
            { text = "书架内筛选", is_enter_default = true, callback = function()
                local kw = dialog:getInputText()
                UIManager:close(dialog); grid:setKeyword(kw) end },
            { text = "微信读书搜索", callback = function()
                local kw = dialog:getInputText()
                UIManager:close(dialog)
                if kw and kw ~= "" then call_weread("searchWithUI", kw) else call_weread("showSearch") end
            end },
        } },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
end

function WeReadShelf.showGrid()
    Data._paused = false
    local weread = Data.find_weread()
    local books, err = Data.get_shelf(weread, { allow_empty = true }) -- BUG-06
    if not books then show_error(weread, err); return end
    ShelfGrid = ShelfGrid or require("wereadshelf_grid")
    local keep_page, keep_kw
    if current_grid then
        -- tapping the 书架 tab again: refresh from cache, keep position
        keep_page, keep_kw = current_grid.page, current_grid.keyword
        UIManager:close(current_grid)
        current_grid = nil
    end
    close_pages()
    ui_icons() -- the grid's own bottom bar uses wereadshelf_ui icons
    local grid
    grid = ShelfGrid:new{
        books = books,
        icons_dir = (plugin_dir or ".") .. "/icons",
        page = keep_page or 1,
        keyword = keep_kw,
        active_action_id = QA_ID,
        placeholder = books[1] and books[1].title or nil, -- UI-SPEC: 占位为书名推荐
        on_open = function(book)
            local ok, e = Data.open_book(weread, book.bookId)
            if not ok then info(Data.MESSAGES[e] or ("打开失败：" .. tostring(e))) end
        end,
        on_import = function() call_weread("openBookshelf") end, -- BUG-07: errors are shown
        on_select = function()
            info("「选择」（批量管理）计划在二期提供。\n现在可点「导入」进入微信读书书架管理。")
        end,
        on_search = function(g) WeReadShelf.showSearchDialog(g) end,
        on_discover = function() WeReadShelf.showDiscover() end,
        on_shelf = function() WeReadShelf.showGrid() end,
        on_me = function() WeReadShelf.showMe() end,
    }
    local orig_close = grid.onCloseWidget
    grid.onCloseWidget = function(self_w)
        if current_grid == self_w then current_grid = nil end
        if active_tab == QA_ID and current_grid == nil then active_tab = nil end
        return orig_close(self_w)
    end
    current_grid = grid
    active_tab = QA_ID
    UIManager:show(grid, "full")
    return grid
end

-- Legacy text list (v0.1) -------------------------------------------------

function WeReadShelf.showShelfStatic()
    local weread = Data.find_weread()
    local books, err = Data.get_shelf(weread)
    if not books then show_error(weread, err); return end

    local menu
    local items = {
        {
            text = "↻ 在微信读书中刷新 / 管理书架",
            callback = function()
                UIManager:close(menu)
                call_weread("openBookshelf")
            end,
        },
    }
    for _i, item in ipairs(books) do
        local book_id = item.bookId
        items[#items + 1] = {
            text = Data.format_text(item),
            mandatory = Data.format_mandatory(item),
            callback = function()
                UIManager:close(menu)
                local ok, e = Data.open_book(weread, book_id)
                if not ok then info(Data.MESSAGES[e] or ("打开失败：" .. tostring(e))) end
            end,
        }
    end
    menu = Menu:new{
        title = string.format("Real微读（%d）", #books),
        item_table = items,
        is_borderless = true,
        title_bar_fm_style = true,
    }
    UIManager:show(menu)
end

function WeReadShelf:showShelf() WeReadShelf.showGrid() end

WeReadShelf._Layout = Layout
return WeReadShelf
