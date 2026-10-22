-- wereadshelf.koplugin — "微信书架" for SimpleUI: 3-tab bottom bar
-- (发现 / 书架 / 我) + 4-column cover grid, backed by weread.koplugin's local
-- shelf cache. Does not modify weread or SimpleUI files.
--
-- SimpleUI 2.7.5 extension points used (official, documented):
--   QA.register(descriptor)            features/sui_quickactions.lua:23-53
--     get_icon(id) per render          features/sui_quickactions.lua:1913-1941
--   external QA ids accepted as tabs   infra/sui_config.lua:296-326 loadTabConfig
--   BarInjection.register(desc)        infra/sui_core.lua:1066-1097
--     -> SimpleUI wraps our widget with its bar  infra/sui_patches.lua:1796-2025
--   navpager arrows call onPrevPage/onNextPage on the top widget with page_num
--                                      screens/sui_bottombar.lua:1059-1079, 1136, 1195
--   Tab preset (only on explicit user action, with backup):
--     Config.saveTabConfig             infra/sui_config.lua:327-330 ("simpleui_bar_tabs")
--     Config.saveNavbarMode            infra/sui_config.lua:346-350 ("simpleui_bar_mode": icons)
--     "simpleui_bar_navpager_enabled"  infra/sui_config.lua:2841 (max 4 tabs, :109)
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
local Layout = require("wereadshelf_layout")
local ShelfGrid -- lazy (pulls in UI widgets)

local QA_ID       = "wereadshelf_open"     -- 书架 (id kept from v0.1 so existing tabs keep working)
local QA_DISCOVER = "wereadshelf_discover" -- 发现
local QA_ME       = "wereadshelf_me"       -- 我
local BI_ID       = "wereadshelf_grid"

local PRESET_KEYS = { "simpleui_bar_tabs", "simpleui_bar_mode", "simpleui_bar_navpager_enabled" }
local PRESET = {
    simpleui_bar_tabs = { QA_DISCOVER, QA_ID, QA_ME },
    simpleui_bar_mode = "icons",
    simpleui_bar_navpager_enabled = true,
}

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

-- Solid icon variant = selected state; see icon_for below.
local current_grid, current_page, active_tab
local close_pages, ui_icons -- defined in the Pages section below

function WeReadShelf:init()
    plugin_dir = self.path or plugin_dir
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    self:registerSimpleUI()
    pcall(WeReadShelf.restorePrunedTabs)
    -- SimpleUI may be loaded after us (plugin load order); retry once later.
    UIManager:nextTick(function() self:registerSimpleUI() end)
    -- Reading menu (opt-in setting "reader_menu"; on with 微信读书模式).
    if self.ui and self.ui.document and S():isTrue("reader_menu") then
        self:hookReader()
    end
    -- v0.3.4 微信读书模式 = remembered setting "open_on_start". While it is on,
    -- every time the file manager comes up (KOReader start *and* after a book
    -- is closed — ReaderUI:onClose/onHome rebuild the FileManager, which
    -- re-inits plugins) we put the shelf on top, so the user never lands on
    -- the SimpleUI / file browser screen. 「返回 KOReader」 pauses this for the
    -- current session only (Data._paused); any re-entry clears the pause.
    local in_fm = self.ui and not self.ui.document
    if in_fm then
        Data._startup_done = true
        if WeReadShelf.shouldAutoEnter() then
            UIManager:nextTick(function() WeReadShelf.showGrid() end)
        end
    end
    self:onDispatcherRegisterActions()
end

function WeReadShelf.shouldAutoEnter()
    return S():isTrue("open_on_start") and not Data._paused
end

