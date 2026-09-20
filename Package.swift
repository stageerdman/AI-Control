// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AIControlCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AIControlCore",
            targets: ["AIControlCore"]
        )
    ],
    targets: [
        .target(
            name: "AIControlCore",
            path: "Sources/AIControlCore"
        ),
        .testTarget(
            name: "AIControlCoreTests",
            dependencies: ["AIControlCore"],
            path: "Tests/AIControlCoreTests"
        )
    ]
)
