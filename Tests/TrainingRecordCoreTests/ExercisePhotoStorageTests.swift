import Foundation
import Testing
@testable import TrainingRecordCore

// T009 照片存储（人类选定方案 1）：每次存图用新文件名；先写新文件 → 保存动作库 → 成功才尽力删旧；
// 启动清理删除没有被引用的文件，且不动本进程正在保存、尚未提交的新文件。没有备份、没有恢复日志、不持久化绝对路径。

// MARK: - 测试替身

/// 按顺序记录文件系统与动作库发生的事。
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ event: String) { lock.lock(); items.append(event); lock.unlock() }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

private struct InjectedFailure: Error {}

/// 内存文件系统，可注入写 / 删 / 列目录失败。`write` 对已存在的名字抛错（和真实实现一致：绝不覆盖）。
private final class FakePhotoFileSystem: PhotoFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data]
    private var writesFail = false
    private var removalsFail = false
    private var listingFails = false
    private let log: EventLog

    init(files: [String: Data] = [:], log: EventLog = EventLog()) {
        self.files = files
        self.log = log
    }

    func setWritesFail(_ value: Bool) { lock.lock(); writesFail = value; lock.unlock() }
    func setRemovalsFail(_ value: Bool) { lock.lock(); removalsFail = value; lock.unlock() }
    func setListingFails(_ value: Bool) { lock.lock(); listingFails = value; lock.unlock() }
    func put(_ name: String, _ data: Data = Data("x".utf8)) { lock.lock(); files[name] = data; lock.unlock() }
    var names: Set<String> { lock.lock(); defer { lock.unlock() }; return Set(files.keys) }
    func data(_ name: String) -> Data? { lock.lock(); defer { lock.unlock() }; return files[name] }

    func list() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        if listingFails { throw InjectedFailure() }
        return Array(files.keys)
    }

    func write(_ data: Data, named fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        log.add("write \(fileName)")
        if writesFail || files[fileName] != nil { throw InjectedFailure() }
        files[fileName] = data
    }

    func remove(named fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        log.add("remove \(fileName)")
        if removalsFail { throw InjectedFailure() }
        files[fileName] = nil
    }
}

/// 动作库仓储替身：可注入保存 / 读取失败，也可以让保存停在半路（模拟「新文件已写、库还没提交」）。
private actor ScriptedLibraryRepository: ExerciseLibraryRepository {
    private let inner = InMemoryExerciseLibraryRepository()
    private let log: EventLog
    private var saveFails = false
    private var readsFail = false
    private var parkSaves = false
    private var parked: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var hasArrived = false

    init(log: EventLog = EventLog()) { self.log = log }

    func setSaveFails(_ value: Bool) { saveFails = value }
    func setReadsFail(_ value: Bool) { readsFail = value }
    func setParkSaves(_ value: Bool) { parkSaves = value }
    func seed(_ exercise: ExerciseDefinition) async { try? await inner.save(exercise) }

    /// 等到有一次保存停在半路。
    func waitUntilSaveParked() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        parkSaves = false
        parked?.resume()
        parked = nil
    }

    func allExercises() async throws -> [ExerciseDefinition] {
        if readsFail { throw InjectedFailure() }
        return try await inner.allExercises()
    }

    func exercise(id: UUID) async throws -> ExerciseDefinition? {
        if readsFail { throw InjectedFailure() }
        return try await inner.exercise(id: id)
    }

    func save(_ exercise: ExerciseDefinition) async throws {
        log.add("save \(exercise.photoFileName ?? "nil")")
        if saveFails { throw InjectedFailure() }
        if parkSaves {
            guard parked == nil else { throw InjectedFailure() }  // 重叠的保存：抛错而不是覆盖续体，变异时让测试变红而不是挂起
            hasArrived = true
            arrival?.resume(); arrival = nil
            await withCheckedContinuation { parked = $0 }
        }
        try await inner.save(exercise)
    }

    func delete(id: UUID) async throws {
        log.add("deleteRow")
        try await inner.delete(id: id)
    }
}

