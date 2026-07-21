// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiControlApp",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "MiControlApp", targets: ["MiControlApp"])
    ],
    targets: [
        .executableTarget(name: "MiControlApp", path: "Sources/MiControlApp"),
        .testTarget(name: "MiControlAppTests", dependencies: ["MiControlApp"], path: "Tests/MiControlAppTests"),
    ],
    swiftLanguageModes: [.v5]
)
