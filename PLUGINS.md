# KOReader 微信读书复刻 — 插件调研（2026-10-21）

目标设备：Kindle Paperwhite 5，固件 5.16.2.1.1（已越狱，不升级）。所有组件仅放在 `/mnt/us/koreader/`（USB 根目录 `koreader/`）下，不改 Kindle 系统。
源码只读克隆在 `vendor/`：weread.koplugin@ae3930f(2026-10-18)、miuread-koreader@8aac230(2026-10-08, v6.0.0)（simpleui.koplugin 快照已于 0.3.7 删除；Real微读不再使用 SimpleUI，下文为早期调研记录）。

## 1. KOReader 本体
- 最新稳定版：**v2026.07.2**（构建 2026-10-13）。
- PW5 + 5.16.2.1.1 应使用 **`koreader-kindlepw2-v2026.07.2.zip`**（kindlepw2 = PW2 及以上、固件 ≤5.16.2.1.1；`kindlehf` 仅用于 ≥5.16.3，**不要选错**）。
- 安装：zip 解压到 Kindle USB 根，使 `koreader/` 和 `extensions/` 在根下 → 需已装 KUAL（KindleModding 推荐 KUAL/KUALA 启动器）→ KUAL 里 “KOReader → Start KOReader”（内存紧可用 “no framework” 模式，退出较慢）。
- 退出回原生：KOReader 菜单 → 退出（Exit）即回 Kindle 主界面；`extensions/` 是 KUAL 菜单项，不改系统。"no framework" 模式退出会重启 Kindle 框架。
- 插件要求：weread.koplugin 建议 KOReader ≥2026.03；ZenOS 需 ≥2026.03；Project: Title 严格绑定 KOReader 版本（最新 v3.8.3 适配 2026.07/.01/.02）。

## 2. 微信读书插件

| 项目 | finlater/weread.koplugin | miumiupy98-art/miuread-koreader（觅阅 MiuRead） |
|---|---|---|
| 链接 | https://github.com/finlater/weread.koplugin | https://github.com/miumiupy98-art/miuread-koreader |
| 最新版本 | v1.6.0（2026-10-05 发布；main 最新提交 2026-10-18） | v6.0.0 Stable（tag 提交 2026-10-08） |
| 许可证 | AGPL-3.0 | AGPL-3.0-only（源自 finlater v0.1.1 的分叉，大幅重构） |
| 热度 | ~900 star，38 open issues | ~650 star，18 open issues |
| 登录 | 仅**微信扫码**；前置条件：手机微信读书 App「我→设置→微信读书 Skill→获取 API Key」；可能需输入 4 位验证码；v1.6 支持多设备登录 | 扫码；README 写明“登录与书架管理授权是两套独立凭证，不是单扫码统一” |
| 拉书架 | 能（代码中 `/shelf/sync`） | 能，并可加入/移出微信书架 |
| 正文 | 能下载：按章、多选章节、预下载下一章、整书下载，生成本地书用 KOReader 阅读；公众号文章 | 能下载（EPUB 安全替换等） |
| 进度同步 | 能：进度同步 + 阅读时长上报/统计；v1.6 加了“立即同步进度”手势 | 能：“精确进度同步、云端/本地可信锚点、已读完状态同步” |
| 划线/想法 | **拉取并展示**（`/book/underlines`、想法弹窗），本地书也能匹配；代码中未找到上传划线到微信读书的接口 → 写回：查不到/看起来不支持 | 支持“划线与想法”（README 未明确说写回，查不到确证） |
| 书城/搜索/排行 | 搜索书籍、书评、书籍详情 | 书城：推荐、**排行榜**、分类、全库搜索、相似推荐 |
| 听书 | 查不到 | 查不到 |
| Kindle 支持 | README 明确支持 Kindle/Kobo 等 | 名称即“适用于 Kindle” |
| UI 集成 | 提供 SimpleUI 快捷操作 / ZenOS 底栏按钮入口 | 自带主页推荐快捷栏、控制中心入口 |
| 已知问题 | 旧版 KOReader 菜单找不到插件（#14）；部分书正文/脚注异常（1.4.x 修复）；脚注改动后需重下书 | 发行说明强调需真机验证；双凭证 |

## 3. 美化插件

| 项目 | 链接 / 版本 / 许可 | 能做什么 | 底部导航 | 书架网格 |
|---|---|---|---|---|
| SimpleUI | https://github.com/doctorhetfield-cmd/simpleui.koplugin ，v2.7.5（2026-10-04），GPL-3.0 | 主页（在读、最近、集合、目标、统计、快捷操作）、**底部导航栏最多 5 个 Tab**、顶栏、Flat Library 网格；按元素字体字号；启动时自动禁用不兼容插件 | ✅ | ✅（Flat Library / Collections 封面网格） |
| ZenOS（原 Zen UI） | https://github.com/AnthonyGress/zen_ui.koplugin ，v3.1.0（2026-08-23），文档 https://zen-labs.org/zen-os/docs/installation | Navbar 底栏、Home Book Strip、Launcher、书籍详情、图标包；**会自动禁用 SimpleUI 等**，与 Project: Title 冲突 | ✅ | ✅ |
| Project: Title | https://github.com/joshuacant/ProjectTitle ，v3.8.3（2026-08-03，适配 KOReader 2026.07.x） | 替换 Cover Browser 文件浏览器：封面网格/列表、排序、顶部工具栏 | ❌（查不到底栏） | ✅ |

