-- BOX-ONLY preview harness: fakes a logged-in weread with synthetic covers,
-- opens one of our pages (WSPREV_MODE = shelf|shelf2|discover|me|reader|font),
-- screenshots to WSPREV_OUT, quits. Never shipped to the Kindle.
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local logger = require("logger")
local H = WidgetContainer:extend{ name = "zzwsprev" }
local titles = {"平凡的世界","杀死一只知更鸟","小王子","蛤蟆先生去看心理医生","狂人日记","神的孩子全跳舞","漫游在雨中池塘","自卑与超越","海边的卡夫卡","我是落花生","厌女","追风筝的人"}
local function exists(p) local f = io.open(p) if f then f:close() return true end end
local MODE = os.getenv("WSPREV_MODE") or "shelf"

local function fake_weread()
    local books = {}
    for i, t in ipairs(titles) do
        local c = "/tmp/korprev/covers/" .. (i - 1) .. ".png"
        books[i] = { bookId = tostring(1000 + i), title = t, author = "", readUpdateTime = 100 - i,
            finishReading = (i % 4 == 0) and 1 or 0, _thumb = exists(c) and c or nil }
    end
    return {
        library_db = { accountKey = function() return "k" end, getShelf = function() return books end },
        settings = { is_api_configured = function() return true end,
            get = function(_, k, d) if k == "account" then return { name = "书友小明" } end return d end },
        getShelfCoverCache = function() return { pathFor = function(_, b) return b._thumb end } end,
        openBookshelf = function() end, showSearch = function() end, showMPShelfPage = function() end,
        showWereadCollection = function() end, showReadStats = function() end,
        runOnlineTask = function(_, _l, cb) cb(); return true end,
        client = { get_read_stats = function() return { totalReadTime = 5 * 3600 + 23 * 60,
            readStat = { { stat = "笔记", counts = "37条" } } } end },
    }
end

local function shot()
    local out = os.getenv("WSPREV_OUT") or "/tmp/korprev/shot.png"
    Screen:shot(out)
    logger.info("WSPREV shot", out)
    UIManager:scheduleIn(1, function() UIManager:quit() end)
end

