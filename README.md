# Real微读 for Kindle（kindle-weread-shelf）

在越狱 Kindle Paperwhite 5 的 KOReader 上，一比一复刻**微信读书墨水屏版**的界面与体验。

## 组成
| 组件 | 版本 | 位置 |
|---|---|---|
| KOReader | v2026.07.x（kindlepw2 包） | 设备上已装 |
| weread.koplugin（微信读书登录/书架/下载/进度同步） | 1.6.0 | `vendor/weread.koplugin` |
| **wereadshelf.koplugin（本项目，自研）** | **0.3.6** | `src/wereadshelf.koplugin` |

Real微读提供：自带「发现 / 书架 / 我」底部导航、4 列封面网格书架，以及微信读书风格阅读菜单和字体面板。只读 weread 缓存，不修改 weread、KOReader 或 Kindle 系统；无需安装 SimpleUI。

## 安装
1. 退出 KOReader，USB 连接 Kindle，先备份 `koreader/settings/`。
2. 把 `vendor/weread.koplugin` 和 `src/wereadshelf.koplugin` 两个文件夹拷到 `koreader/plugins/`。
3. 启动 KOReader，打开「Real微读 → 登录、同步与管理书架」完成登录和同步，再点「打开 Real微读」。

详细步骤见 `src/INSTALL.md`，代码结构见 `src/README.md`。

## 文档与测试
- `SPEC.md` 需求，`UI-SPEC.md` 界面规范，`PLUGINS.md` 插件调研
- `src/spec/` 离线测试：`sh spec/setup_deps.sh && luajit spec/test_*.lua`
- `tests/` 测试用例与报告，`preview/` 模拟器截图

## 许可
vendor 下插件遵循各自许可证（weread.koplugin AGPL-3.0；仓库内保留的 SimpleUI 仅用于旧版兼容和测试）。
