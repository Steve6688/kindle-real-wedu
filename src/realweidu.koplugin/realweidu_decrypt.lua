-- realweidu_decrypt.lua (0.6.0) — byte-identical, fast replacement for weread
-- 1.6.0's chapter-shard decoder (rweread/lib/content.lua decode_content_shards /
-- decode_content_shard), installed at runtime by realweidu_fastdl; no weread file
-- is changed. weread decodes in pure Lua: an MD5 per shard, a per-character table
-- for the swap reversal and a base64 decoder that builds a "0"/"1" string for
-- every bit. On a Kindle that is seconds per chapter. Here: MD5 via libcrypto
-- (or KOReader's sha2 / weread's own as fallbacks), swaps and base64 on a LuaJIT
-- FFI byte buffer. Output is identical (spec/bench_decrypt.lua checks it).
local ffi = require("ffi")
local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local M = {}

local ABC_MD5 = "900150983cd24fb0d6963f7d28e17f72"
local function pick_md5()
    local cands = {}
    cands[#cands + 1] = function()
        pcall(ffi.cdef, "unsigned char *MD5(const unsigned char *d, size_t n, unsigned char *md);")
        local lib
        for _, name in ipairs({ "crypto", "libcrypto.so.57", "libcrypto.so", "libcrypto.so.1.1", "libcrypto.so.1.0.0", "libcrypto.so.3" }) do
            local ok, l = pcall(function()
                if ffi.loadlib and name == "crypto" then return ffi.loadlib("crypto", "57") end
                return ffi.load(name)
            end)
            if ok and l then lib = l; break end
        end
        if not lib then return nil end
        local out = ffi.new("unsigned char[16]")
        return function(s)
            lib.MD5(s, #s, out)
            local t = {}
            for i = 0, 15 do t[i + 1] = string.format("%02x", out[i]) end
            return table.concat(t)
        end
    end
    cands[#cands + 1] = function()
        local sha = require("ffi/sha2")
        return sha.md5
    end
    for idx, mk in ipairs(cands) do
        local ok, f = pcall(mk)
        if ok and type(f) == "function" then
            local ok2, h = pcall(f, "abc")
            if ok2 and type(h) == "string" and h:lower() == ABC_MD5 then M.md5_name = idx == 1 and "libcrypto" or "sha2"; return f end
        end
    end
    local Crypto = package.loaded["rweread.lib.crypto"] or require("rweread.lib.crypto")
    M.md5_name = "weread"
    return Crypto.md5_hex
end
local md5 = pick_md5()
M.md5_hex = md5

local function checked_body(response_text)
    if not response_text or #response_text <= 32 then return "" end
    local expected = response_text:sub(1, 32)
    local body = response_text:sub(33)
    if md5(body):upper() ~= expected then error("Shard MD5 mismatch") end
    return body
end

-- verbatim from weread content.lua (tiny; depends only on the last bytes)
local function swap_positions(encoded)
    local length = #encoded
    if length < 4 then return {} end
    if length < 11 then return {0, 2} end
    local n = math.min(4, math.floor((length + 9) / 10))
    local tmp = {}
    for i = length, length - n + 1, -1 do
        local byte = encoded:byte(i)
        local bin = {}
        repeat
            table.insert(bin, 1, tostring(byte % 2))
            byte = math.floor(byte / 2)
        until byte == 0
        local value = tonumber(table.concat(bin), 4) or 0
        table.insert(tmp, tostring(value))
    end
    tmp = table.concat(tmp)
    local result = {}
    local m = length - n - 2
    local step = #tostring(m)
    local i = 1
    while #result < 10 and i + step - 1 < #tmp do
        table.insert(result, (tonumber(tmp:sub(i, i + step - 1)) or 0) % m)
        local end2 = math.min(i + step, #tmp)
        if i + 1 <= #tmp then
            table.insert(result, (tonumber(tmp:sub(i + 1, end2)) or 0) % m)
        end
        i = i + step
    end
    return result
end

-- base64 value per byte after weread's -_ -> +/ mapping; -1 = dropped (incl. '=')
local VAL = ffi.new("int16_t[256]")
for c = 0, 255 do VAL[c] = -1 end
local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for i = 1, 64 do VAL[abc:byte(i)] = i - 1 end
VAL[("-"):byte()] = 62; VAL[("_"):byte()] = 63

local function decode_encoded_body(body)
    if #body == 0 then return "" end
    local len = #body - 1 -- encoded = body:sub(2)
    if len <= 0 then return "" end
    local encoded = body:sub(2)
    local pos = swap_positions(encoded)
    if #pos % 2 == 1 then error("bad swap table") end -- weread would error too
    local buf = ffi.new("uint8_t[?]", len)
    ffi.copy(buf, encoded, len)
    -- reverse_swaps: chars are 1-based in weread; buf is 0-based
    for i = #pos, 1, -2 do
        for k = 1, 0, -1 do
            local l, r = pos[i] + k, pos[i - 1] + k
            if l < len and r < len then
                buf[l], buf[r] = buf[r], buf[l]
            elseif l ~= r then
                return nil -- out of range: let the caller use weread's code
            end
        end
    end
    local out = ffi.new("uint8_t[?]", math.floor(len * 3 / 4) + 3)
    local o, acc, nb = 0, 0, 0
    for p = 0, len - 1 do
        local v = VAL[buf[p]]
        if v >= 0 then
            acc = bor(lshift(band(acc, 0xFFFF), 6), v); nb = nb + 6
            if nb >= 8 then nb = nb - 8; out[o] = band(rshift(acc, nb), 0xFF); o = o + 1 end
        end
    end
    return ffi.string(out, o)
end

local function weread_content()
    return package.loaded["rweread.lib.content"] or package.loaded["weread.lib.content"]
end

function M.decode_content_shards(e0, e1, e3)
    local body = checked_body(e0) .. checked_body(e1) .. checked_body(e3)
    local r = decode_encoded_body(body)
    if r == nil then
        local C = weread_content(); return C._wrs_orig_decode(e0, e1, e3)
    end
    return r
end

function M.decode_content_shard(e0)
    local r = decode_encoded_body(checked_body(e0))
    if r == nil then
        local C = weread_content(); return C._wrs_orig_decode1(e0)
    end
    return r
end

-- Install into weread's Content table (idempotent). Returns true when patched.
function M.install(Content)
    if type(Content) ~= "table" or Content._wrs_fast_decode then return false end
    if type(Content.decode_content_shards) ~= "function" or type(Content.decode_content_shard) ~= "function" then return false end
    Content._wrs_orig_decode = Content.decode_content_shards
    Content._wrs_orig_decode1 = Content.decode_content_shard
    Content.decode_content_shards = M.decode_content_shards
    Content.decode_content_shard = M.decode_content_shard
    Content._wrs_fast_decode = true
    return true
end

return M
