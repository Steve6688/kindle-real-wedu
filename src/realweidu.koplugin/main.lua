-- realweidu.koplugin — "Real微读": standalone WeRead-style home for KOReader
-- (发现 / 书架 / 我 with its own bottom bar) + 4-column cover grid, backed by
-- weread.koplugin's local shelf cache. Does not modify weread files and does
-- not need (or touch) SimpleUI (removed in 0.3.7).
--
-- weread 1.6.0 entry points used (public methods on the plugin instance,
-- mixed in at weread main.lua:222-233):
--   openBookshelf()   main.lua:33  (0.3.8: redirected to Real微读's shelf)
--   refreshBookshelf() weread/ui/library.lua:150 (login if needed + shelf sync)
--   showSearch()      weread/ui/library.lua:1640   (online WeRead search dialog)
--   searchWithUI(kw)  weread/ui/library.lua:1673
--   showReadStats()   weread/ui/read_report.lua:238 (reading statistics)

local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage     = require("ui/widget/infomessage")
local Menu            = require("ui/widget/menu")
local logger          = require("logger")
local Logic           = require("realweidu_logic")

-- Must be required at top level: KOReader only puts the plugin dir on
-- package.path while dofile()'ing main.lua (frontend/pluginloader.lua:242-244).
local Data   = require("realweidu_data")
-- 0.4.0: weread.koplugin 1.6.0 is embedded (rweread/, AGPL-3.0, finlater and
-- contributors). Its modules are required lazily at runtime too, so keep this
-- plugin's folder on package.path after loading.
do
    local src = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$")
    if src and not package.path:find(src .. "/?.lua", 1, true) then
        package.path = src .. "/?.lua;" .. package.path
    end
end
local okw, WeReadPlugin = pcall(require, "rweread.plugin")
if not okw then logger.warn("realweidu: embedded weread failed to load:", WeReadPlugin); WeReadPlugin = nil end
local FastDL = require("realweidu_fastdl")
local Stream = require("realweidu_stream") -- 0.6.1 边下边读
local Layout = require("realweidu_layout")
local ShelfGrid -- lazy (pulls in UI widgets)

local QA_ID       = "realweidu_open"     -- 书架 (tab id)
local QA_DISCOVER = "realweidu_discover" -- 发现
local QA_ME       = "realweidu_me"       -- 我

local RealWeidu = WidgetContainer:extend{
    name = "realweidu",
    is_doc_only = false,
}

-- Plugin dir from this file's path (main.lua is dofile()'d by
-- frontend/pluginloader.lua:244, so the chunk source is its full path).
local plugin_dir = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$")

local function info(text)
    UIManager:show(InfoMessage:new{ text = text })
end

