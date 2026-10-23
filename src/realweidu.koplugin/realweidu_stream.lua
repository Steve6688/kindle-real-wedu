-- realweidu_stream.lua (0.6.1) — 边下边读: a full-book download opens for
-- reading as soon as its first chapters are in; the rest download in the
-- background while reading. weread 1.6.0 is not changed: Downloader:start is
-- wrapped at runtime for full-book jobs only (not prefetch / single chapter /
-- separate chapters); everything else still goes through weread.
--
-- Engine
--   * a sliding window of worker processes (realweidu_fastdl's runner) runs
--     weread's own chapter fetch (Content.fetch_chapter_xhtml + CSS once +
--     finalize_single_chapter_content for images), CONCURRENCY at a time,
--     STAGGER s apart;
--   * every finished chapter is persisted at once to
--     <book cache dir>/.realweidu_stream/ch/<i>.xhtml with a meta.lua (book,
--     chapters, css, assets), so an exit / crash / power-off loses at most
--     the chapters in flight; the job list lives in G_reader_settings
--     "realweidu_stream" and is resumed on the next start;
--   * failures retry with backoff (RETRY_DELAYS); a chapter that keeps
--     failing is parked (shown as a "下载失败" placeholder) and tried again
--     on the next resume; HTTP 429 pauses the whole job for RATE_PAUSE s.
-- Reading
--   * once chapters 1..FIRST_READY are in, the EPUB is built with weread's
--     own Content.save_book_epub (same path / name as a normal full
--     download, no cover page, so spine item k == chapter k ==
--     /body/DocFragment[k]) with a placeholder page for every missing
--     chapter, registered as the book's cached_full_book and opened;
--   * on every page update the current chapter is checked: a placeholder
--     chapter is moved to the front of the queue (and the next one after
--     it); when it arrives the book is rebuilt and reloaded at that chapter;
--     a reader near the end of a chapter whose next chapter has arrived gets
--     a rebuild + reload that keeps the exact position (KOReader saves and
--     restores the xpointer; earlier chapters are byte-identical, so the
--     xpointer stays valid);
--   * when everything is in, the final EPUB is identical in content to the
--     non-streamed download and the job is removed.
local M = {
    CONCURRENCY = 3,
    STAGGER = 0.25,
    POLL = 0.2,
    FIRST_READY = 3,
    WORKER_TIMEOUT = 90,
    RETRY_DELAYS = { 2, 5, 15 },
    RATE_PAUSE = 30,
    NEAR_END_PAGES = 3,
    SETTING = "realweidu_stream",
    jobs = {},      -- [book_id] = live job
    finished = {},  -- [epub path] = finished job whose open book still has placeholders
    deps = {},      -- test injection: Content, proc, UIManager, now, G, lfs
}

local function dep(name)
    if M.deps[name] ~= nil then return M.deps[name] end
    if name == "UIManager" then return require("ui/uimanager") end
    if name == "G" then return rawget(_G, "G_reader_settings") end
    if name == "lfs" then return require("libs/libkoreader-lfs") end
    if name == "now" then
        local FastDL = package.loaded["realweidu_fastdl"]
        return FastDL and FastDL._now or function() return os.time() + (os.clock() % 1) end
    end
    if name == "Content" then
        return package.loaded["rweread.lib.content"] or package.loaded["weread.lib.content"]
    end
    if name == "WorkerSettings" then
        return package.loaded["rweread.lib.worker_settings"] or package.loaded["weread.lib.worker_settings"]
    end
    if name == "proc" then
        local FastDL = require("realweidu_fastdl")
        return FastDL.get_proc and FastDL.get_proc() or nil
    end
end
M.dep = dep
local function now() return dep("now")() end

local function logi(...)
    local ok, lg = pcall(require, "logger")
    if ok and lg and lg.info then lg.info(...) end
end

-- ---------------------------------------------------------------- pure helpers

function M.chapter_from_xpointer(xp)
    local n = type(xp) == "string" and xp:match("^/body/DocFragment%[(%d+)%]")
    return n and tonumber(n) or nil
end

function M.count_done(job)
    local n = 0
    for i = 1, job.total do if job.done[i] then n = n + 1 end end
    return n
end

function M.ready_to_open(job)
    for i = 1, math.min(M.FIRST_READY, job.total) do
        if not job.done[i] then return false end
    end
    return true
