# 微信书架（wereadshelf.koplugin）安装说明 — v0.3.4（底栏 + 书架 + 发现 + 我 + 阅读菜单 + 字体面板 + 一键回原生）

适用：KOReader v2026.07.1 + weread.koplugin 1.6.0（Kindle PW5）。无需 SimpleUI。
本插件**只读** weread 的本地缓存，不修改 weread 或 KOReader 文件，只新增/更新插件目录和设置文件 `settings/wereadshelf.lua`。

## 0. 先备份（必做）
USB 连接 Kindle，把整个 `koreader/settings/` 复制到电脑，例如 `settings.bak-20261021/`。
其中含 `weread.lua`（登录凭据）等重要数据。

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
3. 安全弹出 → KUAL 启动 KOReader → 插件管理确认「Real微读」已勾选，版本 0.3.6。
4. 确保 weread 里打开过一次书架（联网），让它缓存书架和封面——本插件只显示这份缓存。

启动后进入 KOReader 菜单 → Real微读：
- 第一次使用点「登录、同步与管理书架」；
- 日常使用只需点「打开 Real微读」；
- 另外两个开关分别控制阅读菜单和启动直达。

## 2. 使用
- **打开**：KOReader 菜单 → Real微读 → 打开 Real微读。
- **登录或同步**：KOReader 菜单 → Real微读 → 登录、同步与管理书架。
- **书架**：4 列封面网格（PW5 每页 8 本）。点封面即可阅读或进入书籍详情；可滑动或用翻页键翻页，搜索框支持书架内筛选和微信读书搜索。
- **阅读菜单**（需开启）：阅读时点屏幕中部 → 顶栏（‹ 章节名=返回书架、书签、⋯更多）+ 底栏 5 图标：返回 / 目录 / 进度跳转 / 亮度 / 字体。点菜单外区域关闭。⋯ 里有：添加/删除书签、书签列表、搜索全书、书籍详情、刷新屏幕、KOReader 原生菜单。
- **字体面板**：底栏「A」→ 字号、粗细、行距、边距 4 条滑杆（点 −/+ 或点滑杆位置），首行缩进开关，字体按钮（只显示设备上已装的中文字体）。改动按本书保存，与 KOReader 原生字体设置是同一份。PDF 等版式文档点「A」打开 KOReader 原生设置。

## 3. 回退
- **回到旧版**：退出 KOReader，备份当前目录，删除 `plugins/wereadshelf.koplugin/`，再拷回旧版文件夹。
- **完全卸载**：退出 KOReader，删除 `plugins/wereadshelf.koplugin/`；如不保留设置，再删除 `settings/wereadshelf.lua`。
- KOReader 无法启动/设置异常：用第 0 步备份的 `settings/` 整个覆盖回去。

## 5. 出问题时请提供
`koreader/crash.log`（搜 `wereadshelf`、`simpleui`），哪一步、屏幕上的提示文字，最好一张照片。

## v0.3.4 进入 / 退出
- 开启微信读书模式后：启动 KOReader、合上书 → 直接回到书架（不再看到 SimpleUI 首页）。
- 「我」→「返回 KOReader」：本次运行留在 KOReader 文件浏览器；设置不变，下次启动仍进书架。
- 再进入：KOReader 菜单首页（☰）→「进入微信书架」，或点底栏任一 Tab，或手势「打开微信书架」。
- 彻底恢复原生：「我」→「退出到 Kindle / 恢复原生…」。