-- 0.4.1: renamed wereadshelf.koplugin -> realweidu.koplugin. One-time
-- migration of our own settings (weread's settings/weread.lua + weread/ data
-- are untouched). Idempotent; never overwrites an existing new-name value.
local LEGACY = "wereadshelf"
local function rename_ids(t, depth)
    if type(t) ~= "table" or depth > 6 then return false end
    local changed = false
    for k, v in pairs(t) do
        if type(k) == "string" and k:find(LEGACY, 1, true) == 1 then
            local nk = "realweidu" .. k:sub(#LEGACY + 1)
            if t[nk] == nil then t[nk] = v end
            t[k] = nil; changed = true
        elseif type(v) == "string" and v:find(LEGACY .. "_", 1, true) == 1 then
            t[k] = "realweidu" .. v:sub(#LEGACY + 1); changed = true
        end
        if type(v) == "table" and rename_ids(v, depth + 1) then changed = true end
    end
    return changed
end
RealWeidu._rename_ids = function(t) return rename_ids(t, 0) end
function RealWeidu.migrate(G, settings_dir)
    G = G or rawget(_G, "G_reader_settings")
    local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not settings_dir then
        local ok, DS = pcall(require, "datastorage")
        settings_dir = ok and DS:getSettingsDir() or nil
    end
    local moved = {}
    -- 1. settings/wereadshelf*.lua -> settings/realweidu*.lua
    if settings_dir and lfs_ok then
        for f in lfs.dir(settings_dir) do
            if f:find(LEGACY, 1, true) == 1 and f:match("%.lua") then
                local nf = "realweidu" .. f:sub(#LEGACY + 1)
                if not lfs.attributes(settings_dir .. "/" .. nf, "mode") then
                    if os.rename(settings_dir .. "/" .. f, settings_dir .. "/" .. nf) then table.insert(moved, nf) end
                end
            end
        end
        -- 2. gesture / profile action ids (wereadshelf_open -> realweidu_open)
        for _, f in ipairs({ "gestures.lua", "profiles.lua" }) do
            local path = settings_dir .. "/" .. f
            if lfs.attributes(path, "mode") then
                local ok, LS = pcall(require, "luasettings")
                if ok then
                    local st = LS:open(path)
                    if rename_ids(st.data, 0) then st:flush(); table.insert(moved, f) end
                end
            end
        end
    end
    if G and G.data then
        -- 3. G_reader_settings keys wereadshelf_* (and nested action ids)
        local dirty = false
        for k, v in pairs(G.data) do
            if type(k) == "string" and k:find(LEGACY, 1, true) == 1 then
                local nk = "realweidu" .. k:sub(#LEGACY + 1)
                if G.data[nk] == nil then G.data[nk] = v end
                G.data[k] = nil; dirty = true
            end
        end
        -- 4. the old wereadshelf.koplugin folder, if still present, stays off
        local dis = G:readSetting("plugins_disabled") or {}
        if dis.realweidu then dis.realweidu = nil; dirty = true end
        if not dis[LEGACY] then dis[LEGACY] = true; dirty = true end
        if dirty then G:saveSetting("plugins_disabled", dis); if G.flush then G:flush() end end
    end
    if #moved > 0 then logger.info("realweidu: migrated", table.concat(moved, ", ")) end
    return moved
end
-- An old wereadshelf.koplugin loaded in this same session (it sorts after
-- us) is refused before it can create a second shelf / menu entry.
do
    local okp, PL = pcall(require, "pluginloader")
    if okp and type(PL) == "table" and not PL._realweidu_guard then
        PL._realweidu_guard = true
        local orig = PL.createPluginInstance
        PL.createPluginInstance = function(pl, plugin, attr)
            if plugin and plugin.name == LEGACY then
                logger.info("realweidu: ignoring old wereadshelf.koplugin (renamed to realweidu.koplugin)")
                return nil, "superseded by realweidu.koplugin"
            end
            return orig(pl, plugin, attr)
        end
    end
end
pcall(RealWeidu.migrate)

-- Own settings file (only written by explicit menu actions).
local _settings
local function settings()
    if not _settings then
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        _settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/realweidu.lua")
    end
    return _settings
end
RealWeidu._settings_override = nil -- tests
local function S() return RealWeidu._settings_override or settings() end
-- v0.3.5: reader menu defaults to ON; only an explicit false turns it off.
local function on(key) return S():readSetting(key) ~= false end
RealWeidu.isOn = on
RealWeidu.ENTER_TEXT = "进入 Real微读"
RealWeidu.VERSION = "0.6.1"

-- Put 「进入 Real微读」 at the top of KOReader's ☰ (main) menu tab instead of
-- after Exit (items missing from the order table are appended at the end).
local function pin_menu_entry()
    for _, mod in ipairs({ "ui/elements/filemanager_menu_order", "ui/elements/reader_menu_order" }) do
        local ok, order = pcall(require, mod)
        if ok and type(order) == "table" and type(order.main) == "table" then
            local has = false
            for _, k in ipairs(order.main) do if k == "realweidu_enter" then has = true end end
            if not has then table.insert(order.main, 1, "realweidu_enter") end
        end
    end
end

-- 0.4.0: one plugin. Start the embedded weread on this ui (file manager or
-- reader) under the same name ("weread"), settings file (settings/weread.lua)
-- and data dir (<data>/weread), so login, cookies, cache and downloaded books
-- carry over untouched. A separately installed weread.koplugin (loaded before
-- us) is detached for this session and disabled for the next start.
RealWeidu._plugin_class = nil -- tests
local function detach_foreign(ui, old)
    for i = #ui, 1, -1 do if ui[i] == old then table.remove(ui, i) end end
    if type(ui.active_widgets) == "table" then
        for i = #ui.active_widgets, 1, -1 do if ui.active_widgets[i] == old then table.remove(ui.active_widgets, i) end end
    end
    local reg = ui.menu and ui.menu.registered_widgets
    if type(reg) == "table" then
        for i = #reg, 1, -1 do if reg[i] == old then table.remove(reg, i) end end
    end
    pcall(function() if old.prefetch_worker and old.prefetch_worker.cancel then old.prefetch_worker:cancel() end end)
    local G = rawget(_G, "G_reader_settings")
    if G then
        local dis = G:readSetting("plugins_disabled") or {}
        if not dis.weread then
            dis.weread = true
            G:saveSetting("plugins_disabled", dis)
            if G.flush then G:flush() end
        end
    end
    RealWeidu._detached_foreign = true
    logger.info("realweidu: separate weread.koplugin detached and disabled (now built into Real微读)")
end

function RealWeidu.attachWeread(ui)
    if type(ui) ~= "table" then return nil end
    local old = ui.weread
    if old and old._real_embedded then return old end
    if old then detach_foreign(ui, old) end
    local cls = RealWeidu._plugin_class or WeReadPlugin
    if cls and not cls.version then -- PluginLoader would copy weread's _meta (version, fullname)
        local okm, meta = pcall(require, "rweread._weread_meta")
        if okm and type(meta) == "table" then for k, v in pairs(meta) do if cls[k] == nil then cls[k] = v end end end
    end
    if not cls then ui.weread = nil; return nil end
    local ok, inst = pcall(cls.new, cls, { ui = ui, dialog = ui.dialog, view = ui.view, document = ui.document,
        path = (plugin_dir or ".") .. "/rweread", _real_embedded = true })
    if not ok or type(inst) ~= "table" then
        logger.warn("realweidu: embedded weread init failed:", inst)
        ui.weread = nil
        return nil
    end
    inst._real_embedded = true
    inst.real_shelf_redirect = function() return RealWeidu.toRealShelf() end
    inst._wrs_redirect = true
    if type(ui.registerModule) == "function" then ui:registerModule("weread", inst) else ui.weread = inst end
    return inst
end

local current_grid, current_page, active_tab
local close_pages, take_pages, ui_icons, call_weread -- defined further below

function RealWeidu:init()
    plugin_dir = self.path or plugin_dir
    RealWeidu.attachWeread(self.ui)
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
        if RealWeidu.shouldAutoEnter() then
            UIManager:nextTick(function() RealWeidu.showGrid() end)
            if UIManager.scheduleIn then
                UIManager:scheduleIn(1.5, function() RealWeidu.ensureOnTop() end)
            end
        end
    end
    self:onDispatcherRegisterActions()
    -- v0.3.8: every weread 「书架」 entry point opens Real微读's shelf.
    if self.ui and self.ui.weread then pcall(RealWeidu.redirectWereadShelf, self.ui.weread) end
    -- v0.3.8: smooth page turns (no animation, fewer full flashes); session only.
    if self.ui and self.ui.document then pcall(RealWeidu.applySmoothTurns) end
    -- v0.3.6 faster weread downloads (default ON; 更多设置 → 快速下载).
    if on("fast_download") then
        local ok, e = pcall(FastDL.install)
        if not ok then logger.warn("realweidu: fast download not installed:", e)
        elseif e and FastDL.speedups then -- 0.6.0
            logger.info("realweidu: fast download installed", "decrypt=", tostring(FastDL.speedups.decrypt),
                "gzip=", tostring(FastDL.speedups.gzip), "md5=", tostring(FastDL.Decrypt.md5_name))
        end
        -- 0.6.1 边下边读: full-book downloads open after the first chapters
        local oks, es = pcall(Stream.install)
        if not oks then logger.warn("realweidu: stream download not installed:", es) end
        if self.ui and self.ui.document then pcall(Stream.on_reader_open, self.ui) end
        Stream.on_change = function() -- shelf progress label, at most every 10 s
            local g = current_grid
            if not (g and g._refresh) or (UIManager._window_stack and #UIManager._window_stack > 0
                and UIManager._window_stack[#UIManager._window_stack].widget ~= g) then return end
            local t = os.time()
            if RealWeidu._stream_shelf_t and t - RealWeidu._stream_shelf_t < 10 then return end
            RealWeidu._stream_shelf_t = t
            pcall(g._refresh, g)
        end
        if not RealWeidu._stream_resumed and UIManager.scheduleIn then
            RealWeidu._stream_resumed = true -- once per KOReader session
            UIManager:scheduleIn(3, function() pcall(Stream.resume_all) end)
        end
    end
end

-- 0.6.1: a book downloading in the background follows the reader's chapter.
function RealWeidu:onPageUpdate()
    if self.ui and self.ui.document and (next(Stream.jobs) ~= nil or next(Stream.finished) ~= nil) then
        local ok, e = pcall(Stream.on_page, self.ui)
        if not ok then logger.warn("realweidu: stream page", e) end
    end
end

function RealWeidu.shouldAutoEnter()
    return not Data._paused and not RealWeidu._exiting -- 返回 KOReader pauses only until next start / re-entry
end

-- Something (e.g. a stale SimpleUI Home Screen) may still be shown after our first
-- tick; check again shortly and bring the shelf back to the front.
local function is_ours(w)
    return w and (w.name == "realweidu_grid" or w.name == "realweidu_discover" or w.name == "realweidu_me")
end
function RealWeidu.ensureOnTop()
    if Data._paused then return false end
    local RUI = package.loaded["apps/reader/readerui"]
    if RUI and RUI.instance then return false end -- a book is open: never cover it
    local st = UIManager._window_stack
    local top = type(st) == "table" and st[#st] and st[#st].widget
    if type(top) ~= "table" or is_ours(top) then return false end
    local nm = tostring(top.name or "")
    if nm == "filemanager" or nm == "homescreen" or nm:find("^sui_") then
        RealWeidu.showGrid(); return true
    end
    return false
end

-- Gesture / dispatcher action: 「打开 Real微读」 (assignable in KOReader
-- 设置 → 手势管理, also usable from profiles / QuickMenu).
function RealWeidu:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or type(Dispatcher) ~= "table" or type(Dispatcher.registerAction) ~= "function" then return end
    pcall(Dispatcher.registerAction, Dispatcher, "realweidu_open", {
        category = "none", event = "RealWeiduOpen", title = "打开 Real微读", general = true,
    })
    -- legacy id from <=0.4.0 (gestures not yet migrated keep working)
    pcall(Dispatcher.registerAction, Dispatcher, "wereadshelf_open", {
        category = "none", event = "RealWeiduOpen", title = "打开 Real微读（旧）", general = true,
    })
end

function RealWeidu:onRealWeiduOpen()
    RealWeidu.enter(self.ui)
    return true
end

-- One-tap entry from plain KOReader (main-menu item, gesture, tab tap).
-- In the reader it closes the book first (to the file manager), then shows
-- the shelf.
function RealWeidu.enter(ui)
    Data._paused = false
    RealWeidu._exiting = nil
    if ui and ui.document and type(ui.onHome) == "function" then
        local ok = pcall(ui.onHome, ui)
        if ok and not RealWeidu.shouldAutoEnter() then
            UIManager:scheduleIn(0.3, function() RealWeidu.showGrid() end)
        end
        return
    end
    return RealWeidu.showGrid()
end

-- 「返回 KOReader」: close our pages, stay in KOReader's file browser for this
-- session. Settings are untouched; the mode comes back on next start, after
-- re-entry via menu / gesture, or by tapping a bottom-bar tab.
function RealWeidu.leaveToKOReader()
    Data._paused = true
    close_pages()
    info("已返回 KOReader。\n再次进入：KOReader 菜单 ☰ 第一项「进入 Real微读」，或手势「打开 Real微读」；下次启动自动进入。")
end

function RealWeidu:addToMainMenu(menu_items)
    -- v0.3.4: one obvious top-level entry (first page of the KOReader menu).
    local ui = self.ui
    menu_items.realweidu_enter = {
        text = RealWeidu.ENTER_TEXT,
        sorting_hint = "main",
        callback = function() RealWeidu.enter(ui) end,
    }
    menu_items.realweidu = {
        text = "Real微读",
        sorting_hint = "tools",
        sub_item_table = {
            { text = "打开 Real微读", callback = function() RealWeidu.showGrid() end },
            {
                text = "登录与同步书架",
                callback = function() RealWeidu.openWereadManagement() end,
                separator = true,
            },
            {
                text = "阅读时使用 Real微读菜单",
                checked_func = function() return on("reader_menu") end,
                callback = function() RealWeidu.toggleSetting("reader_menu") end,
            },
            { text = "阅读设置…", callback = function() RealWeidu.showSettingsDialog() end,
              separator = true },
            -- 0.4.0: weread's own menu (login, shelf, search, public accounts,
            -- cache, reading report, settings ...) folded in here
            { text = "微信读书功能", sub_item_table_func = function()
                local w = self.ui and self.ui.weread
                if w and type(w.getMainMenuItems) == "function" then
                    local ok, items = pcall(w.getMainMenuItems, w)
                    if ok and type(items) == "table" then return items end
                end
                return { { text = "微信读书模块未加载", enabled = false } }
            end },
        },
    }
end

-- v0.3.8: weread's own shelf list never shows. Every way into it on a weread
-- instance (openBookshelf / launch / showBookshelf: ☰ 微信读书 → 书架, the
-- 「微信读书·书架」 gesture, the end-of-book dialog's 书架 button, third-party
-- launchers, and refreshBookshelf's result after login / sync) ends in
-- showBookshelf or showShelfView (weread/ui/library.lua:71,150,365); both
-- are replaced on the instance so they open Real微读's shelf instead. The
-- public-account list (mode "public_account") is not a 书架 and stays.
-- In a book, the book is closed first (the file manager re-init then shows
-- the shelf, exactly like closing a book).
function RealWeidu.toRealShelf()
    local RUI = package.loaded["apps/reader/readerui"]
    local r = RUI and RUI.instance
    if r and r.document then
        Data._paused = false
        UIManager:nextTick(function() RealWeidu.enter(r) end)
        return true
    end
    UIManager:nextTick(function() RealWeidu.showGrid() end)
    return true
end

function RealWeidu.redirectWereadShelf(weread)
    if type(weread) ~= "table" or weread._wrs_redirect then return false end
    if type(weread.showShelfView) ~= "function" and type(weread.showBookshelf) ~= "function" then return false end
    weread._wrs_redirect = true
    local orig_view = weread.showShelfView
    weread._wrs_orig_showShelfView = orig_view
    weread.showShelfView = function(self_w, mode, keyword, old_view, options)
        if mode == "public_account" and orig_view then
            return orig_view(self_w, mode, keyword, old_view, options)
        end
        if old_view then pcall(UIManager.close, UIManager, old_view) end
        if self_w.shelf_view == old_view then self_w.shelf_view = nil end
        return RealWeidu.toRealShelf()
    end
    weread._wrs_orig_showBookshelf = weread.showBookshelf
    weread.showBookshelf = function(self_w)
        local cached
        pcall(function() cached = self_w.library_db and self_w.library_db:getShelf() end)
        if (type(cached) == "table" and #cached > 0) or type(self_w.refreshBookshelf) ~= "function" then
            return RealWeidu.toRealShelf()
        end
        -- nothing cached yet: weread's sync (QR login first when needed);
        -- its result goes through showShelfView -> Real微读
        return self_w:refreshBookshelf()
    end
    -- after a successful QR login: fetch the shelf and show it in Real微读
    if type(weread.refreshLoginMenu) == "function" then
        local orig_login = weread.refreshLoginMenu
        local was = Data.is_logged_in(weread)
        weread.refreshLoginMenu = function(self_w, ...)
            local r = orig_login(self_w, ...)
            local now = Data.is_logged_in(self_w)
            if now and not was and type(self_w.refreshBookshelf) == "function" then
                UIManager:scheduleIn(0.5, function() pcall(self_w.refreshBookshelf, self_w) end)
            end
            was = now
            return r
        end
    end
    return true
end

-- 书架同步 / 导入 / 登录: weread's sync (and QR login when needed); the
-- result is shown in Real微读's shelf (see redirectWereadShelf).
function RealWeidu.syncShelf()
    local weread = Data.find_weread()
    if not weread then
        info("未找到 weread.koplugin，请先安装或启用微信读书插件。")
        return false
    end
    RealWeidu.redirectWereadShelf(weread)
    local fn = weread.refreshBookshelf or weread.openBookshelf
    if type(fn) ~= "function" then info("微信读书插件版本不支持书架同步。"); return false end
    local ok, err = pcall(fn, weread)
    if not ok then info("书架同步失败：" .. tostring(err)); return false end
    return true
end
-- older name (☰ menu, tests)
RealWeidu.openWereadManagement = RealWeidu.syncShelf

-- v0.3.8 流畅翻页 (default on, session only; nothing is written to KOReader's
-- settings): no page-turn animation (readerview.lua onPageChangeAnimation) and,
-- when the user kept KOReader's default (6), a full e-ink refresh every 12
-- pages instead of 6 (UIManager.FULL_REFRESH_COUNT, uimanager.lua:17,741).
-- Page turns keep KOReader's "partial" waveform (text stays crisp; "fast"/A2
-- would ghost and look jagged on PW5).
RealWeidu.SMOOTH_REFRESH_COUNT = 12
function RealWeidu.applySmoothTurns()
    local okv, RV = pcall(require, "apps/reader/modules/readerview")
    if on("smooth_turns") then
        if okv and type(RV) == "table" and not RV._wrs_orig_anim then
            RV._wrs_orig_anim = RV.onPageChangeAnimation or false
            RV.onPageChangeAnimation = function() end
        end
        local G = rawget(_G, "G_reader_settings")
        local user_rate = G and G:readSetting("full_refresh_count")
        if user_rate == nil and not (G and G:isTrue("night_mode")) then
            if UIManager._wrs_orig_rate == nil then UIManager._wrs_orig_rate = UIManager.FULL_REFRESH_COUNT or false end
            UIManager.FULL_REFRESH_COUNT = RealWeidu.SMOOTH_REFRESH_COUNT
        end
        return true
    end
    if okv and type(RV) == "table" and RV._wrs_orig_anim ~= nil then
        RV.onPageChangeAnimation = RV._wrs_orig_anim or nil
        RV._wrs_orig_anim = nil
    end
    if UIManager._wrs_orig_rate ~= nil then
        UIManager.FULL_REFRESH_COUNT = UIManager._wrs_orig_rate or nil
        UIManager._wrs_orig_rate = nil
    end
    return false
end

function RealWeidu.toggleSetting(key)
    S():saveSetting(key, not on(key)); S():flush()
    if key == "smooth_turns" then pcall(RealWeidu.applySmoothTurns) end
    if key == "reader_menu" then info("已保存，下次打开书时生效。") end
end

-- Same as KOReader's own 退出 (frontend/ui/elements/common_exit_menu_table.lua:8-19);
-- on Kindle the launcher then returns to the native home screen.
-- 0.4.2 fix: KOReader only quits once its window stack is empty; our
-- full-screen shelf/「我」 pages stayed open on top of the closed file
-- manager, so Exit closed the FM underneath and KOReader kept running.
function RealWeidu.exitToKindle()
    RealWeidu._exiting = true
    Data._paused = true
    close_pages()
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("Exit"))
    -- anything else still on screen (dialogs, notices) must not keep KOReader alive
    UIManager:nextTick(function()
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i]
            if w and w.widget then UIManager:close(w.widget) end
        end
        pcall(UIManager.quit, UIManager)
    end)
end

function RealWeidu.confirmExitToKindle()
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = "退出 KOReader，返回 Kindle 主界面？",
        ok_text = "退出",
        ok_callback = function() RealWeidu.exitToKindle() end,
    })
end

-- 「我」 rows, as in 0.3.3 (+ 返回 KOReader, which 0.3.5 added).
function RealWeidu.meRows()
    return {
        { text = "阅读时长统计", fn = function() call_weread("showReadStats") end },   -- read_report.lua:238
        { text = "我的笔记", fn = function()
            info("weread 1.6.0 没有「全部笔记」列表接口。\n打开一本书后：阅读菜单「更多」→ 书签列表，"
                .. "或 weread 菜单「划线和想法管理」查看该书笔记。") end },
        { text = "书架同步", fn = function() RealWeidu.syncShelf() end },
        { text = "阅读设置", fn = function() RealWeidu.showSettingsDialog() end },
        { text = "退出到 Kindle", fn = function() RealWeidu.confirmExitToKindle() end },
        { text = "返回 KOReader", fn = function() RealWeidu.leaveToKOReader() end },
    }
end

-- 「阅读设置」 dialog (0.3.3 look): switches + KOReader's full menu.
function RealWeidu.settingsItems()
    local function mark(k) return on(k) and "✓ " or "　" end
    return {
        { text = mark("reader_menu") .. "Real微读阅读菜单", fn = function() RealWeidu.toggleSetting("reader_menu") end },
        { text = mark("fast_download") .. "快速下载（3–5 章并行）", fn = function()
            RealWeidu.toggleSetting("fast_download")
            info("已保存，重启 KOReader 后生效。") end },
        { text = mark("smooth_turns") .. "流畅翻页（无动画 · 每 12 页全刷）", fn = function()
            RealWeidu.toggleSetting("smooth_turns") end },
    }
end
-- 0.3.7 name kept for callers
RealWeidu.moreSettingsItems = RealWeidu.settingsItems

function RealWeidu.showSettingsDialog()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local buttons = {}
    for _, it in ipairs(RealWeidu.settingsItems()) do
        buttons[#buttons + 1] = { { text = it.text, callback = function() UIManager:close(dlg); it.fn() end } }
    end
    dlg = ButtonDialog:new{ title = "阅读设置", buttons = buttons }
    UIManager:show(dlg)
    return dlg
end
RealWeidu.showMoreSettings = RealWeidu.showSettingsDialog

-- KOReader's own full menu, on top of the file manager (our pages close).
function RealWeidu.openKOReaderMenu()
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
RealWeidu.CENTER_ZONE = { ratio_x = 0.25, ratio_y = 0.25, ratio_w = 0.5, ratio_h = 0.5 }

function RealWeidu:hookReader()
    local ui = self.ui
    if not (ui and type(ui.registerTouchZones) == "function") then return end
    ui:registerTouchZones({ {
        id = "realweidu_menu_tap",
        ges = "tap",
        screen_zone = RealWeidu.CENTER_ZONE,
        overrides = { "tap_forward", "tap_backward" },
        handler = function() return RealWeidu.showReaderMenu(ui) end,
    },
    -- 0.5.0 查词模式: when on, a single tap on a word looks it up (and adds it to the
    -- vocabulary builder); taps in the left/right edge strips, or on no word, fall through
    -- to page turning / the menu zone. When off the handler returns false immediately.
    {
        id = "realweidu_lookup_tap",
        ges = "tap",
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        overrides = { "realweidu_menu_tap", "tap_forward", "tap_backward", "readermenu_tap", "readerconfigmenu_tap" },
        handler = function(ges) return RealWeidu.lookupTap(ui, ges) end,
    } })
end

function RealWeidu.lookupModeOn()
    local G = rawget(_G, "G_reader_settings")
    return G and G:isTrue(Logic.LOOKUP_SETTING) or false
end

function RealWeidu.setLookupMode(on)
    local G = rawget(_G, "G_reader_settings")
    if not G then return end
    G:saveSetting(Logic.LOOKUP_SETTING, on and true or false)
    if G.flush then pcall(G.flush, G) end
end

function RealWeidu.lookupTap(ui, ges)
    local pos = ges and ges.pos
    if not pos or not RealWeidu.lookupModeOn() then return false end
    local W = require("device").screen:getWidth()
    if Logic.lookup_tap_action(RealWeidu.lookupModeOn(), pos.x, W) ~= "lookup" then return false end
    local word
    pcall(function()
        local hp = ui.view:screenToPageTransform(pos)
        if hp then word = ui.document:getWordFromPosition(hp) end
    end)
    local text = word and word.word
    if type(text) ~= "string" or not text:match("%S") then return false end -- no word: page turn / menu
    if not ui.dictionary then return false end
    -- auto-add to KOReader's vocabbuilder: its WordLookedUp handler only records non-manual
    -- lookups while vocabulary_builder.enabled is true, so enable it just for this lookup.
    local G = rawget(_G, "G_reader_settings")
    local vs = G and G:readSetting("vocabulary_builder")
    local restore, prev = false, nil
    local english = Logic.is_english_word(text) -- 0.5.1: non-Latin selections never stored
    if type(vs) == "table" and (vs.enabled and true or false) ~= english then
        prev = vs.enabled; vs.enabled = english; restore = true
    end
    local boxes = word.sbox and { word.sbox } or nil
    local ok, err = pcall(ui.dictionary.onLookupWord, ui.dictionary, text, false, boxes)
    if restore then vs.enabled = prev end
    if not ok then logger.warn("realweidu: lookup", err) end
    if english and type(vs) ~= "table" and ui.vocabbuilder then
        pcall(ui.handleEvent, ui, require("ui/event"):new("WordLookedUp", text,
            ui.doc_props and ui.doc_props.display_title or "", true))
    end
    return true
end

function RealWeidu.showReaderMenu(ui)
    ui_icons()
    local RM = require("realweidu_readermenu")
    local weread = Data.find_weread()
    local menu = RM:new{
        ui = ui, weread = weread,
        on_back = function()
            -- ReaderUI:onHome closes the book and shows the file manager
            -- (apps/reader/readerui.lua:929-933); then open our shelf on top.
            -- FM init re-opens the shelf itself when the mode is on.
            Data._paused = false
            local ok = pcall(ui.onHome, ui)
            if ok and not RealWeidu.shouldAutoEnter() then
                UIManager:scheduleIn(0.3, function() RealWeidu.showGrid() end)
            end
        end,
    }
    UIManager:show(menu, "full") -- 刷新规则：打开菜单一次全屏刷新
    return true
end

-- Conventional launcher name.
function RealWeidu:launch() RealWeidu.showGrid() end

-- Public API -----------------------------------------------------------

function RealWeidu.get_shelf(opts)
    return Data.get_shelf(Data.find_weread(), opts)
end

function RealWeidu.open_book(book_id)
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
                -- weread sync (QR login first if needed, common.lua:182) -> Real微读 shelf
                RealWeidu.syncShelf()
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
    if not ok then logger.warn("realweidu:", method, e); info("打开失败：" .. tostring(e)) end
    return ok
end

-- Pages ------------------------------------------------------------------------

ui_icons = function()
    local U = require("realweidu_ui")
    U.icons_dir = (plugin_dir or ".") .. "/icons"
    return U
end

-- Only one of our tab pages is open at a time (tab switching replaces it).
close_pages = function(except)
    if current_page and current_page ~= except then UIManager:close(current_page); current_page = nil end
    if current_grid and current_grid ~= except then UIManager:close(current_grid); current_grid = nil end
end

-- 0.4.2 speed: detach the open page, show the new one, then close the old.
-- Closing first made KOReader repaint the file manager underneath (a full
-- extra paint) before our page was drawn.
take_pages = function()
    local a, b = current_page, current_grid
    current_page, current_grid = nil, nil
    return { a, b }
end
local first_paint = true
local function refresh_mode()
    -- first entry: one full refresh (clears ghosting); tab switches: partial
    if first_paint then first_paint = false; return "full" end
    return "partial"
end
RealWeidu._refresh_mode = refresh_mode
local function drop_pages(old)
    if old then
        if old[1] then UIManager:close(old[1]) end
        if old[2] then UIManager:close(old[2]) end
    end
end

local function show_page(page, tab, old)
    local orig = page.onCloseWidget
    page.onCloseWidget = function(w)
        if current_page == w then current_page = nil end
        if active_tab == tab and current_page == nil and current_grid == nil then active_tab = nil end
        if orig then return orig(w) end
    end
    Data._paused = false
    current_page = page
    active_tab = tab
    UIManager:show(page, refresh_mode())
    drop_pages(old)
    return page
end

-- 发现: search (weread showSearch, library.lua:1640), 最近阅读 from the local
-- shelf cache, and the WeRead entries weread 1.6.0 really has. weread has no
-- recommendation / ranking / category API (only /store/search, /shelf/sync,
-- /book/info, /review/list, /readdata/detail ... in weread/lib/client.lua),
-- so 「为你推荐」 is hidden as UI-SPEC v1.1 asks when data is unavailable.
function RealWeidu.showDiscover()
    local weread = Data.find_weread()
    if not weread then info(Data.MESSAGES[Data.ERR_NO_PLUGIN]); return end
    local books = Data.get_shelf(weread) or {}
    ui_icons()
    local old_pages = take_pages() -- 0.4.2: closed after the new page is up
    local Pages = require("realweidu_pages")
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
    entries[#entries + 1] = { text = "刷新 / 管理书架", fn = function() RealWeidu.syncShelf() end }
    local page = Pages.Discover:new{
        books = books, entries = entries,
        on_nav_discover = function() RealWeidu.showDiscover() end,
        on_nav_shelf = function() RealWeidu.showGrid() end,
        on_nav_me = function() RealWeidu.showMe() end,
        on_search = function() call_weread("showSearch") end,
        on_open = function(b)
            local ok, e = Data.open_book(weread, b.bookId)
            if not ok then info(Data.MESSAGES[e] or ("打开失败：" .. tostring(e))) end
        end,
        on_all = function() RealWeidu.showGrid() end,
    }
    return show_page(page, QA_DISCOVER, old_pages)
end

-- 我: account name (weread settings "account", qr_login.lua:288-293), 本周阅读
-- (weread client:get_read_stats("weekly"), client.lua:680 -> totalReadTime),
-- 读完 = finished books on the cached shelf, 笔记 = readStat chip if the
-- server sends one (read_stats.lua:189-201), else "—".
function RealWeidu.statsCache() return S():readSetting("stats_cache") or {} end

function RealWeidu.refreshStats(weread, on_done, silent, delay)
    if not weread or type(weread.runOnlineTask) ~= "function" or type(weread.client) ~= "table" then return false end
    local Logic = require("realweidu_logic")
    return weread:runOnlineTask("阅读统计", function()
        local ok, raw = pcall(weread.client.get_read_stats, weread.client, "weekly")
        local good = ok and type(raw) == "table" -- BUG-04: nil / non-table is a failure too
        if good then
            local c = { week_min = Logic.minutes(raw.totalReadTime), notes = Logic.notes_from_summary(raw), at = os.time() }
            S():saveSetting("stats_cache", c); S():flush()
        else
            logger.warn("realweidu: weekly stats failed:", raw)
        end
        if on_done then on_done(good, not ok and raw or nil) end
    end, delay or 0.1, { silent_offline = silent })
end

function RealWeidu.showMe()
    local weread = Data.find_weread()
    if not weread then info(Data.MESSAGES[Data.ERR_NO_PLUGIN]); return end
    local Logic = require("realweidu_logic")
    ui_icons()
    local old_pages = take_pages() -- 0.4.2: closed after the new page is up
    local account = {}
    pcall(function() account = weread.settings:get("account", {}) or {} end)
    local books = Data.get_shelf(weread) or {}
    local function stats()
        local c = RealWeidu.statsCache()
        local hint
        if c.at then hint = "本周阅读更新于 " .. os.date("%m-%d %H:%M", c.at) .. "，点数据卡刷新"
        else hint = "点数据卡联网获取本周阅读" end
        return { week_min = c.week_min, finished = Logic.count_finished(books), notes = c.notes, hint = hint }
    end
    local Pages = require("realweidu_pages")
    local page
    page = Pages.Me:new{
        account_name = Data.is_logged_in(weread) and (account.name or "") or "",
        stats = stats(),
        show_stats = true, -- 0.3.3 look: 数据卡 (本周阅读 / 读完 / 笔记)
        rows = RealWeidu.meRows(),
        on_nav_discover = function() RealWeidu.showDiscover() end,
        on_nav_shelf = function() RealWeidu.showGrid() end,
        on_nav_me = function() RealWeidu.showMe() end,
        on_refresh_stats = function()
            RealWeidu.refreshStats(weread, function(good, err)
                if page then page.stats = stats(); page:refresh() end
                if not good then
                    info("本周阅读刷新失败" .. (err and ("：" .. tostring(err)) or "（服务器没有返回数据）")
                        .. "。\n页面上是上次的数据。")
                end
            end, false)
        end,
    }
    show_page(page, QA_ME, old_pages)
    -- 0.3.3: refresh when online and the cache is older than 30 min (silent offline)
    local c = RealWeidu.statsCache()
    if not c.at or os.time() - c.at > 1800 then
        RealWeidu.refreshStats(weread, function()
            if current_page == page then page.stats = stats(); page:refresh() end
        end, true, 2) -- 0.4.2: weread's HTTP is blocking; start it after the page is up and settled
    end
    return page
end

-- Grid ---------------------------------------------------------------------

function RealWeidu.showSearchDialog(grid)
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

function RealWeidu.showGrid()
    Data._paused = false
    local weread = Data.find_weread()
    if weread then pcall(RealWeidu.redirectWereadShelf, weread) end
    local books, err = Data.get_shelf(weread, { allow_empty = true }) -- BUG-06
    if not books then show_error(weread, err); return end
    ShelfGrid = ShelfGrid or require("realweidu_grid")
    local keep_page, keep_kw
    if current_grid then
        -- tapping the 书架 tab again: refresh from cache, keep position
        keep_page, keep_kw = current_grid.page, current_grid.keyword
    end
    local old_pages = take_pages() -- 0.4.2: closed after the new page is up
    ui_icons() -- the grid's own bottom bar uses realweidu_ui icons
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
        on_import = function() RealWeidu.syncShelf() end, -- 0.3.8: sync -> back to this shelf
        on_select = function()
            info("「选择」（批量管理）计划在二期提供。\n现在可点「导入」进入微信读书书架管理。")
        end,
        on_search = function(g) RealWeidu.showSearchDialog(g) end,
        on_discover = function() RealWeidu.showDiscover() end,
        on_shelf = function() RealWeidu.showGrid() end,
        on_me = function() RealWeidu.showMe() end,
    }
    local orig_close = grid.onCloseWidget
    grid.onCloseWidget = function(self_w)
        if current_grid == self_w then current_grid = nil end
        if active_tab == QA_ID and current_grid == nil then active_tab = nil end
        return orig_close(self_w)
    end
    current_grid = grid
    active_tab = QA_ID
    UIManager:show(grid, refresh_mode())
    drop_pages(old_pages)
    return grid
end

-- Legacy text list (v0.1) -------------------------------------------------

function RealWeidu.showShelfStatic()
    local weread = Data.find_weread()
    local books, err = Data.get_shelf(weread)
    if not books then show_error(weread, err); return end

    local menu
    local items = {
        {
            text = "↻ 在微信读书中刷新 / 管理书架",
            callback = function()
                UIManager:close(menu)
                RealWeidu.syncShelf()
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

function RealWeidu:showShelf() RealWeidu.showGrid() end

RealWeidu._Layout = Layout
return RealWeidu
