# trainingrecord-T007 按 UI 设计 v1 实现界面（供人类试用后决定）

状态: approved（2026-11-01 人类看截图后确认 UI 没问题，批准采用）
分支: task/trainingrecord-T007（基于 task/trainingrecord-T006 审查交付的 1527f15，并已带上 frontend 的设计稿提交）
执行者: code
里程碑: 不进 m2-app。人类说「要做出来才能决定」：本单做出真实界面给人类试用；人类批准后再单独开 PR，不批准则整个分支不合并
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - App/（除 App/TrainingRecordApp.swift 外的全部视图文件，可新建、改名、删除；可新建 App/Trend/）
  - App/Assets.xcassets/（新建：DESIGN.md §1 的 Color Set 与 AccentColor）
  - project.yml（修改：仅限设置 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` 等接入 Asset Catalog 所需项）
  - docs/screenshots/trainingrecord-T007-*.png（新建）
  - 只读参考：ui/DESIGN.md、ui/index.html、ui/screenshots/（frontend 的设计稿，不得修改）

负责人: hermes

## 目标

把 frontend 的设计稿 `ui/DESIGN.md`（方向 B「健身」式）落到真实 App 里，让人类在模拟器上实际操作后决定是否采用。设计稿在浏览器打开 `ui/index.html` 可看，`ui/screenshots/` 是参考图。

DESIGN.md 当前写着「待人类批准、未批准前不得据此实现」。人类已明确指示先实现出来再决定，本单即为该指示，按本单执行。

## 验收标准

**机器可判（review 核对）：**

- [ ] `Sources/`、`Tests/`、`Package.swift` 一行不改；`swift test` 全绿（数量与 T006 交付时相同）
- [ ] `xcodegen generate` 后 Debug 与 Release 两种配置 `xcodebuild build -project TrainingRecord.xcodeproj -scheme TrainingRecord -destination 'generic/platform=iOS Simulator' -quiet` 都退出 0
- [ ] 信息架构按 DESIGN.md §7：`TabView` 三个标签「记录 / 历史 / 趋势」，图标 `square.and.pencil` / `clock.arrow.circlepath` / `chart.xyaxis.line`；趋势从历史页里移出成为独立标签，历史页不再有趋势入口
- [ ] Asset Catalog 包含 §1 中标注 Asset 名的全部颜色（`Surface2`、`Label2`、`LabelDisabled`、`AccentColor`、`OnTint`、`MetricStrength`、`MetricVolume`、`Danger`、`OnDanger`），每个都有 Any 与 Dark 两套，数值与 §1 表一致
- [ ] App/ 中不出现写死的颜色（`Color(red:`、`Color(hue:`、`#colorLiteral`、十六进制颜色字符串），不出现写死字号（`.font(.system(size:`）；唯一例外是 §2 `display` 用 `@ScaledMetric(relativeTo: .largeTitle)`
- [ ] 指标色规则：最佳 1RM 处处用 `MetricStrength`，容量处处用 `MetricVolume`；可点击元素不用指标色
- [ ] T004/T005 已有的 `accessibilityIdentifier` 保留（可迁移到新视图，但字符串值不变）；趋势标签新增：趋势页根、动作选择器、指标分段、趋势图、数据列表
- [ ] §8.2 行内错误文案与 §8.8 页面级状态文案逐字使用（「重量需为 0–1000 kg 的数字」等）
- [ ] 保存中按钮状态按 §8.1（`ProgressView` +「保存中」，按钮不可点，表单仍可编辑）
- [ ] 保存失败提示按 §8.7（不自动消失，有「重试」）
- [ ] DEBUG 截图辅助沿用 T005/T006 的做法：只在 DEBUG + 启动参数下生效；Release 产物不含这些参数
- [ ] 不实现 DESIGN.md §9 的 P1–P3（上次成绩、最近动作、复制上次训练）——它们需要改 Core，不在本单范围
- [ ] CI 兼容：部署目标 iOS 17，不用 iOS 18+ 才有的 API（例如 `Tab(...)` 新式 TabView 构造器、`.containerRelativeFrame` 以外的 iOS 18 新修饰符要先查可用性）；不用局部变量名遮蔽它调用的函数名

**人类判断（review 不判视觉）：**

- [ ] 截图与 `ui/screenshots/` 参考图对应。深色、浅色各一套，每套至少：记录（空）、记录（已填 2 个动作）、历史列表、训练明细、趋势（≥4 个点）、趋势（只有 1 个点）。文件名 `trainingrecord-T007-<页面>-<dark|light>.png`
- [ ] 额外一张 `trainingrecord-T007-dynamic-type-ax3.png`：最大辅助字号（AX3）下的记录页，证明主数字不被截断（§6）
- [ ] 交付消息里列出与设计稿不一致的地方及原因（系统控件做不到、iOS 17 限制等）

## 计划

1. 确认在 `/Users/phx/dev/TrainingRecord`、分支 `task/trainingrecord-T007`（hermes 已建好，含设计稿提交与本任务单）
2. 读 `ui/DESIGN.md` 全文，浏览器打开 `ui/index.html` 对照
3. 建 Asset Catalog → 改信息架构（三个标签）→ 逐页实现记录、历史、明细、趋势 → 各种状态
4. 构建 Debug/Release；模拟器截图（深浅两套 + AX3）
5. commit、正常 push（不 force）。**不开 PR。** 用 `message_agent` 通知 review：任务单路径、分支名、审查对比基线 `1527f15`、截图路径、与设计稿的差异清单，并回报 hermes

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|
| 1 | 通过（2 SHOULD-FIX） | 83 tests、9 色 Any/Dark 全符、隔离 XCUITest 8 项；WeekSummary 把下周一 00:00 计入本周；history.goRecordButton 在 AX 树中不存在 | 2026-11-01 |
| 2 | 通过 | 11c3983 普通 merge 带入 T006 修复 bd79293；cc00328 半开区间 + AX 容器修正；旧版/变异红、新版 9/9 绿 | 2026-11-01 |

## 升级说明

（状态为 escalated 时必填）
