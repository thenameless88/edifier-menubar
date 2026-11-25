// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EdifierBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MR5Protocol"),
        .executableTarget(name: "EdifierBar", dependencies: ["MR5Protocol"]),
        .executableTarget(name: "mr5-selftest", dependencies: ["MR5Protocol"]),
    ]
)
