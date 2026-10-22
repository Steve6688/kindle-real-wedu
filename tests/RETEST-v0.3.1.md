# wereadshelf.koplugin v0.3.1 回归测试报告

日期：2026-10-21 23:45（UTC+8）。对照 tests/BUGS-v0.3.0.md 和 TEST-NOTES.md §0。未修改任何功能代码。
preview/ 已先备份到 `tests/preview-backup-v0.3.0-*`，之后重跑模拟器（EXIT 0，生成 7 张图，含新增的 me-paged-1236x1100.png）。

## 1. 离线测试
| 脚本 | v0.3.0 | v0.3.1 |
|---|---|---|
| test_layout.lua | 42/42 | 42/42 |
| test_logic.lua | 39/39 | 60/60 |
| test_main_smoke.lua | 56/56 | 71/71（日志里的 db locked / HTTP 500 是故意注入的失败） |
| test_shelf_data.lua | 34/34 | 35/35 |
| 合计 | 171 | **208/208 通过** |

## 2. BUG 逐条复核
| Bug | 结论 | 依据 |
|---|---|---|
| BUG-01 字体无高亮 | **关闭**（选中中文字体后的高亮需真机复核） | logic.font_list 把当前字体插到第一位并标记；预览里「Noto Serif」显示黑底，「思源黑体」名称不再截断 |
| BUG-02 无备份回原生 | **关闭** | backToNative 无备份时直接返回 false + NO_BACKUP，不写任何设置；back_to_native_then 失败时只弹提示，不重启也不退出 |
| BUG-03 写入路径不对称 | **关闭** | apply 和 restore 都走 write_sui，再调 Config.saveTabConfig / saveNavbarMode（vendor sui_config.lua:328/347 会清 _tabs_cache / _navbar_mode_cache）；tabs 先 copy_list 再写；原值为 nil 时 set(nil) 等于删除，navpager 为 nil 时显式 del |
| BUG-04 刷新失败无提示 | **关闭** | ok 且结果是 table 才算成功；失败时弹“本周阅读刷新失败…页面上是上次的数据” |
| BUG-05 列表行丢失 | **关闭**（但引出 NEW-01） | rows_paged 分页，fit=1..4 时 5 行都能翻到；矮屏预览出现「更多 ›」 |
| BUG-06 空书架进不去 | **关闭** | get_shelf 新增 allow_empty，showGrid 用它，网格显示“书架为空。点右上「导入」…” |
| BUG-07 导入静默失败 | **关闭** | grid 的「导入」和文字列表的刷新都改走 call_weread，失败会提示 |
| BUG-08 首行缩进误导 | **关闭**（排版效果需真机看） | 改名「强制首行缩进」，开时显示「✓ 强制首行缩进」黑底；关闭只撤销 tweak，书本 CSS 的缩进保留（预览中关状态下正文仍有缩进） |

回归检查：无备份时「只退出」「取消」行为不变；applyWeChatMode 的 reader_menu 备份逻辑不变；Discover/Me 仍走 `get_shelf(...) or {}`，与 allow_empty 互不影响。没有发现回归。

## 3. 新发现
### NEW-01 [P3] 「我」/「发现」列表分页在 fit≤2 时超出可用高度，会压到底栏
- 复现：可用高度只够 2 行时（如 me-paged-1236x1100 的场景）点「更多 ›」进入第 2 页。
- 预期：每页最多占 fit 行。
- 实际：logic.page_rows(5,2,1) 返回「‹ 上一页」+ 1 行 +「更多 ›」，共 3 行，比 2 行可用空间多 1 行。fit=1 时第 1 页也是 2 行。原因是 `slots = math.max(slots, 1)` 后没有扣掉上一页/下一页行。PW5 全屏下 fit≥5，不会触发。
- 位置：wereadshelf_logic.lua page_rows（`slots = math.max(slots, 1)`）；wereadshelf_pages.lua:75-95。

### NEW-02 [P3] 同一字体家族的不同地区版本显示同一个名称，无法区分
- 复现：设备上同时装有 Noto Sans CJK SC 和 TC（或 JP/KR）→ 打开字体面板。
- 实际：font_label 都返回「思源黑体」，出现两个一样的按钮。兜底规则 `" [STJK][CPR]$"` 还会把任意以 " KR"/" SC" 等结尾的字体名截掉后缀（例如 "Something KR" 变成 "Something"）。
- 预期：保留地区标识，例如「思源黑体 SC / TC」。
- 位置：wereadshelf_logic.lua FONT_NAMES / font_label。

### NEW-03 [P3]（外观）「更多 ›」行文字带 ›，右侧又画了 chevron，出现双箭头
- 位置：wereadshelf_pages.lua rows_paged（「更多 ›」/「‹ 上一页」），还要加上 Page:row 固定画的 chevron_right。

## 4. 37 条用例中可离线部分重跑（17 条）
| 用例 | v0.3.0 | v0.3.1 |
|---|---|---|
| TC-03 / 04 / 06 / 10 / 23（书架内筛选）/ 32 / 33 / 36 / 37 | PASS | PASS |
| TC-13 字体面板 | FAIL（BUG-01） | **PASS** |
| TC-29 我页 | PASS | PASS（矮屏分页见 NEW-01） |
| TC-35 无备份回原生 | FAIL（BUG-02） | **PASS** |
| TC-05 / 22 / 24 / 28 / 30 | FAIL（已知限制） | FAIL（已知限制，未变） |

全部 37 条统计：PASS 12 / FAIL(真 bug) 0 / FAIL(已知限制) 5 / 待真机 20。
需真机重点复核：BUG-01（选中中文字体后的高亮）、BUG-08（排版效果）、TC-33/34 回原生、TC-36 加载顺序。
