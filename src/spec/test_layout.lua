-- Unit tests for wereadshelf_layout.lua (pure Lua, no KOReader).
local here = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = here .. "/../wereadshelf.koplugin/?.lua;" .. package.path
local L = require("wereadshelf_layout")
local fails, n = 0, 0
local function check(name, c) n = n + 1; print((c and "ok   " or "FAIL ") .. name); if not c then fails = fails + 1 end end

-- PW5 content height as in 0.3.3 (top inset + bar, ~1380 px)
local m = L.compute{ screen_w = 1236, avail_h = 1380 }
check("4 columns", m.cols == 4)
check("cover width 252 (1236-2*45-3*45)/4", m.cover_w == 252)
check("cover 2:3", m.cover_h == 378)
check("grid fits screen width", 2 * m.margin + m.grid_w <= 1236 and 1236 - (2 * m.margin + m.grid_w) < 4)
check("search capsule touch >=120", m.search_h >= 120)
check("title row touch >=120", m.title_row_h >= 120)
check("cell taller than 120", m.cell_h >= 120 and m.cell_w >= 120)
check("header = 24+120+120", m.header_h == 264)
check("rows fit grid height", m.rows * m.cell_h + (m.rows - 1) * m.row_gap <= m.grid_h)
check("PW5 rows = 2, per_page = 8", m.rows == 2 and m.per_page == 8)
-- 0.3.8 own status line (82) + bar (226): 1648-82-226 = 1340
local o = L.compute{ screen_w = 1236, avail_h = 1648 - 82 - 226 }
check("0.3.8 own bars: 2 rows x 4 = 8 per page (0.3.3 look)", o.rows == 2 and o.per_page == 8)
-- full screen without any bar: (1648-264+30)/(472+30) = 2.8 -> still 2 rows
local f = L.compute{ screen_w = 1236, avail_h = 1648 }
check("no bar: 2 rows (whole rows only)", f.rows == 2 and f.per_page == 8)
check("taller screen -> 3 rows", L.compute{ screen_w = 1236, avail_h = 1800 }.rows == 3)
-- tiny height still gives at least one row
check("min 1 row", L.compute{ screen_w = 1236, avail_h = 100 }.rows == 1)
-- scaling to a 758-wide screen keeps touch minimums
local s = L.compute{ screen_w = 758, avail_h = 900 }
check("small screen keeps 120px search", s.search_h == 120)
check("small screen 4 cols positive", s.cover_w > 100)

-- pagination
check("page_count 0 -> 1", L.page_count(0, 8) == 1)
check("page_count 8 -> 1", L.page_count(8, 8) == 1)
check("page_count 9 -> 2", L.page_count(9, 8) == 2)
check("page_count 17 -> 3", L.page_count(17, 8) == 3)
check("clamp low", L.clamp_page(0, 17, 8) == 1)
check("clamp high", L.clamp_page(9, 17, 8) == 3)
check("clamp nil", L.clamp_page(nil, 17, 8) == 1)
local list = {}
for i = 1, 17 do list[i] = { title = "书" .. i, author = (i % 2 == 0) and "Kafka" or "鲁迅" } end
local p3, a, b, pg = L.page_slice(list, 3, 8)
check("last page has 1 item", #p3 == 1 and a == 17 and b == 17 and pg == 3)
local p1 = L.page_slice(list, 1, 8)
check("first page 8 items", #p1 == 8 and p1[1].title == "书1" and p1[8].title == "书8")
local pe = L.page_slice({}, 1, 8)
check("empty slice", #pe == 0)
check("page_of", L.page_of(1, 8) == 1 and L.page_of(8, 8) == 1 and L.page_of(9, 8) == 2)

-- cell positions & hit test
local x1, y1, r1, c1 = L.cell_pos(m, 1)
check("cell1 at margin,0", x1 == 45 and y1 == 0 and r1 == 1 and c1 == 1)
local x4 = L.cell_pos(m, 4)
check("cell4 x", x4 == 45 + 3 * (252 + 45))
local x5, y5, r5, c5 = L.cell_pos(m, 5)
check("cell5 second row", x5 == 45 and y5 == m.cell_h + m.row_gap and r5 == 2 and c5 == 1)
check("hit cell1", L.hit(m, 50, 10, 8) == 1)
check("hit cell4 title area", L.hit(m, x4 + 10, m.cover_h + 20, 8) == 4)
check("hit gap between columns = nil", L.hit(m, 45 + 252 + 10, 10, 8) == nil)
check("hit left margin = nil", L.hit(m, 10, 10, 8) == nil)
check("hit row gap = nil", L.hit(m, 50, m.cell_h + 5, 8) == nil)
check("hit cell6", L.hit(m, x5 + (252 + 45) + 1, y5 + 1, 8) == 6)
check("hit beyond count = nil", L.hit(m, x5 + 1, y5 + 1, 3) == nil)
check("hit beyond rows = nil", L.hit(m, 50, 2 * (m.cell_h + m.row_gap) + 1, 99) == nil)

-- local filter
check("filter title", #L.filter(list, "书1") == 9) -- 书1, 书10..书17
check("filter author ci", #L.filter(list, "kafka") == 8)
check("filter blank = all", #L.filter(list, "  ") == 17)
check("filter nil = all", L.filter(list, nil) == list)
check("filter plain (no pattern)", #L.filter({ { title = "a.b" }, { title = "axb" } }, "a.b") == 1)

print(string.format("\n%d checks, %d failed", n, fails)); os.exit(fails == 0 and 0 or 1)
