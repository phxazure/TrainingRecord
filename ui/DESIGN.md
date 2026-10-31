# TrainingRecord 设计规范 v1 —— 方向 B「健身」式

状态：待人类批准（未批准前 code / code-local 不得据此实现）
设计稿：`ui/index.html`（浏览器直接打开；右上角切换深色 / 浅色）
截图：`ui/screenshots/`

## 0. 原则

1. 只用 iOS 系统结构：`TabView`、`NavigationStack`、`List(.insetGrouped)`、`Picker`、`DatePicker`、`ContentUnavailableView`、`swipeActions`、Swift Charts。不自造导航、不自造控件。
2. 世界观只通过四样东西进入：圆体数字、指标色、深色优先、一个签名动作。
3. **签名动作：指标色即身份。** 「最佳 1RM」永远是 `metric-strength`（玫红），「容量」永远是 `metric-volume`（青）。同一个数字在列表、明细、趋势里颜色一致——用户看颜色就知道看的是哪种量。
4. 交互色（按钮、开关、选中）只有一个：`tint`（荧光绿）。指标色不用于可点击元素；`tint` 不用于数据。
5. 深色优先（像「健身」），浅色完整可用，跟随系统，不提供 App 内开关。

## 1. 颜色

所有颜色在 Asset Catalog 建 Color Set（Any / Dark 两套），名字即下表 token 名。表中未列 Asset 名的直接用系统色。
对比度为实测值（WCAG 2.x），基准是该 token 实际所在的底色。

| token | 用途 | 深色 | 浅色 | SwiftUI | 对比度（深 / 浅） |
|---|---|---|---|---|---|
| `bg` | 页面底 | `#000000` | `#F2F2F7` | `Color(.systemGroupedBackground)` | — |
| `surface` | 卡片 / 分组行 | `#1C1C1E` | `#FFFFFF` | `Color(.secondarySystemGroupedBackground)` | — |
| `surface-2` | 输入框底、序号徽章、禁用填充 | `#2C2C2E` | `#E5E5EA` | `Color(.tertiarySystemFill)` 不够深，**用 Asset `Surface2`** | — |
| `label` | 主文字 | `#FFFFFF` | `#000000` | `.primary` | 17.9 / 21 |
| `label-2` | 次文字、占位符、单位 | `rgba(235,235,245,.60)` | `#636366` | 深色 `.secondary`；浅色系统 `.secondary` 只有 3.4:1，**用 Asset `Label2`** | 5.94 on surface / 5.99 on surface；on surface-2：5.29 / 4.77 |
| `label-disabled` | 禁用文字（WCAG 豁免） | `rgba(235,235,245,.30)` | `rgba(60,60,67,.30)` | Asset `LabelDisabled` | — |
| `separator` | 分隔线、图表网格 | `rgba(84,84,88,.65)` | `rgba(60,60,67,.29)` | `Color(.separator)` | — |
| `tint` | 唯一交互色 | `#A6FF00` | `#357000` | Asset `AccentColor`（即 App tint） | 13.7 on surface / 6.05 on surface |
| `on-tint` | tint 填充上的文字 | `#000000` | `#FFFFFF` | Asset `OnTint` | 16.9 / 6.05 |
| `metric-strength` | 最佳 1RM（数字、线、点） | `#FF4F6E` | `#C8103F` | Asset `MetricStrength` | 5.34 on surface / 5.83 on surface |
| `metric-volume` | 容量（数字、线、点） | `#1EEAEF` | `#006E80` | Asset `MetricVolume` | 11.4 on surface / 5.93 on surface |
| `danger` | 错误文字、删除 | `#FF6961` | `#C4001A` | Asset `Danger` | 6.03 on surface / 6.25 on surface |
| `on-danger` | 删除滑块上的文字 | `#000000` | `#FFFFFF` | Asset `OnDanger` | 7.45 / 6.25 |
| `material` | 标签栏 / 提示条 | 设计稿近似 `rgba(37,37,37,.72)` + blur 20 | 设计稿近似 `rgba(249,249,249,.78)` + blur 20 | `.regularMaterial`（系统材质，不自绘） | — |

规则：
- 指标色文字只出现在 `surface` 或 `bg` 上，不放在 `surface-2` 上（深色 `metric-strength` on surface-2 只有 4.38:1）。
- 正负变化不用红绿：「较上次 +1.7 kg」用该指标色 + 箭头图标，下降用 `label-2` + 向下箭头。红色只表示错误。
- 设计稿网页外框（画廊页的标题、说明）复用同一套 token，不额外引入颜色。

## 2. 字体与字号

