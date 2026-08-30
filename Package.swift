// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EpexMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EpexMenuBar", targets: ["EpexMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "EpexMenuBar",
            path: "Sources/EpexMenuBar"
        )
    ]
)
