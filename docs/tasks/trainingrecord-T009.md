# trainingrecord-T009 动作库界面 + 四标签 + 层级下钻

状态: planned
分支: task/trainingrecord-T009（基于 task/trainingrecord-T008 审查通过的 b3f4fdf，堆叠开发）
执行者: code
里程碑: m3-library（T008 数据层 → T009 界面；两单都通过后 hermes 开一个 PR 到 main）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - App/（全部视图文件，可新建、改名、删除；App/TrainingRecordApp.swift 可改）
  - App/Assets.xcassets/（仅限新增界面需要的资源；已有 9 个颜色数值不改）
  - Sources/TrainingRecordCore/（只新增文件；另可修改 WorkoutDraft.swift，仅限给 ExerciseDraft 加 exerciseID）
  - Tests/TrainingRecordCoreTests/（只新增文件）
  - docs/screenshots/trainingrecord-T009-*.png（新建）
  - 只读参考：ui/DESIGN.md（颜色、字号、间距、圆角、状态的 token 继续以它为准）

负责人: hermes

## 人类的要求（2026-11-01，逐条）

1. 底部四个标签：**训练**（原「记录」改名）、**动作库**、**历史**、**趋势**
2. **多用二级界面（点进去），少用切换**：不用分段控件/Picker 在同一页切换内容
3. 趋势：第一屏列出整体训练趋势和全部动作（一行一个）；点某个动作进去看该动作的数据
4. 动作库：不预置动作；可设名字、训练部位、照片；按部位分组；可修改（改名同步历史与趋势——T008 已实现）
5. 训练页**不显示「上次成绩」**
6. 「合并」定位为**合并记录**，界面要讲清楚它是干什么的
7. 设计稿 §9 的「最近动作」「复制上次训练」要做
8. 其余由 hermes / 执行者按 DESIGN.md 决定，做出来给人类试用后再改

## 信息架构（hermes 定稿）

```
TabView
├─ 训练   square.and.pencil     NavigationStack「训练」
│   ├─ 空状态：「复制上次训练（日期 · 动作名…）」次要按钮（P3）
│   ├─ 最近动作胶囊行（最多 6 个，横向滚动；已在本次训练里的置灰）（P2）
│   ├─ 动作卡片（沿用 T007）
│   └─ 「添加动作」→ push「选择动作」：按部位分组 + 搜索 + 「新建动作」
├─ 动作库  dumbbell             NavigationStack「动作库」
│   ├─ 按部位分组列表（行：照片缩略图或占位图标、名字、记录次数）；右上「+」新建
│   └─ 点行 → push「动作详情」
├─ 历史   clock.arrow.circlepath NavigationStack「历史」
│   └─ 训练列表 → 训练明细 → 点某个动作 → push「动作详情」
└─ 趋势   chart.xyaxis.line      NavigationStack「趋势」
    ├─ 第一屏：整体趋势卡片 + 动作列表（行：名字、部位、最近一次最佳 1RM、较上一次变化箭头）
    └─ 点行 → push「动作详情」
```

**动作详情**（四处入口共用同一个视图）：
- 照片（无则占位图标）、名字、部位
- 最佳 1RM 折线图、容量折线图**上下并列**（不切换），下面是按日期倒序的数据列表
- 最近几次记录（每次：日期 + 各组 重量×次数）
- 工具栏「编辑」→ push 编辑页（名字、部位、照片）
- 编辑页底部：「合并记录到其他动作…」「删除动作」

## 验收标准

### 机器可判（review 核对）

Core（只新增文件，`swift test`）：
- [ ] 整体趋势：按周聚合（周一 00:00 起，半开区间，与 WeekSummary 一致），最近 N 周（默认 12）每周训练次数与总容量；空周补 0；用固定日历/时区的测试覆盖跨周边界、空周、N 周之外的数据不计入
- [ ] 动作列表摘要：每个动作最近一次的最佳 e1RM（复用 T003 的 Epley 与舍入）以及与上一次的差值（上升/下降/持平/无上一次）；按最近使用日期降序；只含动作库里存在的动作；有测试
- [ ] 若给 `ExerciseDraft` 加 `exerciseID`：T004 已有测试照常通过
- [ ] T001–T008 已有测试文件一字不改，全部通过