- 文字：SF Pro（系统字体），中文由系统回退到苹方。
- 数字：**SF Pro Rounded**，所有重量、次数、容量、1RM、日期数字。`.fontDesign(.rounded)` + `.monospacedDigit()`。
- 全部走 Dynamic Type 文字样式，不写死字号。下表是默认（Large）尺寸，设计稿按此绘制。

| token | iOS 文字样式 | 字号 / 行高 | 字重 | 用途 |
|---|---|---|---|---|
| `display` | `@ScaledMetric(relativeTo: .largeTitle)` 48 | 48 / 52 | bold, rounded | 趋势页当前值（唯一一处） |
| `large-title` | `.largeTitle` | 34 / 41 | bold | 标签页大标题；明细页汇总数字（rounded；三列宽度 1.6 : 1 : 1，容量列最宽） |
| `title2` | `.title2` | 22 / 28 | bold, rounded | 卡片内主数字（周汇总、历史行日期数字） |
| `title3` | `.title3` | 20 / 25 | semibold | 动作名（录入卡片标题） |
| `headline` | `.headline` | 17 / 22 | semibold | 行主文字、按钮 |
| `body` | `.body` | 17 / 22 | regular | 输入框、正文 |
| `subheadline` | `.subheadline` | 15 / 20 | regular | 行次文字、分段控件 |
| `footnote` | `.footnote` | 13 / 18 | regular | 区段标题、行内错误、单位 |
| `caption` | `.caption` | 12 / 16 | medium | 图表坐标、序号徽章 |
| `caption2` | `.caption2` | 11 / 13 | semibold | 标签栏文字（系统） |

不用全大写，不在标题上方加小标签。

## 3. 间距

4 pt 基准。SwiftUI 里用这些数，不出现别的值。

| token | 值 | 用途 |
|---|---|---|
| `space-1` | 4 | 数字与单位之间、图标与文字之间 |
| `space-2` | 8 | 行内元素间、组行之间 |
| `space-3` | 12 | 卡片内分组之间 |
| `space-4` | 16 | 卡片内边距、屏幕左右边距（= 系统 inset grouped 边距） |
| `space-5` | 20 | 卡片之间（= 系统 section 间距） |
| `space-6` | 24 | 空状态内元素间 |
| `space-8` | 32 | 大标题与首个卡片、空状态上下 |
| `hit` | 44 | 最小可点区域（宽高） |

## 4. 圆角 / 阴影 / 材质

| token | 值 | 用途 |
|---|---|---|
| `radius-sm` | 8 | 序号徽章 |
| `radius-md` | 10 | 输入框 |
| `radius-lg` | 16 | 卡片（`.containerShape` / `RoundedRectangle(cornerRadius: 16, style: .continuous)`） |
| `radius-full` | capsule | 主按钮、动作选择器、提示条、最近动作胶囊 |
| 阴影 | 无 | App 内不用阴影；层级靠 `bg` / `surface` / `surface-2` 三级底色 |
| 材质 | `.regularMaterial` | 仅标签栏、底部提示条 |

### 4.1 系统尺寸与设计稿专用值

下列数值出现在 `ui/index.html` 里，但**不是设计 token**：要么由 iOS 系统控件自带（实现时不写），要么只属于画廊页面。实现中出现这些数需要说明来源。

| 值 | 出处 | 实现时 |
|---|---|---|
| 54（状态栏高）、44（导航栏高）、62（悬浮标签栏高） | iOS 系统栏 | 不写，系统提供 |
| 88（左滑删除按钮宽） | 系统 `swipeActions` | 不写 |
| 36（按钮 / 胶囊最小高）、2（分段控件内边距）、6（日期胶囊上下内边距） | 系统 `.bordered` / `Picker(.segmented)` / `DatePicker(.compact)` | 不写 |
| 1（分隔线）、1.5（输入框描边） | 分隔线 = 系统 hairline；描边 1.5 pt 是本设计的值 | 描边写 `1.5` |
| 2.5（折线宽）、symbolSize 40 / 100（数据点） | 本设计的值，见 8.9 | 写 |
| 24（序号徽章边长 / 标签栏图标）、22（行内图标）、14（chevron、箭头）、56（空状态图标） | SF Symbols 按文字样式缩放 | 用 `.imageScale` / `.font`，不写 pt |
| 40（历史行日期列宽） | 本设计的值，保证 1–31 对齐 | 写，`@ScaledMetric` |
| 390 × 844、圆角 54、120 / 140 底部留白、98（提示条距底） | 画廊里的手机外框，模拟 iPhone 安全区 | 不写，用 safe area |
| 600 / 601 / 1099 / 1440、72（状态板标签列）、320（状态板最小列宽）、96（页面底部留白）、10（图例圆点） | 画廊页面布局 | 与 App 无关 |

