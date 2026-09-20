// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TerminalExperiment",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "TerminalExperiment",
            dependencies: ["SwiftTerm"],
            path: "Sources/TerminalExperiment"
        )
    ]
)