private struct Fixture {
    let log: EventLog
    let files: FakePhotoFileSystem
    let library: ScriptedLibraryRepository
    let storage: ExercisePhotoStorage
    let workflow: ExercisePhotoWorkflow
    let workouts: InMemoryWorkoutRepository

    init(files initial: [String: Data] = [:], token: (@Sendable () -> UUID)? = nil) {
        let log = EventLog()
        let files = FakePhotoFileSystem(files: initial, log: log)
        let library = ScriptedLibraryRepository(log: log)
        let workouts = InMemoryWorkoutRepository()
        let storage = token.map { ExercisePhotoStorage(fileSystem: files, makeToken: $0) } ?? ExercisePhotoStorage(fileSystem: files)
        let service = ExerciseLibraryService(library: library, workouts: workouts)
        self.log = log
        self.files = files
        self.library = library
        self.workouts = workouts
        self.storage = storage
        self.workflow = ExercisePhotoWorkflow(service: service, repository: library, storage: storage)
    }
}

private func jpeg(_ text: String) -> Data { Data(text.utf8) }

private func exerciseID(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

/// 库里已有一个带照片的动作，对应的照片文件也在磁盘上。
private func seededFixture(oldName: String = "OLD-PHOTO.jpg", extraFiles: [String: Data] = [:]) async -> (Fixture, ExerciseDefinition) {
    var files = extraFiles
    files[oldName] = jpeg("old-bytes")
    let fixture = Fixture(files: files)
    let bench = ExerciseDefinition(id: exerciseID(1), name: "卧推", bodyPart: "胸", photoFileName: oldName)!
    await fixture.library.seed(bench)
    return (fixture, bench)
}

// MARK: - 命名

@Suite struct ExercisePhotoNamingTests {
    @Test func fileNameIsOwnerIDDashTokenJpg() {
        let owner = exerciseID(7), token = exerciseID(9)
        #expect(ExercisePhotoNaming.makeFileName(ownerID: owner, token: token)
            == "\(owner.uuidString)-\(token.uuidString).jpg")
    }

    @Test func everyCallProducesANewName() {
        let owner = exerciseID(7)
        let names = Set((0..<50).map { _ in ExercisePhotoNaming.makeFileName(ownerID: owner) })
        #expect(names.count == 50)
        #expect(names.allSatisfy { $0.hasPrefix(owner.uuidString + "-") && $0.hasSuffix(".jpg") && !$0.contains("/") })
    }

    @Test func savedFileNameStartsWithTheExerciseIDAndDiffersFromOldOne() async throws {
        let (fixture, bench) = await seededFixture()
        let updated = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("new")))
        let name = try #require(updated.photoFileName)
        #expect(name.hasPrefix(bench.id.uuidString + "-"))
        #expect(name.hasSuffix(".jpg"))
        #expect(name != "OLD-PHOTO.jpg")
    }
}

// MARK: - 保存顺序

