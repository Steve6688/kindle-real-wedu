# wereadshelf.koplugin v0.3.0 缺陷清单

来源：代码审查 + 离线单测（171/171 通过）+ SDL 模拟器预览图。2026-10-21（UTC+8）。未修改任何功能代码。

## A. 真 bug

### BUG-01 [P3] 字体面板：当前字体不在中文字体列表里时，没有任何按钮被选中，用户看不出当前用的是哪款
- 复现：打开 epub → 点中部 → A。在模拟器里，唯一的按钮「Noto Sans CJ…」是灰底（preview/font-1236x1648.png）。当前 font_face 很可能是 KOReader 默认的拉丁字体（如 Noto Serif），中文靠 fallback 显示，而 pick_fonts 会把纯拉丁字体过滤掉。
- 预期：当前字体按钮黑底白字（SPEC 字体设置面板）。当前字体不在列表时，也应该标出“当前：xxx”，或把它列进去。
- 实际：没有任何按钮选中。另外文字被截断成「Noto Sans CJ…」，标签可读性差。
- 位置：wereadshelf_readermenu.lua:192-200；wereadshelf_logic.lua:85-104（pick_fonts / font_label）。
- 待真机确认：在 PW5 上选中一款中文字体后，该按钮能否正确变黑。如果仍不变黑，就要升级为 P2（说明 font_face 的字段名或格式不匹配）。

### BUG-02 [P2] 从未开启过模式时点「一键回原生」，仍提示“已恢复原状”并要求重启，也会改动用户设置
- 复现：全新安装 → 工具→微信书架→一键回原生→「恢复原状并重启」。
- 预期（TEST-NOTES 2.1.5）：提示“无备份/无需恢复”，不报错，不改设置。
- 实际：backToNative() 走 else 分支，把 reader_menu、open_on_start 强制写成 false。用户之前手动打开的「启动时打开书架」会被清掉。返回值 restored_sui=false 被回调丢弃，照样弹 askForRestart("已恢复原状。")。
- 位置：main.lua:283-286（else 分支）、main.lua:314-317（回调忽略返回值）。

### BUG-03 [P3] 预设应用和恢复走的不是同一条路径，恢复可能不彻底
- 复现：开启模式 → 回原生 → 重启前后分别对比 SimpleUI 底栏模式（文字/图标）。
- 预期：恢复结果与开启前一致。
- 实际：applyPreset 用 Config.saveTabConfig / Config.saveNavbarMode 写入（可能带规范化、写缓存或附带其它 key）；restorePreset 直接 Store:set / Store:del，只调了 invalidateTabsCache，navbar mode 的缓存不会失效。另外 PRESET.simpleui_bar_tabs 是按引用传进 saveTabConfig 的，如果 SimpleUI 原地修改这张表，模块常量也会被改。重启后大概率正常，「恢复并退出到 Kindle」这一路需要真机验证。
- 位置：main.lua:192-195 对比 207-210；main.lua:43。

### BUG-04 [P3] 「我」页手动刷新失败时没有任何提示
- 复现：联网但接口返回非表或报错时，点数据卡。
- 预期：给出“刷新失败”之类的提示（TEST-NOTES：点卡片联网刷新，有提示）。
- 实际：只写 logger.warn。on_done(ok) 中，pcall 成功但返回 nil 时 ok 仍为 true，页面只刷新了旧缓存，“更新于”时间不变，用户分不清刷新有没有成功。
- 位置：main.lua:505-514、547-551。

### BUG-05 [P3] 「我」页列表行空间不足时会被静默丢掉（可能连「退出到 Kindle」一起丢）
- 复现：更小的屏幕，或 hint 换行变高，或 SimpleUI 顶部 inset 更大。
- 预期：5 行入口都在；放不下就分页。
- 实际：`if y + 120 > self.avail then break`，后面的行直接不画，而一键回原生入口恰好在最后一行。PW5 当前布局放得下（模拟器正常），所以是 P3。
- 位置：wereadshelf_pages.lua，Me:build 末尾的 rows 循环。

### BUG-06 [P3] 微信书架为空时无法进入书架 Tab
- 复现：已登录，但微信书架为 0 本（或已同步但为空）→ 点书架 Tab。
- 预期：显示空书架（含搜索框、导入入口）。
- 实际：get_shelf 对 #books==0 返回 ERR_NO_CACHE，showGrid 弹“未同步”对话框，书架 Tab 打不开。发现页则用 `or {}` 正常显示，两处行为不一致。
- 位置：wereadshelf_data.lua:171,189；main.lua:594-595。

### BUG-07 [P3] 「导入」在 weread 异常时静默无反应
- 位置：main.lua:617、648。`pcall(weread.openBookshelf, weread)` 不检查结果，失败时用户点了没任何反馈。应该改用 call_weread()，它会提示错误。

### BUG-08 [P3] 字体面板「首行缩进」的状态只反映插件的 style tweak，不反映书本 CSS
- 复现：书本 CSS 自带缩进（模拟器样书就是这样）→ 胶囊显示“关”，正文却有缩进。
- 影响：用户点“开”看不到变化，会以为开关失效。建议在面板上注明这是“强制首行缩进”。
- 位置：wereadshelf_readermenu.lua:172-181。

## B. 已知限制（程序员已在 TEST-NOTES §3 声明，不计为 bug，但会导致 SPEC/UI-SPEC 项不通过）
- K-01 书城/推荐/榜单/分类：weread 1.6.0 无接口 → SPEC「书城浏览」「排行榜」不通过，发现页无「为你推荐」。
- K-02 底栏翻页为两端 ‹ ›，不是右侧 ∧∨ 胶囊；Tab 图标约 91px（规范 64）；选中有 SimpleUI 下划线指示条（UI-SPEC 要求不加下划线）。预览图已确认。
- K-03 最近阅读显示 4 本（规范 5 本 200×280）。
- K-04 阅读菜单呼出时不显示 KOReader 状态栏（UI-SPEC v1.1 要求显示）。
- K-05 滑杆只能点按，不能拖动；UI-SPEC 的“拖动局部刷新/松手再刷”无法验证。
- K-06 无头像接口，用昵称首字代替；无全局笔记列表，「我的笔记」只是一条说明。
- K-07 字体只列设备已装的中文字体，没有微信读书专有字体。
- K-08 登录/同步/进度/划线/词典/TTS 沿用 weread/KOReader 原功能，插件未改动。
- K-09 每本书的字号等设置在回原生时不回退（设计如此）。

## C. 审查通过项（无问题）
- nil 访问：外部调用基本都用 pcall/type 守卫包住；setStep 访问 document.configurable 只在 isRolling() 下才会走到；showGrid 在 weread 为 nil 时提前返回。
- SimpleUI Tab 回写：tabsToRestore 只在本插件 id 被剪掉时才回写，保留用户原有顺序；每个进程只做一次；单测覆盖。
- 一键回原生（有备份时）：会恢复 3 个 SimpleUI key（原值为 nil 时 del），以及 open_on_start、reader_menu，之后删除备份，重复开关都能还原。需要真机验证 TC-33/34。
- 触控区：书架顶部 search_h/title_row_h ≥120；导入/选择按钮宽度 max(...,120)；阅读菜单栏 ≥120；5 个图标槽各 247px；滑杆整行 ≥120；字体按钮触控高度 = font_pitch ≥120；列表行 ≥120。均满足 ≥110。
