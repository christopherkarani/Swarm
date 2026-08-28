// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation
let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"
let coreOnly = ProcessInfo.processInfo.environment["SWARM_CORE_ONLY"] == "1"
// Root-package lean CI/dev helper: omit in-tree integration *targets* so bare
// `swift build` / `swift test` do not compile HiveCore/Membrane/ContextCore
// orphans (SPM root builds every target). Consumers never set this — they get
// the full Package.swift with trait-gated edges (lean link; use the omit helper
// when the root-package graph must exclude integration package declarations).
let omitIntegrationTargets =
    ProcessInfo.processInfo.environment["SWARM_OMIT_INTEGRATION_TARGETS"] == "1"
let enableIntegrationModules = !coreOnly && !omitIntegrationTargets
#if os(Linux)
let registerAppleIntegrationTargets = false
#else
let registerAppleIntegrationTargets = true
#endif

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
    .library(name: "SwarmOpenTelemetry", targets: ["SwarmOpenTelemetry"]),
    // Deprecated hollow re-export; remove the product in 0.7.0.
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
    // Product edges are Macros-trait-gated so consumers can drop the pin.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"603.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
    // SwiftPM cannot conditionally declare package dependencies from a package
    // trait. These companion packages therefore remain in every resolution;
    // their target product edges below are link-time trait-gated.
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.4.1"),
]

// Integrations trait: opt-in graph/memory/web/Hive paths (off by default).
// HiveCore, Membrane*, and ContextCore* are native in-tree Sources/ targets.
// Product edges into those modules (and their remote deps) are trait-gated so
// lean target links do not include MetalANNS/Wax/crypto/mutex/collections.
//
// ContextCore / Membrane (full stack) require Apple frameworks (Metal, CoreML,
// Accelerate). They are trait-linked only on Apple platforms so Linux
// Integrations can still build Hive + MembraneCore + web helpers without
// compiling the GPU memory stack.
let macrosTrait = "Macros"
let mcpTrait = "MCP"
let otelTrait = "OpenTelemetry"
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
        // Floor at the previously exact pin. 0.1.24 fails to clone (broken
        // homebrew-wax submodule ref). 0.1.25 makes FrameStore.close()/frames()
        // throwing and breaks WaxMemory + WaxMembraneStorage. Revisit after
        // adapting to the throwing API.
        .package(url: "https://github.com/christopherkarani/Wax.git", "0.1.23"..<"0.1.24"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.7.0"),
        .package(url: "https://github.com/swhitty/swift-mutex.git", from: "0.0.6"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ]
    if registerAppleIntegrationTargets {
        packageDependencies.append(
            .package(url: "https://github.com/christopherkarani/MetalANNS.git", from: "0.1.3")
        )
    }
}

var swarmDependencies: [Target.Dependency] = [
    .target(name: "SwarmMacros", condition: .when(traits: [macrosTrait])),
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
        // Wax remains an external package + trait-gated product dependency.
        .product(name: "Wax", package: "Wax", condition: .when(traits: [integrationTrait])),
    ]
    if registerAppleIntegrationTargets {
        swarmDependencies += [
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
        ]
    }
    swarmSwiftSettings.append(.define("SWARM_INTEGRATIONS", .when(traits: [integrationTrait])))
}

