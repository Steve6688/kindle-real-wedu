# Real微读（wereadshelf.koplugin）安装说明 — v0.3.4（底栏 + 书架 + 发现 + 我 + 阅读菜单 + 字体面板 + 一键回原生）

适用：KOReader v2026.07.1 + weread.koplugin 1.6.0 + simpleui.koplugin 2.7.5（Kindle PW5）。
本插件**只读** weread 的本地缓存，不修改 weread / SimpleUI 的任何文件，不改 Kindle 系统，只在 `/mnt/us/koreader/` 下新增/更新一个插件文件夹和一个设置文件 `settings/wereadshelf.lua`（只有你在菜单里点「应用预设」或开关「启动时打开书架」时才写）。

## 0. 先备份（必做）
USB 连接 Kindle，把整个 `koreader/settings/` 复制到电脑，例如 `settings.bak-20261021/`。
其中含 `weread.lua`（登录凭据）、`simpleui/sui_settings.lua`（底栏设置）等。

## 1. 全新安装 / 从 v0.1、v0.2 升级
1. 完全退出 KOReader（菜单 → 退出），USB 连电脑。
2. 删除旧的 `koreader/plugins/wereadshelf.koplugin/`（升级时），再把本仓库 `src/wereadshelf.koplugin/` **整个文件夹**拷过去：
```
koreader/plugins/wereadshelf.koplugin/
    _meta.lua  main.lua  wereadshelf_data.lua  wereadshelf_layout.lua  wereadshelf_grid.lua
    wereadshelf_logic.lua  wereadshelf_ui.lua  wereadshelf_pages.lua  wereadshelf_readermenu.lua
    icons/  (21 个 svg：tab_*、rm_*、bookmark*、more、back_chevron、chevron_right、refresh、search、import、select、wereadshelf)
```
（`src/spec/` 是电脑上的测试和预览工具，**不要拷**。）
3. 安全弹出 → KUAL 启动 KOReader → 插件管理确认「Real微读」已勾选，版本 0.3.4。
4. 确保 weread 里打开过一次书架（联网），让它缓存书架和封面——本插件只显示这份缓存。

从 v0.1 升级：Tab id `wereadshelf_open` 没变，原来放在底栏的「微信书架」格子会自动变成封面网格。

## 2. 配置底栏（二选一）
### A. 一键开启微信读书模式（推荐，可一键回原生）
菜单 → 工具 → 微信书架 → **一键开启微信读书模式…** → 开启 → 重启 KOReader。
它会先把你原来的这 3 项 SimpleUI 设置备份到 `settings/wereadshelf.lua`，再写入：
- `simpleui_bar_tabs` = 发现、书架、我（3 个 Tab）
- `simpleui_bar_mode` = `icons`（仅图标）
- `simpleui_bar_navpager_enabled` = 开（底栏两侧 ‹ › 翻页键）
- 本插件「启动 KOReader 时打开书架」= 开
- 本插件「微信读书风格阅读菜单」= 开（阅读时点屏幕中部 1/2 区域呼出；两侧翻页不变）
不碰 SimpleUI 的其它任何设置。

### B. 手动配置（不想让插件改 SimpleUI 设置时）
菜单名以 SimpleUI 实际界面为准（源码里的英文原文：`Tabs` screens/sui_menu.lua:334、`Icons only` :226、`Navpager` :444；中文界面会是对应译名）。
1. SimpleUI 设置 → Bars → Navigation Bar → Tabs：把 Tab 设为 3 个，依次选「发现」「微信书架」「我」（在动作列表里，都是本插件注册的）。
2. 同一页 Bar mode / 显示方式选 **Icons only（仅图标）**。
3. 打开 **Navpager**（页面翻页箭头；开启后最多 4 个 Tab）。
4. 菜单 → 工具 → 微信书架 → 勾选「启动 KOReader 时打开书架」，需要的话再勾选「微信读书风格阅读菜单」。
5. 如想去掉选中 Tab 上方的黑色指示条，可在 SimpleUI 外观里把底栏改成 floating（可选，未在真机验证）。

## 3. 使用
- **书架 Tab**：4 列封面网格（PW5 每页 8 本），点封面：已下载→打开阅读；未下载→weread 书籍详情。翻页：底栏 ‹ ›、滑动、翻页键。搜索框：书架内筛选 / 微信读书搜索。
- **发现 Tab**：搜索框（→ weread 搜索）、「最近阅读」4 本封面 +「全部 ›」（→ 书架）、「微信读书」入口列表（搜索、公众号文章、收藏、书架——只列 weread 1.6.0 实际有的功能）。weread 没有推荐/榜单/分类接口，「为你推荐」整区隐藏。
- **我 Tab**：头像（昵称首字）、昵称、本周阅读（分钟）/ 读完（本）/ 笔记（条）数据卡（点卡片刷新，需联网）、5 行列表：阅读时长统计、我的笔记、书架同步、阅读设置、退出到 Kindle。
- **阅读菜单**（需开启）：阅读时点屏幕中部 → 顶栏（‹ 章节名=返回书架、书签、⋯更多）+ 底栏 5 图标：返回 / 目录 / 进度跳转 / 亮度 / 字体。点菜单外区域关闭。⋯ 里有：添加/删除书签、书签列表、搜索全书、书籍详情、刷新屏幕、KOReader 原生菜单。
- **字体面板**：底栏「A」→ 字号、粗细、行距、边距 4 条滑杆（点 −/+ 或点滑杆位置），首行缩进开关，字体按钮（只显示设备上已装的中文字体）。改动按本书保存，与 KOReader 原生字体设置是同一份。PDF 等版式文档点「A」打开 KOReader 原生设置。
- 菜单 → 工具 → 微信书架 → 「打开书架（文字列表）」：v0.1 列表仍保留。

## 4. 回退
- **一键回原生**：菜单 → 工具 → 微信书架 → **一键回原生（恢复 KOReader / SimpleUI 原状）…**，或「我」页 →「退出到 Kindle」。可选：恢复原状并重启 KOReader / 恢复原状并退出到 Kindle / 只退出到 Kindle（不改设置）/ 取消。恢复内容：SimpleUI 底栏 3 项设置、阅读菜单开关、启动打开书架开关，全部回到开启前的备份值；从未开启过模式时只提示“没有可恢复的备份”，不改任何设置。**不回退**：你在字体面板里对每本书做的字号等修改（它们本来就是 KOReader 每本书的设置，可在 KOReader 原生菜单里改回）。
- **回到 v0.2**：先一键回原生，退出 KOReader，删 `plugins/wereadshelf.koplugin/`，拷回 v0.2 的文件夹。
- **完全卸载**：先一键回原生，再删除 `plugins/wereadshelf.koplugin/` 和 `settings/wereadshelf.lua`。
- KOReader 无法启动/设置异常：用第 0 步备份的 `settings/` 整个覆盖回去。

## 5. 出问题时请提供
`koreader/crash.log`（搜 `wereadshelf`、`simpleui`），哪一步、屏幕上的提示文字，最好一张照片。
