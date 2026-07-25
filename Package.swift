// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiControlApp",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "MiControlApp", targets: ["MiControlApp"]),
        .executable(name: "MiControlCLI", targets: ["MiControlCLI"]),
    ],
    targets: [
        .executableTarget(name: "MiControlApp", path: "Sources/MiControlApp"),
        .executableTarget(name: "MiControlCLI", path: "Sources/MiControlCLI"),
        .testTarget(name: "MiControlAppTests", dependencies: ["MiControlApp"], path: "Tests/MiControlAppTests"),
    ],
    swiftLanguageModes: [.v5]
)