## 5. 动效

| 场景 | 动效 | 减弱动态效果时 |
|---|---|---|
| 新增组 / 动作 | 系统 List 插入动画 | 同（系统处理） |
| 保存成功 | 底部提示条从标签栏上方弹出（`.spring(duration: 0.35)`），2 秒后淡出；`.sensoryFeedback(.success)` | 只淡入淡出 |
| 分段切换 1RM / 容量 | 图表折线与颜色交叉淡化 0.25 s | 直接切换 |
| 页面跳转 | 系统 push | 同 |

只有「保存成功」是刻意设计的时刻，别处不加入场动画。

## 6. 断点

App 只做 iPhone 竖屏（Dynamic Type 从 xSmall 到 AX3 都不能截断主数字，可换行）。

设计稿网页（`ui/index.html`）的断点：

| 名称 | 视口 | 画廊布局 |
|---|---|---|
| `sm` | ≤ 600 px | 单列，手机框宽度 = 视口 − 2×16 |
| `md` | 601–1099 px | 两列 |
| `lg` | ≥ 1100 px | 自动多列，每列 390 px |

三个断点（390 / 768 / 1440）都已验证无横向滚动。

## 7. 信息架构

```
TabView（悬浮标签栏，.regularMaterial）
├─ 记录   square.and.pencil         NavigationStack，大标题「记录」
├─ 历史   clock.arrow.circlepath    NavigationStack，大标题「历史」 → 训练明细（行内标题）
└─ 趋势   chart.xyaxis.line         NavigationStack，大标题「趋势」        ← 变更：原在「历史」页工具栏分段切换
```

把趋势提为独立标签的理由：趋势是方向 B 的主角；原来「历史」工具栏里的「列表 / 趋势」分段把两种不同任务塞进一个页面。

## 8. 组件与交互状态

iOS 没有 hover；表中 hover 指 iPad 指针 / 键盘焦点场景（系统 `.hoverEffect` 默认即可）。focus 指外接键盘 / 全键盘访问的焦点环（系统默认，颜色 = `tint`）。

### 8.1 主按钮（「保存」，工具栏右上，capsule）

| 状态 | 外观 |
|---|---|
| default | 填充 `tint`，文字 `on-tint` `headline` |
| hover | 系统 `.hoverEffect(.highlight)`；设计稿以 4 pt `surface-2` 外圈示意 |
| focus | 系统焦点环 `tint`，外扩 2 pt |
| active（按下） | 透明度 0.7（系统 borderedProminent 默认） |
| disabled（`canSave == false`） | 填充 `surface-2`，文字 `label-disabled` |
| loading（保存中） | 文字换成 `ProgressView` + 「保存中」，按钮不可点；表单仍可编辑（T004 R1 已保证保存期间编辑不丢） |
| error | 按钮回到 default；底部提示条显示错误（见 8.7） |

### 8.2 文本输入（重量 / 次数 / 动作名）

| 状态 | 外观 |
|---|---|
| default | 底 `surface-2`，`radius-md`，占位符 `label-2`，高 44 |
| focus | 1.5 pt `tint` 描边 |
| filled | 文字 `label`，数字用 rounded |
| error | 1.5 pt `danger` 描边；加组行下方（整行宽）`footnote` `danger` 文字 + `exclamationmark.circle.fill`。重量和次数都错时只提示重量（与 `SetInputError` 先校验重量一致） |
| disabled | 底 `surface-2`，文字 `label-disabled` |
| loading / empty | 不适用（输入框无加载态；空即 default） |

键盘：重量 `.decimalPad`，次数 `.numberPad`，动作名 `.default` + 回车即添加。

行内错误文案（对应 `SetInputError`）：
- `.invalidWeight` →「重量需为 0–1000 kg 的数字」
- `.invalidReps` →「次数需为 1–1000 的整数」
- 动作重名 →「本次训练已有「卧推」」
- 动作名为空 → 不提示，「添加动作」按钮禁用

### 8.3 加组按钮（圆形，`plus`）

| 状态 | 外观 |
|---|---|
| default | 44×44 圆，填充 `tint`，图标 `on-tint` |
| hover / focus / active | 同 8.1 |
| disabled（重量和次数都为空） | 填充 `surface-2`，图标 `label-disabled` |
| loading / empty / error | 不适用；校验失败走 8.2 error |

### 8.4 动作卡片（录入）