App：
- [ ] TabView 四个标签，名称与 SF Symbol 按上图；「训练」标签沿用原 `record.*` 的 accessibilityIdentifier 字符串值（只改显示名）
- [ ] 全 App 不出现用分段控件/Picker 切换**页面内容**的写法（表单里选值的 Picker，如部位选择，不算）；T007 趋势页的动作 Picker 和「最佳 1RM / 容量」分段已移除
- [ ] 动作详情是一个共用视图，从训练页（选择动作时可预览可不做）、动作库、历史明细、趋势四处中的后三处必须能 push 进入同一视图
- [ ] 新建/编辑动作：名字必填；部位从常用列表选（胸、背、肩、手臂、腿、臀、核心、全身、有氧）或输入自定义；重名就地提示（文案「动作库里已有「X」」）；保存调用 T008 的 `ExerciseLibraryService`
- [ ] 照片：`PhotosPicker` 选图（iOS 17 可用），缩放到长边 ≤ 1024px、JPEG 质量 0.8，存到 Application Support/ExercisePhotos/<动作 id>.jpg；`photoFileName` 只存文件名；换照片、删照片、删动作时删除旧文件；有「移除照片」
- [ ] **合并记录**：编辑页里叫「合并记录到其他动作…」；点开后先选目标动作，再弹确认，确认文案逐字为：
      「把「源动作」的 N 次训练记录并入「目标动作」，之后「源动作」会从动作库删除。适用于同一个动作被记成了两个名字。此操作不能撤销。」
      （N = 源动作出现的训练场次数）。按钮「合并」（破坏性样式）/「取消」
- [ ] **删除动作**：没有记录时确认后删除；有记录时不允许删除，提示「「X」有 N 次训练记录，不能直接删除。如果它和另一个动作是同一个，可以用「合并记录」。」
- [ ] 改名/合并/删除后，历史、趋势、训练页的数据立即反映（返回或切标签后重新加载即可）
- [ ] 训练页：不显示上次成绩；「最近动作」与「复制上次训练」按上图，数据来自 T008 的 `recentExercises` / `lastSessionTemplate`；`lastSessionTemplate` 为 nil 时不显示该按钮
- [ ] 回填失败时（App 启动的 backfill 抛错）界面给出可见提示（训练页顶部一行提示即可）
- [ ] DEBUG 截图辅助：只在 DEBUG + 启动参数下生效；样例数据写完后**再调用一次 backfill**，保证样例条目有动作库 id；新增「预填动作库（含 1 张示例照片）」的启动参数；Release 产物不含任何这些参数
- [ ] 新视图关键控件都有 accessibilityIdentifier（动作库列表、行、新建按钮、动作详情根、两张图、编辑按钮、合并入口、删除入口、选择动作页、搜索框、最近动作胶囊、复制上次训练按钮、趋势第一屏整体卡片、趋势动作行）
- [ ] 颜色、字号走 DESIGN.md token：最佳 1RM 用 MetricStrength、容量用 MetricVolume、可点元素用 tint；不写死颜色和字号
- [ ] `xcodegen generate` 后 Debug、Release `xcodebuild` 都退出 0；`swift test` 全绿
- [ ] CI 兼容：Xcode 26.6 / Swift 6.3、部署目标 iOS 17；不用 iOS 18+ API（例如新式 `Tab(...)` 构造器、`.navigationTransition(.zoom)` 等）；不用局部变量遮蔽同名函数
- [ ] 不改 `project.yml`、`Package.swift`、`.github/`（本机令牌也推不上 workflow 改动）

### 人类判断（review 不判视觉）

- [ ] 截图（深色、浅色各一套）：训练（空状态含复制上次训练 + 最近动作）、训练（已添加动作）、选择动作页、动作库列表、动作详情（带照片）、动作编辑页、合并记录确认弹窗、删除被拒提示、历史明细→动作详情、趋势第一屏、趋势→动作详情；加 AX3 一张（动作详情）。文件名 `trainingrecord-T009-<页面>-<dark|light>.png`
- [ ] 交付消息列出：自己做的设计决定、与 DESIGN.md 不一致处、没能验证的状态

## 计划

1. 在 `/Users/phx/dev/TrainingRecord` 切到 `task/trainingrecord-T009`（hermes 已建好并提交本任务单）
2. Core 两个聚合函数：先测后写
3. 四标签与导航骨架 → 动作库与动作详情 → 训练页（选择动作、最近动作、复制上次训练）→ 趋势第一屏 → 历史接入动作详情 → 照片 → 合并与删除 → 回填提示
4. 构建 Debug/Release；模拟器截图（方法：DEBUG 启动参数直达目标状态 + `xcrun simctl launch` + `xcrun simctl io booted screenshot`；不要用 osascript）
5. commit、正常 push（不 force）。**里程碑模式：不开 PR。** 通知 review：任务单路径、分支名、对比基线 b3f4fdf、截图路径、设计决定清单；回报 hermes
6. 自查命令不要用 `perl -e` 包裹

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