@Suite struct ExercisePhotoSaveOrderTests {
    @Test func replaceWritesNewFileThenSavesLibraryThenDeletesOld() async throws {
        let (fixture, bench) = await seededFixture()
        let updated = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("new")))
        let new = try #require(updated.photoFileName)

        #expect(fixture.log.events == ["write \(new)", "save \(new)", "remove OLD-PHOTO.jpg"])
        #expect(fixture.files.names == [new])
        #expect(fixture.files.data(new) == jpeg("new"))
        #expect(try await fixture.library.exercise(id: bench.id)?.photoFileName == new)
    }

    @Test func addWithPhotoWritesFileThenSavesLibrary() async throws {
        let fixture = Fixture()
        let created = try await fixture.workflow.add(name: "深蹲", bodyPart: "腿", photoJPEG: jpeg("squat"))
        let name = try #require(created.photoFileName)
        #expect(fixture.log.events == ["write \(name)", "save \(name)"])
        #expect(fixture.files.names == [name])
    }

    @Test func addWithoutPhotoTouchesNoFile() async throws {
        let fixture = Fixture()
        let created = try await fixture.workflow.add(name: "深蹲", bodyPart: "腿", photoJPEG: nil)
        #expect(created.photoFileName == nil)
        #expect(fixture.log.events == ["save nil"])
        #expect(fixture.files.names.isEmpty)
    }

    @Test func removePhotoChangesLibraryFirstThenDeletesFile() async throws {
        let (fixture, bench) = await seededFixture()
        let updated = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .remove)
        #expect(updated.photoFileName == nil)
        #expect(fixture.log.events == ["save nil", "remove OLD-PHOTO.jpg"])
        #expect(fixture.files.names.isEmpty)
    }

    @Test func deleteExerciseDeletesRowFirstThenFile() async throws {
        let (fixture, bench) = await seededFixture()
        try await fixture.workflow.delete(id: bench.id)
        #expect(fixture.log.events == ["deleteRow", "remove OLD-PHOTO.jpg"])
        #expect(try await fixture.library.exercise(id: bench.id) == nil)
    }

    @Test func mergeDeletesSourcePhotoOnlyAfterTheMergeSucceeds() async throws {
        let (fixture, source) = await seededFixture()
        let target = ExerciseDefinition(id: exerciseID(2), name: "杠铃卧推", bodyPart: "胸", photoFileName: "TARGET.jpg")!
        await fixture.library.seed(target)
        fixture.files.put("TARGET.jpg")

        try await fixture.workflow.merge(sourceID: source.id, into: target.id)

        #expect(fixture.log.events == ["deleteRow", "remove OLD-PHOTO.jpg"])
        #expect(fixture.files.names == ["TARGET.jpg"])
    }

    @Test func mergeIntoItselfKeepsThePhoto() async throws {
        let (fixture, bench) = await seededFixture()
        try await fixture.workflow.merge(sourceID: bench.id, into: bench.id)
        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
        #expect(try await fixture.library.exercise(id: bench.id)?.photoFileName == "OLD-PHOTO.jpg")
    }

    @Test func keepLeavesThePhotoAlone() async throws {
        let (fixture, bench) = await seededFixture()
        let updated = try await fixture.workflow.update(id: bench.id, name: "平板卧推", bodyPart: "胸", photo: .keep)
        #expect(updated.photoFileName == "OLD-PHOTO.jpg")
        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
    }

    // 绝不覆盖：令牌撞车时，第二次保存写文件失败 → 不保存、已有文件字节不变。
    @Test func neverOverwritesAnExistingFile() async throws {
        let owner = exerciseID(1), token = exerciseID(99)
        let existing = ExercisePhotoNaming.makeFileName(ownerID: owner, token: token)
        let fixture = Fixture(files: [existing: jpeg("first")], token: { token })
        let bench = ExerciseDefinition(id: owner, name: "卧推", bodyPart: "胸", photoFileName: existing)!
        await fixture.library.seed(bench)

        await #expect(throws: PhotoStorageError.writeFailed) {
            _ = try await fixture.workflow.update(id: owner, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("second")))
        }
        #expect(fixture.files.data(existing) == jpeg("first"))
        #expect(try await fixture.library.exercise(id: owner)?.photoFileName == existing)
        #expect(!fixture.log.events.contains { $0.hasPrefix("save") })
        #expect(!fixture.log.events.contains { $0.hasPrefix("remove") })
    }
}

// MARK: - 失败路径

