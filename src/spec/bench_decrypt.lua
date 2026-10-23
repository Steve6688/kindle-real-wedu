-- Box benchmark: chapter decrypt (MD5 check + swap reversal + base64) old vs fast.
-- Run from a KOReader tree: cd /tmp/kor/lib/koreader && ./luajit <repo>/src/spec/bench_decrypt.lua
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;./?.lua;./frontend/?.lua;./common/?.lua;" .. package.path
package.cpath = "./common/?.so;./libs/?.so;" .. package.cpath
package.loaded["rweread.lib.logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
local Content = require("rweread.lib.content")
local Crypto = require("rweread.lib.crypto")
local F = require("realweidu_decrypt")
local function clock() return os.clock() end
math.randomseed(7)
local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function shard(n)
    local t = {}
    for i = 1, n do local k = math.random(1, 64); t[i] = b64:sub(k, k) end
    local body = "x" .. table.concat(t)
    return Crypto.md5_hex(body):upper() .. body
end
local orig = Content.decode_content_shards
local fails = 0
for _, kb in ipairs({ 1, 20, 60, 200 }) do
    local n = kb * 1024 * 4 / 3 / 3
    local e0, e1, e3 = shard(math.floor(n)), shard(math.floor(n) + 1), shard(math.floor(n) + 2)
    local t0 = clock(); local a = orig(e0, e1, e3); local t1 = clock()
    local b = F.decode_content_shards(e0, e1, e3); local t2 = clock()
    local m0 = clock(); Crypto.md5_hex(e1:sub(33)); local m1 = clock()
    local same = a == b
    if not same then fails = fails + 1 end
    print(string.format("decrypt %4d KB chapter: weread %8.1f ms | fast %6.1f ms | x%.0f | weread md5 share %5.1f ms | identical=%s",
        kb, (t1 - t0) * 1000, (t2 - t1) * 1000, (t1 - t0) / math.max(t2 - t1, 1e-6), (m1 - m0) * 3000, tostring(same)))
end
-- edge cases: tiny / empty / bad md5 must behave like weread
for _, s in ipairs({ "", "short", shard(1), shard(2), shard(3), shard(8), shard(10), shard(11) }) do
    local ok1, r1 = pcall(orig, s, s, s); local ok2, r2 = pcall(F.decode_content_shards, s, s, s)
    if ok1 ~= ok2 or (ok1 and r1 ~= r2) then fails = fails + 1; print("MISMATCH len", #s) end
    local ok3, r3 = pcall(Content.decode_content_shard, s); local ok4, r4 = pcall(F.decode_content_shard, s)
    if ok3 ~= ok4 or (ok3 and r3 ~= r4) then fails = fails + 1; print("MISMATCH single len", #s) end
end
local bad = shard(50); bad = "0" .. bad:sub(2)
local okb = pcall(F.decode_content_shards, bad, bad, bad)
if okb then fails = fails + 1; print("bad md5 not rejected") end
print(fails == 0 and "bench ok (fast == weread on all inputs)" or ("FAILED " .. fails)); os.exit(fails == 0 and 0 or 1)
