// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexSwitcher",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexSwitcher",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CodexSwitcher",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
