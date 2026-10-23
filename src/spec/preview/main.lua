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

local function stream_reader_steps(ui)
    -- 0.6.1 边下边读 screens: reading while downloading, a placeholder chapter, swap-in
    local S = require("realweidu_stream")
    local out = os.getenv("WSPREV_DIR") or "/tmp/korprev"
    local step = _G.__wsprev_stream_step or 0
    _G.__wsprev_stream_step = step + 1
    local function log(...) io.stderr:write("WSPREV stream " .. table.concat({ ... }, " ") .. "\n") end
    if step == 0 then
        UIManager:scheduleIn(3, function()
            local job = next(S.jobs) and select(2, next(S.jobs))
            log("reading", "done=" .. (job and S.count_done(job) or -1), "total=" .. (job and job.total or -1))
            Screen:shot(out .. "/reading-while-downloading.png")
            local xp = "/body/DocFragment[18]"
            ui:handleEvent(require("ui/event"):new("GotoXPointer", xp, xp))
            UIManager:scheduleIn(0.8, function()
                Screen:shot(out .. "/placeholder-toast.png")
                UIManager:scheduleIn(1.0, function()
                    Screen:shot(out .. "/placeholder.png")
                    log("placeholder", "priority=" .. tostring(job and job.priority), "chapter=" .. tostring(S.current_chapter(ui)))
                end)
            end)
        end)
    else
        UIManager:scheduleIn(3, function()
            log("swapped", "chapter=" .. tostring(S.current_chapter(ui)))
            Screen:shot(out .. "/swapped-in.png")
            UIManager:scheduleIn(1, function() UIManager:quit() end)
        end)
    end
end