swarmSwiftSettings.append(.define("SWARM_MACROS", .when(traits: [macrosTrait])))
swarmSwiftSettings.append(.define("SWARM_MCP", .when(traits: [mcpTrait])))
swarmSwiftSettings.append(.define("SWARM_OTEL", .when(traits: [otelTrait])))

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
            .product(name: "SwiftSyntax", package: "swift-syntax", condition: .when(traits: [macrosTrait])),
            .product(
                name: "SwiftSyntaxMacros",
                package: "swift-syntax",
                condition: .when(traits: [macrosTrait])
            ),
            .product(
                name: "SwiftCompilerPlugin",
                package: "swift-syntax",
                condition: .when(traits: [macrosTrait])
            ),
            .product(
                name: "SwiftSyntaxBuilder",
                package: "swift-syntax",
                condition: .when(traits: [macrosTrait])
            ),
            .product(
                name: "SwiftDiagnostics",
                package: "swift-syntax",
                condition: .when(traits: [macrosTrait])
            ),
            .product(name: "SwiftParser", package: "swift-syntax", condition: .when(traits: [macrosTrait])),
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
            .product(
                name: "OpenTelemetryApi",
                package: "opentelemetry-swift-core",
                condition: .when(traits: [otelTrait])
            ),
            .product(
                name: "OpenTelemetrySdk",
                package: "opentelemetry-swift-core",
                condition: .when(traits: [otelTrait])
            ),
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
            .product(name: "MCP", package: "swift-sdk", condition: .when(traits: [mcpTrait])),
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmCapabilityShowcaseSupport",
        dependencies: [
            "Swarm",
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
                .product(name: "MCP", package: "swift-sdk", condition: .when(traits: [mcpTrait])),
            ]
            if enableIntegrationModules {
                dependencies += [
                    .target(name: "MembraneCore", condition: .when(traits: [integrationTrait])),
                ]
                if registerAppleIntegrationTargets {
                    dependencies += [
                        .target(
                            name: "Membrane",
                            condition: .when(platforms: appleIntegrationPlatforms, traits: [integrationTrait])
                        ),
                        .target(
                            name: "ContextCore",
                            condition: .when(platforms: appleIntegrationPlatforms, traits: [integrationTrait])
                        ),
                    ]
                }
            }
            return dependencies
        }(),
        exclude: ["MCP/Fixtures"],
        resources: [],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "Swarm",
            .target(name: "SwarmMacros", condition: .when(traits: [macrosTrait])),
            .product(
                name: "SwiftSyntaxMacrosTestSupport",
                package: "swift-syntax",
                condition: .when(traits: [macrosTrait])
            ),
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
            .product(
                name: "OpenTelemetryApi",
                package: "opentelemetry-swift-core",
                condition: .when(traits: [otelTrait])
            ),
            .product(
                name: "OpenTelemetrySdk",
                package: "opentelemetry-swift-core",
                condition: .when(traits: [otelTrait])
            ),
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
    // lean target links exclude these integration remotes. The MCP/OpenTelemetry
    // package pins remain because their declarations cannot be conditionalized
    // by package traits.
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

        .testTarget(
            name: "HiveSwarmTests",
            dependencies: [
                "Swarm",
                .target(name: "HiveCore", condition: .when(traits: [integrationTrait])),
            ],
            swiftSettings: swarmSwiftSettings
        ),
    ]

    if registerAppleIntegrationTargets {
        packageTargets += [
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
                    .product(name: "Logging", package: "swift-log"),
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
        ]
    }
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
                .enableExperimentalFeature("StrictConcurrency"),
                .define("SWARM_MCP", .when(traits: [mcpTrait])),
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
        // Macros on by default (SE-0450). Consumers disable with `traits: []` to
        // drop swift-syntax; FunctionTool is the macro-free tool path.
        // Opt-in traits enable Macros so `traits: ["MCP"]` / `["OpenTelemetry"]`
        // / `["Integrations"]` keep @Tool (specifying traits replaces defaults).
        .default(enabledTraits: [macrosTrait]),
        .trait(
            name: macrosTrait,
            description: """
            Enable Swarm compiler macros (@Tool, @Parameter, #Prompt, @Traceable, \
            and related plugins). On by default. Disable to drop the swift-syntax \
            dependency; use FunctionTool for the macro-free tool path.
            """
        ),
        .trait(
            name: mcpTrait,
            description: """
            Enable the SwarmMCP product: MCP Swift SDK server adapter \
            (`SwarmMCPServerService`). Off by default. Does not affect Swarm's \
            built-in MCP client. Enabling MCP also enables Macros.
            """,
            enabledTraits: [macrosTrait]
        ),
        .trait(
            name: otelTrait,
            description: """
            Enable the SwarmOpenTelemetry product: OpenTelemetry tracing wrappers \
            and OTLP/HTTP export. Off by default. Enabling OpenTelemetry also \
            enables Macros.
            """,
            enabledTraits: [macrosTrait]
        ),
        .trait(
            name: integrationTrait,
            description: """
            Enable SWARM_INTEGRATIONS: durable Hive workflows, ContextCore+Wax default memory, \
            Membrane adapters, and web helpers. Off by default. HiveCore, Membrane, and \
            ContextCore are native in-tree Sources/ targets (internal; not separate products). \
            ContextCore / full Membrane session stack require Apple platforms (Metal/CoreML); \
            Linux Integrations still gets Hive + MembraneCore + web helpers. \
            Wax remains an external package for now. Enabling Integrations also enables Macros.
            """,
            enabledTraits: [macrosTrait]
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