-- Gesture / dispatcher action: 「打开微信书架」 (assignable in KOReader
-- 设置 → 手势管理, also usable from profiles / QuickMenu).
function WeReadShelf:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or type(Dispatcher) ~= "table" or type(Dispatcher.registerAction) ~= "function" then return end
    pcall(Dispatcher.registerAction, Dispatcher, "wereadshelf_open", {
        category = "none", event = "WeReadShelfOpen", title = "打开微信书架", general = true,
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
    info("已返回 KOReader。\n再次进入：KOReader 菜单首页「进入微信书架」，或底栏任一 Tab，或手势「打开微信书架」。")
end

-- Solid icon variant = selected state (UI-SPEC: 选中态换实心图标). SimpleUI's
-- own plugin.active_action stayed "home" for our injected widgets in the box
-- emulator, so we track it ourselves: the tab whose page is open is selected.

local function icon_for(base, id_self)
    return function(_id)
        if not plugin_dir then return nil end
        local on = active_tab == id_self
        return plugin_dir .. "/icons/" .. base .. (on and "_active" or "") .. ".svg"
    end
end

function WeReadShelf:registerSimpleUI() return WeReadShelf.registerSimpleUIStatic() end

function WeReadShelf.registerSimpleUIStatic()
    local QA = package.loaded["features/sui_quickactions"]
    if type(QA) ~= "table" or type(QA.register) ~= "function" then return false end
    local descs = {
        { id = QA_ID, label = "微信书架", base = "tab_shelf",
          execute = function() WeReadShelf.showGrid() end },
        { id = QA_DISCOVER, label = "发现", base = "tab_discover",
          execute = function() WeReadShelf.showDiscover() end },
        { id = QA_ME, label = "我", base = "tab_me",
          execute = function() WeReadShelf.showMe() end },
    }
    local any_new = false
    for _, d in ipairs(descs) do
        if not (type(QA.isRegistered) == "function" and QA.isRegistered(d.id)) then
            local ok, err = pcall(QA.register, {
                id = d.id, label = d.label,
                icon = plugin_dir and (plugin_dir .. "/icons/" .. d.base .. ".svg") or nil,
                get_icon = icon_for(d.base, d.id),
                is_in_place = true,
                is_async_in_place = true, -- our widgets outlive execute()
                execute = function(_ctx) d.execute() end,
            })
            if ok then any_new = true else logger.warn("wereadshelf: QA.register failed:", d.id, err) end
        end
    end
    local UI = package.loaded["infra/sui_core"]
    if type(UI) == "table" and type(UI.BarInjection) == "table" and type(UI.BarInjection.register) == "function" then
        -- One descriptor per page widget. The injected bar is built with the
        -- *previous* tab active (sui_patches.lua:2003-2011); active_action_id
        -- only updates the FM's bar (:1873-1886), so on_inject also marks our
        -- tab active on our own bar via Bottombar.setActiveTab
        -- (screens/sui_bottombar.lua:937-959).
        for _, b in ipairs({
            { name = BI_ID, tab = QA_ID, pageable = true },
            { name = "wereadshelf_discover", tab = QA_DISCOVER, pageable = false },
            { name = "wereadshelf_me", tab = QA_ME, pageable = false },
        }) do
            pcall(UI.BarInjection.register, {
                id = b.name, widget_name = b.name, active_action_id = b.tab, is_pageable = b.pageable,
                on_inject = function(widget, ctx)
                    local BB = package.loaded["screens/sui_bottombar"]
                    if type(BB) == "table" and type(BB.setActiveTab) == "function" then
                        pcall(BB.setActiveTab, widget, b.tab, ctx and ctx.tabs)
                    end
                    if type(widget._syncBar) == "function" then pcall(widget._syncBar, widget) end
                end,
            })
        end
    end
    if any_new then
        -- Tabs referencing our ids may have been dropped from the cached tab
        -- list if SimpleUI read its config before we registered.
        local Config = package.loaded["infra/sui_config"]
        if type(Config) == "table" and type(Config.invalidateTabsCache) == "function" then
            pcall(Config.invalidateTabsCache)
        end
    end
    return true
end

-- Preset (explicit, reversible) ----------------------------------------------

local function sui_modules()
    local Store = package.loaded["infra/sui_store"]
    local Config = package.loaded["infra/sui_config"]
    if type(Store) ~= "table" or type(Config) ~= "table" then return nil end
    return Store, Config
end

-- BUG-03: apply and restore share one write path. Tabs / bar mode go through
-- SimpleUI's own setters, which also drop their caches (sui_config.lua:328-331,
-- 347-350); SUISettings:set(k, nil) deletes the key (sui_settings.lua:130,
-- luasettings.lua:102). Tables are copied so SimpleUI never holds our constant.
local function copy_list(t)
    if type(t) ~= "table" then return t end
    local c = {}; for i, v in ipairs(t) do c[i] = v end; return c
end
local function write_sui(Store, Config, vals)
    Config.saveTabConfig(copy_list(vals.simpleui_bar_tabs))
    Config.saveNavbarMode(vals.simpleui_bar_mode)
    if vals.simpleui_bar_navpager_enabled == nil then Store:del("simpleui_bar_navpager_enabled")
    else Store:set("simpleui_bar_navpager_enabled", vals.simpleui_bar_navpager_enabled) end
    if type(Config.invalidateTabsCache) == "function" then Config.invalidateTabsCache() end
end

function WeReadShelf.applyPreset()
    local Store, Config = sui_modules()
    if not Store then return false, "SimpleUI 未加载" end
    local s = S()
    if not s:readSetting("preset_backup") then
        local backup = { _saved = true }
        for _, k in ipairs(PRESET_KEYS) do backup[k] = copy_list(Store:get(k)) end
        backup.open_on_start = s:isTrue("open_on_start")
        s:saveSetting("preset_backup", backup)
    end
    write_sui(Store, Config, PRESET)
    s:saveSetting("open_on_start", true)
    s:flush()
    return true
end

function WeReadShelf.restorePreset()
    local Store, Config = sui_modules()
    if not Store then return false, "SimpleUI 未加载" end
    local s = S()
    local b = s:readSetting("preset_backup")
    if type(b) ~= "table" then return false, "没有可恢复的备份（从未应用过预设）" end
    write_sui(Store, Config, b)
    s:saveSetting("open_on_start", b.open_on_start == true)
    s:delSetting("preset_backup")
    s:flush()
    return true
end

local function ask_restart(text)
    -- UIManager:askForRestart shows its own confirm box (frontend/ui/uimanager.lua:1628)
    UIManager:askForRestart(text .. "需要重启 KOReader 才能完整生效。")
end

function WeReadShelf:addToMainMenu(menu_items)
    -- v0.3.4: one obvious top-level entry (first page of the KOReader menu).
    local ui = self.ui
    menu_items.wereadshelf_enter = {
        text = "进入微信书架",
        sorting_hint = "main",
        callback = function() WeReadShelf.enter(ui) end,
    }
    menu_items.wereadshelf = {
        text = "微信书架",
        sorting_hint = "tools",
        sub_item_table = {
            { text = "打开书架（封面网格）", callback = function() WeReadShelf.showGrid() end },
            { text = "打开发现页", callback = function() WeReadShelf.showDiscover() end },
            { text = "打开我的页", callback = function() WeReadShelf.showMe() end },
            { text = "打开书架（文字列表）", callback = function() WeReadShelf.showShelfStatic() end, separator = true },
            {
                text = "微信读书风格阅读菜单（点屏幕中部呼出）",
                checked_func = function() return S():isTrue("reader_menu") end,
                callback = function() WeReadShelf.toggleSetting("reader_menu") end,
            },
            {
                text = "微信读书模式（启动/合上书时自动进书架）",
                checked_func = function() return S():isTrue("open_on_start") end,
                callback = function() WeReadShelf.toggleSetting("open_on_start") end,
                separator = true,
            },
            { text = "一键开启微信读书模式…", callback = function() WeReadShelf.confirmWeChatMode() end },
            {
                text = "一键回原生（恢复 KOReader / SimpleUI 原状）…",
                callback = function() WeReadShelf.confirmBackToNative() end,
            },
        },
    }
end

function WeReadShelf.toggleSetting(key)
    S():saveSetting(key, not S():isTrue(key)); S():flush()
    if key == "reader_menu" then info("阅读菜单设置将在下次打开书时生效。") end
end

-- 微信读书模式 = SimpleUI preset (with backup) + reading menu + open on start.
function WeReadShelf.applyWeChatMode()
    local ok, e = WeReadShelf.applyPreset()
    if not ok then return false, e end
    Data._paused = false
    local s = S()
    local b = s:readSetting("preset_backup")
    if type(b) == "table" and b.reader_menu == nil then
        b.reader_menu = s:isTrue("reader_menu"); s:saveSetting("preset_backup", b)
    end
    s:saveSetting("reader_menu", true)
    s:flush()
    return true
end

-- 一键回原生: undo everything this plugin changed. SimpleUI keys come back
-- from the backup taken before the first change; our own switches go back to
-- their pre-mode values (default off). Book-level font settings changed from
-- the 字体 panel are KOReader's per-book settings and are kept.
-- Returns true | false, reason. BUG-02: without a backup nothing was changed
-- by us, so nothing is touched (the user's own switches stay as they are).
WeReadShelf.NO_BACKUP = "没有可恢复的备份：从未开启过微信读书模式，设置未改动。"
function WeReadShelf.backToNative()
    local s = S()
    local b = s:readSetting("preset_backup")
    if type(b) ~= "table" then return false, WeReadShelf.NO_BACKUP end
    local reader_menu = b.reader_menu == true
    local ok, e = WeReadShelf.restorePreset()
    if not ok then return false, e end
    s:saveSetting("reader_menu", reader_menu)
    s:flush()
    close_pages()
    return true
end

local function back_to_native_then(after)
    local ok, e = WeReadShelf.backToNative()
    if ok then after() else info(tostring(e)) end
end

function WeReadShelf.confirmWeChatMode()
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = "将开启微信读书模式（先备份，可用「一键回原生」完全恢复）：\n"
            .. "• SimpleUI 底栏 Tab = 发现、书架、我；仅图标；底栏翻页键\n"
            .. "• 启动时打开书架\n• 阅读时点屏幕中部呼出微信读书风格菜单\n"
            .. "不修改 SimpleUI 的其它设置，也不修改 KOReader 的设置。",
        ok_text = "开启",
        ok_callback = function()
            local ok, e = WeReadShelf.applyWeChatMode()
            if ok then ask_restart("已开启。") else info("未开启：" .. tostring(e)) end
        end,
    })
