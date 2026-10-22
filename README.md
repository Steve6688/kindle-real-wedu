# kindle-weread-shelf — Real微读 (wereadshelf.koplugin) v0.4.0

KOReader 插件：在 Kindle（PW5, 1236×1648）上复刻微信读书墨水屏风格——0.3.3 风格界面（顶部时间/电量，底栏 ‹ 发现 书架 我 ›）、4 列封面书架、发现页、我的页、微信读书风格阅读菜单与字体面板。只读 weread.koplugin 的本地缓存，不改 weread 文件。

依赖：KOReader v2026.07.1。**0.4.0 起已内置 weread.koplugin 1.6.0**（只装这一个插件；升级时删除 `koreader/plugins/weread.koplugin`，登录/缓存/已下载书/设置原样保留）。**不需要、也不再支持 SimpleUI**（0.3.7 起完全移除；旧设备上请删除 `koreader/plugins/simpleui.koplugin/`）。

## 安装
把 `src/wereadshelf.koplugin/` 整个文件夹拷到 Kindle 的 `koreader/plugins/`，详见 [src/INSTALL.md](src/INSTALL.md)。

## 怎么用（v0.4.0）
- **装好即开启**：拷进 `koreader/plugins/` 后启动 KOReader，直接进入 Real微读书架。没有开关，不用设置。
- **每次启动、每次合上书** 都回到 Real微读。
- **返回 KOReader**：「我」→ 返回 KOReader（只这一次；下次启动仍进 Real微读）。
- **再进入**：KOReader 菜单 ☰ 第一项 **进入 Real微读**，或手势 **打开 Real微读**（设置 → 手势管理）。
- **「我」页**（0.3.3 样式）：账号、数据卡（本周阅读 / 读完 / 笔记，点卡片刷新）、阅读时长统计、我的笔记、书架同步、阅读设置、退出到 Kindle、返回 KOReader。
- **阅读设置**：Real微读阅读菜单、快速下载（3–5 章并行）、流畅翻页（无翻页动画、每 12 页全刷一次）、KOReader 设置（完整菜单），都是开关，默认开。
- **所有「书架」都进 Real微读书架**：底栏书架、登录/同步之后、微信读书菜单里的「书架」、手势「微信读书·书架」、读完一本的「书架」按钮、第三方启动器，都不再打开 weread 的书架列表（公众号列表除外）。
- **阅读中**点屏幕中部 → 顶栏（‹ 章节名、书签、⋯）+ 底栏 5 图标（返回 / 目录 / 进度 / 亮度 / A）；「A」直接打开字体设置面板（字号、粗细、行距、边距、首行缩进、字体），与 0.3.3 相同。
- **快速下载**（默认开）：整本下载时滑动窗口并行预取，从 3 章起，连续成功后逐步升到 5 章（错开 ≥0.25 s 启动）；出错并发减半并暂停 2 s，遇到 429/限流或连续 2 次出错改回逐章（weread 原流程及其重试退避）；去掉章与章之间 0.1 s 空等、不再每章重写不变的 style.css、笔记索引在主进程顺序写入；进度条每秒最多刷新一次；已下载章节照旧跳过。

底栏只有 发现 / 书架 / 我（v0.3.6 去掉 ‹ › 翻页箭头，用滑动或翻页键翻页），每个主页面都显示，由 Real微读自己绘制（0.3.3 样式；‹ › 在书架页翻页）。