function H:init()
    if _G.__wsprev_done then return end
    if self.ui.document then
        if MODE == "pageturn" then
            _G.__wsprev_done = true
            UIManager:scheduleIn(4, function()
                -- per-turn cost in the emulator: event handling (KOReader + all
                -- plugin hooks) and the repaint, 40 forward turns
                local time = require("ui/time")
                local Event = require("ui/event")
                local hs, ps = {}, {}
                for i = 1, 40 do
                    local t0 = time.now()
                    self.ui:handleEvent(Event:new("GotoViewRel", 1))
                    local t1 = time.now()
                    UIManager:forceRePaint()
                    local t2 = time.now()
                    hs[i], ps[i] = time.to_us(t1 - t0) / 1000, time.to_us(t2 - t1) / 1000
                end
                local function stat(a) local s, m = 0, 0 for _, v in ipairs(a) do s = s + v; if v > m then m = v end end
                    table.sort(a); return s / #a, a[math.floor(#a / 2)], m end
                local ha, hm, hx = stat(hs)
                local pa, pm, px = stat(ps)
                local f = io.open((os.getenv("WSPREV_OUT") or "/tmp/korprev/pageturn") .. ".txt", "w")
                f:write(string.format("plugin=%s turns=40 handler avg %.1f ms median %.1f max %.1f | repaint avg %.1f ms median %.1f max %.1f | full_refresh_count=%s anim_patched=%s\n",
                    tostring(self.ui.realweidu ~= nil), ha, hm, hx, pa, pm, px, tostring(UIManager.FULL_REFRESH_COUNT),
                    tostring(require("apps/reader/modules/readerview")._wrs_orig_anim ~= nil)))
                f:close()
                UIManager:quit()
            end)
            return
        end
        if MODE ~= "reader" and MODE ~= "font" and MODE ~= "sheet" and MODE ~= "progress" then return end
        _G.__wsprev_done = true
        UIManager:scheduleIn(4, function()
            local P = self.ui.realweidu
            local menu_ok = P and P.showReaderMenu and P.showReaderMenu(self.ui)
            local top = UIManager._window_stack[#UIManager._window_stack].widget
            for i = #UIManager._window_stack, 1, -1 do
                local w = UIManager._window_stack[i].widget
                if w.name == "realweidu_readermenu" then top = w end
            end
            for i = #UIManager._window_stack, 1, -1 do -- box only: drop the stray "no weread" notice
                local w = UIManager._window_stack[i] and UIManager._window_stack[i].widget
                if w and w.text and w.name ~= "realweidu_readermenu" then UIManager:close(w) end
            end
            if MODE == "sheet" and top.toggleFont then top:toggleFont() end
            if MODE == "progress" and top.toggleProgressCard then top:toggleProgressCard() end -- 0.4.5
            if MODE == "font" and top.refresh then top.font_open = true; top:refresh("ui") end
            if os.getenv("WSPREV_SET") and top.setStep then
                local Logic = require("realweidu_logic")
                top:setStep(Logic.SLIDERS[1], 6)               -- 字号 -> 26
                top:setStep(Logic.SLIDERS[4], 4)               -- 边距 -> 20
                top:toggleIndent()
                local c = self.ui.document.configurable
                logger.info("WSPREV set font_size", c.font_size, "margins", c.h_page_margins and c.h_page_margins[1],
                    "indent", tostring(self.ui.styletweak:isTweakEnabled("paragraph_indent")))
                UIManager:scheduleIn(2, function()
                    self.ui:onClose()
                    local DocSettings = require("docsettings")
                    local ds = DocSettings:open("/tmp/korprev/sample.epub")
                    logger.info("WSPREV saved font_size", ds:readSetting("copt_font_size"), "margins",
                        (ds:readSetting("copt_h_page_margins") or {})[1], "tweaks", require("dump")(ds:readSetting("style_tweaks")))
                    UIManager:quit()
                end)
                return
            end
            logger.info("WSPREV reader menu", tostring(menu_ok), top.name)
            UIManager:scheduleIn(3, shot)
        end)
        return
    end
    if MODE == "reader" or MODE == "font" or MODE == "sheet" or MODE == "pageturn" or MODE == "progress" then
        _G.__wsprev_reader = true
        UIManager:scheduleIn(1, function()
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
        end)
        return
    end
    _G.__wsprev_done = true
    do -- 0.4.0 log: who provides ui.weread, how many ☰ entries, old plugin disabled?
        local w = self.ui.weread
        local n = 0
        for _, m in ipairs(self.ui.menu and self.ui.menu.registered_widgets or {}) do if m.name and m.name:match("weread$") then n = n + 1 end end
        local dis = G_reader_settings:readSetting("plugins_disabled") or {}
        io.stderr:write(string.format("WSPREV040 embedded=%s path=%s weread_menus=%d old_disabled=%s\n",
            tostring(w and w._real_embedded), tostring(w and w.path), n, tostring(dis.weread)))
    end
    local real_weread = self.ui.weread
    self.ui.weread = fake_weread()
    if MODE == "stats" then -- also: every embedded module must load under its rweread.* name
        local root = "plugins/realweidu.koplugin/"
        local bad = {}
        for f in io.popen("cd " .. root .. " && find rweread -name '*.lua'"):lines() do
            local mod = f:gsub("%.lua$", ""):gsub("/", ".")
            local ok, e = pcall(require, mod)
            if not ok then bad[#bad + 1] = mod .. ": " .. tostring(e):sub(1, 160) end
        end
        io.stderr:write("WSPREV modules bad=" .. #bad .. "\n" .. table.concat(bad, "\n") .. "\n")
    end
    if MODE == "stats" then -- 阅读时长统计 on the REAL embedded weread (stubbed network)
        UIManager:scheduleIn(3, function()
            local w = real_weread
            self.ui.weread = w
            w.requireLogin = function() return true end
            w.isNetworkOnline = function() return true end
            w.client = w.client or {}
            w.client.gateway = function(_, path) io.stderr:write("WSPREV gateway " .. tostring(path) .. "\n"); return { baseTime = os.time() - 86400 * 3, readTimes = { [tostring(os.time() - 86400)] = 3600 },
                totalReadTime = 7200, readBooks = {} } end
            local P = self.ui.realweidu
            P.showMe()
            UIManager:scheduleIn(1, function()
                local ok, e = pcall(P.meRows()[1].fn)
                io.stderr:write("WSPREV stats ok=" .. tostring(ok) .. " " .. tostring(e) .. "\n")
            end)
            UIManager:scheduleIn(4, shot)
        end)
        return
    end
    if MODE == "timing" then -- tap -> screen updated (build + forceRePaint), ms
        local time = require("ui/time")
        local P = self.ui.realweidu
        local function top() local st = UIManager._window_stack; return st[#st] and st[#st].widget end
        local function close_extra() -- dialogs/notices on top of our page
            for _ = 1, 5 do local t = top(); if t and t.name ~= "realweidu_grid" and t.name ~= "realweidu_me"
                and t.name ~= "realweidu_discover" and t.name ~= "filemanager" then UIManager:close(t); UIManager:forceRePaint() else break end end
        end
        local function grid() P.showGrid(); return top() end
        local function tapg(field) return function() local g = grid(); UIManager:forceRePaint(); local t0 = time.now(); g[field](g); return t0 end end
        local acts = {
            { "底栏 书架", function() P.showGrid() end },
            { "底栏 发现", function() P.showDiscover() end },
            { "底栏 我", function() P.showMe() end },
            { "书架 翻页", function() local g = top(); if g.onGotoPage then g:onGotoPage(2) end end, pre = function() P.showGrid() end },
            { "书架 打开书", function() local g = top(); g.on_open(g.page_items[1], g) end, pre = function() P.showGrid() end },
            { "书架 搜索", function() local g = top(); g.on_search(g) end, pre = function() P.showGrid() end },
            { "书架 导入(同步)", function() local g = top(); g.on_import(g) end, pre = function() P.showGrid() end },
            { "书架 选择", function() local g = top(); g.on_select(g) end, pre = function() P.showGrid() end },
        }
        for i, r in ipairs(P.meRows()) do
            if r.text ~= "退出到 Kindle" then
                acts[#acts + 1] = { "我 · " .. r.text, r.fn, pre = function() P.showMe() end }
            else
                acts[#acts + 1] = { "我 · 退出到 Kindle(确认框)", r.fn, pre = function() P.showMe() end }
            end
        end
        for _, it in ipairs(P.settingsItems()) do
            acts[#acts + 1] = { "阅读设置 · " .. (it.text:gsub("^✓ ", ""):gsub("^　", "")), it.fn, pre = function() P.showMe(); P.showSettingsDialog() end }
        end
        acts[#acts + 1] = { "☰ 进入 Real微读", function() P.enter(self.ui) end, pre = function() P.leaveToKOReader(); close_extra() end }
        local out = {}
        local i = 0
        local function step()
            i = i + 1
            local a = acts[i]
            if not a then
                local f = io.open(os.getenv("WSPREV_TIMING") or "/tmp/korprev/timing.txt", "w")
                f:write(table.concat(out, "\n"), "\n"); f:close()
                io.stderr:write("WSPREV timing done\n"); UIManager:quit(); return
            end
            close_extra()
            if a.pre then pcall(a.pre) end
            UIManager:forceRePaint()
            local t0 = time.now()
            local ok, e = pcall(a[2])
            UIManager:forceRePaint()
            local ms = time.to_ms(time.now() - t0)
            out[#out + 1] = string.format("%s\t%d%s", a[1], ms, ok and "" or ("\tERR " .. tostring(e)))
            UIManager:scheduleIn(0.6, function() close_extra(); step() end)
        end
        UIManager:scheduleIn(3, step)
        return
    end
    if MODE == "exit" then -- 退出到 Kindle: confirm, then OK must quit KOReader
        UIManager:scheduleIn(3, function()
            local P = self.ui.realweidu
            P.showMe()
            UIManager:scheduleIn(1, function()
                local row; for _, r in ipairs(P.meRows()) do if r.text == "退出到 Kindle" then row = r end end
                row.fn()
                UIManager:scheduleIn(0.5, function()
                    local top = UIManager._window_stack[#UIManager._window_stack].widget
                    io.stderr:write("WSPREV exit confirm=" .. tostring(top.ok_callback ~= nil) .. "\n")
                    local q = UIManager.quit
                    UIManager.quit = function(...) io.stderr:write("WSPREV exit QUIT called\n"); return q(...) end
                    top.ok_callback()
                end)
            end)
            UIManager:scheduleIn(8, function() io.stderr:write("WSPREV exit still running\n"); shot() end)
        end)
        return
    end
    if MODE == "startup" then -- no action: Real微读 must open by itself
        UIManager:scheduleIn(5, shot); return
    end
    UIManager:scheduleIn(3, function()
        local P = self.ui.realweidu
        if MODE == "fmmenu" then
            if self.ui.menu then
                local m = self.ui.menu
                if not m.tab_item_table and m.setUpdateItemTable then m:setUpdateItemTable() end
                m:onShowMenu()
                UIManager:scheduleIn(0.5, function()
                    local function find(w, d)
                        if type(w) ~= "table" or d > 8 then return end
                        if w.switchMenuTab and w.tab_item_table then return w end
                        for _, c in ipairs(w) do local r = find(c, d + 1) if r then return r end end
                    end
                    for _, e in ipairs(UIManager._window_stack) do
                        local tm = find(e.widget, 0)
                        if tm then tm:switchMenuTab(#tm.tab_item_table) end
                    end
                end)
            end
        elseif MODE == "leave" then
            P.showMe(); UIManager:scheduleIn(1, function() P.leaveToKOReader() end)
            UIManager:scheduleIn(4, shot); return
        elseif MODE == "more" then
            P.showMe(); UIManager:scheduleIn(1, function() P.showMoreSettings() end)
            UIManager:scheduleIn(4, shot); return
        elseif MODE == "download" then
            -- weread 1.6.0's own progress dialog, as fast download drives it
            package.path = os.getenv("WSPREV_WEREAD") .. "/?.lua;" .. package.path
            local DD = require("rweread.ui.download_dialog")
            local F = require("realweidu_fastdl")
            P.showGrid()
            UIManager:scheduleIn(1, function()
                local d = DD:new{ title = "下载中 · 第 37/120 章（3 章并行）：第三十七章 长安的荔枝",
                    progress_max = 120, buttons = { { { text = "取消下载", callback = function() end } } } }
                F.throttle_dialog(d)
                d:show(); d:reportProgress(36)
            end)
            UIManager:scheduleIn(4, shot); return
        elseif MODE == "settings" then
            P.showMe(); UIManager:scheduleIn(1, function() P.showSettingsDialog() end)
            UIManager:scheduleIn(4, shot); return
        elseif MODE == "fontpanel" then
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
            UIManager:scheduleIn(4, function()
                local ui = require("apps/reader/readerui").instance
                local RM = require("realweidu_readermenu")
                local menu = RM:new{ ui = ui, weread = ui and ui.weread, on_back = function() end }
                menu.font_open = true; menu:_build()
                UIManager:show(menu, "ui")
                UIManager:scheduleIn(2, shot)
            end)
            return
        elseif MODE == "brightness" then
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
            UIManager:scheduleIn(4, function()
                local ui = require("apps/reader/readerui").instance
                local RM = require("realweidu_readermenu")
                local menu = RM:new{ ui = ui, weread = ui and ui.weread, on_back = function() end }
                menu.sheet_open = true; menu:_build()
                UIManager:show(menu, "ui")
                UIManager:scheduleIn(2, shot)
            end)
            return
        elseif MODE == "readingmenu" or MODE == "tocsheet" then
            -- open sample book then show our reading menu / TOC sheet
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
            UIManager:scheduleIn(4, function()
                local RUI = require("apps/reader/readerui")
                local ui = RUI.instance
                local P2 = ui and ui.realweidu
                if not P2 then io.stderr:write("WSPREV no realweidu on reader\n"); shot(); return end
                -- ensure reader menu setting on
                pcall(function()
                    local S = require("luasettings"):open(require("datastorage"):getSettingsDir().."/realweidu.lua")
                    S:saveSetting("reader_menu", true); S:flush()
                end)
                local RM = require("realweidu_readermenu")
                local menu = RM:new{ ui = ui, weread = ui.weread,
                    on_back = function() end }
                if MODE == "tocsheet" then menu.toc_open = true; menu:_build() end
                UIManager:show(menu, "ui")
                io.stderr:write("WSPREV readingmenu toc="..tostring(menu.toc_open).."\n")
                UIManager:scheduleIn(2, shot)
            end)
            return
        elseif MODE == "discover" then P.showDiscover()
        elseif MODE == "me" then P.showMe()
        else
            local g = P.showGrid()
            if MODE == "shelf2" and g then g:onGotoPage(2) end
        end
        UIManager:scheduleIn(3, shot)
    end)
end
return H
