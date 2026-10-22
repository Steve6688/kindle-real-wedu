# kindle-weread-shelf — Real微读 (wereadshelf.koplugin) v0.3.7

KOReader 插件：在 Kindle（PW5, 1236×1648）上复刻微信读书墨水屏风格——自带底栏 3 Tab（发现 / 书架 / 我）、4 列封面书架、发现页、我的页、微信读书风格阅读菜单与字体面板。只读 weread.koplugin 的本地缓存，不改 weread 文件。

依赖：KOReader v2026.07.1 + weread.koplugin 1.6.0。**不需要、也不再支持 SimpleUI**（0.3.7 起完全移除；旧设备上请删除 `koreader/plugins/simpleui.koplugin/`）。

## 安装
把 `src/wereadshelf.koplugin/` 整个文件夹拷到 Kindle 的 `koreader/plugins/`，详见 [src/INSTALL.md](src/INSTALL.md)。

## 怎么用（v0.3.7）
- **装好即开启**：拷进 `koreader/plugins/` 后启动 KOReader，直接进入 Real微读书架。没有开关，不用设置。
- **每次启动、每次合上书** 都回到 Real微读。
- **返回 KOReader**：「我」→ 返回 KOReader（只这一次；下次启动仍进 Real微读）。
- **再进入**：KOReader 菜单 ☰ 第一项 **进入 Real微读**，或手势 **打开 Real微读**（设置 → 手势管理）。
- **「我」页**直接列出全部功能（无二级菜单）：阅读时长统计、我的笔记、书架同步·登录与管理、刷新本周阅读数据、Real微读阅读菜单（开关）、快速下载（开关）、KOReader 设置、退出到 Kindle、返回 KOReader。
- **阅读中**点屏幕中部 → 「A」= 阅读设置底部弹窗：字号（A− 数字 A+）、亮度 / 暖光、翻页方式（点击 / 滑动 / 按键，无实体键的设备不显示「按键」）、更多设置 ›（字体·行距·边距·缩进、目录、书签、进度、搜索、KOReader 阅读设置）。局部刷新，不全屏闪。
- **快速下载**（默认开）：整本下载时最多 3 章并行（错开 0.4 s 启动），出错自动降为 1 章并沿用 weread 的重试退避；进度条每秒最多刷新一次；已下载章节照旧跳过。

底栏只有 发现 / 书架 / 我（v0.3.6 去掉 ‹ › 翻页箭头，用滑动或翻页键翻页），每个主页面都显示，由 Real微读自己绘制。

## 目录
- `src/wereadshelf.koplugin/` 插件；`src/spec/` 离线测试与模拟器预览；`SPEC.md` / `UI-SPEC.md` 规范；`vendor/` 依赖插件快照。

## 测试
```
cd src && sh spec/setup_deps.sh && for t in test_shelf_data test_logic test_layout test_main_smoke test_fastdl; do luajit spec/$t.lua; done
```

## Changelog
- **0.3.7** 「我」页直接列出全部 9 项（阅读时长统计 / 我的笔记 / 书架同步·登录与管理 / 刷新本周阅读数据 / 阅读菜单开关 / 快速下载开关 / KOReader 设置 / 退出到 Kindle / 返回 KOReader），去掉「更多设置」一层，开关当场更新 ✓；阅读中底部弹窗的「更多设置 ›」保留。**彻底移除 SimpleUI**：不再依赖、不再改它的设置、删掉「恢复 SimpleUI 原设置」和 `vendor/simpleui.koplugin`，底栏（发现/书架/我）始终由 Real微读自己绘制；启动进 Real微读、合上书回书架、☰「进入 Real微读」、手势、快速下载不变。设备上残留旧 SimpleUI 也不会盖住书架，但建议删除 `plugins/simpleui.koplugin/`。
- **0.3.6** 下载提速：weread 1.6.0 整本下载改为最多 3 章并行预取（运行时补丁，不改 weread 文件，可在更多设置关闭），去掉每章额外的进程启动等待与逐章 e-ink 刷新，出错降级为单章并保留原重试退避；估计整本下载快 2.5–3 倍（真机待测）。「我」页精简为 账号 + 更多设置 + 返回 KOReader，原 4 行收进更多设置；底栏去掉 ‹ ›；阅读中新增「阅读设置」底部弹窗（字号、亮度/暖光、翻页方式、更多设置）。
- **0.3.5** 极简：装好默认开启，启动/合上书必进 Real微读（首次启动自动接管 SimpleUI 首页/引导页并备份，可恢复）；「我」只留一个「返回 KOReader」；阅读设置只剩 2 项（Real微读阅读菜单、更多设置…）；管理/恢复/退出收进「更多设置」；去掉「一键开启」和模式开关；☰ 第一项「进入 Real微读」；手势「打开 Real微读」。
- **0.3.4** 进入/退出简化：微信读书模式开启时启动与合上书自动回书架；「我」页新增「返回 KOReader」（会话内暂停）；KOReader 菜单首页「进入微信书架」；Dispatcher 手势动作「打开微信书架」；点任一底栏 Tab 即恢复模式；开关更名「微信读书模式（启动/合上书时自动进书架）」。
- **0.3.3** 见 tests/RETEST-v0.3.3.md。
