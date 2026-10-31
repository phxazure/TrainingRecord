# trainingrecord-T006 本地持久化（SwiftData）+ 中文本地化

状态: planned
分支: task/trainingrecord-T006（基于 task/trainingrecord-T005 审查通过的 e5f7454，堆叠开发）
执行者: code
里程碑: m2-app（T004 → T005 → T006，三单完成后由 hermes 开一个 PR 到 main）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - Package.swift（修改：新增 library/target `TrainingRecordPersistence` 与测试 target）
  - Sources/TrainingRecordPersistence/（新建目录，文件数不限）
  - Tests/TrainingRecordPersistenceTests/（新建目录，文件数不限）
  - project.yml（修改：App 依赖新 product；声明中文为开发语言）
  - App/TrainingRecordApp.swift（修改：改用持久化仓储）
  - App/ContentView.swift（修改：仅删除 `.environment(\.locale, …)` 临时修补及其注释）
  - docs/screenshots/trainingrecord-T006-*.png（新建）

负责人: hermes

## 目标

1. 训练记录存到手机本地，App 退出、重启后数据还在。用 SwiftData 实现 `WorkoutRepository`，放在新的 SwiftPM target `TrainingRecordPersistence`（依赖 Core，可 `import SwiftData`），**不放 App target**，这样能用 `swift test` 在 macOS 上无模拟器测试。Core 保持不依赖任何 UI/持久化框架。
2. 正式修复日期显示英文：App 声明中文为开发语言，去掉 T004 在 ContentView 里的 `.environment(\.locale, zh-Hans)` 临时修补。

hermes 已实测：新 target 内 `@Model` + `@ModelActor` + `ModelConfiguration(isStoredInMemoryOnly: true)` 在本项目的 `swift test`（macOS 14 目标）下可编译运行。

## 验收标准

**签名按此**（可微调，交付消息里列出最终签名）：

```swift
// TrainingRecordPersistence
public actor SwiftDataWorkoutRepository: WorkoutRepository {   // 推荐 @ModelActor
    /// 内存模式（测试用）
    public static func inMemory() throws -> SwiftDataWorkoutRepository
    /// 磁盘模式，url 为存储文件位置
    public static func onDisk(url: URL) throws -> SwiftDataWorkoutRepository
}
```

仓储行为（与 `InMemoryWorkoutRepository` 完全一致，`WorkoutRepository` 文档注释即规范）：
- [ ] 空仓储 `allSessions() == []`，`session(id:)` 返回 nil
- [ ] 保存后读回的 `WorkoutSession` 与原值 `==`：包括 id、date、动作顺序、组顺序、每组重量（含小数）与次数、动作名
- [ ] 同 id 再保存为覆盖，不产生第二条
- [ ] `allSessions()` 按 date 降序；date 相同按 `id.uuidString` 升序；用乱序写入验证
- [ ] `delete(id:)` 删除目标、保留其余；删除不存在的 id 静默成功
- [ ] 并发 100 次保存不同 session 后 count == 100（`withThrowingTaskGroup` 且 `try await group.waitForAll()`）
- [ ] **持久性**：用临时目录下的文件 `onDisk(url:)` 保存若干条 → 释放该实例 → 用同一 url 新建实例 → 读回全部相等；测试结束删除临时目录
- [ ] 动作、组的顺序在持久化后不变（SwiftData 关系默认无序，必须显式保存顺序或整体编码，并有测试锁定）
- [ ] 建议：把 Core 已有的仓储行为测试抽成可对两种实现都跑的共享用例；若不抽，至少上面每条都对 SwiftData 实现有测试
- [ ] 测试不能恒真。review 会做变异：覆盖改为新增、排序反转、次级排序去掉、组顺序打乱、delete 不生效、重开后读不到 —— 每一种至少让一个测试变红

App 接入：
- [ ] `TrainingRecordApp` 改用 `SwiftDataWorkoutRepository.onDisk(url:)`，存储位置在 Application Support 下（目录不存在时创建）
- [ ] 打开存储失败时不崩溃：退回内存仓储，并在界面给出可见提示（文案自定，如「无法打开本地数据，本次记录不会保存」）
- [ ] DEBUG 截图用的样例数据启动参数仍然只写入内存仓储，不得写进真实的本地存储
- [ ] 模拟器实测重启：保存 1 次训练 → 终止 App（`xcrun simctl terminate`）→ 重新启动 → 「历史」里仍能看到。截图 `trainingrecord-T006-after-relaunch.png`

本地化：
- [ ] `project.yml` 设置开发语言为中文（`options.developmentLanguage: zh-Hans`，并让生成的 Info.plist 的 `CFBundleDevelopmentRegion` 为 `zh-Hans`）
- [ ] 删除 ContentView 的 `.environment(\.locale, …)` 后，**模拟器系统语言为英文时**（`xcrun simctl spawn <udid> defaults write -g AppleLanguages '(en)'` 后重启模拟器）日期仍显示中文；截图 `trainingrecord-T006-en-device.png` 证明。截完把模拟器语言恢复为 `zh-Hans`
- [ ] 若仅改开发语言不足以让系统选中文，可以加一个最小的中文本地化资源让 App 声明支持 zh-Hans；不得为此加英文本地化

通用：
- [ ] Core（`Sources/TrainingRecordCore`）一行不改；T001–T005 的测试不改；`swift test` 全绿
- [ ] `xcodegen generate` 后 `xcodebuild build -project TrainingRecord.xcodeproj -scheme TrainingRecord -destination 'generic/platform=iOS Simulator' -quiet` 退出 0（Debug 和 Release 都要）
- [ ] CI 兼容：CI 用 Xcode 26.6 / Swift 6.3，比本机旧。不要用局部变量名遮蔽它调用的函数名；不用 iOS 18+ / macOS 15+ 才有的 API（包括 SwiftData 在 iOS 18 才加的 `#Index`、`#Unique`、`HistoryDescriptor` 等）
- [ ] 不改 `.github/`，不引入第三方依赖

## 计划

1. 确认在 `/Users/phx/dev/TrainingRecord`、分支 `task/trainingrecord-T006`（hermes 已建好并提交本任务单）
2. 先写持久化测试 → 变红；再实现 → 全绿
3. 接入 App，处理打开失败；改 project.yml，去掉 locale 修补
4. 构建；模拟器实测重启和英文系统两项，截图
5. commit、正常 push（不 force）。**里程碑模式：不开 PR。** 用 `message_agent` 通知 review：任务单路径、分支名、审查对比基线 `e5f7454`、最终签名、截图路径，并回报 hermes

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
