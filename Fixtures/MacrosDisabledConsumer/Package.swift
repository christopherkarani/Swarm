// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacrosDisabledConsumer",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "MacrosDisabledConsumer", targets: ["MacrosDisabledConsumer"]),
    ],
    dependencies: [
        // Empty traits disable default-on Macros and must resolve without swift-syntax.
        .package(name: "Swarm", path: "../..", traits: []),
    ],
    targets: [
        .target(
            name: "MacrosDisabledConsumer",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "MacrosDisabledConsumerTests",
            dependencies: [
                "MacrosDisabledConsumer",
                .product(name: "Swarm", package: "Swarm"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