## 许可与致谢
内置的微信读书功能来自 [weread.koplugin](https://github.com/finlater/weread.koplugin) 1.6.0（© 2026 finlater and contributors，**AGPL-3.0-only**；`rweread/fonts` 的 NotoEmoji 为 OFL 1.1）。合并后的插件整体按 AGPL-3.0 发布，见 `LICENSE-AGPL-3.0` 与 `src/wereadshelf.koplugin/rweread/{LICENSE,NOTICE}`。

## 目录
- `src/wereadshelf.koplugin/` 插件；`src/spec/` 离线测试与模拟器预览；`SPEC.md` / `UI-SPEC.md` 规范；`vendor/` 依赖插件快照。

## 测试
```
cd src && sh spec/setup_deps.sh && for t in test_shelf_data test_logic test_layout test_main_smoke test_fastdl; do luajit spec/$t.lua; done
```

## Changelog
- **0.4.0** 合并为一个插件：weread.koplugin 1.6.0 内置到 `wereadshelf.koplugin/rweread/`（模块改名 `rweread.*`，与残留的旧插件互不冲突）。设置名仍为 `weread`（settings/weread.lua、数据目录 weread/），无需重新登录或迁移。书架重定向改为直接修改内置代码（library.lua / qr_login.lua），快速下载作用于内置模块，行为与 0.3.8 相同。☰ 只有一个「Real微读」入口，微信读书原有功能（登录、书架、公众号、缓存等）收在其中「微信读书功能」。若仍装着独立的 weread.koplugin：本次会话自动摘除，并在 KOReader 中禁用，下次启动不再加载。内置版关闭 weread 自动更新（它会用上游版本覆盖插件目录）。
- **0.3.8** 下载再提速：滑动窗口取代 0.3.7 的「3 章一批」等待，并发 3→5 自适应、出错减半/限流转逐章；去掉章间 0.1 s 空等与每章重复写 style.css；笔记索引改在主进程写（避免多进程争用 SQLite）。离线模型（spec/test_fastdl.lua，60 章）：weread 原版 3.5 s/章 → 0.3.7 1.6 s/章 → 0.3.8 0.6 s/章（约 2.6× 于 0.3.7，真机受网络/CPU 限制，预计 1.5–2.5×）。界面恢复 0.3.3 样子（顶部时间/电量、底栏 ‹ 发现 书架 我 › 与选中横条、「我」数据卡 + 原 5 行、「A」直接字体面板、阅读设置对话框），进入/退出方式保持 0.3.5–0.3.7 不变，快速下载开关在「我 → 阅读设置」。所有「书架」入口（含 weread 自己的书架入口、登录/同步后）统一进 Real微读书架。翻页：默认关闭翻页动画、用户未改时全刷间隔 6→12 页（仅本次会话，不写 KOReader 设置）；模拟器实测每次翻页本插件额外开销约 1 ms。
- **0.3.7** 「我」页直接列出全部 9 项（阅读时长统计 / 我的笔记 / 书架同步·登录与管理 / 刷新本周阅读数据 / 阅读菜单开关 / 快速下载开关 / KOReader 设置 / 退出到 Kindle / 返回 KOReader），去掉「更多设置」一层，开关当场更新 ✓；阅读中底部弹窗的「更多设置 ›」保留。**彻底移除 SimpleUI**：不再依赖、不再改它的设置、删掉「恢复 SimpleUI 原设置」和 `vendor/simpleui.koplugin`，底栏（发现/书架/我）始终由 Real微读自己绘制；启动进 Real微读、合上书回书架、☰「进入 Real微读」、手势、快速下载不变。设备上残留旧 SimpleUI 也不会盖住书架，但建议删除 `plugins/simpleui.koplugin/`。
- **0.3.6** 下载提速：weread 1.6.0 整本下载改为最多 3 章并行预取（运行时补丁，不改 weread 文件，可在更多设置关闭），去掉每章额外的进程启动等待与逐章 e-ink 刷新，出错降级为单章并保留原重试退避；估计整本下载快 2.5–3 倍（真机待测）。「我」页精简为 账号 + 更多设置 + 返回 KOReader，原 4 行收进更多设置；底栏去掉 ‹ ›；阅读中新增「阅读设置」底部弹窗（字号、亮度/暖光、翻页方式、更多设置）。
- **0.3.5** 极简：装好默认开启，启动/合上书必进 Real微读（首次启动自动接管 SimpleUI 首页/引导页并备份，可恢复）；「我」只留一个「返回 KOReader」；阅读设置只剩 2 项（Real微读阅读菜单、更多设置…）；管理/恢复/退出收进「更多设置」；去掉「一键开启」和模式开关；☰ 第一项「进入 Real微读」；手势「打开 Real微读」。
- **0.3.4** 进入/退出简化：微信读书模式开启时启动与合上书自动回书架；「我」页新增「返回 KOReader」（会话内暂停）；KOReader 菜单首页「进入微信书架」；Dispatcher 手势动作「打开微信书架」；点任一底栏 Tab 即恢复模式；开关更名「微信读书模式（启动/合上书时自动进书架）」。
- **0.3.3** 见 tests/RETEST-v0.3.3.md。
