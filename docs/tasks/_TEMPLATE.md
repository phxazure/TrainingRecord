# <id> <标题>

状态: draft | planned | in_dev | in_review | changes_requested | approved | merged | escalated
分支: task/<id>
执行者: code | code-local          ← 没有这个字段，谁都不得开工
工作目录: /绝对路径（并行时两个执行者必须用不同目录）
范围:
  - 允许修改的路径（白名单，超出即越界）

负责人: hermes

## 目标

一句话说清要什么，以及为什么。

## 验收标准

必须可机器或人可判定。禁止"实现 X 功能"这种。

- [ ] 例: `multiply(2, 3)` 返回 6，且有测试覆盖
- [ ] 例: 测试命令全绿

## 计划

（hermes 写：分几步、每步验证什么）

## UI 契约

（涉及界面时由 frontend 填写 `ui/DESIGN.md` 的路径与版本；无界面可删）

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
