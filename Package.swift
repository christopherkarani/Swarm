// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation
let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"
let coreOnly = ProcessInfo.processInfo.environment["SWARM_CORE_ONLY"] == "1"
// Root-package lean CI/dev helper: omit in-tree integration *targets* so bare
// `swift build` / `swift test` do not compile HiveCore/Membrane/ContextCore
// orphans (SPM root builds every target). Consumers never set this — they get
// the full Package.swift with trait-gated edges (lean resolve, no MetalANNS).
let omitIntegrationTargets =
    ProcessInfo.processInfo.environment["SWARM_OMIT_INTEGRATION_TARGETS"] == "1"
let enableIntegrationModules = !coreOnly && !omitIntegrationTargets

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
    .library(name: "SwarmOpenTelemetry", targets: ["SwarmOpenTelemetry"]),
    .library(name: "SwarmMembrane", targets: ["SwarmMembrane"]),
    .library(name: "SwarmMCP", targets: ["SwarmMCP"]),
]

if includeDemo {
    packageProducts.append(.executable(name: "SwarmDemo", targets: ["SwarmDemo"]))
    packageProducts.append(.executable(name: "SwarmMCPServerDemo", targets: ["SwarmMCPServerDemo"]))
}

var packageDependencies: [Package.Dependency] = [
    // Floor swift-syntax at 601 so SPM cannot resolve 600.x (especially 600.0.1).
    //
    // Background: Xcode 26 (Swift 6.2.x) ships implicit SwiftPM prebuilts for
    // swift-syntax via the swiftlang "MacroSupport" prebuilt server. The 600.0.1
    // prebuilt is built against an older macOS SDK and fails to load on consumer
    // machines with "SDK does not match" warnings followed by
    // "Unable to find module dependency: 'SwiftSyntax'" errors. That prebuilt
    // download cannot be disabled from a consumer project (SWIFT_USE_PREBUILT_MACROS=NO,
    // IDESwiftPackageEnablePrebuilts=NO, SWIFTPM_DISABLE_PREBUILTS=1 and
    // -skipMacroValidation all fail to suppress it). Floor ≥ 601 keeps resolution
    // on toolchains/prebuilts that work with Swift 6.2 / Xcode 26.
    // Only SwarmMacros (+ SwiftSyntaxMacrosTestSupport in tests) depends on
    // swift-syntax. Upper bound stays <603 for package-graph stability.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"603.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.4.1"),
]

