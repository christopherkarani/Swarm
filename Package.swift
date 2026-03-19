// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation

let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
    .library(name: "SwarmHive", targets: ["SwarmHive"]),
    .library(name: "SwarmMembrane", targets: ["SwarmMembrane"]),
    .library(name: "SwarmMCP", targets: ["SwarmMCP"]),
]

if includeDemo {
    packageProducts.append(.executable(name: "SwarmDemo", targets: ["SwarmDemo"]))
    packageProducts.append(.executable(name: "SwarmMCPServerDemo", targets: ["SwarmMCPServerDemo"]))
}

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
    .package(url: "https://github.com/christopherkarani/Wax.git", from: "0.1.17"),
    .package(
        url: "https://github.com/christopherkarani/Conduit",
        exact: "0.3.5",
        traits: [
            .trait(name: "OpenAI"),
            .trait(name: "OpenRouter"),
            .trait(name: "Anthropic"),
        ]
    ),
    .package(url: "https://github.com/christopherkarani/Membrane", from: "0.1.1"),
]

packageDependencies.append(.package(url: "https://github.com/christopherkarani/Hive", from: "0.1.7"))

var swarmDependencies: [Target.Dependency] = [
    "SwarmMacros",
    .product(name: "Logging", package: "swift-log"),
    .product(name: "Wax", package: "Wax"),
    .product(name: "Conduit", package: "Conduit"),
    .product(name: "HiveCore", package: "Hive"),
    .product(name: "Membrane", package: "Membrane", condition: .when(traits: ["membrane"])),
    .product(name: "MembraneHive", package: "Membrane", condition: .when(traits: ["membrane"]))
]

var swarmSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .define("SWARM_HIVE", .when(traits: ["hive"])),
    .define("SWARM_MEMBRANE", .when(traits: ["membrane"]))
]

var packageTargets: [Target] = [
    // MARK: - Macro Implementation (Compiler Plugin)
    .macro(
        name: "SwarmMacros",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),

    // MARK: - Main Library
    .target(
        name: "Swarm",
        dependencies: swarmDependencies,
        exclude: [
            "HiveSwarm",
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmHive",
        dependencies: [
            "Swarm",
            .product(name: "HiveCore", package: "Hive"),
        ],
        path: "Sources/Swarm/HiveSwarm",
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmMembrane",
        dependencies: [
            "Swarm",
        ],
        path: "Sources/SwarmMembrane",
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmMCP",
        dependencies: [
            "Swarm",
            .product(name: "MCP", package: "swift-sdk"),
        ],
        swiftSettings: swarmSwiftSettings
    ),

    // MARK: - Tests
    .testTarget(
        name: "SwarmTests",
        dependencies: [
            "Swarm",
            "SwarmHive",
            "SwarmMCP",
            .product(name: "Conduit", package: "Conduit"),
        ],
        resources: [
            .copy("Guardrails/INTEGRATION_TEST_SUMMARY.md"),
            .copy("Guardrails/QUICK_REFERENCE.md")
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "HiveSwarmTests",
        dependencies: [
            "Swarm",
            "SwarmHive",
            .product(name: "HiveCore", package: "Hive")
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "SwarmMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    )
]

if includeDemo {
    packageTargets.append(
        .executableTarget(
            name: "SwarmDemo",
            dependencies: ["Swarm"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )

    packageTargets.append(
        .executableTarget(
            name: "SwarmMCPServerDemo",
            dependencies: [
                "Swarm",
                "SwarmMCP",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )
}

let package = Package(
    name: "Swarm",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
    ],
    products: packageProducts,
    traits: [
        .trait(
            name: "hive",
            description: "Enable Hive-backed workflow and runtime integration features."
        ),
        .trait(
            name: "membrane",
            description: "Enable Membrane-based planning and tool output transformations."
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
