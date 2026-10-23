-- realweidu_net.lua (0.6.0) — gzip transfer + per-phase timing for weread 1.6.0's
-- HTTP client (rweread/lib/client.lua Client:request), applied at runtime; no
-- weread file is changed. weread asks for identity encoding, so every reader page
-- (a full HTML page with the whole __INITIAL_STATE__, fetched once per chapter),
-- the catalog and the text shards cross the Kindle's Wi-Fi uncompressed.
-- Here weread.qq.com text requests (no file sink) send "Accept-Encoding: gzip"
-- and gzip/deflate bodies are inflated with zlib through the LuaJIT FFI. If the
-- body cannot be inflated the request is repeated exactly as weread made it.
local ffi = require("ffi")

local M = { enabled = true, perf = {} }

-- zlib inflate (gzip + zlib wrappers via windowBits 15+32) --------------------
local zlib, Z_OK, Z_STREAM_END, Z_BUF_ERROR = nil, 0, 1, -5
local function zinit()
    if zlib ~= nil then return zlib end
    zlib = false
    local ok = pcall(function()
        pcall(require, "ffi/zlib_h") -- defines Bytef/uInt/uLong when present
        pcall(ffi.cdef, "typedef unsigned char Byte; typedef Byte Bytef; typedef unsigned long uLong; typedef unsigned uInt;")
        pcall(ffi.cdef, [[
typedef struct rw_z_stream_s {
    const Bytef *next_in; uInt avail_in; uLong total_in;
    Bytef *next_out; uInt avail_out; uLong total_out;
    const char *msg; void *state; void *zalloc; void *zfree; void *opaque;
    int data_type; uLong adler; uLong reserved;
} rw_z_stream;
int inflateInit2_(rw_z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(rw_z_stream *strm, int flush);
int inflateEnd(rw_z_stream *strm);
const char *zlibVersion(void);
]])
        local lib
        if ffi.loadlib then pcall(function() lib = ffi.loadlib("z", 1) end) end
        for _, name in ipairs({ "z", "libz.so.1", "libz.so" }) do
            if lib then break end
            pcall(function() lib = ffi.load(name) end)
        end
        local _ = lib.inflate -- resolves the symbol or errors
        zlib = lib
    end)
    if not ok then zlib = false end
    return zlib
end

function M.inflate(data)
    local z = zinit()
    if not z then return nil, "no zlib" end
    local strm = ffi.new("rw_z_stream")
    if z.inflateInit2_(strm, 15 + 32, z.zlibVersion(), ffi.sizeof("rw_z_stream")) ~= Z_OK then return nil, "init" end
    local inbuf = ffi.new("uint8_t[?]", #data)
    ffi.copy(inbuf, data, #data)
    strm.next_in = inbuf; strm.avail_in = #data
    local CH = 256 * 1024
    local out = ffi.new("uint8_t[?]", CH)
    local parts, res = {}, nil
    repeat
        strm.next_out = out; strm.avail_out = CH
        res = z.inflate(strm, 0)
        if res ~= Z_OK and res ~= Z_STREAM_END and not (res == Z_BUF_ERROR and strm.avail_in == 0) then
            z.inflateEnd(strm); return nil, "inflate " .. tostring(res)
        end
        parts[#parts + 1] = ffi.string(out, CH - strm.avail_out)
    until res == Z_STREAM_END or (strm.avail_in == 0 and strm.avail_out ~= 0)
    z.inflateEnd(strm)
    if res ~= Z_STREAM_END then return nil, "truncated" end
    return table.concat(parts)
end

function M.gzip_available() return zinit() and true or false end

-- per-phase timing ---------------------------------------------------------------
local function now()
    local ok, t = pcall(require, "ui/time")
    if ok and t and t.now and t.to_s then return t.to_s(t.now()) end
    local oks, socket = pcall(require, "socket")
    if oks and socket and socket.gettime then return socket.gettime() end
    return os.time()
end
M.now = now

function M.add(phase, secs, bytes, wire)
    local p = M.perf[phase]
    if not p then p = { n = 0, s = 0, bytes = 0, wire = 0 }; M.perf[phase] = p end
    p.n = p.n + 1; p.s = p.s + (secs or 0); p.bytes = p.bytes + (bytes or 0); p.wire = p.wire + (wire or bytes or 0)
end

function M.reset() local old = M.perf; M.perf = {}; return old end

function M.merge(into, from)
    for k, v in pairs(from or {}) do
        local p = into[k]
        if not p then p = { n = 0, s = 0, bytes = 0, wire = 0 }; into[k] = p end
        p.n = p.n + (v.n or 0); p.s = p.s + (v.s or 0); p.bytes = p.bytes + (v.bytes or 0); p.wire = p.wire + (v.wire or 0)
    end
    return into
end

function M.summary(perf)
    local keys = {}
    for k in pairs(perf or M.perf) do keys[#keys + 1] = k end
    table.sort(keys)
    local t = {}
    for _, k in ipairs(keys) do
        local p = (perf or M.perf)[k]
        t[#t + 1] = string.format("%s n=%d %.2fs avg=%.0fms %dKB wire=%dKB", k, p.n, p.s, p.n > 0 and p.s / p.n * 1000 or 0,
            math.floor(p.bytes / 1024), math.floor(p.wire / 1024))
    end
    return table.concat(t, " | ")
end

function M.classify(url)
    url = tostring(url or "")
    if url:find("/web/book/chapter/e_2", 1, true) then return "net_css" end
    if url:find("/web/book/chapter/e_", 1, true) then return "net_shard" end
    if url:find("chapterInfos", 1, true) then return "net_chapter_list" end
    if url:find("/web/reader/", 1, true) then return "net_reader_page" end
    return "net_other"
end

local function header(h, name)
    if type(h) ~= "table" then return nil end
    for k, v in pairs(h) do if type(k) == "string" and k:lower() == name then return v end end
end

-- Install into weread's Client class (idempotent).
function M.install(Client)
    if type(Client) ~= "table" or type(Client.request) ~= "function" or Client._wrs_net then return false end
    Client._wrs_net = true
    local orig = Client.request
    Client._wrs_orig_request = orig
    Client.request = function(self, opts)
        opts = opts or {}
        local phase = M.classify(opts.url)
        local t0 = now()
        local want = M.enabled and not opts.sink and type(opts.url) == "string"
            and opts.url:match("^https?://[%w%.]*weread%.qq%.com/") ~= nil and zinit()
        if want then
            local o2 = {}
            for k, v in pairs(opts) do o2[k] = v end
            local h = {}
            for k, v in pairs(opts.headers or {}) do h[k] = v end
            h["Accept-Encoding"] = "gzip"
            o2.headers = h
            M._inflight_gzip = true -- read by the offline bench only (mock mode strips headers)
            local okr, body, code, rh, status = pcall(orig, self, o2)
            M._inflight_gzip = nil
            if not okr then error(body, 0) end
            local enc = tostring(header(rh, "content-encoding") or ""):lower()
            if type(body) == "string" and (enc == "gzip" or enc == "deflate") then
                local plain = M.inflate(body)
                if plain then
                    M.add(phase, now() - t0, #plain, #body)
                    return plain, code, rh, status
                end
                -- could not inflate: repeat exactly as weread would
            else
                M.add(phase, now() - t0, type(body) == "string" and #body or 0)
                return body, code, rh, status
            end
        end
        local body, code, rh, status = orig(self, opts)
        M.add(phase, now() - t0, type(body) == "string" and #body or 0)
        return body, code, rh, status
    end
    return true
end

-- Wrap a function on a table with a timer (phase name).
function M.time(tbl, name, phase)
    local f = tbl and tbl[name]
    if type(f) ~= "function" or tbl["_wrs_timed_" .. name] then return false end
    tbl["_wrs_timed_" .. name] = f
    tbl[name] = function(...)
        local t0 = now()
        local r = { pcall(f, ...) }
        M.add(phase, now() - t0)
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2, table.maxn(r))
    end
    return true
end

return M
