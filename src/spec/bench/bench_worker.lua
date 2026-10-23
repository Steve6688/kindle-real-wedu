-- One download worker against mock_weread.py through weread's own Client (mock_endpoint)
-- and Content.fetch_chapter_xhtml (reader page + e_0/e_1/e_3 + decrypt), then the
-- chapter checkpoint write. args: PORT MODE(old|new) K W NCH OUTDIR
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../realweidu.koplugin/?.lua;./?.lua;./frontend/?.lua;./common/?.lua;" .. package.path
package.cpath = "./common/?.so;./libs/?.so;" .. package.cpath
package.loaded["rweread.lib.logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
require("setupkoenv")
_G.G_reader_settings = require("luasettings"):open("/tmp/wrbench_gs.lua")
require("dbg"):turnOff()
local port, mode, K, W, NCH, OUT = arg[1], arg[2], tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5]), arg[6]
local Client = require("rweread.lib.client")
local Content = require("rweread.lib.content")
local Net = require("realweidu_net")
local Decrypt = require("realweidu_decrypt")
Net.install(Client)
if mode == "new" then Decrypt.install(Content) else Net.enabled = false end
Net.time(Content, "decode_content_shards", "decrypt")
Net.time(Content, "extract_reader_state", "parse_reader_state")
-- bench-only shim: weread's mock mode keeps only 4 headers; put Accept-Encoding back
local http = require("socket.http")
local oreq = http.request
http.request = function(r, ...)
    if type(r) == "table" and Net._inflight_gzip then r.headers = r.headers or {}; r.headers["Accept-Encoding"] = "gzip" end
    return oreq(r, ...)
end
local store = {}
local settings = { mock_endpoint = "http://127.0.0.1:" .. port,
    get = function(_, k, d) return store[k] or d end, set = function(_, k, v) store[k] = v end,
    merge_set_cookie = function() end, is_cookie_configured = function() return true end }
local client = Client:new(settings)
local book = { book_id = "3300000001", bookId = "3300000001", title = "长安的荔枝" }
os.execute("mkdir -p " .. OUT)
for c = 1, NCH do
    if (c - 1) % W == K then
        local x = Content.fetch_chapter_xhtml(client, settings, book, { chapterUid = c, chapterIdx = c, title = "第" .. c .. "章" })
        local t0 = Net.now()
        local f = assert(io.open(string.format("%s/%04d.xhtml", OUT, c), "wb")); f:write(x); f:close()
        Net.add("disk_chapter", Net.now() - t0, #x)
    end
end
local t = {}
for k, v in pairs(Net.perf) do t[#t + 1] = string.format('"%s":{"n":%d,"s":%.4f,"bytes":%d,"wire":%d}', k, v.n, v.s, v.bytes, v.wire) end
print("{" .. table.concat(t, ",") .. "}")
