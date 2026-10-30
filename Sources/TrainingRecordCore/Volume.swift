/// 单组容量 = 重量 × 次数。
public func volume(of set: SetEntry) -> Double {
    set.weight * Double(set.reps)
}

/// 场次总容量 = 各组容量之和（无组时为 0）。
public func totalVolume(of session: WorkoutSession) -> Double {
    session.sets.reduce(0) { $0 + volume(of: $1) }
}
