-- Builds a synthetic WeRead book for the network bench: valid e_0/e_1/e_3 shards
-- (weread's own MD5 + swap + base64 scheme, verified by weread's decoder), a
-- reader page with __INITIAL_STATE__, chapterInfos and css. Out: $1 (dir).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../realweidu.koplugin/?.lua;./?.lua;./frontend/?.lua;./common/?.lua;" .. package.path
package.cpath = "./common/?.so;./libs/?.so;" .. package.cpath
package.loaded["rweread.lib.logger"] = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
local Content = require("rweread.lib.content")
local Crypto = require("rweread.lib.crypto")
local out, NCH, KB = arg[1], tonumber(arg[2] or 40), tonumber(arg[3] or 40)
os.execute("mkdir -p " .. out)
local b64c = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(s)
    return ((s:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return b64c:sub(c + 1, c + 1)
    end))
end
-- swap_positions from weread (copied in realweidu_decrypt; reuse via a probe)
local src = io.open(here .. "/../../realweidu.koplugin/realweidu_decrypt.lua"):read("*a")
local sp = src:match("(local function swap_positions.-\nend\n)")
local swap_positions = loadstring(sp .. "\nreturn swap_positions")()
local function encode(xhtml)
    local B = b64(xhtml):gsub("%+", "-"):gsub("/", "_")
    local pos = swap_positions(B)
    local ch = {}
    for i = 1, #B do ch[i] = B:sub(i, i) end
    for i = 2, #pos, 2 do
        for k = 0, 1 do
            local l, r = pos[i] + k + 1, pos[i - 1] + k + 1
            ch[l], ch[r] = ch[r], ch[l]
        end
    end
    local body = "x" .. table.concat(ch)
    local a, b = math.floor(#body / 3), math.floor(#body * 2 / 3)
    local parts = { body:sub(1, a), body:sub(a + 1, b), body:sub(b + 1) }
    for i = 1, 3 do parts[i] = Crypto.md5_hex(parts[i]):upper() .. parts[i] end
    return parts
end
local para = "李善德伸手接过，只觉得两撇胡须抖了一抖。长安城的荔枝，从岭南送来要五千里路，一骑红尘妃子笑，无人知是荔枝来。"
local infos = {}
math.randomseed(3)
for c = 1, NCH do
    local t = { '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>第', c, '章</title></head><body><h2>第', c, '章</h2>' }
    local n = 0
    while n < KB * 1024 do
        -- prose-like entropy: random common CJK (~2500 chars) + punctuation, so gzip
        -- ratios are realistic (repeating one sentence would compress 20x)
        local w = {}
        for j = 1, math.random(40, 160) do
            local cp = 0x4E00 + math.floor(math.random() ^ 2 * 2500)
            if math.random() < 0.08 then cp = 0xFF0C end
            w[j] = string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
        end
        local p = "<p>" .. table.concat(w) .. "。</p>"
        t[#t + 1] = p; n = n + #p
    end
    t[#t + 1] = "</body></html>"
    local x = table.concat(t)
    local parts = encode(x)
    assert(Content.decode_content_shards(parts[1], parts[2], parts[3]) == x, "fixture roundtrip")
    for i, e in ipairs({ "e_0", "e_1", "e_3" }) do
        local f = io.open(string.format("%s/%d.%s", out, c, e), "wb"); f:write(parts[i]); f:close()
    end
    infos[#infos + 1] = string.format('{"chapterUid":%d,"chapterIdx":%d,"title":"第%d章 长安的荔枝","wordCount":%d,"level":1,"updateTime":1700000000,"price":0,"paid":1,"isMPChapter":0,"files":[],"anchors":[]}', c, c, c, KB * 300)
end
local WeRead = require("rweread.lib.protocol")
local map = {}
for c = 1, NCH do map[#map + 1] = string.format('"%s":%d', WeRead.e(c), c) end
local mf = io.open(out .. "/cmap.json", "wb"); mf:write("{" .. table.concat(map, ",") .. "}"); mf:close()
local list = '{"data":[{"bookId":"3300000001","updated":[' .. table.concat(infos, ",") .. ']}]}'
local f = io.open(out .. "/chapterInfos.json", "wb"); f:write(list); f:close()
-- reader page: real pages carry the whole catalog + book info + many inline scripts
local pad = {}
for i = 1, 600 do pad[#pad + 1] = string.format('<link rel="preload" href="https://cdn.weread.qq.com/web/wrwebnjlogic/js/chunk.%08x.js" as="script">', i * 2654435761 % 4294967296) end
local state = '{"reader":{"bookInfo":{"bookId":"3300000001","title":"长安的荔枝","author":"马伯庸","intro":"' .. string.rep(para, 4) .. '"},"psvts":"psv_abcdef0123456789","pclts":"pcl_1700000000","token":"tok_0123456789abcdef","currentChapter":{"chapterUid":1},"progress":{"book":{"chapterUid":1}},"chapterInfos":[' .. table.concat(infos, ",") .. ']}}'
local html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>长安的荔枝 - 微信读书</title>' .. table.concat(pad) ..
    '</head><body><div id="app"></div><script>window.__INITIAL_STATE__=' .. state .. ';(function(){var s;})();</script>' ..
    string.rep('<script src="https://cdn.weread.qq.com/web/wrwebnjlogic/js/app.0123456789abcdef.js"></script>', 40) .. '</body></html>'
f = io.open(out .. "/reader.html", "wb"); f:write(html); f:close()
f = io.open(out .. "/e_2", "wb"); local css = "p{text-indent:2em;line-height:1.6;margin:0}h2{font-size:1.4em}"; f:write(Crypto.md5_hex("x" .. css):upper() .. "x" .. css); f:close()
print(string.format("fixtures: %d chapters x ~%d KB xhtml, reader page %d KB -> %s", NCH, KB, math.floor(#html / 1024), out))
