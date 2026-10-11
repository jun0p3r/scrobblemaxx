// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Scrobblemaxx",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Scrobblemaxx", path: "Sources/Scrobblemaxx")
    ]
)
