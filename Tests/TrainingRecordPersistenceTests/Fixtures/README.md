# 旧版存储样本

`legacy-T006.store` 是用 **T006 已合并版本（main 上的 `bd79293`）** 的代码生成的 SwiftData 磁盘存储，
用来验证新代码（带动作 id 和动作库）能原样打开旧用户的数据并完成回填。

内容：2 场训练、3 个动作、7 组；动作条目没有 `exerciseID` 列，存储里没有动作库的表。

| 场次 id | 日期（Unix 秒） | 动作 |
|---|---|---|
| …00a1 | 1_700_000_000 | 卧推 60×10、62.5×8、65×6；深蹲 100×5、100×5 |
| …00a2 | 1_700_600_000 | 硬拉 120×5、140×3 |

测试**只在临时目录里的副本上**打开它（迁移会改文件），不会改动这个文件。

## 怎么生成的

1. `git worktree add --detach <临时目录> bd79293`（不改那个版本的代码）。
2. 在该 worktree 的 `Tests/TrainingRecordPersistenceTests/` 里临时放一个测试（**不提交**），内容如下：

```swift
import Foundation
import Testing
import TrainingRecordCore
@testable import TrainingRecordPersistence

@Suite struct GenerateLegacyStore {
    @Test func generate() async throws {
        let out = try #require(ProcessInfo.processInfo.environment["LEGACY_STORE_OUT"])
        let url = URL(fileURLWithPath: out)
        try? FileManager.default.removeItem(at: url)
        func u(_ s: String) -> UUID { UUID(uuidString: s)! }
        func entry(_ name: String, _ sets: [(Double, Int)]) -> ExerciseEntry {
            ExerciseEntry(name: name, sets: sets.map { SetEntry(weight: $0.0, reps: $0.1)! })!
        }
        let s1 = WorkoutSession(
            id: u("00000000-0000-0000-0000-0000000000a1"),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [entry("卧推", [(60, 10), (62.5, 8), (65, 6)]), entry("深蹲", [(100, 5), (100, 5)])]
        )
        let s2 = WorkoutSession(
            id: u("00000000-0000-0000-0000-0000000000a2"),
            date: Date(timeIntervalSince1970: 1_700_600_000),
            exercises: [entry("硬拉", [(120, 5), (140, 3)])]
        )
        do {
            let repo = try SwiftDataWorkoutRepository.onDisk(url: url)
            try await repo.save(s1)
            try await repo.save(s2)
        }
    }
}
```

3. 在该 worktree 运行：`LEGACY_STORE_OUT=/tmp/legacy-T006.store swift test --filter GenerateLegacyStore`
4. 合并 WAL，让单个文件自包含：`sqlite3 /tmp/legacy-T006.store "PRAGMA wal_checkpoint(TRUNCATE);"`
5. 只复制 `legacy-T006.store`（不带 `-wal` / `-shm`）到本目录，删掉 worktree。

校验：`sqlite3 legacy-T006.store "select count(*) from ZSESSIONRECORD; select count(*) from ZSETRECORD;"` 得到 `2`、`7`；
`sqlite3 legacy-T006.store ".tables"` 里没有动作库的表。
