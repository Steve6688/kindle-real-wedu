-- wereadshelf_fastdl.lua — faster full-book downloads for weread.koplugin 1.6.0,
-- applied at runtime (no weread file is changed; removed by turning it off).
--
-- Where the time went (weread/lib/downloader.lua 1.6.0), per chapter, strictly
-- one after another:
--   * a fork via Trapper:dismissableRunInSubprocess (_runInterruptible :457),
--     whose poll interval grows from 125 ms to 1 s (frontend/ui/trapper.lua:583)
--     so a 2-3 s chapter typically waits 0.25-1 s extra after it is done;
--   * 4 HTTPS requests, each a fresh TCP+TLS handshake (LuaSocket has no
--     keep-alive): reader page (ensure_reader_state) + shards e_0/e_1/e_3
--     (content.lua:1580);
--   * 2 scheduleIn(0.1) hops and 3-4 progress-dialog repaints (setTitle +
--     reportProgress, each a "fast" e-ink refresh).
-- What this does (0.3.8), bounded and conservative:
--   1. A sliding window of worker processes prefetches the next chapter
--      sources while weread processes the current one (no batch barrier).
--      Concurrency starts at 3 and grows by 1 after every 4 clean chapters up
--      to 5; workers start >= 0.25 s apart (never a burst). Each worker runs
--      weread's own fetch (reader page + shards + CSS once), so the request
--      pattern per chapter is unchanged; look-ahead is bounded (memory).
--   2. Backoff: any worker error halves concurrency, pauses new starts for
--      2 s and sends that chapter through weread's normal path (its retries
--      with 0.8 s × n backoff). HTTP 429 / rate-limit text, two errors in a
--      row, or a txt-format book -> serial (weread's own path) for the rest
--      of the job.
--   3. Less per-chapter overhead: the result is consumed in-process (no extra
--      fork), the 0.1 s idle hop between chapters is gone, the unchanged
--      style.css checkpoint is not rewritten per chapter, the annotation
--      source cache is written serially in the main process (no SQLite
--      contention between workers), and progress repaints are throttled to
--      one per second. Book metadata (settings "books") is still saved once
--      at the end, as in weread. Cached/completed chapters are skipped.
local M = {
    CONCURRENCY = 3,      -- start with this many parallel chapter fetches
    MAX_CONCURRENCY = 5,  -- adaptive ceiling (0.3.8)
    RAISE_AFTER = 4,      -- consecutive successes before +1 worker
    STAGGER = 0.25,       -- s between worker starts (never a burst)
    POLL = 0.05,          -- s
    WORKER_TIMEOUT = 90,  -- s; then the chapter falls back to weread's path
    UI_MIN_INTERVAL = 1.0,-- s between progress repaints
    cache = {},           -- [book:uid] = { xhtml=, css= }
    stats = { batches = 0, prefetched = 0, fallbacks = 0, raised = 0, css_skipped = 0, max_seen = 0 },
}

local function now() return os.time() + (os.clock() % 1) end
M._now = function()
    local ok, t = pcall(require, "ui/time")
    if ok and t and t.now and t.to_s then return t.to_s(t.now()) end
    return now()
end

local function key(book, chapter)
    return tostring(book.book_id or book.bookId) .. ":" .. tostring(chapter.chapterUid)
end
M.key = key

local function is_rate_limit(err)
    local e = tostring(err or ""):lower()
    return e:find("429", 1, true) ~= nil or e:find("too many", 1, true) ~= nil
        or e:find("rate", 1, true) ~= nil or e:find("频繁", 1, true) ~= nil
end
M.is_rate_limit = is_rate_limit

-- Per-job pipeline state (0.3.8): a sliding window of workers instead of
-- 0.3.7's batch barrier. c = current concurrency (adaptive).
local function pipe(dl)
    local p = dl._wrs
    if not p then
        p = { c = M.CONCURRENCY, ok_streak = 0, err_streak = 0, serial = false,
              jobs = {}, failed = {}, live = 0, last_spawn = -1e9, css_job = false }
        dl._wrs = p
    end
    return p
end
M.pipe = pipe

-- Next chapter indices to prefetch: not completed, not cached, not in flight,
-- not failed, inside a bounded look-ahead window (bounded memory on a PW5).
function M.plan(dl, n)
    local p = dl._wrs or {}
    local out, i = {}, dl.index
    local limit = dl.index + M.MAX_CONCURRENCY + 2
    while i <= dl.total and i < limit and #out < n do
        local ch = dl.chapters[i]
        if ch and not (dl.completed and dl.completed[i]) and not M.cache[key(dl.book, ch)]
            and not (p.jobs and p.jobs[i]) and not (p.failed and p.failed[i]) then
            out[#out + 1] = i
        end
        i = i + 1
    end
    return out
end

-- Default process runner (KOReader ffi/util); swappable in tests.
M.proc = nil
local function proc()
    if M.proc then return M.proc end
    local ok, ffiutil = pcall(require, "ffi/util")
    if not ok or type(ffiutil.runInSubProcess) ~= "function" then return nil end
    local buffer = require("string.buffer")
    M.proc = {
        spawn = function(fn)
            return ffiutil.runInSubProcess(function(_pid, wfd)
                local okr, res = pcall(fn)
                local s = buffer.encode(okr and res or { ok = false, err = tostring(res) })
                ffiutil.writeToFD(wfd, s, true)
            end, true)
        end,
        poll = function(pid, fd)
            local done = ffiutil.isSubProcessDone(pid)
            local ready = fd and ffiutil.getNonBlockingReadSize(fd) ~= 0
            if ready or done then
                local s = (ready or done) and ffiutil.readAllFromFD(fd) or ""
                local okd, t = pcall(buffer.decode, s)
                if not done then
                    -- collect later so it does not stay a zombie
                    local UIManager = require("ui/uimanager")
                    local function reap() if not ffiutil.isSubProcessDone(pid) then UIManager:scheduleIn(1, reap) end end
                    UIManager:scheduleIn(1, reap)
                end
                return true, okd and t or { ok = false, err = "no result" }
            end
            return false
        end,
        kill = function(pid, fd)
            pcall(ffiutil.terminateSubProcess, pid)
            local UIManager = require("ui/uimanager")
            local function reap()
                if ffiutil.isSubProcessDone(pid) then pcall(ffiutil.readAllFromFD, fd)
                else UIManager:scheduleIn(2, reap) end
            end
            UIManager:scheduleIn(2, reap)
        end,
    }
    return M.proc
end

-- Worker: weread's own chapter fetch (reader page + shards, unchanged request
-- pattern) and CSS. The annotation-source cache write (one SQLite db per book)
-- is done later in the main process, so parallel workers never contend for it.
local function spawn(D, dl, i, Content, WorkerSettings)
    local P, p = proc(), pipe(dl)
    local chapter = dl.chapters[i]
    local book = {}
    for k, v in pairs(dl.book) do book[k] = v end
    local need_css = not (dl.state and dl.state.css) and not p.css_job
    if need_css then p.css_job = true end
    local state_css = dl.state and dl.state.css
    local fetch_x = Content.fetch_chapter_xhtml
    local pid, fd = P.spawn(function()
        local cap = WorkerSettings and WorkerSettings.capture(D.settings)
        local xhtml, css
        if type(fetch_x) == "function" then
            xhtml = fetch_x(D.client, D.settings, book, chapter)
            if need_css then css = Content.fetch_chapter_css(D.client, D.settings, book, chapter) end
        else -- older weread: fall back to the combined call
            local st = { css = state_css or (not need_css and "" or nil) }
            xhtml = Content._wrs_orig_fetch(D.client, D.settings, book, chapter, st)
            css = need_css and st.css or nil
        end
        return { ok = true, xhtml = xhtml, css = css, fmt = book._content_format, auth = cap and cap() or nil }
    end)
    local j = { i = i, chapter = chapter, pid = pid, fd = fd, t0 = M._now(), css = need_css }
    p.jobs[i] = j
    p.last_spawn = j.t0
    if pid then
        p.live = p.live + 1
        if p.live > M.stats.max_seen then M.stats.max_seen = p.live end
    else
        j.res = { ok = false, err = "spawn" }
    end
    return j
end

local function on_result(D, dl, j, WorkerSettings, fingerprint)
    local p = dl._wrs
    p.jobs[j.i] = nil
    if j.pid then p.live = p.live - 1 end
    local r = j.res or {}
    if r.ok and type(r.xhtml) == "string" then
        M.cache[key(dl.book, j.chapter)] = { xhtml = r.xhtml, css = r.css, fmt = r.fmt, annot = true }
        M.stats.prefetched = M.stats.prefetched + 1
        if r.auth and WorkerSettings then pcall(WorkerSettings.merge, D.settings, fingerprint, r.auth) end
        if r.fmt == "txt" then p.serial = true end -- txt books cache inside the fetch: stay serial
        p.err_streak = 0
        p.ok_streak = p.ok_streak + 1
        if not p.serial and p.ok_streak >= M.RAISE_AFTER and p.c < M.MAX_CONCURRENCY then
            p.c = p.c + 1; p.ok_streak = 0; M.stats.raised = M.stats.raised + 1
        end
    else
        M.stats.fallbacks = M.stats.fallbacks + 1
        p.failed[j.i] = true -- this chapter goes through weread's path (its retries + backoff)
        if j.css then p.css_job = false end
        p.ok_streak = 0
        p.err_streak = p.err_streak + 1
        p.c = math.max(1, math.floor(p.c / 2))
        p.cooldown_until = M._now() + 2
        if is_rate_limit(r.err) or p.err_streak >= 2 then
            p.serial = true; dl._fast_single = true -- serial for the rest of this job
        end
    end
end

local function kill_all(dl)
    local p, P = dl._wrs, proc()
    if not p then return end
    for i, j in pairs(p.jobs) do
        if not j.res and j.pid and P then P.kill(j.pid, j.fd) end
        p.jobs[i] = nil
    end
    p.live = 0
end
M.kill_all = kill_all

-- One scheduler tick: poll workers, start one more if allowed, resume the
-- waiting weread step once its chapter is ready (or failed).
local function tick(D, dl, Content, WorkerSettings, UIManager, resume)
    local p, P = dl._wrs, proc()
    if dl.cancelled then
        kill_all(dl); p.ticking = false
        if p.waiting then p.waiting = nil; resume() end
        return
    end
    local now = M._now()
    for _, j in pairs(p.jobs) do
        if not j.res and j.pid then
            local fin, res = P.poll(j.pid, j.fd)
            if fin then j.res = res
            elseif now - j.t0 > M.WORKER_TIMEOUT then
                P.kill(j.pid, j.fd); j.res = { ok = false, err = "timeout" }
            end
        end
    end
    for _, j in pairs(p.jobs) do
        if j.res then on_result(D, dl, j, WorkerSettings, p.fingerprint) end
    end
    if not p.serial and p.live < p.c and now - p.last_spawn >= M.STAGGER
        and not (p.cooldown_until and now < p.cooldown_until and not p.waiting) then
        local nx = M.plan(dl, 1)[1]
        if nx then spawn(D, dl, nx, Content, WorkerSettings) end
    end
    if p.waiting and not p.jobs[p.waiting] then
        local idx = p.waiting
        local ch = dl.chapters[idx]
        if M.cache[key(dl.book, ch)] or p.failed[idx] or p.serial then
            p.waiting = nil
            resume()
        end
    end
    if p.live > 0 or p.waiting or (not p.serial and #M.plan(dl, 1) > 0) then
        UIManager:scheduleIn(M.POLL, function() tick(D, dl, Content, WorkerSettings, UIManager, resume) end)
    else
        p.ticking = false
    end
end

local function ensure_tick(D, dl, Content, WorkerSettings, UIManager, resume)
    local p = pipe(dl)
    if p.ticking or p.serial then return end
    p.ticking = true
    p.fingerprint = p.fingerprint or (WorkerSettings and WorkerSettings.fingerprint(D.settings))
    M.stats.batches = M.stats.batches + 1
    tick(D, dl, Content, WorkerSettings, UIManager, resume)
end
M._ensure_tick = ensure_tick

-- Throttle a DownloadDialog's repaints.
function M.throttle_dialog(dialog)
    if not dialog or dialog._wrs_throttled then return dialog end
    dialog._wrs_throttled = true
    local last = -1e9
    for _, name in ipairs({ "reportProgress", "setTitle" }) do
        local orig = dialog[name]
        if type(orig) == "function" then
            dialog[name] = function(self, v, ...)
                local t = M._now()
                local final = name == "reportProgress" and self.progress_max and tonumber(v) and tonumber(v) >= self.progress_max
                if final or t - last >= M.UI_MIN_INTERVAL then
                    if name == "reportProgress" then last = t end
                    return orig(self, v, ...)
                end
                -- skipped: store value so the next repaint is current
                if name == "setTitle" then self._wrs_title = v; self.title = v end
            end
        end
    end
    return dialog
end

-- Install into weread 1.6.0. Returns true when patched.
function M.install()
    local D = package.loaded["weread.lib.downloader"]
    local Content = package.loaded["weread.lib.content"]
    if type(D) ~= "table" or type(Content) ~= "table" or D._wrs_fast then return false end
    if type(D._step) ~= "function" or type(D._runInterruptible) ~= "function"
        or type(Content.fetch_single_chapter_source) ~= "function" then return false end
    local UIManager = require("ui/uimanager")
    local WorkerSettings = package.loaded["weread.lib.worker_settings"]
    D._wrs_fast = true
    Content._wrs_orig_fetch = Content.fetch_single_chapter_source
    Content.fetch_single_chapter_source = function(client, settings, book, chapter, state)
        local k = key(book, chapter)
        local hit = M.cache[k]
        if hit then
            M.cache[k] = nil
            if hit.fmt and not book._content_format then book._content_format = hit.fmt end
            -- the annotation-source cache write, serial in the main process
            if hit.annot and type(Content.cache_annotation_source) == "function" then
                Content.cache_annotation_source(settings, book, chapter, hit.xhtml)
            end
            if state and not state.css and hit.css then state.css = hit.css end
            if state and not state.css then
                state.css = Content.fetch_chapter_css(client, settings, book, chapter)
            end
            return hit.xhtml
        end
        return Content._wrs_orig_fetch(client, settings, book, chapter, state)
    end
    -- full-book checkpoint: style.css is rewritten after every chapter even
    -- when it did not change; skip identical rewrites (file must exist).
    M._css_saved = {}
    if type(Content.save_full_download_css) == "function" then
        local orig_css = Content.save_full_download_css
        Content._wrs_orig_save_css = orig_css
        Content.save_full_download_css = function(workspace, css)
            local k = workspace and workspace.path
            local v = css or ""
            if k and M._css_saved[k] == v then
                local okl, lfs = pcall(require, "libs/libkoreader-lfs")
                if not okl or type(lfs) ~= "table" or lfs.attributes(k .. "/style.css", "mode") == "file" then
                    M.stats.css_skipped = M.stats.css_skipped + 1
                    return true
                end
            end
            local r = orig_css(workspace, css)
            if k then M._css_saved[k] = v end
            return r
        end
    end
    local orig_run = D._runInterruptible
    D._runInterruptible = function(self, dl, task)
        if dl._wrs_inproc then dl._wrs_inproc = nil; return task() end
        return orig_run(self, dl, task)
    end
    -- no 0.1 s idle gap between chapters of a foreground download
    local orig_sched = D._scheduleGuarded
    D._scheduleGuarded = function(self, dl, fn, delay)
        if delay == nil and type(dl) == "table" and dl._wrs and dl.trapper and not dl.prefetch then delay = 0 end
        return orig_sched(self, dl, fn, delay)
    end
    local orig_step = D._step
    D._step = function(self, dl)
        dl._wrs_inproc = nil
        if dl.progress_dialog then M.throttle_dialog(dl.progress_dialog) end
        if dl.cancelled or dl.index > dl.total or not dl.trapper or dl.prefetch then
            if dl._wrs and (dl.cancelled or dl.index > dl.total) then kill_all(dl) end
            return orig_step(self, dl)
        end
        local ch = dl.chapters[dl.index]
        if not ch or (dl.completed and dl.completed[dl.index]) then return orig_step(self, dl) end
        local p = dl._wrs
        local function resume()
            self:_scheduleGuarded(dl, function() D._step(self, dl) end, 0)
        end
        if M.cache[key(dl.book, ch)] then
            dl._wrs_inproc = true -- result already here: no fork for this one
            if p then ensure_tick(self, dl, Content, WorkerSettings, UIManager, resume) end
            return orig_step(self, dl)
        end
        if (p and (p.serial or p.failed[dl.index])) or not proc() then return orig_step(self, dl) end
        if not p and #M.plan(dl, 2) <= 1 then return orig_step(self, dl) end -- nothing to overlap
        p = pipe(dl)
        if p.waiting then return end -- already waiting; the ticker resumes the job
        p.waiting = dl.index
        if p.ticking then return end
        ensure_tick(self, dl, Content, WorkerSettings, UIManager, resume)
    end
    return true
end

return M
