-- Box bench: weread's final EPUB packaging (Content.save_book_epub) for the bench chapters.
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../realweidu.koplugin/?.lua;./?.lua;./frontend/?.lua;./common/?.lua;" .. package.path
package.cpath = "./common/?.so;./libs/?.so;" .. package.cpath
package.loaded["rweread.lib.logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
require("setupkoenv")
_G.G_reader_settings = require("luasettings"):open("/tmp/wrbench_gs.lua")
require("dbg"):turnOff()
local Content = require("rweread.lib.content")
local socket = require("socket")
local chapters, bodies = {}, {}
for c = 1, 200 do
    local f = io.open(string.format("/tmp/wrout/%04d.xhtml", c), "rb"); if not f then break end
    bodies[tostring(c)] = f:read("*a"); f:close()
    chapters[#chapters + 1] = { chapterUid = c, chapterIdx = c, title = "第" .. c .. "章", level = 1 }
end
local settings = { cache_dir = "/tmp/wrepub", get = function(_, k, d) return d end }
local t0 = socket.gettime()
local ok, path = pcall(Content.save_book_epub, settings, { book_id = "3300000001", title = "长安的荔枝", author = "马伯庸" }, chapters, bodies, "full", {}, "p{}", nil)
print(string.format("epub_package chapters=%d ok=%s %.3fs %s", #chapters, tostring(ok), socket.gettime() - t0, tostring(path)))
