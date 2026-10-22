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
        if MODE ~= "reader" and MODE ~= "font" then return end
        _G.__wsprev_done = true
        UIManager:scheduleIn(4, function()
            local P = self.ui.wereadshelf
            local menu_ok = P and P.showReaderMenu and P.showReaderMenu(self.ui)
            local top = UIManager._window_stack[#UIManager._window_stack].widget
            if MODE == "font" and top.toggleFont then top:toggleFont() end
            if os.getenv("WSPREV_SET") and top.setStep then
                local Logic = require("wereadshelf_logic")
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
    if MODE == "reader" or MODE == "font" then
        _G.__wsprev_reader = true
        UIManager:scheduleIn(1, function()
            require("apps/reader/readerui"):showReader("/tmp/korprev/sample.epub")
        end)
        return
    end
    _G.__wsprev_done = true
    self.ui.weread = fake_weread()
    if MODE == "startup" then -- no action: Real微读 must open by itself
        UIManager:scheduleIn(5, shot); return
    end
    UIManager:scheduleIn(3, function()
        local P = self.ui.wereadshelf
        for i = #UIManager._window_stack, 1, -1 do -- drop first-run popups (box only)
            local w = UIManager._window_stack[i].widget
            if w ~= self.ui and w.name ~= "filemanager" then UIManager:close(w) end
        end
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
        elseif MODE == "settings" then
            P.showMe(); UIManager:scheduleIn(1, function() P.showSettingsDialog() end)
            UIManager:scheduleIn(4, shot); return
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
