-- Time-to-first-read bench (0.6.1): the real stream engine (worker processes,
-- weread's Client + Content against mock_weread.py, weread's EPUB packager).
-- args: PORT NCH FIRST_READY   (FIRST_READY = NCH emulates 0.6.0: open when all done)
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../realweidu.koplugin/?.lua;./?.lua;./frontend/?.lua;./common/?.lua;" .. package.path
package.cpath = "./common/?.so;./libs/?.so;" .. package.cpath
package.loaded["rweread.lib.logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
require("setupkoenv")
_G.G_reader_settings = require("luasettings"):open("/tmp/wrbench_gs.lua")
require("dbg"):turnOff()
package.loaded["logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
local port, NCH, FR = arg[1], tonumber(arg[2]), tonumber(arg[3])
local ffiutil = require("ffi/util")
local socket = require("socket")
local Client = require("rweread.lib.client")
local Content = require("rweread.lib.content")
local Net = require("realweidu_net"); Net.install(Client)
require("realweidu_decrypt").install(Content)
local http = require("socket.http"); local oreq = http.request
http.request = function(r, ...)
    if type(r) == "table" and Net._inflight_gzip then r.headers = r.headers or {}; r.headers["Accept-Encoding"] = "gzip" end
    return oreq(r, ...)
end
local q = {}
local UI = { scheduleIn = function(_, d, f) q[#q + 1] = { t = socket.gettime() + d, f = f } end,
    nextTick = function(_, f) q[#q + 1] = { t = 0, f = f } end, show = function() end, close = function() end }
package.loaded["ui/uimanager"] = UI
local S = require("realweidu_stream")
local FastDL = require("realweidu_fastdl")
S.deps = { UIManager = UI, now = socket.gettime, Content = Content, proc = FastDL.get_proc() }
S.FIRST_READY = FR
local store = {}
os.execute("rm -rf /tmp/wrstream && mkdir -p /tmp/wrstream")
local settings = { mock_endpoint = "http://127.0.0.1:" .. port, cache_dir = "/tmp/wrstream", download_dir = "/tmp/wrstream",
    get = function(_, k, d) return store[k] or d end, set = function(_, k, v) store[k] = v end, flush = function() end,
    merge_set_cookie = function() end, is_cookie_configured = function() return true end }
local client = Client:new(settings)
local chapters = {}
for c = 1, NCH do chapters[c] = { chapterUid = c, chapterIdx = c, title = "第" .. c .. "章" } end
local book = { book_id = "3300000001", bookId = "3300000001", title = "长安的荔枝" }
local t0 = socket.gettime()
local first, all, path
local D = { settings = settings, client = client, open_file = function(p) first = socket.gettime() - t0; path = p end }
S.on_finished = function() all = socket.gettime() - t0 end
local oor = S.on_result
S.on_result = function(job, j) if os.getenv("DBG") then io.stderr:write(string.format("ch %d %.2fs live=%d\n", j.i, socket.gettime() - j.t0, job.live)) end return oor(job, j) end
S.start(D, book, chapters, {})
while not all do
    table.sort(q, function(a, b) return a.t < b.t end)
    local e = table.remove(q, 1)
    if not e then break end
    local w = e.t - socket.gettime()
    if w > 0 then ffiutil.usleep(math.floor(w * 1e6)) end
    e.f()
end
local f = io.open(path or "", "rb"); local sz = f and f:seek("end") or 0; if f then f:close() end
print(string.format("first_read=%.2fs all_done=%.2fs epub=%dKB", first or -1, all or -1, math.floor(sz / 1024)))