end

function WeReadShelf.confirmBackToNative()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    dlg = ButtonDialog:new{
        title = "一键回原生\n恢复本插件改过的 SimpleUI 底栏设置，关闭微信读书风格菜单和启动进书架。"
            .. "\n（书里调过的字号等属于该书自己的阅读设置，保留。）",
        buttons = {
            { { text = "恢复原状并重启 KOReader", callback = function()
                UIManager:close(dlg)
                back_to_native_then(function() UIManager:askForRestart("已恢复原状。") end) end } },
            { { text = "恢复原状并退出到 Kindle", callback = function()
                UIManager:close(dlg)
                back_to_native_then(WeReadShelf.exitToKindle) end } },
            { { text = "只退出到 Kindle（不改设置）", callback = function()
                UIManager:close(dlg); WeReadShelf.exitToKindle() end } },
            { { text = "取消", callback = function() UIManager:close(dlg) end } },
        },
    }
    UIManager:show(dlg)
end

-- Same as KOReader's own 退出 (frontend/ui/elements/common_exit_menu_table.lua:8-19);
-- on Kindle the launcher then returns to the native home screen.
function WeReadShelf.exitToKindle()
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("Exit"))
end

function WeReadShelf.showSettingsDialog()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local function mark(k) return S():isTrue(k) and "✓ " or "　" end
    local function btn(text, fn) return { { text = text, callback = function() UIManager:close(dlg); fn() end } } end
    dlg = ButtonDialog:new{
        title = "阅读设置",
        buttons = {
            btn(mark("reader_menu") .. "微信读书风格阅读菜单", function() WeReadShelf.toggleSetting("reader_menu") end),
            btn(mark("open_on_start") .. "微信读书模式（自动进书架）", function() WeReadShelf.toggleSetting("open_on_start") end),
            btn("微信读书插件设置（weread）", function()
                -- weread's own settings live in its main menu (weread/ui/menu.lua:155)
                info("请从 KOReader 菜单 → 微信读书 → 设置 进入。") end),
            btn("返回 KOReader（文件浏览器）", function() WeReadShelf.leaveToKOReader() end),
            btn("一键开启微信读书模式…", function() WeReadShelf.confirmWeChatMode() end),
            btn("一键回原生…", function() WeReadShelf.confirmBackToNative() end),
        },
    }
    UIManager:show(dlg)
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

