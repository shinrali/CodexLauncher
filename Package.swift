// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexLauncher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexLauncher", targets: ["CodexLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "CodexLauncher",
            path: "Sources/CodexLauncher"
        ),
        .testTarget(
            name: "CodexLauncherTests",
            dependencies: ["CodexLauncher"],
            path: "Tests/CodexLauncherTests"
        )
    ]
)