// Integrations trait: opt-in graph/memory/web/Hive paths (off by default).
// HiveCore, Membrane*, and ContextCore* are native in-tree Sources/ targets.
// Product edges into those modules (and their remote deps) are trait-gated so
// lean resolve/build does not pull MetalANNS/Wax/crypto/mutex/collections.
//
// ContextCore / Membrane (full stack) require Apple frameworks (Metal, CoreML,
// Accelerate). They are trait-linked only on Apple platforms so Linux
// Integrations can still build Hive + MembraneCore + web helpers without
// compiling the GPU memory stack.
let integrationTrait = "Integrations"
let appleIntegrationPlatforms: [Platform] = [.macOS, .iOS, .tvOS, .visionOS]
if enableIntegrationModules {
    packageDependencies += [
        // Declared when integration modules are registered. All are only *used*
        // through trait-gated product/target edges (Swarm → Hive/Membrane/
        // ContextCore/Wax/SwiftSoup, and in-tree modules → crypto/mutex/
        // collections/MetalANNS). With Integrations off, SPM does not pin them.
        // SWARM_CORE_ONLY=1 or SWARM_OMIT_INTEGRATION_TARGETS=1 drops this block.
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.5"),
        .package(url: "https://github.com/christopherkarani/Wax.git", exact: "0.1.23"),
        .package(url: "https://github.com/christopherkarani/MetalANNS.git", exact: "0.1.3"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.7.0"),
        .package(url: "https://github.com/swhitty/swift-mutex.git", from: "0.0.6"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ]
}

var swarmDependencies: [Target.Dependency] = [
    "SwarmMacros",
    .product(name: "Logging", package: "swift-log"),
]

var swarmSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

if enableIntegrationModules {
    swarmDependencies += [
        // HTML parsing for web helpers; only linked when Integrations is enabled.
        .product(name: "SwiftSoup", package: "SwiftSoup", condition: .when(traits: [integrationTrait])),
        // Portable Integrations modules (all platforms when trait is on).
        .target(name: "HiveCore", condition: .when(traits: [integrationTrait])),
        .target(name: "MembraneCore", condition: .when(traits: [integrationTrait])),
        // Apple-only memory / Membrane session stack (Metal / CoreML / MetalANNS).
        .target(
            name: "Membrane",
            condition: .when(platforms: appleIntegrationPlatforms, traits: [integrationTrait])
        ),
        .target(
            name: "MembraneContextCore",
            condition: .when(platforms: appleIntegrationPlatforms, traits: [integrationTrait])
        ),
        .target(
            name: "ContextCore",
            condition: .when(platforms: appleIntegrationPlatforms, traits: [integrationTrait])
        ),
        // Wax remains an external package + trait-gated product dependency.
        .product(name: "Wax", package: "Wax", condition: .when(traits: [integrationTrait])),
    ]
    swarmSwiftSettings.append(.define("SWARM_INTEGRATIONS", .when(traits: [integrationTrait])))
}

let swarmCoreOnlyExcludes = [
    "Integration/Wax",
    "Integration/Membrane/SessionMembraneAgentAdapter.swift",
    "Integration/Membrane/WaxMembraneStorage.swift",
    "Internal/GraphRuntime",
    "Memory/ContextCoreMemory.swift",
    "Memory/DefaultAgentMemory.swift",
    "Tools/Web",
    "Workflow/WorkflowCheckpointCodec.swift",
    "Workflow/WorkflowCheckpointStore.swift",
    "Workflow/WorkflowDurableEngine.swift",
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
        exclude: enableIntegrationModules ? [] : swarmCoreOnlyExcludes,
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmOpenTelemetry",
        dependencies: [
            "Swarm",
            .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        ],
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
    .target(
        name: "SwarmCapabilityShowcaseSupport",
        dependencies: [
            "Swarm",
            "SwarmMCP",
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .executableTarget(
        name: "SwarmCapabilityShowcase",
        dependencies: [
            "SwarmCapabilityShowcaseSupport",
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),

    // MARK: - Tests
    .testTarget(
        name: "SwarmTests",
        dependencies: {
            var dependencies: [Target.Dependency] = [
                "Swarm",
                "SwarmMCP",
            ]
            if enableIntegrationModules {
                dependencies += [
                    .target(name: "MembraneCore", condition: .when(traits: [integrationTrait])),
                    .target(
                        name: "Membrane",
                        condition: .when(platforms: appleIntegrationPlatforms, traits: [integrationTrait])
                    ),
                ]
            }
            return dependencies
        }(),
        resources: [],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "Swarm",
            "SwarmMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),
    .testTarget(
        name: "SwarmCapabilityShowcaseTests",
        dependencies: [
            "SwarmCapabilityShowcaseSupport",
        ],
        // Inherit SWARM_INTEGRATIONS so requiredFamilies/durable match the support target.
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmOpenTelemetryTests",
        dependencies: [
            "Swarm",
            "SwarmOpenTelemetry",
            .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        ],
        swiftSettings: swarmSwiftSettings
    )
]

if enableIntegrationModules {
    // MARK: - In-tree Integrations modules (internal targets only — no library products)
    // HiveCore, Membrane*, ContextCore* live under Sources/ and are linked into Swarm
    // only when the Integrations trait is enabled.

    let integrationsTargetSwiftSettings: [SwiftSetting] = [
        .enableExperimentalFeature("StrictConcurrency"),
        .swiftLanguageMode(.v6),
    ]

    // Trait-gate remote product deps on in-tree modules. Unconditional product
    // edges made SPM pin MetalANNS/crypto/mutex/collections even when
    // Integrations was off (targets registered but unused). With trait gates,
    // lean resolve only pins always-on remotes (syntax/log/MCP/OTel + NIO).
    //
    // Note: SPM root packages still *compile* every registered target on bare
    // `swift build`/`swift test`. Use product-scoped builds, or
    // SWARM_OMIT_INTEGRATION_TARGETS=1 for root-package lean CI (see
    // scripts/ci/lean-build-test.sh). Consumers only build reachable targets.
    let integrationsRemoteDepsActive = TargetDependencyCondition.when(traits: [integrationTrait])
    let integrationsAppleRemoteDepsActive = TargetDependencyCondition.when(
        platforms: appleIntegrationPlatforms,
        traits: [integrationTrait]
    )

    packageTargets += [
        // HiveCore — durable graph / checkpoint runtime
        .target(
            name: "HiveCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: integrationsRemoteDepsActive),
                .product(name: "Mutex", package: "swift-mutex", condition: integrationsRemoteDepsActive),
            ],
            path: "Sources/HiveCore",
            exclude: ["README.md"],
            swiftSettings: integrationsTargetSwiftSettings
        ),

        // Membrane stack
        .target(
            name: "MembraneCore",
            dependencies: [
                .product(
                    name: "OrderedCollections",
                    package: "swift-collections",
                    condition: integrationsRemoteDepsActive
                ),
            ],
            path: "Sources/MembraneCore",
            swiftSettings: integrationsTargetSwiftSettings
        ),
        .target(
            name: "MembraneContextCore",
            dependencies: [
                "MembraneCore",
                "ContextCore",
            ],
            path: "Sources/MembraneContextCore",
            swiftSettings: integrationsTargetSwiftSettings
        ),
        .target(
            name: "Membrane",
            dependencies: [
                "MembraneCore",
                "MembraneContextCore",
            ],
            path: "Sources/Membrane",
            swiftSettings: integrationsTargetSwiftSettings
        ),

        // ContextCore stack (MetalANNS remains remote; Apple + Integrations only)
        .target(
            name: "ContextCoreTypes",
            path: "Sources/ContextCoreTypes",
            swiftSettings: integrationsTargetSwiftSettings
        ),
        .target(
            name: "ContextCoreShaders",
            path: "Sources/ContextCoreShaders",
            resources: [.process("Shaders")],
            swiftSettings: integrationsTargetSwiftSettings,
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: appleIntegrationPlatforms)),
            ]
        ),
        .target(
            name: "ContextCoreEngine",
            dependencies: [
                "ContextCoreShaders",
                "ContextCoreTypes",
                .product(
                    name: "MetalANNS",
                    package: "MetalANNS",
                    condition: integrationsAppleRemoteDepsActive
                ),
            ],
            path: "Sources/ContextCoreEngine",
            swiftSettings: integrationsTargetSwiftSettings,
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: appleIntegrationPlatforms)),
                .linkedFramework("CoreML", .when(platforms: appleIntegrationPlatforms)),
                .linkedFramework("Accelerate", .when(platforms: appleIntegrationPlatforms)),
            ]
        ),
        .target(
            name: "ContextCore",
            dependencies: [
                "ContextCoreEngine",
                "ContextCoreTypes",
                .product(
                    name: "MetalANNS",
                    package: "MetalANNS",
                    condition: integrationsAppleRemoteDepsActive
                ),
            ],
            path: "Sources/ContextCore",
            resources: [.process("Resources")],
            swiftSettings: integrationsTargetSwiftSettings,
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: appleIntegrationPlatforms)),
                .linkedFramework("CoreML", .when(platforms: appleIntegrationPlatforms)),
                .linkedFramework("Accelerate", .when(platforms: appleIntegrationPlatforms)),
            ]
        ),

        .testTarget(
            name: "HiveSwarmTests",
            dependencies: [
                "Swarm",
                .target(name: "HiveCore", condition: .when(traits: [integrationTrait])),
            ],
            swiftSettings: swarmSwiftSettings
        ),
    ]
}

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
        // Lean default: core Swarm + Foundation Models only. Opt in for full graph.
        .default(enabledTraits: []),
        .trait(
            name: integrationTrait,
            description: """
            Enable SWARM_INTEGRATIONS: durable Hive workflows, ContextCore+Wax default memory, \
            Membrane adapters, and web helpers. Off by default. HiveCore, Membrane, and \
            ContextCore are native in-tree Sources/ targets (internal; not separate products). \
            ContextCore / full Membrane session stack require Apple platforms (Metal/CoreML); \
            Linux Integrations still gets Hive + MembraneCore + web helpers. \
            Wax remains an external package for now.
            """
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