@Suite struct ExercisePhotoFailureTests {
    // 验收：换图保存失败 → 旧图与库不变（新文件也被尽力删掉）。
    @Test func replaceFailingLibrarySaveKeepsOldPhotoAndLibraryRecord() async throws {
        let (fixture, bench) = await seededFixture()
        await fixture.library.setSaveFails(true)

        await #expect(throws: InjectedFailure.self) {
            _ = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("new")))
        }

        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
        #expect(fixture.files.data("OLD-PHOTO.jpg") == jpeg("old-bytes"))
        #expect(try await fixture.library.exercise(id: bench.id) == bench)
        // 顺序：写新 → 保存失败 → 删新；旧文件从头到尾没被碰。
        let events = fixture.log.events
        try #require(events.count == 3)
        #expect(events[0].hasPrefix("write ") && events[1].hasPrefix("save ") && events[2].hasPrefix("remove "))
        #expect(!events.contains("remove OLD-PHOTO.jpg"))
    }

    // 保存失败后「尽力删新文件」自己也失败：不报错，错误仍是保存失败；孤立文件留给下次清理。
    @Test func replaceFailureWithFailingCleanupStillReportsTheSaveFailureAndLeavesAnOrphanForSweeping() async throws {
        let (fixture, bench) = await seededFixture()
        await fixture.library.setSaveFails(true)
        fixture.files.setRemovalsFail(true)

        await #expect(throws: InjectedFailure.self) {
            _ = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("new")))
        }
        #expect(fixture.files.names.count == 2)  // 旧图 + 删不掉的新文件
        #expect(try await fixture.library.exercise(id: bench.id) == bench)

        fixture.files.setRemovalsFail(false)
        let result = await fixture.workflow.sweepUnreferencedPhotos()
        guard case .completed(let deleted, let failed) = result else { Issue.record("应完成清理"); return }
        #expect(deleted.count == 1 && failed.isEmpty)
        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
    }

    // 验收：新建时写文件失败 → 不产生动作；用户再试同一个名字不会被「重名」挡住。
    @Test func addWhenWritingTheFileFailsCreatesNoExercise() async throws {
        let fixture = Fixture()
        fixture.files.setWritesFail(true)

        await #expect(throws: PhotoStorageError.writeFailed) {
            _ = try await fixture.workflow.add(name: "深蹲", bodyPart: "腿", photoJPEG: jpeg("squat"))
        }
        #expect(try await fixture.library.allExercises().isEmpty)
        #expect(!fixture.log.events.contains { $0.hasPrefix("save") })
        #expect(fixture.files.names.isEmpty)

        fixture.files.setWritesFail(false)
        let retry = try await fixture.workflow.add(name: "深蹲", bodyPart: "腿", photoJPEG: jpeg("squat"))
        #expect(retry.photoFileName != nil)
        #expect(try await fixture.library.allExercises().count == 1)
    }

    @Test func replaceWhenWritingTheFileFailsChangesNothing() async throws {
        let (fixture, bench) = await seededFixture()
        fixture.files.setWritesFail(true)

        await #expect(throws: PhotoStorageError.writeFailed) {
            _ = try await fixture.workflow.update(id: bench.id, name: "改名", bodyPart: "背", photo: .replace(jpeg("new")))
        }
        #expect(try await fixture.library.exercise(id: bench.id) == bench)  // 名字、部位、照片都没动
        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
        #expect(!fixture.log.events.contains { $0.hasPrefix("save") })
    }

    @Test func addFailingLibrarySaveRemovesTheNewFileAndCreatesNothing() async throws {
        let fixture = Fixture()
        await fixture.library.setSaveFails(true)
        await #expect(throws: InjectedFailure.self) {
            _ = try await fixture.workflow.add(name: "深蹲", bodyPart: "腿", photoJPEG: jpeg("squat"))
        }
        #expect(fixture.files.names.isEmpty)
        #expect(try await fixture.library.allExercises().isEmpty)
    }

    @Test func duplicateNameOnAddWithPhotoLeavesNoFileBehind() async throws {
        let (fixture, _) = await seededFixture()
        await #expect(throws: ExerciseLibraryError.duplicateName) {
            _ = try await fixture.workflow.add(name: "卧推", bodyPart: "胸", photoJPEG: jpeg("dup"))
        }
        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
    }

    // 验收：尽力删失败 → 业务操作照常成功；下次清理删掉孤立文件，被引用的文件不动。
    @Test func bestEffortDeleteFailureSucceedsAndNextSweepRemovesTheOrphanButNotReferencedFiles() async throws {
        let (fixture, bench) = await seededFixture()
        let other = ExerciseDefinition(id: exerciseID(2), name: "深蹲", bodyPart: "腿", photoFileName: "SQUAT.jpg")!
        await fixture.library.seed(other)
        fixture.files.put("SQUAT.jpg", jpeg("squat-bytes"))
        fixture.files.setRemovalsFail(true)

        let updated = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("new")))
        let new = try #require(updated.photoFileName)
        // 操作成功、库指向新图；旧图因为删不掉而留着（孤立）。
        #expect(fixture.files.names == ["OLD-PHOTO.jpg", "SQUAT.jpg", new])

        // 目录依旧不可写时的清理：不抛错，报告没删掉的。
        let stuck = await fixture.workflow.sweepUnreferencedPhotos()
        #expect(stuck == .completed(deleted: [], failed: ["OLD-PHOTO.jpg"]))

        // 目录恢复可写后的下一次清理（= 下次启动）。
        fixture.files.setRemovalsFail(false)
        let result = await fixture.workflow.sweepUnreferencedPhotos()
        #expect(result == .completed(deleted: ["OLD-PHOTO.jpg"], failed: []))
        #expect(fixture.files.names == ["SQUAT.jpg", new])
        #expect(fixture.files.data("SQUAT.jpg") == jpeg("squat-bytes"))
        #expect(fixture.files.data(new) == jpeg("new"))
    }

    @Test func bestEffortDeleteFailureOnRemoveDeleteAndMergeStillSucceeds() async throws {
        let (fixture, bench) = await seededFixture()
        fixture.files.setRemovalsFail(true)

        _ = try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .remove)
        #expect(try await fixture.library.exercise(id: bench.id)?.photoFileName == nil)

        let other = ExerciseDefinition(id: exerciseID(2), name: "深蹲", bodyPart: "腿", photoFileName: "SQUAT.jpg")!
        let target = ExerciseDefinition(id: exerciseID(3), name: "硬拉", bodyPart: "背")!
        await fixture.library.seed(other); await fixture.library.seed(target)
        fixture.files.put("SQUAT.jpg")
        try await fixture.workflow.merge(sourceID: other.id, into: target.id)
        try await fixture.workflow.delete(id: bench.id)
        #expect(try await fixture.library.allExercises().map(\.name) == ["硬拉"])
        // 两张都没删掉，都成了孤立文件，等下次清理。
        #expect(fixture.files.names == ["OLD-PHOTO.jpg", "SQUAT.jpg"])

        fixture.files.setRemovalsFail(false)
        _ = await fixture.workflow.sweepUnreferencedPhotos()
        #expect(fixture.files.names.isEmpty)
    }
}

