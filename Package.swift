// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhitePointBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WhitePointBar",
            path: "Sources/WhitePointBar"
        )
    ]
)
