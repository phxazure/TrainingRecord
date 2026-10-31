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

/// 动作库的界面状态与操作。规则都在 `ExerciseLibraryService`（T008），这里只负责照片文件和刷新。
@MainActor @Observable
final class LibraryStore {
    let service: ExerciseLibraryService
    let repository: any ExerciseLibraryRepository
    let photos: ExercisePhotoStore

    /// 动作库全部动作（按部位、名字排序）。
    private(set) var exercises: [ExerciseDefinition] = []
    /// 启动时的回填（数据迁移）失败。
    private(set) var backfillFailed = false
    /// 照片被换/删时自增，让缩略图重新读文件（文件名不变）。
    private(set) var photoRevision = 0

    @ObservationIgnored private let logger = Logger(subsystem: "com.phx.TrainingRecord", category: "ExerciseLibrary")

    init(service: ExerciseLibraryService, repository: any ExerciseLibraryRepository, photos: ExercisePhotoStore) {
        self.service = service
        self.repository = repository
        self.photos = photos
    }

    func reload() async {
        do {
            exercises = try await repository.allExercises()
        } catch {
            logger.error("加载动作库失败：\(String(describing: error))")
        }
    }

    func definition(id: UUID) -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    /// 启动时回填一次：把已有历史里的动作关联到动作库。幂等；失败不崩溃，只标记（训练页顶部给提示）。
    func runBackfill() async {
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

    // MARK: 增删改

    @discardableResult
    func add(name: String, bodyPart: String, photoData: Data?) async throws -> ExerciseDefinition {
        let created = try await service.add(name: name, bodyPart: bodyPart, photoFileName: nil)
        guard let photoData else {
            await reload()
            return created
        }
        do {
            let fileName = try photos.save(imageData: photoData, exerciseID: created.id)
            let updated = try await service.update(
                id: created.id, name: created.name, bodyPart: created.bodyPart, photoFileName: fileName
            )
            photoRevision += 1
            await reload()
            return updated
        } catch {
            photos.remove(fileName: photos.fileName(for: created.id))
            await reload()
            throw error
        }
    }

    @discardableResult
    func update(id: UUID, name: String, bodyPart: String, photo: PhotoChange) async throws -> ExerciseDefinition {
        let current = definition(id: id)
        let newFileName: String?
        switch photo {
        case .keep:
            newFileName = current?.photoFileName
        case .remove:
            newFileName = nil
        case .replace(let data):
            newFileName = try photos.save(imageData: data, exerciseID: id)
        }
        let updated = try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: newFileName)
        if case .remove = photo { photos.remove(fileName: current?.photoFileName) }
        if case .keep = photo {} else { photoRevision += 1 }
        await reload()
        return updated
    }

    /// 删除动作；仍有训练记录时抛 `.inUse`。成功后删除它的照片文件。
    func delete(id: UUID) async throws {
        let fileName = definition(id: id)?.photoFileName
        try await service.delete(id: id)
        photos.remove(fileName: fileName)
        await reload()
    }

    /// 合并记录：source 的历史并入 target，source 从动作库删除（连同它的照片文件）。
    func merge(sourceID: UUID, into targetID: UUID) async throws {
        let fileName = definition(id: sourceID)?.photoFileName
        try await service.merge(sourceID: sourceID, into: targetID)
        photos.remove(fileName: fileName)
        await reload()
    }
}
