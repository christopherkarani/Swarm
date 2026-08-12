// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WaxChat",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "WaxChat", targets: ["WaxChat"]),
        .library(name: "WaxChatCore", targets: ["WaxChatCore"]),
    ],
    dependencies: [
        // WaxMemory + WebSearchTool require Integrations.
        .package(name: "Swarm", path: "../../", traits: ["Integrations"]),
    ],
    targets: [
        .target(
            name: "WaxChatCore",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/WaxChatCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "WaxChat",
            dependencies: [
                "WaxChatCore",
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/WaxChat",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "WaxChatCoreTests",
            dependencies: [
                "WaxChatCore",
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Tests/WaxChatCoreTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
