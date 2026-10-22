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
-- What this does, bounded and conservative:
--   1. Prefetches the next chapter sources in up to CONCURRENCY (3) worker
--      processes at once, started STAGGER s apart, polled every 0.1 s. Each
--      worker runs weread's own Content.fetch_single_chapter_source, so the
--      request pattern per chapter is unchanged; only 3 chapters overlap.
--      The main step then consumes the result in-process (no extra fork).
--   2. On any worker error (HTTP error, rate limit, timeout) prefetch drops to
--      1 worker for the rest of the job and the failing chapter goes through
--      weread's normal path, which keeps its retries with backoff (0.8 s × n).
--   3. Progress dialog updates are throttled to at most one per second.
--   Cached / already-completed chapters are skipped as before (resume map).
local M = {
    CONCURRENCY = 3,      -- max parallel chapter fetches
    STAGGER = 0.4,        -- s between worker starts (no request bursts)
    POLL = 0.1,           -- s
    WORKER_TIMEOUT = 90,  -- s; then the chapter falls back to weread's path
    UI_MIN_INTERVAL = 1.0,-- s between progress repaints
    cache = {},           -- [book:uid] = { xhtml=, css= }
    stats = { batches = 0, prefetched = 0, fallbacks = 0 },
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

-- Pick next chapter indices to prefetch (not completed, not cached).
function M.plan(dl, n)
    local out = {}
    local i = dl.index
    while i <= dl.total and #out < n do
        local ch = dl.chapters[i]
        if ch and not (dl.completed and dl.completed[i]) and not M.cache[key(dl.book, ch)] then
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

-- Run a prefetch batch asynchronously, then call done().
function M.prefetch(D, dl, Content, WorkerSettings, UIManager, done)
    local limit = dl._fast_single and 1 or M.CONCURRENCY
    local idxs = M.plan(dl, limit)
    local P = proc()
    if #idxs <= 1 or not P then return done() end -- nothing to overlap: weread's own path
    M.stats.batches = M.stats.batches + 1
    local fingerprint = WorkerSettings and WorkerSettings.fingerprint(D.settings)
    local jobs, pending = {}, #idxs
    local have_css = dl.state and dl.state.css ~= nil
    local t0 = M._now()
    local function finish()
        for _, j in ipairs(jobs) do
            if j.res and j.res.ok then
                M.cache[key(dl.book, j.chapter)] = { xhtml = j.res.xhtml, css = j.res.css }
                M.stats.prefetched = M.stats.prefetched + 1
                if j.res.auth and WorkerSettings then pcall(WorkerSettings.merge, D.settings, fingerprint, j.res.auth) end
            elseif j.res then
                dl._fast_single = true -- be gentle from now on
                M.stats.fallbacks = M.stats.fallbacks + 1
            end
        end
        done()
    end
    local function start(n)
        local i = idxs[n]
        local chapter = dl.chapters[i]
        local book = {}
        for k, v in pairs(dl.book) do book[k] = v end
        local state = { css = dl.state and dl.state.css }
        local skip_css = (not have_css) and n > 1
        if skip_css then state.css = "" end
        local pid, fd = P.spawn(function()
            local cap = WorkerSettings and WorkerSettings.capture(D.settings)
            local xhtml = Content._wrs_orig_fetch(D.client, D.settings, book, chapter, state)
            return { ok = true, xhtml = xhtml, css = (not skip_css) and state.css or nil, auth = cap and cap() or nil }
        end)
        local j = { chapter = chapter, pid = pid, fd = fd }
        jobs[#jobs + 1] = j
        if not pid then j.res = { ok = false, err = "spawn" }; pending = pending - 1 end
    end
    local started = 0
    local function tick()
        if dl.cancelled then
            for _, j in ipairs(jobs) do if not j.res and j.pid then P.kill(j.pid, j.fd) end end
            return done()
        end
        local elapsed = M._now() - t0
        if started < #idxs and elapsed >= started * M.STAGGER then
            started = started + 1; start(started)
        end
        for _, j in ipairs(jobs) do
            if not j.res and j.pid then
                local fin, res = P.poll(j.pid, j.fd)
                if fin then j.res = res; pending = pending - 1
                elseif elapsed > M.WORKER_TIMEOUT then
                    P.kill(j.pid, j.fd); j.res = { ok = false, err = "timeout" }; pending = pending - 1
                end
            end
        end
        if started >= #idxs and pending <= 0 then return finish() end
        UIManager:scheduleIn(M.POLL, tick)
    end
    tick()
end

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
            if state and not state.css and hit.css then state.css = hit.css end
            if state and not state.css then
                state.css = Content.fetch_chapter_css(client, settings, book, chapter)
            end
            return hit.xhtml
        end
        return Content._wrs_orig_fetch(client, settings, book, chapter, state)
    end
    local orig_run = D._runInterruptible
    D._runInterruptible = function(self, dl, task)
        if dl._wrs_inproc then dl._wrs_inproc = nil; return task() end
        return orig_run(self, dl, task)
    end
    local orig_step = D._step
    D._step = function(self, dl)
        dl._wrs_inproc = nil
        if dl.progress_dialog then M.throttle_dialog(dl.progress_dialog) end
        if dl.cancelled or dl.index > dl.total or not dl.trapper or dl.prefetch then
            return orig_step(self, dl)
        end
        local ch = dl.chapters[dl.index]
        if ch and not (dl.completed and dl.completed[dl.index]) then
            if M.cache[key(dl.book, ch)] then
                dl._wrs_inproc = true -- result already here: no fork for this one
                return orig_step(self, dl)
            end
            if dl._wrs_busy then return end -- a batch is running; it resumes the job
            do
                dl._wrs_busy = true
                return M.prefetch(self, dl, Content, WorkerSettings, UIManager, function()
                    -- back through weread's own guarded scheduler (xpcall +
                    -- Trapper coroutine), so errors and forks behave as before
                    self:_scheduleGuarded(dl, function()
                        dl._wrs_busy = nil
                        if M.cache[key(dl.book, ch)] then dl._wrs_inproc = true end
                        orig_step(self, dl)
                    end, 0)
                end)
            end
        end
        return orig_step(self, dl)
    end
    return true
end

return M
