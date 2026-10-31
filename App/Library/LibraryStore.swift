import Foundation
import Observation
import OSLog
import TrainingRecordCore

/// 照片的变化。
enum PhotoChange {
    case keep
    case remove
    case replace(Data)
}

/// 动作库的界面状态与操作。规则都在 `ExerciseLibraryService`（T008），这里负责：照片文件的提交 / 补偿、刷新的先后顺序、
/// 以及把所有会改动作库的操作排成一队（一次只跑一个），避免「读—改—写」被别的操作插进来。
@MainActor @Observable
final class LibraryStore {
    let service: ExerciseLibraryService
    let repository: any ExerciseLibraryRepository
    let photos: ExercisePhotoStore

    /// 动作库全部动作（按部位、名字排序）。这是**展示缓存**，不能当作写入的依据（写入前一律读仓储里的最新值）。
    private(set) var exercises: [ExerciseDefinition] = []
    /// 最近一次加载动作库是否成功过（失败时不要拿空的 `exercises` 去同步训练草稿）。
    private(set) var isLoaded = false
    /// 启动时的回填（数据迁移）失败。
    private(set) var backfillFailed = false
    /// 照片被换/删时自增，让缩略图重新读文件（文件名不变）。
    private(set) var photoRevision = 0
    /// 本次运行里合并过的动作：被并入的 id → 目标 id。训练草稿据此把已添加的动作改指向目标。
    private(set) var mergedInto: [UUID: UUID] = [:]
    /// 删除 / 合并后没能删掉的照片文件名，会在下一次操作或启动时重试。
    private(set) var pendingPhotoCleanup: Set<String> = []

    @ObservationIgnored private let logger = Logger(subsystem: "com.phx.TrainingRecord", category: "ExerciseLibrary")
    @ObservationIgnored private var reloadToken = 0
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(service: ExerciseLibraryService, repository: any ExerciseLibraryRepository, photos: ExercisePhotoStore) {
        self.service = service
        self.repository = repository
        self.photos = photos
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
    /// 回填之后清理上次遗留的临时 / 备份 / 孤立照片文件。
    func runBackfill() async {
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
                await sweepPhotos()
            }
        } catch {
            logger.error("启动整理失败：\(String(describing: error))")
        }
    }

    /// 删除没有被任何动作引用的照片文件；删不掉的记下来，下次再试。只在串行队列里调用。
    private func sweepPhotos() async {
        guard let all = try? await repository.allExercises() else { return }
        let referenced = Set(all.compactMap(\.photoFileName))
        let failed = photos.sweep(keeping: referenced)
        pendingPhotoCleanup = Set(failed)
        if !failed.isEmpty { logger.error("照片文件清理失败，稍后重试：\(failed.joined(separator: ", "))") }
    }

    /// 删除一个已确认不再需要的照片文件；失败时记录并留待重试，不让整个操作失败（动作库那边已经成功了）。
    private func removePhotoFile(_ fileName: String?) {
        guard let fileName else { return }
        do {
            try photos.remove(fileName: fileName)
        } catch {
            pendingPhotoCleanup.insert(fileName)
            logger.error("删除照片文件失败「\(fileName)」，稍后重试：\(String(describing: error))")
        }
    }

    // MARK: 增删改

    /// 新建动作。带照片时：先把照片处理成临时文件（失败则什么都没创建），再创建条目、放置照片、写回文件名；
    /// 中途任何一步失败都回滚本次创建，不留下半成品条目（否则重试会被自己留下的同名条目挡住）。
    @discardableResult
    func add(name: String, bodyPart: String, photoData: Data?) async throws -> ExerciseDefinition {
        try await serialized {
            let staged = try photoData.map { try photos.stage(imageData: $0) }
            let created: ExerciseDefinition
            do {
                created = try await service.add(name: name, bodyPart: bodyPart, photoFileName: nil)
            } catch {
                if let staged { photos.discard(staged) }
                throw error
            }
            guard let staged else {
                await reload()
                return created
            }
            do {
                let installed = try photos.install(staged, exerciseID: created.id)
                do {
                    let updated = try await service.update(
                        id: created.id, name: created.name, bodyPart: created.bodyPart, photoFileName: installed.fileName
                    )
                    photos.finalize(installed)
                    photoRevision += 1
                    await reload()
                    return updated
                } catch {
                    photos.rollback(installed)
                    throw error
                }
            } catch {
                photos.discard(staged)
                do {
                    try await service.delete(id: created.id)  // 回滚本次创建
                } catch {
                    logger.error("新建失败后回滚条目也失败：\(String(describing: error))")
                }
                await reload()
                throw error
            }
        }
    }

    /// 修改动作。照片的变化是「先提交文件、再更新条目、失败则还原」：失败时旧照片保持原样，也不留孤立文件。
    @discardableResult
    func update(id: UUID, name: String, bodyPart: String, photo: PhotoChange) async throws -> ExerciseDefinition {
        try await serialized {
            // 读仓储里的最新值，不用展示缓存（缓存可能落后）。
            guard let current = try await repository.exercise(id: id) else { throw ExerciseLibraryError.notFound }
            let updated: ExerciseDefinition
            switch photo {
            case .keep:
                updated = try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: current.photoFileName)
            case .remove:
                updated = try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: nil)
                removePhotoFile(current.photoFileName)
                photoRevision += 1
            case .replace(let data):
                let staged = try photos.stage(imageData: data)
                let installed: ExercisePhotoStore.InstalledPhoto
                do {
                    installed = try photos.install(staged, exerciseID: id)
                } catch {
                    photos.discard(staged)
                    throw error
                }
                do {
                    updated = try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: installed.fileName)
                } catch {
                    photos.rollback(installed)
                    throw error
                }
                photos.finalize(installed)
                photoRevision += 1
            }
            await reload()
            await retryPendingCleanup()
            return updated
        }
    }

    /// 删除动作；仍有训练记录时抛 `.inUse`。成功后删除它的照片文件。
    func delete(id: UUID) async throws {
        try await serialized {
            let fileName = try await repository.exercise(id: id)?.photoFileName
            try await service.delete(id: id)
            removePhotoFile(fileName)
            await reload()
            await retryPendingCleanup()
        }
    }

    /// 合并记录：source 的历史并入 target，source 从动作库删除（连同它的照片文件）。
    /// 可能只完成一部分（历史已改、source 条目还在）：重试可以补完。
    func merge(sourceID: UUID, into targetID: UUID) async throws {
        try await serialized {
            let fileName = try await repository.exercise(id: sourceID)?.photoFileName
            try await service.merge(sourceID: sourceID, into: targetID)
            mergedInto[sourceID] = targetID
            removePhotoFile(fileName)
            await reload()
            await retryPendingCleanup()
        }
    }

    /// 重试上次没删掉的照片文件。
    private func retryPendingCleanup() async {
        guard !pendingPhotoCleanup.isEmpty else { return }
        await sweepPhotos()
    }
}