注意三者互斥/冲突：ZenOS 与 PT 冲突且会关掉 SimpleUI；只选一个。

## 4. MVP 能力表

| MVP | weread.koplugin | MiuRead | SimpleUI | ZenOS | PT | 结论 |
|---|---|---|---|---|---|---|
| 1 账号登录、书架同步 | ✅ 扫码+Skill API Key | ✅（双凭证） | — | — | — | 能做 |
| 2 打开书阅读、进度回传 | ✅ 下载后读 + 进度/时长上报 | ✅ 精确同步 | — | — | — | 能做 |
| 3 首页/书架布局靠拢官方 | 部分：自有书架列表 | 部分：自有主页 | 部分：底栏+网格+入口，但书架网格是本地书，不是“微信书架”数据 | 部分：同左 | 部分：仅网格 | **部分能做**，一比一需自写 |
| 4 字体字号行距可调且持久 | KOReader 原生（底部菜单字体/字号/行距，按书或全局默认保存） | 同 | 主页 UI 字体 | — | — | 能做（原生） |
| 5 一键回 Kindle 原生 | — | — | — | — | — | KOReader 原生“退出”即可；“一键”可用手势/快捷操作绑定 Exit（部分） |
| 二期 划线想法同步 | 拉取✅ / 写回查不到 | 部分 | | | | 部分 |
| 二期 书城搜索 | 搜索✅ | 书城+搜索✅ | | | | 能做 |
| 二期 听书 | 查不到 | 查不到 | | | | 做不到（无现成） |
| 二期 排行榜 | 查不到 | ✅ | | | | MiuRead 能做 |
| 二期 时长统计 | ✅ 上报+统计 | ✅ | 阅读统计卡 | | | 能做 |

## 5. 推荐组合
**KOReader v2026.07.2（kindlepw2 包，KUAL 启动） + finlater/weread.koplugin v1.6.0 + SimpleUI v2.7.5。**
理由：weread.koplugin 是上游、更新最勤、官方文档写了 SimpleUI 集成（快捷操作 → 插件 → 微信读书、图标放 `koreader/settings/simpleui/sui_icons`）；SimpleUI 提供底部导航与网格。备选：需要书城/排行榜时评估 MiuRead（二者同源，**不要同时启用**以免凭证/数据冲突，未验证是否共存）。不同时装 ZenOS/PT。

## 6. 需要自己补写
1. 一个“官方风格”主页/书架视图：把微信书架数据（weread 插件的 library_db/封面缓存）渲染成网格，并作为 SimpleUI 的一个 Tab 或模块（SimpleUI 原生网格只读本地文件）。
2. 底部导航 Tab 配置与图标：书架 / 书城(搜索) / 我的(统计)，对齐官方墨水屏版。
3. 阅读页菜单定制：KOReader 顶/底菜单裁剪为官方样式（可能需 user patch 放 `koreader/patches/`）。
4. 字体包与默认排版预设（中文字体放 `koreader/fonts/`，写默认 settings），保证持久。
5. “一键回原生”：手势或 SimpleUI 快捷操作绑定 Exit；可选 KUAL 菜单脚本。
6. 二期：划线/想法写回微信读书（现有插件看起来只读）、听书（无现成实现）、排行榜（可移植 MiuRead 的，注意 AGPL）。

## 7. 风险
- 接口变化：两插件依赖微信读书非公开/Skill 接口，随时可能失效；需锁定版本并关闭自动更新或先验证再更新。
- 账号风险：README 免责声明明说可能封号；建议使用小号测试、控制请求频率。
- 版权/许可：下载正文到本地仅限个人学习；插件为 AGPL，修改后分发须开源同协议；不得商用。
- 兼容性：Project: Title 绑定 KOReader 小版本；SimpleUI/ZenOS 会自动禁用“不兼容插件”，可能误关 weread 入口，需实测；PW5 内存有限，多插件后台预下载需关注。
- 固件：选错 kindlehf 包将无法运行；不升级固件以免越狱失效。

## 8. 来源
- https://github.com/finlater/weread.koplugin ， https://github.com/finlater/weread.koplugin/releases
- https://github.com/miumiupy98-art/miuread-koreader
- https://github.com/doctorhetfield-cmd/simpleui.koplugin ， https://github.com/doctorhetfield-cmd/simpleui.koplugin/releases/
- https://github.com/AnthonyGress/zen_ui.koplugin/releases/tag/v3.1.0 ， https://zen-labs.org/zen-os/docs/installation
- https://github.com/joshuacant/ProjectTitle/releases
- https://build.koreader.rocks/download/stable/2026.07.2/
- https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices
- https://kindlemodding.org/jailbreaking/post-jailbreak/koreader.html

## 9. 三句话结论
MVP 的登录、书架同步、阅读与进度回传、字体持久和退出回原生，用 KOReader 2026.07.2（kindlepw2 包）+ weread.koplugin v1.6.0 即可直接实现。首页/书架“一比一”只有 SimpleUI 能提供底栏与网格骨架，微信书架网格和阅读页菜单需要我们自写 SimpleUI 模块/用户补丁。二期中书城、排行、时长已有现成（MiuRead/weread），划线写回和听书查不到现成实现，且整体面临接口变动与封号风险。