-- Conventional launcher names (SimpleUI scanner: onShow/show/open/launch).
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

local function call_weread(method, ...)
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
        rows = {
            { text = "阅读时长统计", fn = function() call_weread("showReadStats") end },   -- read_report.lua:238
            { text = "我的笔记", fn = function()
                info("weread 1.6.0 没有「全部笔记」列表接口。\n打开一本书后：阅读菜单「更多」→ 书签列表，"
                    .. "或 weread 菜单「划线和想法管理」查看该书笔记。") end },
            { text = "书架同步", fn = function() call_weread("openBookshelf") end },        -- main.lua:33
            { text = "阅读设置", fn = function() WeReadShelf.showSettingsDialog() end },
            { text = "返回 KOReader", bold = true, fn = function() WeReadShelf.leaveToKOReader() end },
            { text = "退出到 Kindle / 恢复原生…", fn = function() WeReadShelf.confirmBackToNative() end },
        },
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
    -- auto refresh when online and the cache is older than 30 min (no prompt when offline)
    local c = WeReadShelf.statsCache()
    if not c.at or os.time() - c.at > 1800 then
        WeReadShelf.refreshStats(weread, function()
            if current_page == page then page.stats = stats(); page:refresh() end
        end, true)
    end
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
        title = string.format("微信书架（%d）", #books),
        item_table = items,
        is_borderless = true,
        title_bar_fm_style = true,
    }
    UIManager:show(menu)