// MARK: - 启动清理

@Suite struct ExercisePhotoSweepTests {
    // 验收：库加载失败 → 不清理。
    @Test func sweepIsSkippedWhenTheLibraryCannotBeLoaded() async {
        let (fixture, _) = await seededFixture(extraFiles: ["ORPHAN.jpg": jpeg("o")])
        await fixture.library.setReadsFail(true)

        let result = await fixture.workflow.sweepUnreferencedPhotos()

        #expect(result == .skipped)
        #expect(fixture.files.names == ["OLD-PHOTO.jpg", "ORPHAN.jpg"])
        #expect(!fixture.log.events.contains { $0.hasPrefix("remove") })

        // 库恢复后清理才会删。
        await fixture.library.setReadsFail(false)
        #expect(await fixture.workflow.sweepUnreferencedPhotos() == .completed(deleted: ["ORPHAN.jpg"], failed: []))
    }

    @Test func sweepIsSkippedWhenTheDirectoryCannotBeListed() async {
        let (fixture, _) = await seededFixture(extraFiles: ["ORPHAN.jpg": jpeg("o")])
        fixture.files.setListingFails(true)
        #expect(await fixture.workflow.sweepUnreferencedPhotos() == .skipped)
        #expect(fixture.files.names == ["OLD-PHOTO.jpg", "ORPHAN.jpg"])
    }

