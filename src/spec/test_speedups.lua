-- 0.6.0 offline tests: fast decrypt == weread decrypt, gzip transfer, phase timings.
-- Run: luajit spec/test_speedups.lua (KOReader's luajit or any LuaJIT with libz)
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
package.loaded["rweread.lib.logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
local Crypto = require("rweread.lib.crypto")
-- weread's decoder, loaded from its own file without KOReader deps
for _, m in ipairs({ "rweread.lib.reader_state", "rweread.lib.protocol" }) do package.loaded[m] = package.loaded[m] or {} end
local Content = require("rweread.lib.content")
local D = require("realweidu_decrypt")
local Net = require("realweidu_net")
check("md5 backend picked and correct", D.md5_hex("abc") == "900150983cd24fb0d6963f7d28e17f72" and D.md5_name ~= nil)
math.randomseed(11)
local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_+/="
local function shard(len)
    local t = {}
    for i = 1, len do local k = math.random(1, #b64); t[i] = b64:sub(k, k) end
    local body = "x" .. table.concat(t)
    return Crypto.md5_hex(body):upper() .. body
end
local orig3, orig1 = Content.decode_content_shards, Content.decode_content_shard
local same, cases = true, 0
for _, len in ipairs({ 0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 33, 100, 1000, 4099, 30000 }) do
    for _ = 1, 3 do
        local a, b, c = shard(len), shard(len + 1), shard(len + 7)
        local ok1, r1 = pcall(orig3, a, b, c); local ok2, r2 = pcall(D.decode_content_shards, a, b, c)
        local ok3, r3 = pcall(orig1, a); local ok4, r4 = pcall(D.decode_content_shard, a)
        cases = cases + 1
        if ok1 ~= ok2 or r1 ~= r2 or ok3 ~= ok4 or r3 ~= r4 then same = false; print("  mismatch at", len) end
    end
end
check("fast decrypt byte-identical to weread (" .. cases .. " random shard sets, incl. '=' and tiny)", same)
for _, s in ipairs({ "", "short", string.rep("A", 32), string.rep("A", 33) }) do
    local ok1, r1 = pcall(orig3, s, s, s); local ok2, r2 = pcall(D.decode_content_shards, s, s, s)
    if ok1 ~= ok2 or (ok1 and r1 ~= r2) then same = false end
end
check("edge inputs behave like weread (empty / <=32 bytes / bad md5 error)", same)
local bad = shard(64); bad = (bad:sub(1, 1) == "0" and "1" or "0") .. bad:sub(2)
check("bad MD5 still rejected", not pcall(D.decode_content_shards, bad, shard(3), shard(3)))
check("install swaps in fast decoder, keeps originals", D.install(Content) and Content.decode_content_shards == D.decode_content_shards
    and Content._wrs_orig_decode == orig3 and not D.install(Content))

-- gzip ------------------------------------------------------------------------
local gz = "\31\139\8\0\0\0\0\0\0\255\123\186\111\221\147\253\11\95\172\223\253\100\231\50\133\140\212\156\156\124\133\244\170\204\2\133\167\163\226\163\226\163\226\163\226\131\76\28\0\130\144\33\20\176\4\0\0"
local want = string.rep("微信读书 hello gzip ", 50)
check("zlib available via FFI", Net.gzip_available())
check("inflate gzip body", Net.inflate(gz) == want)
check("truncated gzip -> nil (caller re-requests)", Net.inflate(gz:sub(1, 30)) == nil and Net.inflate("not gzip") == nil)
local calls = {}
local mode = "gzip"
local Client = { request = function(self, o)
    calls[#calls + 1] = { url = o.url, ae = o.headers and o.headers["Accept-Encoding"], sink = o.sink, hdr = o.headers }
    if mode == "gzip" and o.headers and o.headers["Accept-Encoding"] then return gz, 200, { ["content-encoding"] = "gzip" }, "200" end
    if mode == "broken" and o.headers and o.headers["Accept-Encoding"] then return "garbage", 200, { ["Content-Encoding"] = "gzip" }, "200" end
    return want, 200, {}, "200"
end }
check("Client patched once", Net.install(Client) and not Net.install(Client))
Net.reset()
local body, code = Client:request({ url = "https://weread.qq.com/web/book/chapter/e_0", method = "POST", headers = { Referer = "r" } })
check("weread text request asks for gzip, body inflated", body == want and code == 200 and calls[1].ae == "gzip" and calls[1].hdr.Referer == "r")
calls = {}; mode = "broken"
body = Client:request({ url = "https://weread.qq.com/web/reader/abc" })
check("un-inflatable body -> request repeated exactly as weread made it", body == want and #calls == 2 and calls[2].ae == nil)
calls = {}; mode = "gzip"
Client:request({ url = "https://weread.qq.com/x.jpg", sink = function() end })
Client:request({ url = "https://res.weread.qq.com.evil.com/a" })
Client:request({ url = "https://cdn.example.com/a" })
check("file sinks and non-weread hosts untouched", calls[1].ae == nil and calls[2].ae == nil and calls[3].ae == nil)
local opts = { url = "https://weread.qq.com/web/book/chapterInfos", headers = {} }
Client:request(opts)
check("caller's opts/headers not mutated", opts.headers["Accept-Encoding"] == nil)
Net.enabled = false; calls = {}
Client:request({ url = "https://weread.qq.com/web/book/chapter/e_1" })
check("disabled -> identical to weread", calls[1].ae == nil); Net.enabled = true
check("phase classes", Net.classify("https://weread.qq.com/web/reader/x") == "net_reader_page"
    and Net.classify("https://weread.qq.com/web/book/chapter/e_3") == "net_shard"
    and Net.classify("https://weread.qq.com/web/book/chapter/e_2") == "net_css"
    and Net.classify("https://weread.qq.com/web/book/chapterInfos") == "net_chapter_list")
local p = Net.perf
check("timings recorded with plain + wire bytes", p.net_shard and p.net_shard.n >= 1 and p.net_shard.bytes > p.net_shard.wire
    and p.net_reader_page and p.net_reader_page.n == 1)
local agg = Net.merge({}, { a = { n = 1, s = 0.5, bytes = 10, wire = 5 } }); Net.merge(agg, { a = { n = 2, s = 1, bytes = 1, wire = 1 } })
check("worker perf merges", agg.a.n == 3 and agg.a.s == 1.5 and agg.a.bytes == 11)
check("summary text", Net.summary(agg):find("a n=3 1.50s", 1, true) ~= nil)
local T = { f = function(x) return x * 2, "y" end, g = function() error("boom") end }
Net.time(T, "f", "ph"); Net.time(T, "g", "ph")
local r1, r2 = T.f(21)
check("timer wrapper keeps results and errors", r1 == 42 and r2 == "y" and not pcall(T.g) and Net.perf.ph.n == 2)
local fsrc = io.open(here .. "/../realweidu.koplugin/realweidu_fastdl.lua"):read("*a")
check("fastdl installs decrypt + gzip + timers and logs one summary per job", fsrc:find("decrypt = Decrypt.install(Content)", 1, true)
    and fsrc:find("Net.install(L[\"rweread.lib.client\"]", 1, true) and fsrc:find('"realweidu download_perf"', 1, true)
    and fsrc:find("perf = Net.reset()", 1, true) and fsrc:find("Net.merge(Net.perf, r.perf)", 1, true))
print(string.format("\n%d checks, %d failed", n, fails)); os.exit(fails == 0 and 0 or 1)
