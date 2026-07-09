// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ActiveLens",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ActiveLens",
            path: "Sources/ActiveLens"
        ),
        .testTarget(
            name: "ActiveLensTests",
            dependencies: ["ActiveLens"],
            path: "Tests/ActiveLensTests"
        ),
    ]
)