    // 验收 7：旧版遗留的命名（<动作 id>.jpg）只要库里引用就照常保留；没人引用的旧版临时 / 备份文件按普通孤立文件清掉。
    @Test func sweepKeepsReferencedLegacyNamesAndRemovesUnreferencedFiles() async {
        let legacy = "\(exerciseID(1).uuidString).jpg"
        let (fixture, _) = await seededFixture(
            oldName: legacy,
            extraFiles: [
                "\(exerciseID(5).uuidString).jpg": jpeg("deleted-exercise"),
                "\(legacy).backup": jpeg("b"),
                "\(UUID().uuidString).staging": jpeg("s"),
            ]
        )
        let result = await fixture.workflow.sweepUnreferencedPhotos()
        guard case .completed(let deleted, let failed) = result else { Issue.record("应完成清理"); return }
        #expect(deleted.count == 3 && failed.isEmpty)
        #expect(fixture.files.names == [legacy])
        #expect(fixture.files.data(legacy) == jpeg("old-bytes"))
    }

    @Test func sweepWithNothingToDoDeletesNothing() async {
        let (fixture, _) = await seededFixture()
        #expect(await fixture.workflow.sweepUnreferencedPhotos() == .completed(deleted: [], failed: []))
        #expect(fixture.files.names == ["OLD-PHOTO.jpg"])
    }

    // 验收：清理与进行中的保存并发 → 新文件不被删。
    // 真造场景：换图的库保存停在半路（新文件已在磁盘上、库里还没有它），这时跑一次清理。
    @Test func sweepDuringAnInFlightSaveDoesNotDeleteTheNewFile() async throws {
        let (fixture, bench) = await seededFixture(extraFiles: ["ORPHAN.jpg": jpeg("o")])
        await fixture.library.setParkSaves(true)

        let saving = Task {
            try await fixture.workflow.update(id: bench.id, name: "卧推", bodyPart: "胸", photo: .replace(jpeg("new")))
        }
        await fixture.library.waitUntilSaveParked()
        // 此刻：新文件在盘上，库里仍引用旧图。
        let onDisk = fixture.files.names
        let newName = try #require(onDisk.subtracting(["OLD-PHOTO.jpg", "ORPHAN.jpg"]).first)
        #expect(onDisk.count == 3)
        #expect(try await fixture.library.exercise(id: bench.id)?.photoFileName == "OLD-PHOTO.jpg")

        let sweep = await fixture.workflow.sweepUnreferencedPhotos()

        #expect(sweep == .completed(deleted: ["ORPHAN.jpg"], failed: []))  // 真孤立文件被清掉
        #expect(fixture.files.names == ["OLD-PHOTO.jpg", newName])         // 进行中的新文件还在

        await fixture.library.release()
        let updated = try await saving.value
        #expect(updated.photoFileName == newName)
        #expect(fixture.files.names == [newName])                          // 提交后旧图被尽力删掉，新图在
        #expect(fixture.files.data(newName) == jpeg("new"))
        #expect(await fixture.workflow.sweepUnreferencedPhotos() == .completed(deleted: [], failed: []))
    }

