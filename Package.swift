// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TrainingRecordCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TrainingRecordCore", targets: ["TrainingRecordCore"])],
    targets: [
        .target(name: "TrainingRecordCore"),
        .testTarget(name: "TrainingRecordCoreTests", dependencies: ["TrainingRecordCore"])
    ]
)
