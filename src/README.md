# src/

- `wereadshelf.koplugin/` — KOReader 插件 v0.3.4（拷到 Kindle，见 INSTALL.md）
  - `wereadshelf_data.lua` 数据层（v0.1 起未改）：`get_shelf(weread, opts)`、`open_book(weread, bookId)`、`plan_open`、`find_weread`
  - `wereadshelf_layout.lua` **新**：网格布局/分页/点击命中/本地筛选的纯计算（UI-SPEC v1 数值，按屏宽 /1236 缩放）
  - `wereadshelf_grid.lua` **新**：4 列封面网格书架页（只用 KOReader 自带 widget）
  - `wereadshelf_logic.lua` **v0.3**：字体滑杆档位、字体挑选、最近阅读/统计格式化等纯函数
  - `wereadshelf_ui.lua` **v0.3**：黑/白/一种灰的绘制小工具（胶囊、分隔线、封面）
  - `wereadshelf_pages.lua` **v0.3**：「发现」「我」两页
  - `wereadshelf_readermenu.lua` **v0.3**：阅读菜单（顶栏 + 5 图标底栏）与字体面板，单个全屏覆盖 widget（只绘制上下栏）
  - `main.lua` 注册 3 个 SimpleUI 快捷动作（发现/书架/我）、BarInjection、底栏预设/恢复、启动进书架、搜索框、微信读书模式/一键回原生、阅读中部点击区；保留 v0.1 文字列表
  - `icons/` 底栏图标（描边 + 实心选中态）、搜索/导入/选择小图标（SVG）
- `spec/` 离线测试（电脑/box 上跑）：
  `sh spec/setup_deps.sh && luajit spec/test_shelf_data.lua && luajit spec/test_logic.lua && luajit spec/test_layout.lua && luajit spec/test_main_smoke.lua`
  - `test_shelf_data.lua` 用 weread v1.6.0 真实代码 + 真 SQLite 测数据层（35 项）
  - `test_logic.lua` 滑杆/字体/统计纯函数（74 项）
  - `test_layout.lua` 网格分页/布局/命中/筛选（42 项）
  - `test_main_smoke.lua` 桩模块跑 main.lua：3 个 QA、BarInjection、网格路由、搜索、发现/我入口、预设应用/恢复、被 SimpleUI 剪掉的 Tab 恢复、阅读菜单钩子、微信读书模式/一键回原生（71 项；不是真 UI）
  - `preview/run_preview.sh` 只在 box 用：KOReader v2026.07.1 官方 Linux 版（SDL 模拟器 1236×1648@300dpi）+ SimpleUI 2.7.5 + 假 weread（合成封面），自动生成示例 epub，截图 shelf/shelf2/discover/me/reader/font 到 `../preview/`。**不要拷到 Kindle。**

## 设计要点（以源码为准）
| 需求 | 实现 | 依据（文件:行） |
|---|---|---|
| 3 Tab | `QA.register` 三个 id：`wereadshelf_discover` / `wereadshelf_open`（书架，沿用 v0.1 id）/ `wereadshelf_me` | simpleui `features/sui_quickactions.lua:23-53`；外部 id 可作 Tab：`infra/sui_config.lua:296-326` |
| 纯图标 | SimpleUI 设置「仅图标」`simpleui_bar_mode="icons"` | `infra/sui_config.lua:338-350`，`screens/sui_menu.lua:226` |
| 右侧翻页键 | SimpleUI「Navpager」`simpleui_bar_navpager_enabled`（最多 4 Tab） | `infra/sui_config.lua:109,2841-2844`；箭头调用 `onPrevPage/onNextPage`：`screens/sui_bottombar.lua:1059-1079` |
| 书架页带底栏 | `UI.BarInjection.register{widget_name="wereadshelf_grid"}`，SimpleUI 自己包上底栏 | `infra/sui_core.lua:1066-1135`；`infra/sui_patches.lua:1796-1810,1993-2025` |
| 选中态 | 书架网格打开时 `get_icon` 返回实心图标；`on_inject` 里 `Bottombar.setActiveTab` | `features/sui_quickactions.lua:1913-1941`；`screens/sui_bottombar.lua:937-959` |
| 发现 | weread `showSearch()`（微信读书在线搜索对话框；weread 1.6.0 没有书城/推荐页） | weread `weread/ui/library.lua:1640` |
| 我 | weread `showReadStats()`（阅读统计） | weread `weread/ui/read_report.lua:238` |
| 搜索框 | 点开对话框：「书架内筛选」（本地，离线即时）或「微信读书搜索」→ `searchWithUI(kw)` | weread `weread/ui/library.lua:1673` |
| 导入 | weread `openBookshelf()`（刷新/管理书架） | weread `main.lua:33` |
| 选择 | v1 占位提示「二期」（weread 无批量选择 API，不伪造） | — |
| 默认进书架 | 本插件自有开关「启动 KOReader 时打开书架」（默认关，预设会打开）；KOReader `start_with` 只能选内置项，不改它 | simpleui `infra/sui_config.lua:397-413` |

### 已知坑：SimpleUI 启动时会删掉“未注册”的 Tab id
SimpleUI 的 `init()` 调 `Config.sanitizeQASlots()`（simpleui `main.lua:937-943` → `features/sui_quickactions.lua:1403-1422`），把 `QA.isRegistered()` 不认识的 Tab **永久删掉**。插件按路径排序初始化（KOReader `frontend/pluginloader.lua:289`），simpleui 在 wereadshelf 之前，所以 v0.1 放进底栏的「微信书架」重启后会被删（box 模拟器复现）。
v0.2 处理：`main.lua` 被 dofile 时（所有 init 之前）快照 `simpleui_bar_tabs`，注册完后若发现我们的 id 被剪掉，按快照原样写回（只恢复用户自己的列表，不加别的）。日志：`wereadshelf: restored SimpleUI tabs pruned before our registration`。

### 墨水屏 / 内存
- 只用黑、白、#D9D9D9（封面描边）；无动画；整页翻（底栏 ‹ ›、左右/上下滑、物理翻页键）。
- 触控：搜索框、标题行高 120；封面格 252×(378+12+88)。
- 封面直接用 weread 已缓存的 300×450 缩略图（`cover_cache.lua:12-13`），本插件不另存文件；`file_do_cache=false` 不占 KOReader 共用的 8 MiB ImageCache（`imagewidget.lua:41-50`），每次翻页/关闭立即 `free()` 当前页位图。PW5 上一页 8 本 ≈ 8×252×378 B ≈ 0.76 MB。
- PW5（含 SimpleUI 顶栏+底栏）一页 **2 行 × 4 列 = 8 本**；参考图第 3 行是露出半截的滚动效果，规范要求整页翻，故只排整行。