    // 另一种交错：清理读到的「被引用」快照早于提交，而保存在清理结束前已经提交完成。
    // 此时文件已不在「进行中」，只有「清理期间登记过」的记录能保护它。
    @Test func sweepWithAStaleReferencedSnapshotDoesNotDeleteAFileSavedAndCommittedDuringTheSweep() async throws {
        let files = FakePhotoFileSystem()
        let storage = ExercisePhotoStorage(fileSystem: files)
        let owner = exerciseID(1)
        let gate = SweepGate()

        let sweeping = Task {
            await storage.sweepUnreferenced {
                let staleSnapshot: Set<String> = []        // 读库的一刻：新文件还没有
                await gate.parkUntilReleased()              // 之后清理被拖慢
                return staleSnapshot
            }
        }
        await gate.waitUntilParked()

        // 清理停着的时候，一次完整的保存：写文件 → 提交 → 结束（文件不再「进行中」）。
        let saved = try await storage.save(jpeg: jpeg("new"), ownerID: owner, replacing: nil) { $0 }
        #expect(files.names == [saved])

        await gate.release()
        let result = await sweeping.value
        #expect(result == .completed(deleted: [], failed: []))
        #expect(files.names == [saved])
    }

    // 登记时机：清理开始前已经在进行中的保存，同样受保护。
    @Test func sweepStartedWhileASaveIsAlreadyInFlightKeepsItsFile() async throws {
        let files = FakePhotoFileSystem(files: ["ORPHAN.jpg": jpeg("o")])
        let storage = ExercisePhotoStorage(fileSystem: files)
        let commitGate = SweepGate()

        let saving = Task {
            try await storage.save(jpeg: jpeg("new"), ownerID: exerciseID(1), replacing: nil) { (name: String) async throws -> String in
                await commitGate.parkUntilReleased()
                return name
            }
        }
        await commitGate.waitUntilParked()

        let result = await storage.sweepUnreferenced { [] }  // 库里什么都没引用
        #expect(result == .completed(deleted: ["ORPHAN.jpg"], failed: []))
        #expect(files.names.count == 1)

        await commitGate.release()
        let name = try await saving.value
        #expect(files.names == [name])
    }

    // 保护只覆盖清理期间：清理结束后，没被引用的文件（比如那次保存最终失败却没删掉的）下一次清理照样删。
    @Test func protectionEndsWithTheSweep() async throws {
        let files = FakePhotoFileSystem()
        let storage = ExercisePhotoStorage(fileSystem: files)
        let saved = try await storage.save(jpeg: jpeg("new"), ownerID: exerciseID(1), replacing: nil) { $0 }
        #expect(await storage.sweepUnreferenced { [] } == .completed(deleted: [saved], failed: []))
        #expect(files.names.isEmpty)
    }
}

/// 把一个异步步骤停在半路、由测试放行。
private actor SweepGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var hasArrived = false

    func parkUntilReleased() async {
        guard parked == nil else { return }
        hasArrived = true
        arrival?.resume(); arrival = nil
        await withCheckedContinuation { parked = $0 }
    }

    func waitUntilParked() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() { parked?.resume(); parked = nil }
}

// MARK: - 容器路径变化

