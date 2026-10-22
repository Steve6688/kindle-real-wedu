-- Unit tests for realweidu_logic.lua (reader menu / font panel / pages helpers).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../realweidu.koplugin/?.lua;" .. package.path
local L = require("realweidu_logic")
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end
local S = {}; for _, s in ipairs(L.SLIDERS) do S[s.id] = s end

check("4 sliders in UI-SPEC order", #L.SLIDERS == 4 and L.SLIDERS[1].label == "字号" and L.SLIDERS[2].label == "字重"
    and L.SLIDERS[3].label == "行距" and L.SLIDERS[4].label == "边距")
check("events are KOReader's", S.size.event == "SetFontSize" and S.weight.event == "SetFontBaseWeight"
    and S.line.event == "SetLineSpace" and S.margin.event == "SetPageHorizMargins")
check("size steps within ReaderFont clamp 12..255", S.size.steps[1] >= 12 and S.size.steps[#S.size.steps] <= 255)
check("line steps within clamp 50..200", S.line.steps[1] >= 50 and S.line.steps[#S.line.steps] <= 200)
check("nearest exact", L.nearest_index(S.size.steps, 22) == 4)
check("nearest between -> closer", L.nearest_index(S.size.steps, 23) == 4 and L.nearest_index(S.size.steps, 35) == 10)
check("nearest nil -> 1", L.nearest_index(S.size.steps, nil) == 1)
check("nearest weight 0", L.nearest_index(S.weight.steps, 0) == 3)
check("clamp", L.clamp_index(S.size.steps, 0) == 1 and L.clamp_index(S.size.steps, 99) == #S.size.steps)
check("index_from_x start", L.index_from_x(S.size.steps, 0, 1000) == 1)
check("index_from_x end", L.index_from_x(S.size.steps, 999, 1000) == 10)
check("index_from_x mid", L.index_from_x(S.size.steps, 450, 1000) == 5)
check("index_from_x beyond", L.index_from_x(S.size.steps, 5000, 1000) == 10 and L.index_from_x(S.size.steps, -5, 1000) == 1)
check("knob first/last", L.knob_x(S.size.steps, 1, 800, 70) == 35 and L.knob_x(S.size.steps, 10, 800, 70) == 765)
check("knob monotonic", L.knob_x(S.size.steps, 3, 800, 70) < L.knob_x(S.size.steps, 4, 800, 70))
for _, slider in ipairs(L.SLIDERS) do
    for _, width in ipairs({ 240, 480, 800 }) do
        for i = 1, #slider.steps do
            local x = L.knob_x(slider.steps, i, width, 70)
            check("tap visible stop " .. slider.id .. "/" .. width .. "/" .. i,
                L.index_from_x(slider.steps, x, width, 70) == i)
        end
    end
end
check("label size shows value", L.step_label(S.size, 4) == "22")
check("label weight shows name", L.step_label(S.weight, 4) == "+½")
check("label line shows name", L.step_label(S.line, 2) == "行距")
local v = L.read_values({ font_size = 26, font_base_weight = 0.5, line_spacing = 110, h_page_margins = { 15, 15 } })
check("read_values", v.size == 26 and v.weight == 0.5 and v.line == 110 and v.margin == 15)
check("read_values empty", L.read_values(nil).weight == 0)
check("margin event arg {l,r}", L.event_arg(S.margin, 20)[1] == 20 and L.event_arg(S.margin, 20)[2] == 20)
check("size event arg scalar", L.event_arg(S.size, 20) == 20)

local faces = { "Noto Sans", "Noto Serif", "Noto Sans CJK SC", "思源宋体", "FreeSans", "霞鹜文楷", "LXGW WenKai", "DroidSansMono" }
local f = L.pick_fonts(faces, 15)
check("fonts: only installed CJK-capable", #f == 4)
check("fonts: preferred order (思源宋体 first)", f[1] == "思源宋体")
check("fonts: no latin-only", (function() for _, x in ipairs(f) do if x == "FreeSans" or x == "Noto Sans" then return false end end return true end)())
local many = {}; for i = 1, 30 do many[i] = "楷体" .. i end
check("fonts: max 15", #L.pick_fonts(many, 15) == 15)
check("fonts: empty", #L.pick_fonts(nil) == 0)
check("font_label strips Regular", L.font_label("Foo Regular") == "Foo")

local books = { { title = "a", last_read = 9 }, { title = "b", last_read = 5 }, { title = "c", last_read = 0 },
    { title = "d", last_read = 3, finished = true }, { title = "e", last_read = 2, finished = true } }
local r = L.recent(books, 4)
check("recent skips unread, max 4", #r == 4 and r[1].title == "a" and r[3].title == "d")
check("recent n", #L.recent(books, 2) == 2)
check("finished count", L.count_finished(books) == 2)
check("minutes", L.minutes(3630) == 61 and L.minutes(nil) == nil and L.minutes(0) == 0)
check("notes from summary", L.notes_from_summary({ readStat = { { stat = "读过", counts = "3本" }, { stat = "笔记", counts = "12条" } } }) == 12)
check("notes absent -> nil", L.notes_from_summary({ readStat = { { stat = "读过", counts = "3本" } } }) == nil and L.notes_from_summary(nil) == nil)
check("fmt nil -> —", L.fmt_num(nil) == "—" and L.fmt_num(0) == "0")
check("initial utf8", L.initial("小明") == "小" and L.initial("Bob") == "B" and L.initial("") == "我" and L.initial(nil) == "我")
check("reader title chapter", L.reader_title("第一章\n 开始", "书") == "第一章 开始")
check("reader title fallback book", L.reader_title(nil, "平凡的世界") == "平凡的世界" and L.reader_title("", "x") == "x")
local x1, w1 = L.slot(1236, 5, 1); local x5 = L.slot(1236, 5, 5)
check("5 equal slots, each >= 120 wide", x1 == 0 and w1 == 247 and x5 == 988 and w1 >= 120)

-- BUG-01: current face always listed + selected; readable labels
do
    local faces = { "Noto Serif", "Noto Sans CJK SC", "FreeSans" }
    local l, i = L.font_list(faces, "Noto Serif")
    check("BUG-01 latin current face listed first + selected", l[1] == "Noto Serif" and i == 1 and l[2] == "Noto Sans CJK SC")
    local l2, i2 = L.font_list(faces, "Noto Sans CJK SC")
    check("BUG-01 CJK current face selected in place", #l2 == 1 and i2 == 1)
    local _, i3 = L.font_list(faces, nil)
    check("BUG-01 unknown current -> none selected", i3 == nil)
    local many = {}; for k = 1, 20 do many[k] = "Font CJK " .. k end
    local l4, i4 = L.font_list(many, "Latin X", 15)
    check("BUG-01 cap kept at 15 incl. current", #l4 == 15 and l4[1] == "Latin X" and i4 == 1)
    check("BUG-01 label Noto Sans CJK SC -> 思源黑体 SC", L.font_label("Noto Sans CJK SC") == "思源黑体 SC")
    check("BUG-01 label Noto Serif CJK SC -> 思源宋体 SC", L.font_label("Noto Serif CJK SC") == "思源宋体 SC")
    -- NEW-02: regions stay distinct; unknown names keep their suffixes
    local labels, dup = {}, false
    for _, r in ipairs({ "SC", "TC", "HK", "JP", "KR" }) do
        local lb = L.font_label("Noto Sans CJK " .. r)
        if labels[lb] then dup = true end; labels[lb] = true
    end
    check("NEW-02 Noto Sans CJK SC/TC/HK/JP/KR -> 5 distinct labels", not dup and labels["思源黑体 TC"] and labels["思源黑体 KR"])
    check("NEW-02 Source Han Sans K -> 思源黑体 K", L.font_label("Source Han Sans K") == "思源黑体 K")
    check("NEW-02 Noto Sans CJK (no region) -> 思源黑体", L.font_label("Noto Sans CJK") == "思源黑体")
    check("NEW-02 'Something KR' keeps suffix", L.font_label("Something KR") == "Something KR")
    check("NEW-02 'Foo SC Regular' -> 'Foo SC'", L.font_label("Foo SC Regular") == "Foo SC")
    check("NEW-02 Noto Sans CJK SCX -> 思源黑体 SCX (new rule)", L.font_label("Noto Sans CJK SCX") == "思源黑体 SCX")
    check("NEW-04 SC Bold keeps weight", L.font_label("Noto Sans CJK SC Bold") == "思源黑体 SC Bold")
    check("NEW-04 SC vs SC Bold distinct", L.font_label("Noto Sans CJK SC") ~= L.font_label("Noto Sans CJK SC Bold"))
    check("NEW-04 SC Regular -> 思源黑体 SC", L.font_label("Noto Sans CJK SC Regular") == "思源黑体 SC")
    check("NEW-04 Serif TC Medium", L.font_label("Noto Serif CJK TC Medium") == "思源宋体 TC Medium")
    check("NEW-04 Source Han Sans SC-Bold", L.font_label("Source Han Sans SC-Bold") == "思源黑体 SC Bold")
    check("BUG-01 label strips Regular", L.font_label("FZ Font-Regular") == "FZ Font")
end
-- BUG-08: indent switch says it forces the indent
check("BUG-08 indent label off", L.indent_label(false) == "强制首行缩进")
check("BUG-08 indent label on", L.indent_label(true) == "✓ 强制首行缩进")
-- BUG-05: rows are paged, never dropped
do
    local f, l, p, n = L.page_rows(5, 5, 0)
    check("BUG-05 all fit -> one page", f == 1 and l == 5 and not p and not n)
    f, l, p, n = L.page_rows(5, 3, 0)
    check("BUG-05 3 slots: rows 1-2 + nav(下一页)", f == 1 and l == 2 and not p and n)
    local o = L.next_offset(5, 3, 0)
    f, l, p, n = L.page_rows(5, 3, o)
    check("BUG-05 page 2: rows 3-4 + nav(上/下)", f == 3 and l == 4 and p and n)
    f, l, p, n = L.page_rows(5, 3, L.next_offset(5, 3, o))
    check("BUG-05 last page: row 5 (退出) + nav(上一页)", f == 5 and l == 5 and p and not n)
    check("BUG-05 prev from page 3 -> page 2", L.prev_offset(5, 3, 4) == 2)
    check("BUG-05 prev from page 2 -> page 1", L.prev_offset(5, 3, 2) == 0)
    -- NEW-01: a page never uses more than fit slots (fit >= 2), any offset
    local over = {}
    for fit = 2, 6 do for off = 0, 4 do
        if L.page_slots(5, fit, off) > fit then over[#over + 1] = fit .. "/" .. off end
    end end
    check("NEW-01 page_slots <= fit for fit 2..6, every offset", #over == 0, table.concat(over, ","))
    check("NEW-01 page_rows(5,2,1) = 1 row + nav (2 slots)", select(2, L.page_rows(5, 2, 1)) == 2 and L.page_slots(5, 2, 1) == 2)
    check("NEW-01 fit=1 documented minimum: 1 row + nav", L.page_slots(5, 1, 0) == 2)
    -- every row reachable for any fit >= 1
    for fit = 1, 6 do
        local seen, off, guard = {}, 0, 0
        repeat
            local a, b, _, nx = L.page_rows(5, fit, off)
            for k = a, b do seen[k] = true end
            off = b; guard = guard + 1
        until not nx or guard > 10
        local all = true; for k = 1, 5 do all = all and seen[k] == true end
        check("BUG-05 all 5 rows reachable with fit=" .. fit, all)
    end
end

print(string.format("\n%d checks, %d failed", n, fails)); os.exit(fails == 0 and 0 or 1)
