import Foundation

/// 照片的变化（编辑动作时）。`replace` 带的是已经缩放、编码好的 JPEG 数据。
public enum ExercisePhotoChange: Sendable, Equatable {
    case keep
    case remove
    case replace(Data)
}

/// 动作库操作 + 照片文件：把 `ExerciseLibraryService`（规则、历史同步）和 `ExercisePhotoStorage`（文件、保存顺序、清理）接起来。
///
/// 顺序约定（见 `ExercisePhotoStorage` 开头）：
/// - 新建 / 换图：先写新文件 → 保存到动作库 → 成功后尽力删旧；失败尽力删新，动作库与旧图保持原样；
/// - 移除照片 / 删除动作 / 合并：先改动作库，成功后才尽力删文件。
///
/// 本类型不做串行化；会改动作库的操作由调用方（App 的 `LibraryStore`）排队。
public struct ExercisePhotoWorkflow: Sendable {
    public let service: ExerciseLibraryService
    public let repository: any ExerciseLibraryRepository
    public let storage: ExercisePhotoStorage

    public init(service: ExerciseLibraryService, repository: any ExerciseLibraryRepository, storage: ExercisePhotoStorage) {
        self.service = service
        self.repository = repository
        self.storage = storage
    }

    /// 新建动作。带照片时先写照片文件再保存；写文件失败 → 抛 `PhotoStorageError.writeFailed`，不产生动作。
    /// 动作的 id 在保存时才生成，所以照片文件名里的前缀是这次新建专用的临时 id（只影响文件名，不影响引用关系）。
    public func add(name: String, bodyPart: String, photoJPEG: Data?) async throws -> ExerciseDefinition {
        guard let photoJPEG else {
            return try await service.add(name: name, bodyPart: bodyPart, photoFileName: nil)
        }
        let service = self.service
        return try await storage.save(jpeg: photoJPEG, ownerID: UUID(), replacing: nil) { fileName in
            try await service.add(name: name, bodyPart: bodyPart, photoFileName: fileName)
        }
    }

    /// 修改动作。照片的变化见类型说明；写新文件失败时不保存，动作与旧图都不动。
    public func update(id: UUID, name: String, bodyPart: String, photo: ExercisePhotoChange) async throws -> ExerciseDefinition {
        // 读仓储里的最新值（展示缓存可能落后）。
        guard let current = try await repository.exercise(id: id) else { throw ExerciseLibraryError.notFound }
        let service = self.service
        switch photo {
        case .keep:
            return try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: current.photoFileName)
        case .remove:
            let updated = try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: nil)
            storage.discard(current.photoFileName)
            return updated
        case .replace(let jpeg):
            return try await storage.save(jpeg: jpeg, ownerID: id, replacing: current.photoFileName) { fileName in
                try await service.update(id: id, name: name, bodyPart: bodyPart, photoFileName: fileName)
            }
        }
    }

    /// 删除动作（仍有训练记录时抛 `.inUse`）。成功后尽力删它的照片文件。
    public func delete(id: UUID) async throws {
        let fileName = try await repository.exercise(id: id)?.photoFileName
        try await service.delete(id: id)
        storage.discard(fileName)
    }

    /// 合并记录。成功后尽力删源动作的照片文件。
    public func merge(sourceID: UUID, into targetID: UUID) async throws {
        guard sourceID != targetID else { return }  // 并入自己什么都不做；动作还在，照片不能删
        let fileName = try await repository.exercise(id: sourceID)?.photoFileName
        try await service.merge(sourceID: sourceID, into: targetID)
        storage.discard(fileName)
    }

    /// 启动清理：动作库加载成功后，删除库里没有任何动作引用的照片文件；动作库加载失败 → 跳过。
    public func sweepUnreferencedPhotos() async -> PhotoSweepResult {
        let repository = self.repository
        return await storage.sweepUnreferenced {
            Set(try await repository.allExercises().compactMap(\.photoFileName))
        }
    }
}
