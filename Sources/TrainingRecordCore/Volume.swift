/// 单组容量 = 重量 × 次数。
public func volume(of set: SetEntry) -> Double {
    set.weight * Double(set.reps)
}

/// 单动作容量 = 该动作所有组容量之和（无组时为 0）。
public func volume(of exercise: ExerciseEntry) -> Double {
    exercise.sets.reduce(0) { $0 + volume(of: $1) }
}

/// 场次总容量 = 所有动作所有组容量之和（无动作时为 0）。
public func totalVolume(of session: WorkoutSession) -> Double {
    session.exercises.reduce(0) { $0 + volume(of: $1) }
}
