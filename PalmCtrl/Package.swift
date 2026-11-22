// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PalmCtrl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PalmCtrl",
            path: "Sources/PalmCtrl"
        )
    ]
)
