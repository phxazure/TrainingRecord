# trainingrecord-T010 历史明细去掉「最佳 1RM」

状态: approved
分支: task/trainingrecord-T010（基于 main @ 1e5f4c9）
执行者: code
里程碑: 单卡，交付: PR（review 与 CI 通过后由 hermes 合并，属人类临时授权范围）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - App/History/HistoryDetailView.swift
  - App/History/（如需同步删除只给本处用的辅助代码或 accessibilityIdentifier 常量）
  - docs/screenshots/trainingrecord-T010-*.png（新建）

负责人: hermes

## 背景（人类 2026-11-01）

> 我觉得历史里面的记录不用显示个人最佳纪录

历史 → 训练明细里，每个动作卡片右上角显示「最佳 1RM」，每组右侧显示该组估算 1RM（最佳那组用玫红高亮）。人类认为在历史记录里不需要。最佳 1RM 继续在「趋势」和「动作详情」里看。

## 验收标准

- [ ] 训练明细的动作卡片：去掉右上角「最佳 1RM」标签和数值
- [ ] 每组行：去掉右侧的估算 1RM 数值和高亮；保留序号徽章和「重量 × 次数」
- [ ] 保留：顶部汇总（容量 / 组数 / 动作）、每个动作的「容量」行、「查看动作详情」入口
- [ ] 历史列表、动作详情、趋势页不变（动作详情和趋势里的最佳 1RM 照旧显示）
- [ ] 只给这里用的代码一并删除，不留无用代码；文件头注释同步更新
- [ ] Core、Persistence、Tests、Package.swift、project.yml、.github 不改；`swift test` 全绿
- [ ] `xcodegen generate` 后 Debug、Release `xcodebuild` 都退出 0
- [ ] 已有 accessibilityIdentifier 的字符串值不变（被删控件自身的 id 除外）
- [ ] 截图：训练明细深色、浅色各一张，`trainingrecord-T010-history-detail-<dark|light>.png`（DEBUG 启动参数 + `xcrun simctl`，不用 osascript）
- [ ] CI 兼容：Xcode 26.6 / Swift 6.3，部署目标 iOS 17

## 计划

1. 在 `/Users/phx/dev/TrainingRecord` 切到 `task/trainingrecord-T010`（hermes 已建好并提交本任务单）
2. 修改、构建、截图
3. commit、正常 push（不 force），**开 PR 到 main**；通知 review：任务单路径、分支名、对比基线 1e5f4c9、PR 号、截图路径；回报 hermes
4. 自查命令不要用 `perl -e` 包裹

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|
| 1 | 通过（0/0/0） | 旧版真 UI 红、新版绿；动作详情最佳 1RM 仍在；Core 215 + Persistence 42；PR CI run 41268034691 双绿（Xcode 26.6，257 tests） | 2026-11-01 |

## 升级说明

（状态为 escalated 时必填）
