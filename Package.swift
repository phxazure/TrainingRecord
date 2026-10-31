// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TrainingRecordCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TrainingRecordCore", targets: ["TrainingRecordCore"]),
        .library(name: "TrainingRecordPersistence", targets: ["TrainingRecordPersistence"])
    ],
    targets: [
        .target(name: "TrainingRecordCore"),
        .testTarget(name: "TrainingRecordCoreTests", dependencies: ["TrainingRecordCore"]),
        // SwiftData 实现的本地持久化：独立于 App target，可在 macOS 上用 `swift test` 无模拟器测试。
        .target(name: "TrainingRecordPersistence", dependencies: ["TrainingRecordCore"]),
        .testTarget(
            name: "TrainingRecordPersistenceTests",
            dependencies: ["TrainingRecordPersistence", "TrainingRecordCore"]
        )
    ]
)
