import Foundation
import Observation
import OSLog
import TrainingRecordCore

/// 照片的变化（编辑动作时）；`replace` 带的是用户选中的原始图片数据，保存时才缩放、编码。
enum PhotoChange {
    case keep
    case remove
    case replace(Data)
}

/// 动作库的界面状态与操作。规则都在 `ExerciseLibraryService`（T008），照片的命名 / 保存顺序 / 清理在 Core 的
/// `ExercisePhotoWorkflow`；这里负责：刷新的先后顺序、以及把所有会改动作库的操作排成一队（一次只跑一个），
/// 避免「读—改—写」被别的操作插进来。
@MainActor @Observable
final class LibraryStore {
    let service: ExerciseLibraryService
    let repository: any ExerciseLibraryRepository
    let photos: ExercisePhotoStore
    private let workflow: ExercisePhotoWorkflow

    /// 动作库全部动作（按部位、名字排序）。这是**展示缓存**，不能当作写入的依据（写入前一律读仓储里的最新值）。
    private(set) var exercises: [ExerciseDefinition] = []
    /// **最近一次**加载动作库是否成功。只有它为 true 时，`exercises` 才代表仓储里现在的内容：
    /// 加载失败后 `exercises` 是旧缓存，据此推断「某个动作已被删除」会把仍然有效的草稿关联误断开，所以不能用来同步训练草稿。
    private(set) var isLoaded = false
    /// 启动时的回填（数据迁移）失败。
    private(set) var backfillFailed = false
    /// 本次运行里合并过的动作：被并入的 id → 目标 id。训练草稿据此把已添加的动作改指向目标。
    private(set) var mergedInto: [UUID: UUID] = [:]

    @ObservationIgnored private let logger = Logger(subsystem: "com.phx.TrainingRecord", category: "ExerciseLibrary")
    @ObservationIgnored private var reloadToken = 0
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(service: ExerciseLibraryService, repository: any ExerciseLibraryRepository, photos: ExercisePhotoStore) {
        self.service = service
        self.repository = repository
        self.photos = photos
        self.workflow = ExercisePhotoWorkflow(service: service, repository: repository, storage: photos.storage)
    }

    // MARK: 刷新

    /// 重新加载展示缓存。多个加载交错时只认**最后发起**的那一个：较早发起、较晚返回的结果直接丢弃，
    /// 不会让缓存倒退（也就不会让已删除的动作「复活」）。
    func reload() async {
        reloadToken += 1
        let token = reloadToken
        do {
            let loaded = try await repository.allExercises()
            guard token == reloadToken else { return }
            exercises = loaded
            isLoaded = true
        } catch {
            if token == reloadToken { isLoaded = false }  // 最新的一次读取失败：缓存不可信
            logger.error("加载动作库失败：\(String(describing: error))")
        }
    }

    func definition(id: UUID) -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    // MARK: 串行队列

    /// 所有会改动作库 / 照片的操作都经过这里，一次只跑一个。
    private func serialized<T>(_ body: () async throws -> T) async throws -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        defer {
            if waiters.isEmpty {
                isBusy = false
            } else {
                waiters.removeFirst().resume()  // 把「忙」直接交给下一个
            }
        }
        return try await body()
    }

    // MARK: 启动

    /// 启动时回填一次：把已有历史里的动作关联到动作库。幂等；失败不崩溃，只标记（训练页顶部给提示）。
    /// 回填、加载之后清理没有被动作库引用的照片文件。
    func runBackfill() async {
        LegacyPhotoJournalCleanup.run(photoDirectory: photos.fileSystem.directory)
        do {
            try await serialized {
                do {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-simulateBackfillFailure") {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    #endif
                    let created = try await service.backfill()
                    backfillFailed = false
                    logger.info("动作库回填完成，新建 \(created) 个条目")
                } catch {
                    backfillFailed = true
                    logger.error("动作库回填失败：\(String(describing: error))")
                }
                await reload()
            }
        } catch {
            logger.error("启动整理失败：\(String(describing: error))")
        }
        // 清理不排进串行队列：它自己会避开正在保存、还没提交的新文件（见 `ExercisePhotoStorage`）。
        await sweepPhotos()
    }

    /// 启动清理：动作库加载成功后，删除库里没有任何动作引用的照片文件；库加载失败则跳过。
    private func sweepPhotos() async {
        switch await workflow.sweepUnreferencedPhotos() {
        case .skipped:
            logger.error("照片清理已跳过：动作库或照片目录读取失败")
        case .completed(let deleted, let failed):
            if !failed.isEmpty { logger.error("有 \(failed.count) 个孤立照片文件没能删除，留给下次启动") }
            if !deleted.isEmpty { logger.info("清理了 \(deleted.count) 个孤立照片文件") }
        }
    }

    // MARK: 增删改

    /// 新建动作。带照片时：先缩放编码（失败则什么都没动），再写新照片文件，写成功才保存到动作库；
    /// 写文件失败 → 抛 `PhotoStorageError.writeFailed`，不产生动作。
    @discardableResult
    func add(name: String, bodyPart: String, photoData: Data?) async throws -> ExerciseDefinition {
        try await serialized {
            let jpeg = try photoData.map { try photos.encode(imageData: $0) }
            let created = try await workflow.add(name: name, bodyPart: bodyPart, photoJPEG: jpeg)
            await reload()
            return created
        }
    }

    /// 修改动作。换图：先写新文件，库保存成功后才尽力删旧图；保存失败旧图与库记录保持原样。
    @discardableResult
    func update(id: UUID, name: String, bodyPart: String, photo: PhotoChange) async throws -> ExerciseDefinition {
        try await serialized {
            let change: ExercisePhotoChange
            switch photo {
            case .keep: change = .keep
            case .remove: change = .remove
            case .replace(let data): change = .replace(try photos.encode(imageData: data))
            }
            let updated = try await workflow.update(id: id, name: name, bodyPart: bodyPart, photo: change)
            await reload()
            return updated
        }
    }

    /// 删除动作；仍有训练记录时抛 `.inUse`。成功后尽力删它的照片文件。
    func delete(id: UUID) async throws {
        try await serialized {
            try await workflow.delete(id: id)
            await reload()
        }
    }

    /// 合并记录：source 的历史并入 target，source 从动作库删除（成功后尽力删它的照片文件）。
    /// 可能只完成一部分（历史已改、source 条目还在）：重试可以补完。
    func merge(sourceID: UUID, into targetID: UUID) async throws {
        try await serialized {
            try await workflow.merge(sourceID: sourceID, into: targetID)
            if sourceID != targetID { mergedInto[sourceID] = targetID }
            await reload()
        }
    }
}
