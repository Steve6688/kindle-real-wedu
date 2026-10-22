# wereadshelf.koplugin v0.3.3 回归测试报告
日期：2026-10-21 23:55（UTC+8）。未修改任何功能代码。

## 离线测试
42 + 74 + 71 + 35 = **222/222 通过**。补回的 SCX 用例在 test_logic.lua:86，断言「思源黑体 SCX」，通过。

## NEW-04 / NEW-02 复核：均关闭，无回归
font_label 边界穷举（luajit 直接调用）：
- 地区码：SC / TC / JP / KR / HK / K → 「思源黑体 SC」等；SCX →「思源黑体 SCX」，不会被误拆。
- 字重：SC Bold / Medium / Light、TC Black → 保留，如「思源黑体 SC Bold」；"CJK Bold"（无地区码）→「思源黑体 Bold」。
- Regular：结尾的 " Regular" 和 "-Regular" 去掉；在中间的保留（"SC Regular Italic"→「思源黑体 SC Regular Italic」）。单独一个 "Regular" 保持原样。
- 纯拉丁字体："Noto Serif"、"Noto Serif Regular"→「Noto Serif」，"Foo-Regular"→「Foo」，"Something KR" 保持不变。
- 其它：霞鹜文楷 Mono、Droid 黑体正常。

小问题（P3，不单独立 bug）：
- REGIONS 表已不再使用，是死代码。
- 原名里的连续空格会被保留（"SC  Bold"）。
- "Noto Sans CJKSC" 显示为「思源黑体 SC」，这种无空格写法实际不存在。

## 模拟器
程序员的 preview/ 已备份到 tests/preview-dev-v0.3.3-234958/。第一次运行被中断，已先还原再重跑。第二次 EXIT 0，输出存到 tests/preview-tester-run-v0.3.3/，然后把程序员的 7 张图还原到 preview/，逐一 cmp 一致。
字体面板图：「Noto Serif」为黑底（当前字体），「思源黑体 SC」为灰底，「强制首行缩进」胶囊和 4 条滑杆正常，与 v0.3.2 一致。

## 用例（可离线 17 条）
PASS 12 / FAIL(已知限制) 5（TC-05/22/24/28/30）。
全部 37 条：PASS 12 / 真 bug FAIL 0 / 已知限制 5 / 待真机 20。