结构：标题行（动作名 `title3` + 右侧 `ellipsis.circle` 菜单：删除动作）→ 小计（「3 组 · 1,205 kg」，容量用 `metric-volume`）→ 组行列表 → 加组行。
- 组行：序号徽章（`surface-2`，`radius-sm`，`caption`）+「60 kg × 8 次」（数字 rounded `headline`，单位 `footnote` `label-2`）。左滑删除（系统 `swipeActions`，`danger`）。
- empty（动作下还没有组）：小计位置显示「还没有组，在下方输入重量和次数」（`subheadline` `label-2`），不画组列表。

### 8.5 历史行

日期块（日 `title2` rounded + 星期 `caption` `label-2`）｜ 动作名 `headline`（单行截断）+「5 组」`subheadline` `label-2` ｜ 容量 `headline` rounded `metric-volume` + kg ｜ `chevron.right`。
- active：系统行按下高亮
- 左滑：`danger` 填充「删除」+ `trash`，`allowsFullSwipe`
- focus / hover：系统

### 8.6 分段控件（趋势：最佳 1RM / 容量）

系统 `Picker(.segmented)`，不改色（深色下指标色放在选中段底色上只有 4.38:1，且系统控件不便单独着色）。切换后由大数字、折线、列表数值换色来表明当前指标。

| 状态 | 外观 |
|---|---|
| default / active | 系统 |
| focus | 系统焦点环 `tint` |
| disabled（只有 0 个数据点时） | 系统禁用 |
| hover / loading / empty / error | 不适用 |

### 8.7 底部提示条（toast）

capsule，`.regularMaterial`，位于标签栏上方 `space-3`。
- 成功：`checkmark.circle.fill`（`tint`）+「已保存 · 5 组 · 1,890 kg」，2 秒自动消失
- 失败：`exclamationmark.triangle.fill`（`danger`）+「保存失败，训练还在，可以再试一次」+「重试」按钮（`tint` 文字），不自动消失，可下滑关闭

### 8.8 页面级状态

| 页面 | loading | empty | error |
|---|---|---|---|
| 记录 | 不适用 | 插画位用 `figure.strengthtraining.traditional`（`tint`）+「开始记录今天的训练」+「添加第一个动作，再逐组记下重量和次数。」，动作名输入框就在下面 | 见 8.7 |
| 历史 | 首次加载且无旧数据：居中 `ProgressView` +「正在加载…」 | `ContentUnavailableView`：`clock.arrow.circlepath`「还没有训练记录」「在「记录」里保存一次训练，就会出现在这里。」+ 按钮「去记录」（切到记录标签） | 列表顶部错误卡片：`exclamationmark.triangle.fill` `danger`「无法加载训练历史」+「下面是上次加载的结果。」+「重试」。删除失败文案：「删除失败，这次训练还在。」 |
| 明细 | 不适用（数据已在内存） | 不适用 | 不适用 |
| 趋势 | 同历史 | 无任何动作：`ContentUnavailableView` `chart.xyaxis.line`「还没有可看的趋势」「保存训练后，每个动作都会有自己的趋势图。」；只有 1 个点：显示当前值 +「再记录一次「深蹲」就能连成趋势」，不画线 | 同历史 |

### 8.9 趋势图

Swift Charts：`LineMark` + `PointMark`，颜色 = 当前指标色，线宽 2.5，最新一点放大（`symbolSize` 100，其余 40）。纵轴不从 0 起（`.chartYScale(domain: .automatic(includesZero: false))`），网格线 `separator`，坐标 `caption` `label-2`，纵轴在右侧。图下方是数据列表（日期 → 数值，最新在前），给 VoiceOver 和精确读数用。

## 9. 新交互建议（标注为「建议」，不在本次实现范围内）

这三条需要 Core 新增 API，是否实现由人类和 hermes 决定，批准设计**不等于**批准这三条。

| 编号 | 位置 | 内容 | 需要的 Core 能力 |
|---|---|---|---|
| P1 | 记录 · 动作卡片 | 标题下显示「上次 10月27日 · 62.5 kg × 6」；加组输入框以上次重量作占位 | 按动作名取最近一次场次的最佳组 |
| P2 | 记录 · 添加动作 | 输入框下一行「最近动作」胶囊（最多 6 个，横向滚动），点按即添加；已在本次训练中的置灰 | `HistoryViewModel.exerciseNames` 已有，可复用 |
| P3 | 记录 · 空状态 | 「复制上次训练（10月29日 · 硬拉、引体向上）」次要按钮：带入动作名，不带入组 | 取最近一次场次 |

## 10. 交接给实现者

- 实现只改 `App/`（以及新增 Asset Catalog 颜色），Core 与验收标准不受影响（P1–P3 除外）。
- 颜色、字号、间距、圆角一律引用本文件 token，不写魔法数。
- 实现 PR 附模拟器截图与 `ui/screenshots/` 对应图并排，深色 + 浅色各一套。