@Suite struct ExercisePhotoContainerMoveTests {
    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "photo-container-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeWorkflow(directory: URL, library: ScriptedLibraryRepository) -> (ExercisePhotoWorkflow, LocalPhotoFileSystem) {
        let fileSystem = LocalPhotoFileSystem(directory: directory)
        let storage = ExercisePhotoStorage(fileSystem: fileSystem)
        let service = ExerciseLibraryService(library: library, workouts: InMemoryWorkoutRepository())
        return (ExercisePhotoWorkflow(service: service, repository: library, storage: storage), fileSystem)
    }

    // 验收：容器路径变化（同一批文件换基目录）→ 照片照常显示、清理不误删。
    // 库只存文件名；App 更新后容器路径变了，新的基目录下同一批文件照常解析，被引用的不被清理，孤立的照常清理。
    @Test func movingTheWholeDirectoryKeepsPhotosResolvableAndSweepDoesNotDeleteReferencedFiles() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let containerA = root.appending(path: "ContainerA/ExercisePhotos", directoryHint: .isDirectory)
        let containerB = root.appending(path: "ContainerB-NEW-UUID/ExercisePhotos", directoryHint: .isDirectory)
        let library = ScriptedLibraryRepository()

        // 旧容器里：一个新命名的照片、一个旧版 <id>.jpg、一个孤立文件。
        let (workflowA, fileSystemA) = makeWorkflow(directory: containerA, library: library)
        let created = try await workflowA.add(name: "卧推", bodyPart: "胸", photoJPEG: jpeg("bench-bytes"))
        let newStyle = try #require(created.photoFileName)
        let legacy = "\(exerciseID(2).uuidString).jpg"
        try fileSystemA.write(jpeg("legacy-bytes"), named: legacy)
        await library.seed(ExerciseDefinition(id: exerciseID(2), name: "深蹲", bodyPart: "腿", photoFileName: legacy)!)
        try fileSystemA.write(jpeg("orphan"), named: "ORPHAN.jpg")

        // 库里存的只是文件名：不含任何路径成分，也不含旧容器的路径。
        for definition in try await library.allExercises() {
            let stored = try #require(definition.photoFileName)
            #expect(!stored.contains("/") && !stored.contains("ContainerA"))
        }

        // 容器换了位置：整个目录搬到新的基目录下（库不变）。
        try FileManager.default.createDirectory(at: containerB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: containerA, to: containerB)
        #expect(!FileManager.default.fileExists(atPath: containerA.path))

        let (workflowB, fileSystemB) = makeWorkflow(directory: containerB, library: library)

        // 照常显示：用当前基目录拼出的位置能读到原来的字节。
        let newURL = fileSystemB.url(for: newStyle), legacyURL = fileSystemB.url(for: legacy)
        #expect(try Data(contentsOf: newURL) == jpeg("bench-bytes"))
        #expect(try Data(contentsOf: legacyURL) == jpeg("legacy-bytes"))
        #expect(newURL.path.contains("ContainerB-NEW-UUID"))

        // 清理不误删：被引用的两张保留，只有孤立文件被删。
        let result = await workflowB.sweepUnreferencedPhotos()
        #expect(result == .completed(deleted: ["ORPHAN.jpg"], failed: []))
        #expect(try Set(fileSystemB.list()) == [newStyle, legacy])
        #expect(try Data(contentsOf: newURL) == jpeg("bench-bytes"))
        #expect(try Data(contentsOf: legacyURL) == jpeg("legacy-bytes"))

        // 换到新容器后继续换图也照常：旧图（旧命名）被尽力删掉，库指向新文件。
        let replaced = try await workflowB.update(id: exerciseID(2), name: "深蹲", bodyPart: "腿", photo: .replace(jpeg("squat-new")))
        let replacedName = try #require(replaced.photoFileName)
        #expect(try Set(fileSystemB.list()) == [newStyle, replacedName])
        #expect(try Data(contentsOf: fileSystemB.url(for: replacedName)) == jpeg("squat-new"))
    }

    @Test func localFileSystemNeverOverwritesAndListsAMissingDirectoryAsEmpty() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = LocalPhotoFileSystem(directory: root.appending(path: "NotCreatedYet", directoryHint: .isDirectory))
        #expect(try fileSystem.list().isEmpty)

        try fileSystem.write(jpeg("one"), named: "a.jpg")
        #expect(throws: (any Error).self) { try fileSystem.write(jpeg("two"), named: "a.jpg") }
        #expect(try Data(contentsOf: fileSystem.url(for: "a.jpg")) == jpeg("one"))
        try fileSystem.remove(named: "a.jpg")
        #expect(try fileSystem.list().isEmpty)
    }
}