end

function M.complete(job) return M.count_done(job) >= job.total end

-- Next chapters to fetch, in priority order: the chapter the reader waits on
-- and the one after it, then the opening chapters, then onwards from the
-- reader's position, then wrap around. Excludes done / in flight / parked /
-- waiting for a retry delay.
function M.plan(job, n, t)
    t = t or now()
    local out, seen = {}, {}
    local function try(i)
        if #out >= n or seen[i] or i < 1 or i > job.total then return end
        seen[i] = true
        if job.done[i] or job.inflight[i] or job.parked[i] then return end
        local r = job.retry_at[i]
        if r and t < r then return end
        out[#out + 1] = i
    end
    local p = job.priority
    if p then try(p); try(p + 1) end
    for i = 1, math.min(M.FIRST_READY, job.total) do try(i) end
    local from = job.position or p or 1
    for i = from, job.total do try(i) end
    for i = 1, from - 1 do try(i) end
    return out
end

function M.placeholder_xhtml(title, failed)
    local esc = tostring(title or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    local msg = failed and "本章下载失败，联网后会自动重试。" or "本章正在下载，下载完成后会自动显示。"
    return '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>'
        .. esc .. '</title></head><body><h2>' .. esc .. '</h2>'
        .. '<p class="realweidu-stream-placeholder" style="text-align:center;margin-top:3em">' .. msg .. '</p>'
        .. '<p style="text-align:center">（边下边读 · Real微读）</p></body></html>'
end

function M.is_rate_limit(err)
    local e = tostring(err or ""):lower()
    return e:find("429", 1, true) ~= nil or e:find("too many", 1, true) ~= nil or e:find("频繁", 1, true) ~= nil
end

-- Shelf label for a book, or nil when no stream job is pending.
function M.shelf_label(book_id)
    local st = M.status(book_id)
    if not st then return nil end
    local word = st.state == "paused" and "下载暂停" or "边下边读"
    return string.format("%s %d/%d", word, st.done or 0, st.total or 0)
end

function M.status(book_id)
    book_id = tostring(book_id)
    local job = M.jobs[book_id]
    if job then
        return { done = M.count_done(job), total = job.total,
                 state = (job.running and "running") or "paused" }
    end
    local G = dep("G")
    local idx = G and G:readSetting(M.SETTING)
    local e = type(idx) == "table" and idx[book_id]
    if type(e) == "table" then return { done = e.done, total = e.total, state = "paused" } end
    return nil
end

-- ---------------------------------------------------------------- persistence

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function mkdir(p) os.execute("mkdir -p " .. shq(p)) end
local function write(path, data)
    local tmp = path .. ".part"
    local f, e = io.open(tmp, "wb")
    if not f then return false, e end
    f:write(data); f:close()
    return os.rename(tmp, path)
end
local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
M._read, M._write = read, write

local function plain(t, depth)
    depth = depth or 0
    local o = {}
    for k, v in pairs(t or {}) do
        local tk, tv = type(k), type(v)
        if (tk == "string" or tk == "number") and k ~= "_raw" then
            if tv == "string" or tv == "number" or tv == "boolean" then o[k] = v
            elseif tv == "table" and depth < 3 then o[k] = plain(v, depth + 1) end
        end
    end
    return o
end

local function serialize(v, ind)
    ind = ind or ""
    local tv = type(v)
    if tv == "string" then return string.format("%q", v)
    elseif tv == "number" or tv == "boolean" then return tostring(v)
    elseif tv ~= "table" then return "nil" end
    local parts, ni = {}, ind .. " "
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
        local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        parts[#parts + 1] = ni .. ks .. "=" .. serialize(v[k], ni)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
end
M._serialize = serialize

function M.save_meta(job)
    local meta = { book = job.book, chapters = job.chapters, css = job.css, assets = job.assets,
                   built = job.built, path = job.path, done = {} }
    for i = 1, job.total do if job.done[i] then meta.done[#meta.done + 1] = i end end
    write(job.dir .. "/meta.lua", "return " .. serialize(meta))
end

function M.load_meta(dir)
    local s = read(dir .. "/meta.lua")
    if not s then return nil end
    local fn = loadstring(s)
    if not fn then return nil end
    setfenv(fn, {})
    local ok, meta = pcall(fn)
    return ok and type(meta) == "table" and meta or nil
end

local function index_update(job, remove)
    local G = dep("G")
    if not G then return end
    local idx = G:readSetting(M.SETTING)
    if type(idx) ~= "table" then idx = {} end
    if remove then idx[job.book_id] = nil
    else idx[job.book_id] = { dir = job.dir, path = job.path, done = M.count_done(job), total = job.total } end
    G:saveSetting(M.SETTING, idx)
    if remove or (job._flushes or 0) % 5 == 0 then pcall(G.flush, G) end
    job._flushes = (job._flushes or 0) + 1
end
M._index_update = index_update

local function stream_dir(settings, book)
    local Content = dep("Content")
    local id = tostring(book.book_id or book.bookId)
    local base = (Content and Content.book_cache_dir and Content.book_cache_dir(settings, id))
        or ((settings and settings.cache_dir or "/tmp") .. "/" .. id)
    return base .. "/.realweidu_stream"
end
M.stream_dir = stream_dir

-- ---------------------------------------------------------------- job model

function M.new_job(D, book, chapters)
    local book_id = tostring(book.book_id or book.bookId)
    local job = {
        book_id = book_id, D = D, book = plain(book), chapters = {},
        total = #chapters, done = {}, inflight = {}, parked = {}, retry_at = {}, fails = {},
        assets = {}, used_names = {}, built = {}, live = 0, last_spawn = -1e9,
    }
    for i, c in ipairs(chapters) do job.chapters[i] = plain(c) end
    job.dir = stream_dir(D.settings, job.book)
    mkdir(job.dir .. "/ch"); mkdir(job.dir .. "/images")
    local meta = M.load_meta(job.dir)
    if meta and type(meta.chapters) == "table" and #meta.chapters == job.total then
        for _, i in ipairs(meta.done or {}) do
            if read(job.dir .. "/ch/" .. i .. ".xhtml") then job.done[i] = true end
        end
        job.css = meta.css
        job.assets = meta.assets or {}
        job.built = meta.built or {}
        job.path = meta.path
        for _, a in ipairs(job.assets) do job.used_names[(a.href or ""):match("[^/]+$") or ""] = true end
    end
    return job
end

function M.load_job(D, book_id, dir)
    local meta = M.load_meta(dir)
    if not meta or type(meta.book) ~= "table" or type(meta.chapters) ~= "table" then return nil end
    return M.new_job(D, meta.book, meta.chapters)
end

-- Package the EPUB: weread's own packager, placeholders for missing chapters.
function M.build(job)
    local Content = dep("Content")
    local bodies, built = {}, {}
    for i, c in ipairs(job.chapters) do
        local uid = tostring(c.chapterUid)
        local x = job.done[i] and read(job.dir .. "/ch/" .. i .. ".xhtml")
        if x then bodies[uid] = x; built[i] = true
        else bodies[uid] = M.placeholder_xhtml(c.title, job.parked[i]) end
    end
    -- the open document keeps what it was opened with until it is reloaded
    if not job.open_built and M.reader_for(job) and not job.swapping then
        local snap = {}
        for k, v in pairs(job.built or {}) do snap[k] = v end
        job.open_built = snap
    end
    local book = {}
    for k, v in pairs(job.book) do book[k] = v end
    local t0 = now()
    local ok, path = pcall(Content.save_book_epub, job.D.settings, book, job.chapters, bodies,
        "full", job.assets, job.css or "", nil)
    if not ok or type(path) ~= "string" then
        logi("realweidu stream: build failed", tostring(path))
        return nil, path
    end
    job.path, job.built = path, built
    job.book.cache_dir = book.cache_dir
    M.save_meta(job)
    index_update(job)
    logi("realweidu stream: built", string.format("%d/%d chapters in %.2fs", M.count_done(job), job.total, now() - t0))
    return path
end

-- Same record fields weread's downloader writes on a finished full download
-- (downloader.lua apply_cache_result), so the shelf opens the book directly.
function M.register(job)
    local D = job.D
    local s = D and D.settings
    if not (s and s.get and s.set) then return end
    local books = s:get("books", {})
    local r = books[job.book_id] or {}
    for k, v in pairs(job.book) do if r[k] == nil then r[k] = v end end
    r.cached_full_book, r.cached_file = job.path, job.path
    r.cache_dir = job.book.cache_dir or r.cache_dir
    books[job.book_id] = r
    s:set("books", books)
    if s.flush then pcall(s.flush, s) end
    if D.refresh_shelf then pcall(D.refresh_shelf) end
end

-- ---------------------------------------------------------------- workers

local function spawn(job, i)
    local P = dep("proc")
    local Content, WS = dep("Content"), dep("WorkerSettings")
    local D = job.D
    local chapter = job.chapters[i]
    local book = {}
    for k, v in pairs(job.book) do book[k] = v end
    local need_css = job.css == nil and not job.css_job
    if need_css then job.css_job = i end
    local used = {}
    for k in pairs(job.used_names) do used[k] = true end
    local pid, fd = P.spawn(function()
        local Net = package.loaded["realweidu_net"]
        if Net then Net.reset() end
        local cap = WS and WS.capture and WS.capture(D.settings)
        local xhtml = Content.fetch_chapter_xhtml(D.client, D.settings, book, chapter)
        local css = need_css and Content.fetch_chapter_css(D.client, D.settings, book, chapter) or nil
        local assets = {}
        if Content.finalize_single_chapter_content then
            xhtml, assets = Content.finalize_single_chapter_content(D.client, D.settings, book, chapter,
                xhtml, { used_asset_names = used })
        end
        return { ok = true, xhtml = xhtml, css = css, assets = assets, auth = cap and cap() or nil,
                 perf = Net and Net.reset() or nil }
    end)
    local j = { i = i, pid = pid, fd = fd, t0 = now(), css = need_css }
    job.inflight[i] = j
    job.last_spawn = j.t0
    if pid then job.live = job.live + 1 else j.res = { ok = false, err = "spawn failed" } end
end

-- Keep image names unique across parallel workers.
local function store_assets(job, i, xhtml, assets)
    for _, a in ipairs(assets or {}) do
        if a.href and (a.data or a.path) then
            local name = a.href:match("[^/]+$")
            local new = name
            if job.used_names[name] then new = "c" .. i .. "_" .. name end
            if new ~= name then
                xhtml = xhtml:gsub(("images/" .. name):gsub("%p", "%%%0"), "images/" .. new)
            end
            local dst = job.dir .. "/images/" .. new
            if a.data then write(dst, a.data) else os.rename(a.path, dst) end
            job.used_names[new] = true
            table.insert(job.assets, { href = "images/" .. new, media_type = a.media_type, path = dst })
        end
    end
    return xhtml
end

function M.on_result(job, j)
    job.inflight[j.i] = nil
    if j.pid then job.live = job.live - 1 end
    if job.css_job == j.i then job.css_job = nil end
    local r = j.res or {}
    local i = j.i
    if r.ok and type(r.xhtml) == "string" then
        local FastDL = package.loaded["realweidu_fastdl"]
        if r.perf and FastDL and FastDL.Net then FastDL.Net.merge(FastDL.Net.perf, r.perf) end
        local WS = dep("WorkerSettings")
        if r.auth and WS and WS.merge then pcall(WS.merge, job.D.settings, WS.fingerprint and WS.fingerprint(job.D.settings), r.auth) end
        if r.css ~= nil and job.css == nil then job.css = r.css end
        local x = store_assets(job, i, r.xhtml, r.assets)
        local ok = write(job.dir .. "/ch/" .. i .. ".xhtml", x)
        if ok then
            job.done[i] = true; job.fails[i] = nil; job.retry_at[i] = nil
            M.save_meta(job); index_update(job)
            return true
        end
        r.err = "disk write failed"
    end
    job.fails[i] = (job.fails[i] or 0) + 1
    logi("realweidu stream: chapter failed", job.book_id, i, tostring(r.err), "try", job.fails[i])
    if M.is_rate_limit(r.err) then job.pause_until = now() + M.RATE_PAUSE end
    local d = M.RETRY_DELAYS[job.fails[i]]
    if d then job.retry_at[i] = now() + d else job.parked[i] = true end
    return false
end

-- ---------------------------------------------------------------- scheduler

local tick

local function schedule(job)
    if job.scheduled or not job.running then return end
    job.scheduled = true
    dep("UIManager"):scheduleIn(M.POLL, function() job.scheduled = false; tick(job) end)
end

function M.stop(job, keep)
    local P = dep("proc")
    job.running = false
    for i, j in pairs(job.inflight) do
        if j.pid and not j.res and P then P.kill(j.pid, j.fd) end
        job.inflight[i] = nil
    end
    job.live = 0
    if not keep then M.jobs[job.book_id] = nil end
end

-- Final package + cleanup (never while the book is open: see M.swap).
function M.finalize(job)
    local path = M.build(job)
    if not path then return nil end
    M.register(job)
    index_update(job, true)
    os.execute("rm -rf " .. shq(job.dir))
    job.final, job.final_deferred = true, nil
    return path
end

local function finish(job)
    M.stop(job, true)
    M.jobs[job.book_id] = nil
    if M.reader_for(job) then
        -- open book: package when it is reloaded (next placeholder / near end)
        job.final_deferred = true
        if not job.open_built then
            local snap = {}
            for k, v in pairs(job.built or {}) do snap[k] = v end
            job.open_built = snap
        end
        M.finished[job.path] = job
    else
        M.finalize(job)
    end
    job.finished_at = now()
    logi("realweidu stream: done", job.book_id, string.format("chapters=%d total=%.1fs first_read=%s",
        job.total, job.finished_at - (job.t0 or job.finished_at), job.first_read and string.format("%.1fs", job.first_read) or "-"))
    if M.on_finished then pcall(M.on_finished, job) end
    if M.on_change then pcall(M.on_change, job) end
    -- the open book still shows placeholders: swap at the next page update
    local ui = M.reader_for(job)
    if ui then M.on_page(ui) end
end

tick = function(job)
    if not job.running then return end
    local P = dep("proc")
    local t = now()
    local arrived = {}
    for _, j in pairs(job.inflight) do
        if not j.res and j.pid then
            local fin, res = P.poll(j.pid, j.fd)
            if fin then j.res = res
            elseif t - j.t0 > M.WORKER_TIMEOUT then P.kill(j.pid, j.fd); j.res = { ok = false, err = "timeout" } end
        end
    end
    local finished = {}
    for _, j in pairs(job.inflight) do if j.res then finished[#finished + 1] = j end end
    for _, j in ipairs(finished) do
        if M.on_result(job, j) then arrived[#arrived + 1] = j.i end
    end
    if #arrived > 0 and M.on_progress then pcall(M.on_progress, job, arrived) end
    if #arrived > 0 and M.on_change then pcall(M.on_change, job) end
    if M.complete(job) then return finish(job) end
    if not (job.pause_until and t < job.pause_until) and job.live < M.CONCURRENCY
        and t - job.last_spawn >= M.STAGGER then
        local nx = M.plan(job, 1, t)[1]
        if nx then spawn(job, nx) end
    end
    if job.live == 0 and #M.plan(job, 1, math.huge) == 0 then
        -- only parked chapters left: stop; retried on next resume / open
        job.running = false
        index_update(job)
        logi("realweidu stream: paused, parked chapters remain", job.book_id)
        if M.on_progress then pcall(M.on_progress, job, {}) end
        return
    end
    schedule(job)
end

function M.run(job)
    if job.running then return end
    job.running = true
    job.t0 = job.t0 or now()
    M.jobs[job.book_id] = job
    for i in pairs(job.parked) do job.parked[i] = nil; job.fails[i] = nil end
    if M.complete(job) then return finish(job) end
    tick(job)
end

function M.prioritize(job, i)
    if job.priority ~= i then
        job.priority = i
        job.retry_at[i] = nil
        if job.parked[i] then job.parked[i] = nil; job.fails[i] = nil end
    end
    if not job.running then M.run(job) end
end

-- ---------------------------------------------------------------- UI glue

function M.reader_for(job)
    local RUI = package.loaded["apps/reader/readerui"]
    local ui = RUI and RUI.instance
    if ui and ui.document and job.path and ui.document.file == job.path then return ui end
    return nil
end

local function job_for_file(file)
    if M.finished[file] then return M.finished[file] end
    for _, job in pairs(M.jobs) do if job.path == file then return job end end
    local G = dep("G")
    local idx = G and G:readSetting(M.SETTING)
    if type(idx) ~= "table" then return nil end
    for book_id, e in pairs(idx) do
        if type(e) == "table" and e.path == file and M.resume_one then
            return M.resume_one(book_id, e)
        end
    end
    return nil
end
M.job_for_file = job_for_file

local function current_chapter(ui)
    local ok, xp = pcall(function() return ui.document:getXPointer() end)
    return ok and M.chapter_from_xpointer(xp) or nil
end
M.current_chapter = current_chapter

local function toast(text, timeout)
    local ok, InfoMessage = pcall(require, "ui/widget/infomessage")
    if not ok then return end
    local w = InfoMessage:new{ text = text, timeout = timeout or 2 }
    dep("UIManager"):show(w)
    return w
end

-- Rebuild and reload the open book. goto_chapter: jump to its start (the
-- reader was on a placeholder); nil: KOReader keeps the exact xpointer.
function M.swap(ui, job, goto_chapter)
    if job.swapping then return end
    job.swapping = true
    M.pending_goto = goto_chapter and { file = job.path, chapter = goto_chapter } or nil
    logi("realweidu stream: reload", job.book_id, goto_chapter and ("goto " .. goto_chapter) or "keep position")
    dep("UIManager"):nextTick(function()
        -- the EPUB is rewritten only after the open document is closed
        -- (crengine reads the zip lazily: never replace it underneath)
        ui:reloadDocument(function()
            job.swapping = false
            if job.final_deferred then M.finished[job.path] = nil; M.finalize(job)
            elseif not job.final then M.build(job) end
        end, true, function(new_ui) M.apply_pending(new_ui) end)
    end)
end

function M.apply_pending(ui)
    local p = M.pending_goto
    if not (p and ui and ui.document and ui.document.file == p.file) then return end
    M.pending_goto = nil
    local xp = "/body/DocFragment[" .. p.chapter .. "]"
    pcall(function()
        local Event = require("ui/event")
        ui:handleEvent(Event:new("GotoXPointer", xp, xp))
    end)
end

-- A reader (re)opened a file: it now shows what is on disk.
function M.on_reader_open(ui)
    if not (ui and ui.document and ui.document.file) then return end
    local job = job_for_file(ui.document.file)
    if not job then return end
    job.open_built = nil
    if job.final then M.finished[job.path] = nil end
    -- the pending chapter jump runs from reloadDocument's after-open callback
    -- (the document is not rendered yet during plugin init)
end

-- Called on every page update of any open book.
function M.on_page(ui)
    if not (ui and ui.document and ui.document.file) then return end
    local job = job_for_file(ui.document.file)
    if not job then return end
    local idx = current_chapter(ui)
    if not idx then return end
    job.position = idx
    local built = job.open_built or job.built or {}
    if not built[idx] then
        if job.done[idx] then return M.swap(ui, job, idx) end
        M.prioritize(job, idx)
        job.waiting = idx
        if job.toasted ~= idx then
            job.toasted = idx
            toast(string.format("第 %d 章正在下载，完成后自动显示（%d/%d）", idx, M.count_done(job), job.total), 2)
        end
        return
    end
    job.waiting = nil
    local nxt = idx + 1
    if nxt <= job.total and not built[nxt] then
        if job.done[nxt] then
            local left
            pcall(function() left = ui.toc:getChapterPagesLeft(ui.view.state.page or ui.document:getCurrentPage()) end)
            if left == nil then pcall(function() left = ui.toc:getChapterPagesLeft(ui.document:getCurrentPage()) end) end
            if left and left <= M.NEAR_END_PAGES then return M.swap(ui, job, nil) end
        elseif not job.priority or job.priority < idx then
            M.prioritize(job, nxt)
        end
    end
end

-- A chapter arrived: swap at once if the reader sits on its placeholder.
function M.on_progress(job, arrived)
    if job.opening then job.opening(job) end
    local ui = M.reader_for(job)
    if not ui or not job.waiting then return end
    for _, i in ipairs(arrived) do
        if i == job.waiting then job.waiting = nil; return M.swap(ui, job, i) end
    end
end

local function open_path(job)
    local D = job.D
    if D and D.open_file then return D.open_file(job.path) end
    local RUI = require("apps/reader/readerui")
    RUI:showReader(job.path)
end

-- Full-book start: returns true when handled here.
function M.start(D, book, chapters, options)
    if #chapters <= M.FIRST_READY then return false end
    local book_id = tostring(book.book_id or book.bookId)
    local job = M.jobs[book_id]
    if job and job.path then open_path(job); return true end -- already readable
    if not job then
        job = M.new_job(D, book, chapters)
        job.t0 = now()
    end
    job.D = D -- (a resumed job that is not readable yet gets the opening flow)
    local msg
    local function close_msg()
        local m = msg
        msg = nil
        if m then dep("UIManager"):close(m) end
    end
    local function show_wait()
        close_msg()
        local n = 0
        for i = 1, math.min(M.FIRST_READY, job.total) do if job.done[i] then n = n + 1 end end
        local ok, InfoMessage = pcall(require, "ui/widget/infomessage")
        if not ok then return end
        msg = InfoMessage:new{
            text = string.format("正在下载前 %d 章（%d/%d），下载完即可开始阅读。\n其余章节会在阅读时后台下载。\n点按此处可关闭，下载会继续。",
                math.min(M.FIRST_READY, job.total), n, math.min(M.FIRST_READY, job.total)),
            dismiss_callback = function()
                if msg then msg = nil; job.opening = nil end -- the user tapped it away
            end,
        }
        dep("UIManager"):show(msg)
    end
    job.opening = function(j)
        if not M.ready_to_open(j) then
            if not j.running then
                job.opening = nil
                close_msg()
                toast("下载失败，请检查网络后重试。", 3)
                return
            end
            return show_wait()
        end
        job.opening = nil
        close_msg()
        if not M.build(j) then toast("生成电子书失败。", 3) return end
        M.register(j)
        j.first_read = now() - j.t0
        logi("realweidu stream: first_read", j.book_id, string.format("%.2fs", j.first_read),
            string.format("chapters %d/%d", M.count_done(j), j.total))
        if M.on_first_read then pcall(M.on_first_read, j) end
        open_path(j)
    end
    index_update(job)
    if M.ready_to_open(job) then
        if job.opening then job.opening(job) end
        M.run(job)
        return true
    end
    show_wait()
    M.run(job)
    return true
end

-- Resume pending jobs after a restart (or when one of their books is opened).
function M.resume_one(book_id, entry)
    if M.jobs[book_id] then return M.jobs[book_id] end
    local Data = package.loaded["realweidu_data"]
    local weread = Data and Data.find_weread and Data.find_weread()
    local D = weread and weread.downloader
    if not (D and entry and entry.dir) then return nil end
    local job = M.load_job(D, book_id, entry.dir)
    if not job then
        local G = dep("G")
        local idx = G and G:readSetting(M.SETTING) or {}
        idx[book_id] = nil
        if G then G:saveSetting(M.SETTING, idx) end
        return nil
    end
    logi("realweidu stream: resume", book_id, M.count_done(job), "/", job.total)
    M.run(job)
    return M.jobs[book_id] or job
end

function M.resume_all()
    local G = dep("G")
    local idx = G and G:readSetting(M.SETTING)
    if type(idx) ~= "table" then return 0 end
    local n = 0
    for book_id, e in pairs(idx) do
        if not M.jobs[book_id] and M.resume_one(book_id, e) then n = n + 1 end
    end
    return n
end

-- Wrap weread's Downloader:start for full-book jobs.
function M.install()
    local L = package.loaded
    local D = L["rweread.lib.downloader"] or L["weread.lib.downloader"]
    if type(D) ~= "table" or type(D.start) ~= "function" or D._wrs_stream then return false end
    if not dep("proc") then return false end
    local orig = D.start
    D._wrs_stream = true
    D._wrs_orig_start = orig
    D.start = function(self, book, chapters, suffix, options)
        options = options or {}
        if suffix == "full" and not options.prefetch and not options.single_chapter
            and not options.separate_chapters and type(chapters) == "table" and #chapters > M.FIRST_READY
            and not self._active_job and not self._scheduled_start then
            if self.require_login and not self.require_login(true, false) then return false end
            local ok, handled = pcall(M.start, self, book, chapters, options)
            if ok and handled then return true end
            if not ok then logi("realweidu stream: start failed, weread path", tostring(handled)) end
        end
        return orig(self, book, chapters, suffix, options)
    end
    return true
end

return M
