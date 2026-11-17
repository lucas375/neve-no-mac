// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NeveMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NeveMac", targets: ["NeveMac"]),
        .library(name: "NeveScreenSaver", type: .dynamic, targets: ["NeveScreenSaver"])
    ],
    targets: [
        .target(name: "NeveCore"),
        .target(name: "NeveRendering", dependencies: ["NeveCore"]),
        .target(name: "NeveScreenSaver", dependencies: ["NeveCore", "NeveRendering"]),
        .executableTarget(name: "NeveMac", dependencies: ["NeveCore", "NeveRendering"]),
        .testTarget(name: "NeveCoreTests", dependencies: ["NeveCore"])
    ]
)
