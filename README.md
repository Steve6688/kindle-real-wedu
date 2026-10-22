# kindle-weread-shelf — 微信书架 wereadshelf.koplugin v0.3.4

KOReader 插件：在 Kindle（PW5, 1236×1648）上复刻微信读书墨水屏风格——SimpleUI 底栏 3 Tab（发现 / 书架 / 我）、4 列封面书架、发现页、我的页、微信读书风格阅读菜单与字体面板。只读 weread.koplugin 的本地缓存，不改 weread / SimpleUI 文件。

依赖：KOReader v2026.07.1 + weread.koplugin 1.6.0 + simpleui.koplugin 2.7.5。

## 安装
把 `src/wereadshelf.koplugin/` 整个文件夹拷到 Kindle 的 `koreader/plugins/`，详见 [src/INSTALL.md](src/INSTALL.md)。

## 进入 / 退出（v0.3.4 简化）
| 操作 | 做法 |
|---|---|
| 首次开启 | KOReader 菜单 → 工具 → 微信书架 → 一键开启微信读书模式 → 重启 |
| 之后自动进入 | 模式开启后（记住的设置），**启动 KOReader** 和 **合上书** 都直接回到书架，不再停在 SimpleUI / 文件浏览器 |
| 返回 KOReader | 「我」→ **返回 KOReader**（或 我 → 阅读设置 → 返回 KOReader）。只在本次运行中暂停，不改任何设置 |
| 再次进入 | KOReader 菜单首页（☰）→ **进入微信书架**；或点底栏任一 Tab；或手势/快捷动作 **「打开微信书架」**（设置 → 手势管理，可在阅读中使用，会先合上书） |
| 完全关闭 / 回原生 | 「我」→ 退出到 Kindle / 恢复原生…（恢复 SimpleUI 底栏备份并关闭模式） |

底栏（发现 / 书架 / 我 + ‹ › 翻页）在书架、发现、我三页都显示；所有原有功能保留。

## 目录
- `src/wereadshelf.koplugin/` 插件；`src/spec/` 离线测试与模拟器预览；`SPEC.md` / `UI-SPEC.md` 规范；`vendor/` 依赖插件快照。

## 测试
```
cd src && sh spec/setup_deps.sh && for t in test_shelf_data test_logic test_layout test_main_smoke; do luajit spec/$t.lua; done
```

## Changelog
- **0.3.4** 进入/退出简化：微信读书模式开启时启动与合上书自动回书架；「我」页新增「返回 KOReader」（会话内暂停）；KOReader 菜单首页「进入微信书架」；Dispatcher 手势动作「打开微信书架」；点任一底栏 Tab 即恢复模式；开关更名「微信读书模式（启动/合上书时自动进书架）」。
- **0.3.3** 见 tests/RETEST-v0.3.3.md。
