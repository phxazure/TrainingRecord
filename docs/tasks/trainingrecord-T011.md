# trainingrecord-T011 装入 App 图标（方向 B）+ 显示名「训练记录」

状态: approved
分支: task/trainingrecord-T011（基于 ui/app-icon-v1 的 ba4c173，含 frontend 交付与人类批准）
执行者: code
交付: PR（单独开 PR，review 通过后 hermes 开）
降级预案: 无（无高风险机制）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - App/Assets.xcassets/AppIcon.appiconset/（新建，从 ui/icon/trend/AppIcon.appiconset/ 原样复制，文件不改）
  - project.yml（只改：ASSETCATALOG_COMPILER_APPICON_NAME 设为 AppIcon 并删掉「目前没有 App 图标」注释；新增显示名设置）
  - docs/screenshots/trainingrecord-T011-*.png（新建）

负责人: hermes

## 目标

人类 2026-11-01 选定图标方向 B（趋势），主屏显示名改为「训练记录」。按 ui/DESIGN.md §11.5 装进 App。

## 验收标准

- [ ] appiconset 与 ui/icon/trend/AppIcon.appiconset 逐字节一致（`diff -r` 无输出）
- [ ] 主屏显示名为「训练记录」：用 `INFOPLIST_KEY_CFBundleDisplayName`；构建产物 Info.plist 里 `CFBundleDisplayName` = 训练记录（`plutil -p` 证据）；`CFBundleName`、Bundle ID 不变
- [ ] Debug、Release `xcodebuild` 都退出 0，无图标相关警告；`xcrun assetutil --info` 证明产物 Assets.car 含 AppIcon 的 Any、Dark（UIAppearanceDark）、Tinted（ISAppearanceTintable）
- [ ] `swift test` 全绿，测试数不变；`Sources/`、`Tests/`、`App/` 下其他文件不改
- [ ] CI 兼容：Xcode 26.6 构建通过（以 PR 的 CI 为准）
- [ ] 截图（尽力，限时 15 分钟，做不到就报告，不算失败）：模拟器主屏浅色、深色各一张，看得到图标和名字。方法：`xcrun simctl ui booted appearance light|dark` + 结束 App 回主屏 + `xcrun simctl io booted screenshot`；不用 osascript。着色模式需手动操作，不要求

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|
| 1 | 通过（0/0/0） | 图标逐字节一致；Debug/Release 产物显示名「训练记录」、名称与 Bundle ID 不变；Assets.car 含 Any/Dark/Tinted；回退基线时验收探针变红；257 测试。hermes 裁定接受：深色主屏截图仍为浅色图标（主屏图标风格是独立设置，截图属尽力项）；Xcode 26.6 以 CI 为准 | 2026-11-01 |
