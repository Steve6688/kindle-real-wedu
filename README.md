# kindle-weread-shelf — Real微读 (wereadshelf.koplugin) v0.3.5

KOReader 插件：在 Kindle（PW5, 1236×1648）上复刻微信读书墨水屏风格——SimpleUI 底栏 3 Tab（发现 / 书架 / 我）、4 列封面书架、发现页、我的页、微信读书风格阅读菜单与字体面板。只读 weread.koplugin 的本地缓存，不改 weread / SimpleUI 文件。

依赖：KOReader v2026.07.1 + weread.koplugin 1.6.0；simpleui.koplugin 2.7.5 可选。

## 安装
把 `src/wereadshelf.koplugin/` 整个文件夹拷到 Kindle 的 `koreader/plugins/`，详见 [src/INSTALL.md](src/INSTALL.md)。

## 怎么用（v0.3.5：装好就能用）
- **装好即开启**：拷进 `koreader/plugins/` 后启动 KOReader，直接进入 Real微读书架。没有开关，不用设置。
- **每次启动、每次合上书** 都回到 Real微读。
- **返回 KOReader**：「我」→ 返回 KOReader（只这一次；下次启动仍进 Real微读）。
- **再进入**：KOReader 菜单 ☰ 第一项 **进入 Real微读**，或手势 **打开 Real微读**（设置 → 手势管理）。
- **更多设置**（不常用）：「我」→ 阅读设置 → 更多设置…：登录/同步与管理书架、恢复 SimpleUI 原设置、退出到 Kindle。

底栏（发现 / 书架 / 我）在每个主页面都显示；SimpleUI 可选（没有时 Real微读自己画底栏）。

## 目录
- `src/wereadshelf.koplugin/` 插件；`src/spec/` 离线测试与模拟器预览；`SPEC.md` / `UI-SPEC.md` 规范；`vendor/` 依赖插件快照。

## 测试
```
cd src && sh spec/setup_deps.sh && for t in test_shelf_data test_logic test_layout test_main_smoke; do luajit spec/$t.lua; done
```

## Changelog
- **0.3.5** 极简：装好默认开启，启动/合上书必进 Real微读（首次启动自动接管 SimpleUI 首页/引导页并备份，可恢复）；「我」只留一个「返回 KOReader」；阅读设置只剩 2 项（Real微读阅读菜单、更多设置…）；管理/恢复/退出收进「更多设置」；去掉「一键开启」和模式开关；☰ 第一项「进入 Real微读」；手势「打开 Real微读」。
- **0.3.4** 进入/退出简化：微信读书模式开启时启动与合上书自动回书架；「我」页新增「返回 KOReader」（会话内暂停）；KOReader 菜单首页「进入微信书架」；Dispatcher 手势动作「打开微信书架」；点任一底栏 Tab 即恢复模式；开关更名「微信读书模式（启动/合上书时自动进书架）」。
- **0.3.3** 见 tests/RETEST-v0.3.3.md。
