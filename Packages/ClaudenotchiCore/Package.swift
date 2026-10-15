// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudenotchiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudenotchiCore", targets: ["ClaudenotchiCore"]),
        .executable(name: "claudenotchi-hook", targets: ["claudenotchi-hook"]),
    ],
    targets: [
        .target(name: "ClaudenotchiCore"),
        .executableTarget(name: "claudenotchi-hook", dependencies: ["ClaudenotchiCore"]),
        .testTarget(name: "ClaudenotchiCoreTests", dependencies: ["ClaudenotchiCore"]),
    ]
)