end

function WeReadShelf:showShelf() WeReadShelf.showGrid() end

-- IMPORTANT — SimpleUI load-order workaround (no SimpleUI file is changed):
-- simpleui.koplugin's init() calls Config.sanitizeQASlots()
-- (simpleui main.lua:937-943 -> features/sui_quickactions.lua:1403-1422),
-- which *permanently* removes tab ids that QA.isRegistered() does not know
-- yet. Plugins are initialised in path order (frontend/pluginloader.lua:289),
-- so SimpleUI's init runs before ours and would drop our tabs on every boot.
-- main.lua files are all dofile()'d before any init(), and SimpleUI's
-- main.lua already required infra/sui_store (simpleui main.lua:24), so we
-- snapshot the user's own tab list now and, once our ids are registered in
-- init(), put back exactly that list if SimpleUI pruned our ids from it.
do
    local Store = package.loaded["infra/sui_store"]
    if type(Store) == "table" and type(Store.get) == "function" then
        local ok, tabs = pcall(Store.get, Store, "simpleui_bar_tabs")
        if ok and type(tabs) == "table" then
            local copy = {}
            for i, id in ipairs(tabs) do copy[i] = id end
            Data._tabs_snapshot = copy
        end
    end
end

local OUR_IDS = { [QA_ID] = true, [QA_DISCOVER] = true, [QA_ME] = true }

-- Returns the list to write back, or nil when nothing of ours was pruned.
function WeReadShelf.tabsToRestore(snapshot, current, is_valid)
    if type(snapshot) ~= "table" then return nil end
    local cur = {}
    for _, id in ipairs(type(current) == "table" and current or {}) do cur[id] = true end
    local pruned = false
    for _, id in ipairs(snapshot) do
        if OUR_IDS[id] and not cur[id] then pruned = true end
    end
    if not pruned then return nil end
    local out = {}
    for _, id in ipairs(snapshot) do
        if OUR_IDS[id] or cur[id] or (is_valid and is_valid(id)) then out[#out + 1] = id end
    end
    return out
end

function WeReadShelf.restorePrunedTabs()
    local snap = Data._tabs_snapshot
    Data._tabs_snapshot = nil -- once per process
    local Store, Config = sui_modules()
    if not Store or not snap then return false end
    local QA = package.loaded["features/sui_quickactions"]
    local out = WeReadShelf.tabsToRestore(snap, Store:get("simpleui_bar_tabs"),
        QA and QA.isRegistered and function(id) return QA.isRegistered(id) end)
    if not out then return false end
    Store:set("simpleui_bar_tabs", out)
    if type(Config.invalidateTabsCache) == "function" then Config.invalidateTabsCache() end
    logger.info("wereadshelf: restored SimpleUI tabs pruned before our registration:", table.concat(out, ","))
    return true
end

WeReadShelf._Layout = Layout
return WeReadShelf
