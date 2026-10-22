# 微信书架 for Kindle（kindle-weread-shelf）

在越狱 Kindle Paperwhite 5 的 KOReader 上，一比一复刻**微信读书墨水屏版**的界面与体验。

## 组成
| 组件 | 版本 | 位置 |
|---|---|---|
| KOReader | v2026.07.x（kindlepw2 包） | 设备上已装 |
| weread.koplugin（微信读书登录/书架/下载/进度同步） | 1.6.0 | `vendor/weread.koplugin` |
| SimpleUI（底栏/主页框架） | 2.7.5 | `vendor/simpleui.koplugin` |
| **wereadshelf.koplugin（本项目，自研）** | **0.3.3** | `src/wereadshelf.koplugin` |

wereadshelf 提供：「发现 / 书架 / 我」3 Tab 仅图标底栏、4 列封面网格书架、发现与我页、微信读书风格阅读菜单与字体面板、一键开启微信读书模式 / 一键回原生。只读 weread 缓存，不修改其它插件和 Kindle 系统。

## 安装
1. 退出 KOReader，USB 连接 Kindle，先备份 `koreader/settings/`。
2. 把 `vendor/weread.koplugin`、`vendor/simpleui.koplugin`、`src/wereadshelf.koplugin` 三个文件夹拷到 `koreader/plugins/`。
3. 安全弹出 → KUAL 启动 KOReader → 菜单「工具 → 微信书架 → 一键开启微信读书模式」→ 重启。
4. 在微信读书插件里扫码登录并打开一次书架，让封面缓存下来。

详细步骤见 `src/INSTALL.md`，代码结构见 `src/README.md`。

## 文档与测试
- `SPEC.md` 需求，`UI-SPEC.md` 界面规范，`PLUGINS.md` 插件调研
- `src/spec/` 离线测试：`sh spec/setup_deps.sh && luajit spec/test_*.lua`
- `tests/` 测试用例与报告，`preview/` 模拟器截图

## 许可
vendor 下插件遵循各自许可证（weread.koplugin AGPL-3.0，SimpleUI GPL-3.0）。
