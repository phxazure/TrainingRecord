import Foundation
import Testing
@testable import TrainingRecordCore

@Test func positiveSetVolume() {
    let set = SetEntry(weight: 100, reps: 5)
    #expect(set != nil)
    #expect(set.map(volume(of:)) == 500)
}

@Test func decimalWeightSetVolume() {
    let set = SetEntry(weight: 2.5, reps: 4)
    #expect(set != nil)
    #expect(set.map(volume(of:)) == 10)
}

@Test func zeroWeightSetVolume() {
    let set = SetEntry(weight: 0, reps: 10)
    #expect(set != nil)
    #expect(set.map(volume(of:)) == 0)
}

@Test func zeroRepsSetVolume() {
    let set = SetEntry(weight: 100, reps: 0)
    #expect(set != nil)
    #expect(set.map(volume(of:)) == 0)
}

@Test func negativeWeightIsNil() {
    #expect(SetEntry(weight: -100, reps: 5) == nil)
}

@Test func negativeRepsIsNil() {
    #expect(SetEntry(weight: 100, reps: -5) == nil)
}

@Test func totalVolumeSumsSets() {
    let sets = [
        SetEntry(weight: 100, reps: 5),  // 500
        SetEntry(weight: 2.5, reps: 4),  // 10
        SetEntry(weight: 0, reps: 10),   // 0
    ].compactMap { $0 }
    #expect(sets.count == 3)
    let session = WorkoutSession(date: Date(timeIntervalSinceReferenceDate: 0), sets: sets)
    #expect(totalVolume(of: session) == 510)
}

@Test func totalVolumeOfEmptySessionIsZero() {
    let session = WorkoutSession(date: Date(timeIntervalSinceReferenceDate: 0), sets: [])
    #expect(totalVolume(of: session) == 0)
}
