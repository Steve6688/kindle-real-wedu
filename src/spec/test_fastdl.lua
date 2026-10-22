-- Offline test for wereadshelf_fastdl (stubbed weread downloader + processes).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../wereadshelf.koplugin/?.lua;" .. package.path
local q = {}
package.loaded["ui/uimanager"] = { scheduleIn = function(_, _t, f) q[#q + 1] = f end }
package.loaded["ui/time"] = nil
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
local function drain() local i = 0; while #q > 0 and i < 10000 do i = i + 1; table.remove(q, 1)() end end

-- fake weread: sequential downloader that fetches via _runInterruptible
local fetched_in_main, forks, fetched_total = 0, 0, 0
local Content = {}
function Content.fetch_single_chapter_source(_c, _s, _b, ch, state)
    fetched_total = fetched_total + 1
    if ch.fail then error("HTTP 429") end
    state.css = state.css or "css"
    return "<x>" .. ch.chapterUid .. "</x>"
end
function Content.fetch_chapter_css() return "css" end
local D = {}; D.__index = D
function D:_runInterruptible(dl, task) forks = forks + 1; return task() end
function D:_scheduleGuarded(dl, f, _d) q[#q + 1] = f end
function D:_step(dl)
    if dl.index > dl.total then dl.finished = true; return end
    local ch = dl.chapters[dl.index]
    local before = fetched_total
    local ok, x = pcall(function() return self:_runInterruptible(dl, function()
        return Content.fetch_single_chapter_source(self.client, self.settings, dl.book, ch, dl.state) end) end)
    if fetched_total > before then fetched_in_main = fetched_in_main + 1 end
    dl.got[dl.index] = ok and x or ("ERR")
    dl.index = dl.index + 1
    self:_scheduleGuarded(dl, function() self:_step(dl) end)
end
package.loaded["weread.lib.downloader"] = D
package.loaded["weread.lib.content"] = Content
package.loaded["weread.lib.worker_settings"] = { fingerprint = function() return "f" end,
    capture = function() return function() return nil end end, merge = function() return true end }

local F = require("wereadshelf_fastdl")
local t = 0; F._now = function() t = t + 0.1; return t end
local spawned, maxpar, live = 0, 0, 0
F.proc = {
    spawn = function(fn) spawned = spawned + 1; live = live + 1; if live > maxpar then maxpar = live end
        local okr, r = pcall(fn); return { r = okr and r or { ok = false, err = r }, polls = 0 }, 1 end,
    poll = function(pid) pid.polls = pid.polls + 1; if pid.polls >= 12 then live = live - 1; return true, pid.r end; return false end,
    kill = function() live = live - 1 end,
}
check("install patches weread 1.6.0", F.install() and D._wrs_fast)
check("install is idempotent", not F.install())

local function job(nch, fail_at)
    local chs = {}
    for i = 1, nch do chs[i] = { chapterUid = tostring(100 + i), fail = (i == fail_at) } end
    return setmetatable({ client = {}, settings = {} }, D), { index = 1, total = nch, chapters = chs, book = { bookId = "B" },
        state = {}, trapper = {}, completed = {}, got = {} }
end
local d, dl = job(10)
D._step(d, dl); drain()
check("all 10 chapters delivered in order", dl.finished and dl.got[1] == "<x>101</x>" and dl.got[10] == "<x>110</x>")
check("bounded concurrency (<= 3 workers)", maxpar <= 3 and maxpar >= 2)
check("main process did not refetch prefetched chapters", fetched_in_main <= 1)
check("cached chapters skip the extra fork", forks <= 2)
check("css fetched once per batch at most", dl.state.css == "css")
-- failure: drops to single and falls back to weread path (which retries)
spawned, maxpar, live, fetched_in_main, forks = 0, 0, 0, 0, 0
F.stats.fallbacks = 0
d, dl = job(9, 2)
D._step(d, dl); drain()
check("worker error -> fallback counted, job continues", dl.finished and F.stats.fallbacks == 1 and dl.got[2] == "ERR" and dl.got[9] == "<x>109</x>")
check("after error, prefetch is single (no more parallel)", dl._fast_single == true)
-- completed chapters are not refetched
spawned = 0
d, dl = job(6); for i = 1, 6 do dl.completed[i] = true end; dl.index = 7
D._step(d, dl); drain()
check("completed chapters not fetched", spawned == 0 and dl.finished)
-- cancel kills workers
d, dl = job(6); live = 0
D._step(d, dl); dl.cancelled = true; drain()
check("cancel kills running workers", live <= 0)
-- no trapper -> untouched original path
spawned = 0
d, dl = job(3); dl.trapper = nil
D._step(d, dl); drain()
check("no Trapper -> weread original path", spawned == 0 and dl.finished)
-- dialog throttle
local paints = 0
local dlg = { progress_max = 10, reportProgress = function() paints = paints + 1 end, setTitle = function() paints = paints + 1 end }
F.throttle_dialog(dlg); t = 0; F._now = function() t = t + 0.05; return t end
for i = 1, 9 do dlg:setTitle("c" .. i); dlg:reportProgress(i) end
local mid = paints
dlg:reportProgress(10)
check("progress repaints throttled (18 calls -> few)", mid <= 3 and paints == mid + 1)
print(string.format("\n%d checks, %d failed", n, fails)); print(fails == 0 and "fastdl ok" or "fastdl FAILED")
os.exit(fails == 0 and 0 or 1)
