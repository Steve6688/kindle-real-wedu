# Real微读（wereadshelf.koplugin）安装说明 — v0.4.0

适用：KOReader v2026.07.1（Kindle PW5）。**0.4.0 已内置 weread.koplugin 1.6.0（AGPL-3.0），只需装这一个插件。****不需要 SimpleUI。**
内置的微信读书沿用原设置 `settings/weread.lua` 与数据目录 `weread/`：**登录、Cookie、缓存、已下载的书和设置全部保留，不用重新登录。** 本插件自己的设置在 `settings/wereadshelf.lua`。

## 0. 先备份（必做）
USB 连接 Kindle，把整个 `koreader/settings/` 复制到电脑，例如 `settings.bak-20261021/`。
其中含 `weread.lua`（登录凭据）等重要数据。

## 1. 全新安装 / 从 v0.1、v0.2 升级
1. 完全退出 KOReader（菜单 → 退出），USB 连电脑。
2. **删除 `koreader/plugins/weread.koplugin/`**（已内置；若忘了删，Real微读会自动停用它，不会出现两个菜单），再删除旧的 `koreader/plugins/wereadshelf.koplugin/`（升级时），再把本仓库 `src/wereadshelf.koplugin/` **整个文件夹**拷过去：
```
koreader/plugins/wereadshelf.koplugin/
    _meta.lua  main.lua  wereadshelf_data.lua  wereadshelf_layout.lua  wereadshelf_grid.lua
    wereadshelf_logic.lua  wereadshelf_ui.lua  wereadshelf_pages.lua  wereadshelf_readermenu.lua  wereadshelf_fastdl.lua
    rweread/  (内置 weread.koplugin 1.6.0：lib/ ui/ integrations/ icons/ fonts/ LICENSE NOTICE)
    icons/  (21 个 svg：tab_*、rm_*、bookmark*、more、back_chevron、chevron_right、refresh、search、import、select、wereadshelf)
```
（`src/spec/` 是电脑上的测试和预览工具，**不要拷**。）
3. **从 0.3.6 或更早升级：删除 `koreader/plugins/simpleui.koplugin/`**（0.3.7 起不再使用 SimpleUI；残留也不会出错，但会多一套无用菜单）。如需清理，可一并删除 `koreader/settings/simpleui/`。
4. 安全弹出 → KUAL 启动 KOReader → 插件管理确认「Real微读」已勾选，版本 0.3.8。
5. 首次使用需在 ☰ Real微读 → 微信读书功能 里扫码登录（已登录过的保持登录）；确保打开过一次书架（联网），让它缓存书架和封面——本插件只显示这份缓存。

启动 KOReader 后**直接进入 Real微读**（装好即开启，无需任何设置）。第一次使用在书架点「导入」或 我 → 书架同步。

## 2. 使用
- **「我」页**：数据卡（点卡片刷新本周阅读）、阅读时长统计、我的笔记、书架同步、阅读设置、退出到 Kindle、返回 KOReader。
- **阅读设置**（我 → 阅读设置，或 ☰ → 工具 → Real微读 → 阅读设置…）：Real微读阅读菜单、快速下载、流畅翻页、KOReader 设置。
- **书架**：所有「书架」入口（含微信读书插件自己的书架、登录/同步之后）都打开 Real微读书架。
- **打开**：自动。离开后：KOReader 菜单 ☰ 第一项「进入 Real微读」，或手势「打开 Real微读」。
- **返回 KOReader**：我 → 返回 KOReader（仅本次，下次启动仍进 Real微读）。
- **登录或同步**：我 → 书架同步（也可：KOReader 菜单 → 工具 → Real微读）。
- **书架**：4 列封面网格（PW5 每页 8 本）。点封面即可阅读或进入书籍详情；可滑动或用翻页键翻页，搜索框支持书架内筛选和微信读书搜索。
- **阅读菜单**（默认开启）：阅读时点屏幕中部 → 顶栏（‹ 章节名=返回书架、书签、⋯更多）+ 底栏 5 图标：返回 / 目录 / 进度跳转 / 亮度 / 字体。点菜单外区域关闭。⋯ 里有：添加/删除书签、书签列表、搜索全书、书籍详情、刷新屏幕、KOReader 原生菜单。
- **字体面板**：底栏「A」→ 字体设置面板（与 0.3.3 相同）：字号、粗细、行距、边距 4 条滑杆（点 −/+ 或点滑杆位置），首行缩进开关，字体按钮（只显示设备上已装的中文字体）。改动按本书保存，与 KOReader 原生字体设置是同一份。PDF 等版式文档点「A」打开 KOReader 原生设置。

## 3. 回退
- **回到旧版**：退出 KOReader，备份当前目录，删除 `plugins/wereadshelf.koplugin/`，再拷回旧版文件夹。
- **完全卸载**：退出 KOReader，删除 `plugins/wereadshelf.koplugin/`；如不保留设置，再删除 `settings/wereadshelf.lua`。
- KOReader 无法启动/设置异常：用第 0 步备份的 `settings/` 整个覆盖回去。

## 5. 出问题时请提供
`koreader/crash.log`（搜 `wereadshelf`），哪一步、屏幕上的提示文字，最好一张照片。
