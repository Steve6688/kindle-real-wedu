-- 0.6.1 offline tests: 边下边读 engine (realweidu_stream) with fake weread deps.
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
package.loaded["logger"] = { info = function() end, warn = function() end }
local S = require("realweidu_stream")
local T = 0
local queue = {}
local UI = { scheduleIn = function(_, d, f) queue[#queue + 1] = { t = T + d, f = f } end,
    nextTick = function(_, f) queue[#queue + 1] = { t = T, f = f } end, show = function() end, close = function() end }
local function run_until(cond, max)
    for _ = 1, max or 5000 do
        if cond and cond() then return true end
        table.sort(queue, function(a, b) return a.t < b.t end)
        local q = table.remove(queue, 1)
        if not q then return cond and cond() end
        T = math.max(T, q.t); q.f()
    end
    return cond and cond()
end
local Gs = {}
local G = { readSetting = function(_, k) return Gs[k] end, saveSetting = function(_, k, v) Gs[k] = v end, flush = function() end }
local fail_plan = {}  -- [i] = number of failures left (or "429")
local fetched = {}
local Content = {
    book_cache_dir = function(s, id) return s.cache_dir .. "/" .. id end,
    fetch_chapter_xhtml = function(_, _, _, ch)
        local f = fail_plan[ch.idx]
        if f then
            if f == "429" then fail_plan[ch.idx] = nil; error("HTTP 429") end
            if f > 0 then fail_plan[ch.idx] = f - 1; error("network down") end
        end
        fetched[#fetched + 1] = ch.idx
        return "<html><body><p>text of " .. ch.idx .. "</p></body></html>"
    end,
    fetch_chapter_css = function() return "p{}" end,
    finalize_single_chapter_content = function(_, _, _, _, x) return x, {} end,
}
local builds = {}
Content.save_book_epub = function(settings, book, chapters, bodies, suffix)
    builds[#builds + 1] = { bodies = bodies, n = #chapters }
    book.cache_dir = settings.cache_dir .. "/" .. book.bookId
    return book.cache_dir .. "/" .. book.title .. " - " .. suffix .. ".epub"
end
-- synchronous "process": result is ready at the first poll
local proc; proc = { spawn = function(fn) local ok, r = pcall(fn); local id = #queue + 1000 + math.random(1e6)
        proc._r[id] = ok and r or { ok = false, err = tostring(r) }; proc._t[id] = T + 3; return id, id end,
    poll = function(pid) if T >= proc._t[pid] then return true, proc._r[pid] end return false end, _t = {}, kill = function() end, _r = {} }
S.deps = { Content = Content, UIManager = UI, G = G, now = function() return T end, proc = proc, WorkerSettings = false }
S.POLL, S.STAGGER = 0.1, 0
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. tmp)
local books, opened = {}, {}
local settingsT = { cache_dir = tmp, get = function(_, k, d) return k == "books" and books or d end,
    set = function(_, k, v) if k == "books" then books = v end end }
local D = { settings = settingsT, client = {}, open_file = function(p) opened[#opened + 1] = p end,
    require_login = function() return true end }
local chapters = {}
for i = 1, 10 do chapters[i] = { chapterUid = 100 + i, idx = i, title = "第" .. i .. "章" } end
local book = { bookId = "B1", title = "Book" }

check("xpointer -> chapter", S.chapter_from_xpointer("/body/DocFragment[7]/body/p[2]/text().3") == 7
    and S.chapter_from_xpointer("/body/p") == nil)
check("short book stays on weread's path", S.start(D, book, { chapters[1], chapters[2] }) == false)

local first_open_T
S.on_first_read = function() first_open_T = T end
fail_plan[2] = 1 -- chapter 2 fails once, then works (retry)
check("full book handled by stream", S.start(D, book, chapters) == true)
run_until(function() return #opened > 0 end)
local job = S.jobs.B1
check("opened after first 3 chapters, not all", #opened == 1 and job and job.done[1] and job.done[2] and job.done[3]
    and S.count_done(job) < 10)
check("retry after failure (chapter 2 refetched after 2 s backoff)", job.done[2] and first_open_T >= 2)
local b = builds[#builds]
check("placeholders for missing chapters", b.n == 10 and b.bodies["110"]:find("本章正在下载", 1, true) ~= nil
    and b.bodies["101"]:find("text of 1", 1, true) ~= nil)
check("record registered as cached_full_book", books.B1 and books.B1.cached_full_book == opened[1])
check("shelf label shows progress", (S.shelf_label("B1") or ""):match("^边下边读 %d+/10$") ~= nil)
check("job index persisted for resume", Gs.realweidu_stream and Gs.realweidu_stream.B1 and Gs.realweidu_stream.B1.total == 10)

-- priority: reader jumps to chapter 9 (a placeholder)
local target
for i = 10, 4, -1 do if not job.done[i] and not job.inflight[i] then target = i break end end
local plan_before = S.plan(job, 1)
S.prioritize(job, target)
local p = S.plan(job, 1)
check("placeholder chapter goes first", target and p[1] == target)

-- exit mid-download: stop, forget in-memory job, resume from disk
S.stop(job); S.jobs = {}
local done_before = S.count_done(job)
local j2 = S.new_job(D, book, chapters)
check("resume keeps finished chapters from disk", S.count_done(j2) == done_before and done_before >= 3)
fetched = {}
fail_plan[10] = 5 -- chapter 10 keeps failing -> parked
S.run(j2)
run_until(function() return not j2.running end)
check("persistent failure parks chapter, others finish", j2.parked[10] and S.count_done(j2) == 9)
local refetched = false
for _, i in ipairs(fetched) do if i <= done_before then refetched = true end end
check("resumed job does not refetch done chapters", not refetched)
check("paused label on shelf", S.shelf_label("B1") ~= nil)
-- failed placeholder text
check("failed placeholder text", S.placeholder_xhtml("x", true):find("下载失败", 1, true) ~= nil)
-- network back: run again -> completes, final file registered, job removed
fail_plan[10] = nil
S.run(j2)
run_until(function() return S.jobs.B1 == nil end)
check("completes and removes job", S.jobs.B1 == nil and S.shelf_label("B1") == nil and Gs.realweidu_stream.B1 == nil)
local last = builds[#builds]
local all = true
for i = 1, 10 do if not last.bodies[tostring(100 + i)]:find("text of " .. i, 1, true) then all = false end end
check("final epub has every chapter, no placeholder", all)

-- rate limit pauses the job
local j3 = { total = 3, done = {}, inflight = {}, parked = {}, retry_at = {}, fails = {}, chapters = chapters,
    book_id = "X", dir = tmp .. "/x", assets = {}, used_names = {}, live = 1, book = {}, D = D }
os.execute("mkdir -p " .. tmp .. "/x/ch")
S.on_result(j3, { i = 1, pid = 1, res = { ok = false, err = "HTTP 429 too many" } })
check("429 pauses whole job", j3.pause_until and j3.pause_until >= T + 30 and #S.plan(j3, 3) == 2)

-- reader on placeholder: swap with goto when the chapter is done
local reloaded, goto_xp
local F = tmp .. "/B4/B4 - full.epub"
local G2 = tmp .. "/B5/B5 - full.epub"
local fake_ui = { document = { file = F, getXPointer = function() return "/body/DocFragment[5]/body" end,
    getCurrentPage = function() return 1 end },
    reloadDocument = function(self, _, _, cb) reloaded = true; cb({ document = { file = F },
        handleEvent = function(_, ev) goto_xp = ev.args and ev.args[1] end }) end }
package.loaded["ui/event"] = { new = function(_, name, a) return { name = name, args = { a } } end }
local j4 = S.new_job(D, { bookId = "B4", title = "B4" }, chapters)
j4.path = F; j4.built = { true, true, true }; j4.done = { true, true, true, nil, true }
S.jobs.B4 = j4
S.on_page(fake_ui)
run_until(function() return reloaded end, 50)
check("done placeholder chapter swaps in and jumps to it", reloaded and goto_xp == "/body/DocFragment[5]")
fake_ui.document.getXPointer = function() return "/body/DocFragment[7]/body" end
j4.built = S.jobs.B4.built
reloaded = false
S.on_page(fake_ui)
check("missing chapter is prioritized while placeholder shown", j4.priority == 7 and j4.waiting == 7 and not reloaded)
-- near end of a chapter whose next one has arrived: reload keeping position (no goto)
S.stop(j4)
local j5 = S.new_job(D, { bookId = "B5", title = "B5" }, chapters)
j5.path = G2; j5.built = { true, true }; j5.done = { true, true, true }; S.jobs.B5 = j5
reloaded, goto_xp = false, nil
local ui5 = { document = { file = G2, getXPointer = function() return "/body/DocFragment[2]/body" end,
    getCurrentPage = function() return 9 end }, view = { state = { page = 9 } },
    toc = { getChapterPagesLeft = function() return 1 end },
    reloadDocument = function(_, _, _, cb) reloaded = true; cb({ document = { file = G2 }, handleEvent = function(_, ev) goto_xp = ev end }) end }
S.on_page(ui5)
run_until(function() return reloaded end, 50)
check("next chapter swap keeps position", reloaded and goto_xp == nil)
os.execute("rm -rf " .. tmp)
print(string.format("%d/%d passed", n - fails, n))
os.exit(fails == 0 and 0 or 1)
