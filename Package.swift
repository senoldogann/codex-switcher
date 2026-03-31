// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexSwitcher",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CodexSwitcher",
            path: "Sources/CodexSwitcher",
            resources: [
                .copy("Resources/codex.icns")
            ]
        )
    ]
)