function H:init()
    if self.ui.document and MODE == "streamread" then return stream_reader_steps(self.ui) end
    if _G.__wsprev_done then return end
    if MODE == "streamread" then
        _G.__wsprev_done = true
        UIManager:scheduleIn(2, function()
            local S = require("realweidu_stream")
            local Client = require("rweread.lib.client")
            local store = {}
            os.execute("rm -rf /tmp/korprev/stream; mkdir -p /tmp/korprev/stream")
            for k in pairs(S.jobs) do S.stop(S.jobs[k]) end
            G_reader_settings:delSetting(S.SETTING)
            local settings = { mock_endpoint = "http://127.0.0.1:18084", cache_dir = "/tmp/korprev/stream",
                download_dir = "/tmp/korprev/stream",
                get = function(_, k, d) return store[k] or d end, set = function(_, k, v) store[k] = v end, flush = function() end,
                merge_set_cookie = function() end, is_cookie_configured = function() return true end }
            local chapters = {}
            for c = 1, 20 do chapters[c] = { chapterUid = c, chapterIdx = c, title = "第" .. c .. "章" } end
            local t0 = require("socket").gettime()
            S.on_first_read = function(j) io.stderr:write(string.format("WSPREV stream first_read=%.2fs\n", j.first_read)) end
            io.stderr:write("WSPREV stream start\n")
            local okst, est = pcall(S.start, { settings = settings, client = Client:new(settings),
                open_file = function(p) require("apps/reader/readerui"):showReader(p) end },
                { book_id = "3300000001", bookId = "3300000001", title = "长安的荔枝", author = "马伯庸" }, chapters, {})
            io.stderr:write("WSPREV stream started " .. tostring(okst) .. " " .. tostring(est) .. "\n")
        end)
        return
    end
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
        if MODE ~= "reader" and MODE ~= "font" and MODE ~= "sheet" and MODE ~= "progress" and MODE ~= "toc" and MODE ~= "toc2" and MODE ~= "dict" and MODE ~= "vocab" and MODE ~= "lookmenu" and MODE ~= "looktap" then return end
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
            if MODE == "lookmenu" or MODE == "looktap" then -- 0.5.0: 查词模式
                G_reader_settings:saveSetting("realweidu_lookup_mode", MODE == "looktap")
                if MODE == "lookmenu" then
                    top:toggleLookupMode() -- off -> on, via the menu item itself
                    P.showReaderMenu(self.ui)
                    for i = #UIManager._window_stack, 1, -1 do
                        local w = UIManager._window_stack[i].widget
                        if w.name == "realweidu_readermenu" then top = w end
                    end
                    for i = #UIManager._window_stack, 1, -1 do
                        local w = UIManager._window_stack[i] and UIManager._window_stack[i].widget
                        if w and w.text and w.name ~= "realweidu_readermenu" then UIManager:close(w) end
                    end
                    top:showMore()
                    logger.info("WSPREV lookup mode", tostring(G_reader_settings:isTrue("realweidu_lookup_mode")))
                else
                    UIManager:close(top)
                    local Geom = require("ui/geometry")
                    local x, y = tonumber(os.getenv("WSPREV_TX") or 520), tonumber(os.getenv("WSPREV_TY") or 700)
                    local edge = P.lookupTap(self.ui, { ges = "tap", pos = Geom:new{ x = 30, y = y, w = 0, h = 0 } })
                    local hit = P.lookupTap(self.ui, { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } })
                    local vs = G_reader_settings:readSetting("vocabulary_builder")
                    logger.info("WSPREV looktap edge->", tostring(edge), "word->", tostring(hit),
                        "vocab enabled after", tostring(vs and vs.enabled))
                end
                UIManager:scheduleIn(4, shot)
                return
            end
            if MODE == "dict" or MODE == "vocab" then -- 0.5.0: ECDICT lookup / 生词本
                UIManager:close(top)
                for _, w in ipairs({ "serendipity", "abandon", "ran", "apple" }) do
                    self.ui:handleEvent(require("ui/event"):new("WordLookedUp", w, "长安的荔枝", true))
                end
                if MODE == "dict" then
                    self.ui.dictionary:onLookupWord("serendipity")
                else
                    top:openVocabBuilder()
                end
                UIManager:scheduleIn(4, shot)
                return
            end
            if (MODE == "toc" or MODE == "toc2") and top.showTocSheet then -- 0.4.8/0.4.9
                if os.getenv("WSPREV_LONGTOC") then -- box only: fake 100-chapter TOC
                    local t = {}; for k = 1, 100 do t[k] = { title = "第" .. k .. "章 荔枝使者", page = k, depth = 1 } end
                    self.ui.toc.toc = t
                end
                top:showTocSheet()
                if MODE == "toc2" then top:tocTurn(1); top:onSwipe(nil, { direction = "north" }) end
                logger.info("WSPREV toc page", top.toc_page, "of", top.toc_page_count)
            end
            if MODE == "progress" and top.progress_card_rect and top.slider_rect then -- 0.4.6 overlap check
                local c, sl = top.progress_card_rect, top.slider_rect
                logger.info("WSPREV card", c.x, c.y, c.w, c.h, "slider", sl.x, sl.y, sl.w, sl.h,
                    (c.y + c.h <= sl.y) and "CARD_ABOVE_SLIDER_OK" or "CARD_OVERLAPS_SLIDER")
            end
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
    if MODE == "reader" or MODE == "font" or MODE == "sheet" or MODE == "pageturn" or MODE == "progress" or MODE == "toc" or MODE == "toc2" or MODE == "dict" or MODE == "vocab" or MODE == "lookmenu" or MODE == "looktap" then
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
        elseif MODE == "quietopen" or MODE == "loudopen" then -- 0.6.2: no 「正在打开」 popup
            if MODE == "quietopen" then require("realweidu_data").quiet_open_until = os.time() + 5 end
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
            UIManager:scheduleIn(0.01, function()
                local vis = 0
                for _, e in ipairs(UIManager._window_stack) do
                    if e.widget.text and tostring(e.widget.text):find("sample", 1, true) and not e.widget.invisible then vis = vis + 1 end
                end
                io.stderr:write("WSPREV " .. MODE .. " visible_opening_popups=" .. vis .. " quiet_opened="
                    .. tostring(require("realweidu_data").quiet_opened) .. "\n")
                shot()
            end)
            return
        elseif MODE == "taps063" then
            -- 0.6.3: drive REAL gesture events (UIManager:sendEvent(Gesture)) through ReaderUI's
            -- touch zones and our menu; screenshot + state/bounds log after every step.
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
            local Event, Geom = require("ui/event"), require("ui/geometry")
            local ok_t, time = pcall(require, "ui/time")
            local Device = require("device")
            local W, H = Screen:getWidth(), Screen:getHeight()
            local dir = os.getenv("WSPREV_DIR") or "/tmp/korprev"
            local function tap(x, y)
                UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 },
                    time = ok_t and time.now() or 0 }))
            end
            local function menu()
                for i = #UIManager._window_stack, 1, -1 do
                    local w = UIManager._window_stack[i].widget
                    if w.name == "realweidu_readermenu" then return w end
                end
            end
            local function slot(i)
                local L = require("realweidu_logic")
                local x, sw = L.slot(W, 5, i)
                local bh = math.max(require("realweidu_ui").px(130), 120)
                return x + math.floor(sw / 2), H - math.floor(bh / 2)
            end
            local fails = 0
            local function check_state(name)
                local m = menu()
                local st = m and string.format("progress=%s bright=%s font=%s sheet=%s toc=%s",
                    tostring(m.progress_open), tostring(m.bright_open), tostring(m.font_open), tostring(m.sheet_open), tostring(m.toc_open)) or "menu=closed"
                local n_open, oob = 0, 0
                if m then
                    for _, k in ipairs({ "progress_open", "bright_open", "font_open", "sheet_open", "toc_open" }) do if m[k] then n_open = n_open + 1 end end
                    for _, c in ipairs(m[1] or {}) do
                        local o, sz = c.overlap_offset or { 0, 0 }, c:getSize()
                        if o[1] < 0 or o[2] < 0 or o[1] + sz.w > W or o[2] + sz.h > H then
                            oob = oob + 1
                            io.stderr:write(string.format("WSPREV063 OOB %s at %d,%d size %dx%d\n", name, o[1], o[2], sz.w, sz.h))
                        end
                    end
                    for _, h in ipairs(m.hits or {}) do
                        local r = h.r
                        if r.x + r.w > W + 60 or r.y + r.h > H or r.y < 0 then oob = oob + 1
                            io.stderr:write(string.format("WSPREV063 OOB-hit %s %d,%d %dx%d\n", name, r.x, r.y, r.w, r.h)) end
                    end
                end
                if n_open > 1 or oob > 0 then fails = fails + 1 end
                io.stderr:write(string.format("WSPREV063 step %s: %s open_panels=%d out_of_bounds=%d\n", name, st, n_open, oob))
            end
            local steps, k = {}, 0
            local function add(name, fn) steps[#steps + 1] = { name = name, fn = fn } end
            add("01-menu-open", function() tap(math.floor(W / 2), math.floor(H / 2)) end)
            add("02-progress-open", function() tap(slot(3)) end)
            add("03-progress-closed", function() tap(slot(3)) end)
            add("04-progress-open-again", function() tap(slot(3)) end)
            add("05-progress-closed-again", function() tap(slot(3)) end)
            add("06-font-open", function() tap(slot(5)) end)
            add("07-font-to-light", function() tap(slot(4)) end)        -- sun in the font bar
            add("08-light-to-font", function() tap(slot(5)) end)        -- A in the classic bar
            add("09-font-to-light-again", function() tap(slot(4)) end)
            add("10-light-closed", function() tap(slot(4)) end)
            add("11-progress-then-light", function() tap(slot(3)); tap(slot(4)) end)
            add("12-warm-kindle-scale", function()
                -- emulate a Kindle native warmth range (0-24) and KOReader warmth 75%
                local p = Device:getPowerDevice()
                p.fl_warmth_max = 24; p.warmth_scale = 100 / 24
                pcall(p.setWarmth, p, 75)
                local m = menu(); m:refresh("ui")
                local v = m:lightValues()
                io.stderr:write(string.format("WSPREV063 warm ko=%s native=%s range=%s..%s expect native=18\n",
                    tostring(p:frontlightWarmth()), tostring(v.warm), tostring(v.wmin), tostring(v.wmax)))
            end)
            add("13-warm-set-by-tap", function()
                local m = menu()
                -- tap the warm track at its right end -> native 24 (100%)
                local ur = require("realweidu_ui")
                local pad = ur.px(64)
                tap(W - pad - ur.px(110) - 5, m.panel_rect.y + ur.px(30) + ur.px(130) + math.floor(ur.px(130) / 2))
                local p = Device:getPowerDevice()
                io.stderr:write(string.format("WSPREV063 warm after tap ko=%s native=%s\n", tostring(p:frontlightWarmth()), tostring(m:lightValues().warm)))
            end)
            add("14-toc-50pct", function() tap(slot(4)); tap(slot(2)) end)
            add("15-toc-closed", function() tap(math.floor(W * 0.8), math.floor(H / 2)) end)
            local function run()
                k = k + 1
                local st = steps[k]
                if not st then
                    io.stderr:write("WSPREV063 DONE fails=" .. fails .. "\n")
                    UIManager:quit(); return
                end
                st.fn()
                UIManager:scheduleIn(1.2, function()
                    Screen:shot(dir .. "/" .. st.name .. ".png")
                    check_state(st.name)
                    run()
                end)
            end
            UIManager:scheduleIn(4, function()
                for i = #UIManager._window_stack, 1, -1 do
                    local w = UIManager._window_stack[i] and UIManager._window_stack[i].widget
                    if w and w.text then UIManager:close(w) end
                end
                Screen:shot(dir .. "/00-book.png")
                UIManager:scheduleIn(1, run)
            end)
            return
        elseif MODE == "footer" or MODE == "bright2" or MODE == "syncprog" or MODE == "more062" or MODE == "progress062" then
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
            UIManager:scheduleIn(4, function()
                local ui = require("apps/reader/readerui").instance
                for i = #UIManager._window_stack, 1, -1 do
                    local w = UIManager._window_stack[i] and UIManager._window_stack[i].widget
                    if w and w.text then UIManager:close(w) end
                end
                if MODE == "footer" then UIManager:setDirty(nil, "full"); UIManager:scheduleIn(2, shot); return end
                local RM = require("realweidu_readermenu")
                local W = ui.weread
                if MODE == "syncprog" and W then -- stub: WeRead book + remote progress 42%
                    W.detectWeReadBook = function() return "1003" end
                    W.runOnlineTask = function(_, _l, cb) cb(); return true end
                    W.client = W.client or {}
                    W.client.get_progress = function() return { book = { progress = 42 } } end
                end
                local menu = RM:new{ ui = ui, weread = W, on_back = function() end }
                UIManager:show(menu, "ui")
                if MODE == "bright2" then menu:toggleBrightPanel() end
                if MODE == "progress062" then menu:toggleProgressCard() end
                if MODE == "more062" then menu:showMore() end
                if MODE == "syncprog" then menu:syncProgress() end
                io.stderr:write("WSPREV " .. MODE .. " bright_open=" .. tostring(menu.bright_open) .. " bar=" .. tostring(menu.bar_rect and menu.bar_rect.y) .. "\n")
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
        elseif MODE == "discover" or MODE == "discover2" or MODE == "discover3" or MODE == "home064" then
            -- 0.6.2: WeRead rankings/recommendations (synthetic data; box has no WeRead login)
            local R = require("realweidu_rank")
            local names = { "平凡的世界","杀死一只知更鸟","小王子","蛤蟆先生去看心理医生","狂人日记","神的孩子全跳舞","漫游在雨中池塘","自卑与超越","海边的卡夫卡","我是落花生","厌女","追风筝的人" }
            local function list(prefix, n)
                local l = {}
                for i = 1, n do
                    local k = (i - 1) % #names
                    l[i] = { bookId = prefix .. i, title = names[k + 1], author = "作者" .. i,
                        cover_file = (k ~= 4 and k ~= 9) and ("/tmp/korprev/covers/" .. k .. ".png") or nil }
                end
                return l
            end
            for i, t in ipairs(R.TABS) do
                local l = list(t.id, 20)
                if i == 2 then table.insert(l, 1, table.remove(l, 7)) end
                R.lists[t.id] = { books = l }
            end
            local rec = list("rec", 12)
            for i = 1, #rec do rec[i] = list("rec", 12)[((i + 4) % 12) + 1] end
            R.lists[R.RECOMMEND .. ":0"] = { books = rec }
            if MODE == "home064" then
                R.lists[R.RECOMMEND .. ":12"] = { books = list("rec2", 12) }
                for i = 1, 12 do R.lists[R.RECOMMEND .. ":12"].books[i] = list("rec2", 12)[((i + 8) % 12) + 1] end
                local Event, Geom = require("ui/event"), require("ui/geometry")
                local U = require("realweidu_ui")
                local W, H = Screen:getWidth(), Screen:getHeight()
                local dir = os.getenv("WSPREV_DIR") or "/tmp/korprev"
                local fails = 0
                local function log(...) io.stderr:write("WSPREV064 " .. string.format(...) .. "\n") end
                local function tap(x, y)
                    log("  tap %d,%d", x, y)
                    UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }))
                end
                local function top() local st = UIManager._window_stack; return st[#st] and st[#st].widget end
                local function ctr(page, r) return r.x + math.floor(r.w / 2), page.top + r.y + math.floor(r.h / 2) end
                local function find_button(label)
                    for i = #UIManager._window_stack, 1, -1 do
                        local w = UIManager._window_stack[i].widget
                        local bt = w.buttontable
                        if bt then
                            for _, line in ipairs(bt.buttons_layout or {}) do
                                for _, b in ipairs(line) do
                                    if b.text and b.text:find(label, 1, true) and b.dimen then return b end
                                end
                            end
                        end
                    end
                end
                local function check(name)
                    local pg = top()
                    local bad = 0
                    if pg and pg.g then
                        for _, c in ipairs(pg.g) do
                            local o, sz = c.overlap_offset or { 0, 0 }, c:getSize()
                            if o[1] < 0 or o[2] < 0 or o[1] + sz.w > W or pg.top + o[2] + sz.h > H then
                                bad = bad + 1; log("  OOB at %d,%d size %dx%d", o[1], o[2], sz.w, sz.h)
                            end
                        end
                    end
                    if pg and pg.cover_rects and pg.rank_layout then
                        local m = U.px(45)
                        local rows = {}
                        for _, r in ipairs(pg.cover_rects) do
                            rows[r.y] = rows[r.y] or {}
                            table.insert(rows[r.y], r)
                        end
                        local ys = {}
                        for y0, rr in pairs(rows) do
                            ys[#ys + 1] = y0
                            local first, last = rr[1], rr[#rr]
                            local gaps = {}
                            for k = 2, #rr do gaps[#gaps + 1] = rr[k].x - rr[k - 1].x end
                            local even = true
                            for k = 2, #gaps do if math.abs(gaps[k] - gaps[1]) > 1 then even = false end end
                            local ok = #rr == 5 and first.x == m and last.x + last.w == W - m and even
                            if not ok then bad = bad + 1 end
                            log("  row y=%d n=%d left=%d right=%d step=%s even=%s %s", y0, #rr, first.x, last.x + last.w,
                                tostring(gaps[1]), tostring(even), ok and "OK" or "BAD")
                        end
                        local L = pg.rank_layout
                        log("  cover %dx%d vgap=%d weread_bottom=%d avail=%d tab=%d", L.cw, L.ch, L.vgap, pg.weread_bottom, pg.avail, R.tab)
                        if pg.weread_bottom > pg.avail then bad = bad + 1; log("  overlaps nav!") end
                    end
                    if bad > 0 then fails = fails + 1 end
                    log("step %s: top=%s bad=%d", name, tostring(pg and (pg.name or pg.title)), bad)
                end
                local steps = {}
                local function add(name, fn) steps[#steps + 1] = { name = name, fn = fn } end
                local function disc() return P._discover_page end
                add("00-home", function() end)
                add("01-tab-potential", function() tap(ctr(disc(), disc().tab_rects[2])) end)
                add("02-tab-newbook", function() tap(ctr(disc(), disc().tab_rects[4])) end)
                add("03-more-1", function() tap(ctr(disc(), disc().more_rect)) end)
                add("04-more-2", function() tap(ctr(disc(), disc().more_rect)) end)
                add("05-selected-tab-full-list", function() tap(ctr(disc(), disc().tab_rects[4])) end)
                add("06-nav-discover", function() local pg = top(); tap(math.floor(W * 0.3), pg.top + pg.avail + math.floor(pg.nav_h / 2)) end)
                add("07-nav-me", function() local pg = top(); tap(math.floor(W * 0.62), pg.top + pg.avail + math.floor(pg.nav_h / 2)) end)
                add("08-me-settings", function() local pg = top(); tap(ctr(pg, pg.row_rects["阅读设置"])) end)
                add("09-sleep-dialog", function()
                    local b = find_button("自动休眠"); log("  before: setting=%s", tostring(G_reader_settings:readSetting("auto_suspend_timeout_seconds")))
                    tap(b.dimen.x + math.floor(b.dimen.w / 2), b.dimen.y + math.floor(b.dimen.h / 2)) end)
                add("10-sleep-30min", function()
                    local b = find_button("30 分钟")
                    tap(b.dimen.x + math.floor(b.dimen.w / 2), b.dimen.y + math.floor(b.dimen.h / 2)) end)
                add("11-sleep-saved", function()
                    local inst = P._autosuspend_instance()
                    local v = G_reader_settings:readSetting("auto_suspend_timeout_seconds")
                    log("  after: setting=%s live_plugin=%s live_value=%s", tostring(v), tostring(inst ~= nil), tostring(inst and inst.auto_suspend_timeout_seconds))
                    if v ~= 1800 then fails = fails + 1 end
                    for i = #UIManager._window_stack, 1, -1 do
                        local w = UIManager._window_stack[i].widget
                        if w.text and not w.g then UIManager:close(w) end
                    end
                    P.showSettingsDialog()
                end)
                local k = 0
                local function run()
                    k = k + 1
                    local st = steps[k]
                    if not st then log("DONE fails=%d", fails); UIManager:quit(); return end
                    log("== %s", st.name)
                    st.fn()
                    UIManager:scheduleIn(1.2, function()
                        Screen:shot(dir .. "/" .. st.name .. ".png")
                        check(st.name)
                        run()
                    end)
                end
                P.showDiscover()
                UIManager:scheduleIn(3, run)
                return
            end
            if MODE == "discover2" then P.showRanking(2) -- 0.6.3: tapping a ranking name
            else
                if MODE == "discover3" then R.shift_rows() end -- 0.6.3: 换一批
                P.showDiscover()
            end
        elseif MODE == "me" then P.showMe()
        else
            if MODE == "streamshelf" then -- 0.6.1: shelf progress label
                local S = require("realweidu_stream")
                local d = {}
                for i = 1, 37 do d[i] = true end
                S.jobs["1003"] = { book_id = "1003", total = 120, done = d, running = true }
                G_reader_settings:saveSetting(S.SETTING, { ["1006"] = { done = 52, total = 88, dir = "/nonexistent" } })
            end
            local g = P.showGrid()
            if MODE == "shelf2" and g then g:onGotoPage(2) end
        end
        UIManager:scheduleIn(3, shot)
    end)
end
return H
