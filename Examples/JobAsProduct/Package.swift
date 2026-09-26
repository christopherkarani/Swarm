// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JobAsProduct",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Swarm", path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "JobAsProduct",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/JobAsProduct",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
