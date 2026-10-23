-- Offline test + virtual-clock benchmark for realweidu_fastdl
-- (stubbed weread 1.6.0 downloader, worker processes and UIManager).
-- Usage: luajit test_fastdl.lua [path/to/other_fastdl.lua]  (optional comparison)
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end

-- Model (per chapter, seconds; from weread download_perf logs on a PW5-class device):
local LAT = 2.6      -- 4 HTTPS requests (reader page + e_0/e_1/e_3), fresh TLS each
local FORK = 0.45    -- Trapper subprocess start + growing poll interval (avg wait)
local PROC = 0.25    -- footnote scan + checkpoint write + sha256 (main process)
local CSSW = 0.03    -- style.css checkpoint rewrite
local ANNOT = 0.03   -- annotation-source cache write

-- Build a fresh weread stub + scheduler; returns run(nch, opts) -> result.
local function world(module_path)
    local T, q, seq = 0, {}, 0
    local function at(d, f) seq = seq + 1; q[#q + 1] = { t = T + (d or 0), s = seq, f = f } end
    local UI = { scheduleIn = function(_, d, f) at(d, f) end, nextTick = function(_, f) at(0, f) end }
    package.loaded["ui/uimanager"] = UI
    package.loaded["ui/time"] = nil
    local W = { fetched = 0, forks = 0, annot = 0, css_writes = 0, live = 0, maxlive = 0, spawned = 0, inflight = {} }
    local Content = {}
    function Content.fetch_chapter_xhtml(_c, _s, book, ch)
        W.fetched = W.fetched + 1
        W.inflight[ch.chapterUid] = (W.inflight[ch.chapterUid] or 0) + 1
        if ch.fail and (ch.fail == true or ch.fail > 0) then
            if type(ch.fail) == "number" then ch.fail = ch.fail - 1 end
            error(ch.err or "HTTP 500")
        end
        book._content_format = "epub"
        return "<x>" .. ch.chapterUid .. "</x>"
    end
    function Content.fetch_chapter_css() return "css" end
    function Content.cache_annotation_source() W.annot = W.annot + 1; T = T + ANNOT end
    function Content.fetch_single_chapter_source(c, s, b, ch, state)
        local x = Content.fetch_chapter_xhtml(c, s, b, ch)
        Content.cache_annotation_source(s, b, ch, x)
        if not state.css then state.css = Content.fetch_chapter_css() end
        return x
    end
    function Content.save_full_download_css() W.css_writes = W.css_writes + 1; T = T + CSSW; return true end
    local D = {}; D.__index = D
    function D:_runInterruptible(dl, task) W.forks = W.forks + 1; T = T + LAT + FORK; return task() end
    function D:_scheduleGuarded(dl, f, d) at(d or 0.1, f) end
    function D:_step(dl)
        if dl.cancelled then dl.finished = "cancelled"; return end
        if dl.index > dl.total then dl.finished = true; dl.t_end = T; return end
        local ch = dl.chapters[dl.index]
        local ok, x = pcall(function() return self:_runInterruptible(dl, function()
            return Content.fetch_single_chapter_source(self.client, self.settings, dl.book, ch, dl.state) end) end)
        if not ok then
            dl.retries[dl.index] = (dl.retries[dl.index] or 0) + 1
            if dl.retries[dl.index] <= 2 then return self:_scheduleGuarded(dl, function() self:_step(dl) end, 0.8 * dl.retries[dl.index]) end
        end
        dl.got[dl.index] = ok and x or "ERR"
        T = T + PROC
        Content.save_full_download_css({ path = "/ws" }, dl.state.css)
        dl.index = dl.index + 1
        self:_scheduleGuarded(dl, function() self:_step(dl) end)
    end
    package.loaded["weread.lib.downloader"] = D
    package.loaded["weread.lib.content"] = Content
    package.loaded["weread.lib.worker_settings"] = { fingerprint = function() return "f" end,
        capture = function() return function() return nil end end, merge = function() return true end }
    package.loaded["libs/libkoreader-lfs"] = { attributes = function() return "file" end }
    local F
    if module_path then
        package.loaded["realweidu_fastdl"] = nil
        F = dofile(module_path)
        F._now = function() return T end
        F.proc = {
            spawn = function(fn)
                local c = 0; for _ in pairs(F.cache) do c = c + 1 end
                if c > (W.maxcache or 0) then W.maxcache = c end
                W.spawned = W.spawned + 1; W.live = W.live + 1; if W.live > W.maxlive then W.maxlive = W.live end
                local okr, r = pcall(fn)
                return { r = okr and r or { ok = false, err = tostring(r) }, done = T + LAT }, 1
            end,
            poll = function(pid) if T >= pid.done then W.live = W.live - 1; return true, pid.r end; return false end,
            kill = function() W.live = W.live - 1 end,
        }
        F.install()
    end
    local function run(nch, opts)
        opts = opts or {}
        local chs = {}
        for i = 1, nch do chs[i] = { chapterUid = tostring(100 + i) } end
        for i, f in pairs(opts.fail or {}) do chs[i].fail = f end
        for i, e in pairs(opts.err or {}) do chs[i].err = e end
        local d = setmetatable({ client = {}, settings = {} }, D)
        local dl = { index = 1, total = nch, chapters = chs, book = { bookId = "B" .. tostring(seq) },
            state = {}, trapper = (not opts.no_trapper) and {} or nil, completed = opts.completed or {}, got = {}, retries = {} }
        if opts.start_index then dl.index = opts.start_index end
        T = 0
        at(0, function() D._step(d, dl) end)
        local guard = 0
        while #q > 0 and guard < 200000 do
            guard = guard + 1
            table.sort(q, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.s < b.s end)
            local e = table.remove(q, 1)
            if e.t > T then T = e.t end
            if opts.cancel_at and T >= opts.cancel_at and not dl.cancelled then dl.cancelled = true end
            e.f()
        end
        return dl, W, F
    end
    return run, D
end

local NEW = here .. "/../realweidu.koplugin/realweidu_fastdl.lua"
local NCH = 60
local base_dl = world(nil)(NCH)
local run = world(NEW)
local dl, W, F = run(NCH)
local ordered = dl.finished == true
for i = 1, NCH do if dl.got[i] ~= "<x>" .. (100 + i) .. "</x>" then ordered = false end end
check("all 60 chapters delivered, in order, content intact", ordered)
check("adaptive concurrency: starts 3, rises to <= 5", W.maxlive >= 4 and W.maxlive <= 5 and F.stats.raised >= 1)
check("no chapter fetched twice", W.fetched == NCH)
check("results consumed in-process (no per-chapter fork)", W.forks == 0)
check("annotation cache written once per chapter, in main", W.annot == NCH)
check("unchanged style.css written once, not per chapter", W.css_writes == 1 and F.stats.css_skipped == NCH - 1)
check("bounded look-ahead (cache never above 7 chapters)", (W.maxcache or 0) <= 7)
local sp_base = base_dl.t_end / NCH
local sp_new = dl.t_end / NCH
print(string.format("bench  weread 1.6.0 serial : %.2f s/chapter (%.0f s for %d)", sp_base, base_dl.t_end, NCH))
local other = arg[1]
if other then
    local r2 = world(other)
    local dl2 = r2(NCH)
    print(string.format("bench  %s : %.2f s/chapter (%.0f s)", other:match("[^/]+$"), dl2.t_end / NCH, dl2.t_end))
end
print(string.format("bench  0.3.8 pipeline      : %.2f s/chapter (%.0f s)  -> %.1fx vs serial", sp_new, dl.t_end, sp_base / sp_new))
check("pipeline >= 3x faster than weread serial (model)", sp_base / sp_new >= 3)

-- one transient error: concurrency halves, chapter goes through weread's path, job continues
dl, W, F = world(NEW)(20, { fail = { [5] = 1 } })
check("transient error -> chapter retried via weread path, job completes in order",
    dl.finished == true and dl.got[5] == "<x>105</x>" and dl.got[20] == "<x>120</x>" and F.stats.fallbacks == 1)
check("transient error -> not serial (backs off, then may rise again)", not dl._fast_single and dl._wrs.c >= 1)
-- 429 -> serial for the rest of the job
dl, W, F = world(NEW)(20, { fail = { [4] = 1 }, err = { [4] = "e_0 failed: HTTP 429" } })
local spawned_at_429 = W.spawned
check("HTTP 429 -> serial fallback for the rest of the job", dl.finished == true and dl._fast_single == true
    and dl.got[20] == "<x>120</x>")
check("after 429 no new workers beyond those in flight", W.spawned <= 9)
-- two errors in a row -> serial
dl, W, F = world(NEW)(20, { fail = { [3] = 1, [4] = 1 } })
check("two consecutive errors -> serial", dl._fast_single == true and dl.finished == true and dl.got[4] == "<x>104</x>")
-- persistent failure -> weread marks ERR after its own retries, job still finishes
dl, W, F = world(NEW)(10, { fail = { [6] = true } })
check("permanent chapter failure -> weread's own retries then ERR", dl.finished == true and dl.got[6] == "ERR" and dl.got[10] == "<x>110</x>")
-- completed chapters (resume) not refetched
local comp = {}; for i = 1, 6 do comp[i] = true end
dl, W = world(NEW)(6, { completed = comp, start_index = 7 })
check("completed chapters not fetched", W.spawned == 0 and dl.finished == true)
-- cancel kills workers
dl, W = world(NEW)(30, { cancel_at = 5 })
check("cancel kills running workers", W.live <= 0 and dl.finished == "cancelled")
-- no trapper -> untouched original path
dl, W = world(NEW)(3, { no_trapper = true })
check("no Trapper -> weread original path", W.spawned == 0 and dl.finished == true)
-- rate-limit detection
check("rate-limit text detection", F.is_rate_limit("HTTP 429") and F.is_rate_limit("Too Many Requests")
    and F.is_rate_limit("操作频繁") and not F.is_rate_limit("HTTP 500"))
-- dialog throttle
local t = 0; F._now = function() t = t + 0.05; return t end
local paints = 0
local dlg = { progress_max = 10, reportProgress = function() paints = paints + 1 end, setTitle = function() paints = paints + 1 end }
F.throttle_dialog(dlg)
for i = 1, 9 do dlg:setTitle("c" .. i); dlg:reportProgress(i) end
local mid = paints
dlg:reportProgress(10)
check("progress repaints throttled (18 calls -> few)", mid <= 3 and paints == mid + 1)
print(string.format("\n%d checks, %d failed", n, fails)); print(fails == 0 and "fastdl ok" or "fastdl FAILED")
os.exit(fails == 0 and 0 or 1)
