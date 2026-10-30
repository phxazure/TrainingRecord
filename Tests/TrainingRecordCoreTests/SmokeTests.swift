import Testing
@testable import TrainingRecordCore

@Test func versionIsNotEmpty() {
    #expect(!TrainingRecordInfo.version.isEmpty)
}
