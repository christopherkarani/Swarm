import Foundation
@testable import Swarm
import Testing

@Suite("Documentation Freshness")
struct DocumentationFreshnessTests {
    @Test("Workflow stream doc example uses current AgentEvent cases")
    func workflowStreamDocExampleUsesCurrentAgentEventCases() throws {
        let workflowSource = try readRepoFile("Sources/Swarm/Workflow/Workflow.swift")

        #expect(!workflowSource.contains("case .agentOutput"))
        #expect(workflowSource.contains("case .lifecycle(.started(input: let input))"))
        #expect(workflowSource.contains("case .lifecycle(.completed(let result))"))
        #expect(workflowSource.contains("case .lifecycle(.failed(let error))"))
    }

    @Test("API catalog header and Workflow stream line stay fresh")
    func apiCatalogHeaderAndWorkflowStreamLineStayFresh() throws {
        let catalog = try readRepoFile("docs/reference/api-catalog.md")
        let workflowSource = try readRepoFile("Sources/Swarm/Workflow/Workflow.swift")
        let workflowStreamLine = try lineNumber(containing: "public func stream(_ input", in: workflowSource)
        let scannedSourceCount = try countPublicCatalogSourceFiles()

        #expect(catalog.contains("Generated from `Sources/Swarm/` on 2026-04-30; source-verified and refreshed for high-risk public rows on 2026-05-18."))
        #expect(catalog.contains("- Source files scanned: \(scannedSourceCount)"))
        #expect(catalog.contains("| \(workflowStreamLine) | func | public | Workflow.stream(_:)"))
        #expect(catalog.contains("| 42 | enum | public | Swarm | `public enum Swarm` |"))
        #expect(catalog.contains("| 12 | struct | public | LLM | `public struct LLM` |"))
        #expect(catalog.contains("LLM.ollama(_:configure:)"))
        #expect(!catalog.contains("| 12 | enum | public | LLM | `public enum LLM` |"))
        #expect(!catalog.contains("public case openAI(LLM.OpenAIConfig)"))
        #expect(!catalog.contains("LLM.OpenAIConfig"))
    }

    @Test("public docs do not link stale complete reference")
    func publicDocsDoNotLinkCompleteReference() throws {
        let config = try readRepoFile("docs/.vitepress/config.ts")
        let overview = try readRepoFile("docs/reference/overview.md")

        #expect(!config.contains("Complete Reference"))
        #expect(!config.contains("link: '/swarm-complete-reference'"))
        #expect(config.contains("**/swarm-complete-reference.md"))
        #expect(!overview.contains("swarm-complete-reference"))
    }

    @Test("public repo hygiene blocks internal reports and marketing drafts")
    func publicRepoHygieneBlocksInternalReportsAndMarketingDrafts() throws {
        let removedPublicArtifacts = [
            "docs/reference/docs-folder-audit-report.md",
            "docs/reference/docc-audit-report.md",
            "docs/reference/documentation-gap-report.md",
            "docs/reference/documentation-improvement-plan.md",
            "docs/reference/documentation-validation-report.md",
            "docs/reference/twitter-article-web-memory-plane.md",
            "docs/swarm-hacker-news-blog.md",
            "docs/superpowers/specs/2026-03-16-v3-final-push-design.md",
            "docs/superpowers/specs/2026-03-18-ai-code-reviewer-design.md",
            "tasks/todo.md",
        ]

        for file in removedPublicArtifacts {
            #expect(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(file).path), "\(file) should not be present in the public repo")
        }

        let gitignore = try readRepoFile(".gitignore")
        let agentRules = try readRepoFile("AGENTS.md")

        for pattern in [
            "tasks/",
            "docs/superpowers/",
            "docs/reference/*audit-report.md",
            "docs/reference/documentation-*-report.md",
            "docs/reference/documentation-improvement-plan.md",
            "docs/reference/twitter-article-*.md",
            "docs/swarm-hacker-news-blog.md",
            "marketing/",
        ] {
            #expect(gitignore.contains(pattern), "\(pattern) should stay ignored")
            #expect(agentRules.contains(pattern), "\(pattern) should be called out for future agents")
        }
    }

    @Test("API catalog excludes package-only and removed symbols")
    func apiCatalogExcludesPackageOnlyAndRemovedSymbols() throws {
        let catalog = try readRepoFile("docs/reference/api-catalog.md")

        #expect(!catalog.contains("AnyMemory"))
        #expect(!catalog.contains("AgentRuntimeIdentifiable"))
        #expect(!catalog.contains("CallableAgent"))
        #expect(!catalog.contains("Tools/ToolChainBuilder.swift"))
        #expect(!catalog.contains("| ToolChain |"))
    }

    @Test("public memory docs do not advertise removed builder APIs")
    func publicMemoryDocsDoNotAdvertiseRemovedBuilderAPIs() throws {
        let checkedFiles = [
            "README.md",
            "docs/reference/front-facing-api.md",
            "docs/reference/api-catalog.md",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(!text.contains("`MemoryOption`"), "\(file) should not mention removed MemoryOption API")
            #expect(!text.contains("`MemoryBuilder`"), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("MemoryBuilder."), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("@MemoryBuilder"), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("struct MemoryBuilder"), "\(file) should not mention removed MemoryBuilder API")
            #expect(!text.contains("`VectorMemoryBuilder`"), "\(file) should not mention internal VectorMemoryBuilder API")
            #expect(!text.contains("`CompositeMemory`"), "\(file) should not mention removed CompositeMemory API")
            #expect(!text.contains("CompositeMemory."), "\(file) should not mention removed CompositeMemory API")
            #expect(!text.contains("actor CompositeMemory"), "\(file) should not mention removed CompositeMemory API")
        }
    }

    @Test("guardrail docs do not advertise a non-existent timeout")
    func guardrailDocsDoNotAdvertiseMissingTimeout() throws {
        let agentSource = try readRepoFile("Sources/Swarm/Agents/Agent.swift")

        #expect(!agentSource.contains("guardrails with a 30-second timeout"))
        #expect(agentSource.contains("guardrails sequentially and stops on the first failure"))
    }

    @Test("front-facing provider docs match the live base provider protocol")
    func providerDocsUsePromptBasedBaseProtocol() throws {
        let docs = try readRepoFile("docs/reference/front-facing-api.md")
        let providerSource = try readRepoFile("Sources/Swarm/Core/AgentRuntime.swift")
        let conversationSource = try readRepoFile("Sources/Swarm/Providers/ConversationInferenceProvider.swift")

        #expect(providerSource.contains("func generate(prompt: String, options: InferenceOptions) async throws -> String"))
        #expect(conversationSource.contains("public protocol ConversationInferenceProvider"))
        #expect(docs.contains("func generate(prompt: String, options: InferenceOptions) async throws -> String"))
        #expect(docs.contains("public protocol ConversationInferenceProvider: InferenceProvider"))
        #expect(!docs.contains("public protocol InferenceStreamingProvider: InferenceProvider"))
    }

    @Test("public release docs point at the latest remote tag represented by this checkout")
    func publicReleaseDocsUsePublishedVersion() throws {
        let expectedVersion = Swarm.version
        let checkedFiles = [
            "README.md",
            "docs/index.md",
            "docs/guide/getting-started.md",
            "docs/guide/opentelemetry-tracing.md",
            "docs/reference/overview.md",
            "Sources/Swarm/Swarm.swift",
            "Tests/SwarmTests/V2SurfaceAuditTests.swift",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(text.contains(expectedVersion), "\(file) should mention \(expectedVersion)")
            #expect(!text.contains("0.6.1"), "\(file) should not advertise unreleased 0.6.1")
        }
    }

    @Test("front-facing docs cover exported companion products")
    func frontFacingDocsCoverExportedCompanionProducts() throws {
        let docs = try readRepoFile("docs/reference/front-facing-api.md")
        let package = try readRepoFile("Package.swift")

        #expect(package.contains(".library(name: \"SwarmOpenTelemetry\""))
        #expect(package.contains(".library(name: \"SwarmMembrane\""))
        #expect(package.contains(".library(name: \"SwarmMCP\""))

        #expect(docs.contains("SwarmOpenTelemetry"))
        #expect(docs.contains("instrumentedWithOpenTelemetry"))
        #expect(docs.contains("SwarmMembrane"))
        #expect(docs.contains("@_exported import Swarm"))
        #expect(docs.contains("SwarmMCPServerService"))
        #expect(docs.contains("SwarmMCPToolRegistryAdapter"))
    }

    @Test("public macro docs include the inline tool macro")
    func publicMacroDocsIncludeInlineToolMacro() throws {
        let source = try readRepoFile("Sources/Swarm/Macros/MacroDeclarations.swift")
        let frontFacing = try readRepoFile("docs/reference/front-facing-api.md")
        let catalog = try readRepoFile("docs/reference/api-catalog.md")

        #expect(source.contains("public macro Tool(\n    _ name: String,\n    _ description: String"))
        #expect(frontFacing.contains("`#Tool(\"name\", \"description\")`"))
        #expect(catalog.contains("Tool(_:_:)"))
    }

    @Test("getting started uses current memory anchor")
    func gettingStartedUsesCurrentMemoryAnchor() throws {
        let guide = try readRepoFile("docs/guide/getting-started.md")

        #expect(!guide.contains("MemoryOption"))
        #expect(!guide.contains("#10-memoryoption"))
        #expect(!guide.contains("tool chains"))
        #expect(guide.contains("#9-memory-factories"))
    }

    @Test("public docs use current memory factory spelling")
    func publicDocsUseCurrentMemoryFactorySpelling() throws {
        let checkedFiles = [
            "README.md",
            "docs/reference/front-facing-api.md",
            "Sources/Swarm/Memory/AgentMemory.swift",
            "Sources/Swarm/Memory/EmbeddingProvider.swift",
            "Sources/Swarm/Memory/MemoryMessage.swift",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(!text.contains("Memory.conversation"), "\(file) should use contextual .conversation(...) spelling")
            #expect(!text.contains("Memory.vector"), "\(file) should use contextual .vector(...) spelling")
            #expect(!text.contains("Memory.slidingWindow"), "\(file) should use contextual .slidingWindow(...) spelling")
            #expect(!text.contains("Memory.summary"), "\(file) should use contextual .summary(...) spelling")
            #expect(!text.contains("Memory.hybrid"), "\(file) should use contextual .hybrid(...) spelling")
            #expect(!text.contains("Memory.persistent"), "\(file) should use contextual .persistent(...) spelling")
        }
    }

    @Test("source DocC examples use throwing Agent initializers correctly")
    func sourceDocCExamplesUseThrowingAgentInitializersCorrectly() throws {
        let builtInTools = try readRepoFile("Sources/Swarm/Tools/BuiltInTools.swift")

        #expect(!builtInTools.contains("let agent = Agent(tools: BuiltInTools.all)"))
        #expect(builtInTools.contains("let agent = try Agent(tools: BuiltInTools.all)"))
    }

    @Test("website docs do not advertise unsupported workflow guarantees")
    func websiteDocsDoNotAdvertiseUnsupportedWorkflowGuarantees() throws {
        let checkedFiles = [
            "README.md",
            "docs/index.md",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(!text.contains("Auto checkpoints"), "\(file) should describe explicit workflow checkpointing")
            #expect(!text.contains("Compiled DAG"), "\(file) should not overstate the public workflow execution model")
        }

        let index = try readRepoFile("docs/index.md")
        #expect(!index.contains("No cloud API. No network call."), "homepage should not overstate embedding-provider privacy")
        #expect(index.contains("embedding privacy depends on the provider you configure"))
    }

    @Test("website build excludes archival and internal markdown")
    func websiteBuildExcludesArchivalAndInternalMarkdown() throws {
        let config = try readRepoFile("docs/.vitepress/config.ts")
        let excludedPaths = [
            "**/reference/api-quality-assessment.md",
            "**/reference/docc-audit-report.md",
            "**/reference/docs-folder-audit-report.md",
            "**/reference/documentation-gap-report.md",
            "**/reference/documentation-improvement-plan.md",
            "**/reference/documentation-validation-report.md",
            "**/reference/durable-runtime-hardening.md",
            "**/swarm-features.md",
            "**/swarm-complete-reference.md",
            "**/superpowers/**",
        ]

        for path in excludedPaths {
            #expect(config.contains(path), "\(path) should be excluded from the public website build")
        }

        let overview = try readRepoFile("docs/reference/overview.md")
        #expect(!overview.contains("/reference/durable-runtime-hardening"), "overview should not link to a page excluded from the website build")
    }

    @Test("website config matches custom domain deployment")
    func websiteConfigMatchesCustomDomainDeployment() throws {
        let config = try readRepoFile("docs/.vitepress/config.ts")
        let cname = try readRepoFile("docs/public/CNAME").trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(cname == "docs.swarm.dev")
        #expect(config.contains("base: '/',"))
        #expect(config.contains("href: '/logo.svg'"))
        #expect(config.contains("logo: '/logo.svg'"))
        #expect(!config.contains("base: '/Swarm/'"))
        #expect(!config.contains("/Swarm/logo.svg"))
    }

    @Test("docs workflow and release checklist cover docs gates")
    func docsWorkflowAndReleaseChecklistCoverDocsGates() throws {
        let workflow = try readRepoFile(".github/workflows/docs.yml")
        let checklist = try readRepoFile("docs/release/release-checklist.md")

        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("npm ci"))
        #expect(workflow.contains("npm run docs:build"))
        #expect(workflow.contains("if: github.event_name == 'push' && github.ref == 'refs/heads/main'"))

        let requiredCommands = [
            "swift build",
            "swift test --no-parallel",
            "swift run SwarmCapabilityShowcase matrix",
            "cd Examples/CodeReviewer && swift test",
            "npm ci",
            "npm run docs:build",
            "scripts/ci/verify-remote-release.sh",
        ]

        for command in requiredCommands {
            #expect(checklist.contains(command), "release checklist should include \(command)")
        }
    }

    @Test("front-facing docs list current runtime wrappers")
    func frontFacingDocsListCurrentRuntimeWrappers() throws {
        let docs = try readRepoFile("docs/reference/front-facing-api.md")
        let environmentAgent = try readRepoFile("Sources/Swarm/Core/EnvironmentAgent.swift")
        let observedAgent = try readRepoFile("Sources/Swarm/Core/ObservedAgent.swift")

        #expect(environmentAgent.contains("func promptTokenCounter(_ counter: any PromptTokenCounter)"))
        #expect(environmentAgent.contains("func webSearch(_ configuration: WebSearchTool.Configuration)"))
        #expect(observedAgent.contains("func observed(by observer: some AgentObserver)"))

        #expect(docs.contains("agent.promptTokenCounter(myCounter)"))
        #expect(docs.contains("agent.webSearch(WebSearchTool.Configuration(enabled: false))"))
        #expect(docs.contains("agent.observed(by: myObserver)"))
        #expect(!docs.contains("Only `.environment()` and `.memory()` exist"))
    }

    @Test("MCP doc snippets use current API shapes")
    func mcpDocSnippetsUseCurrentAPIShapes() throws {
        let checkedFiles = [
            "Sources/Swarm/MCP/MCPClient.swift",
            "Sources/Swarm/MCP/MCPServer.swift",
            "Sources/Swarm/MCP/MCPProtocol.swift",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(!text.contains("HTTPMCPServer(name:"), "\(file) should not use removed HTTPMCPServer(name:baseURL:) initializer")
            #expect(!text.contains("baseURL:"), "\(file) should not use removed HTTPMCPServer baseURL label")
            #expect(!text.contains("finally {"), "\(file) should not show non-Swift finally syntax")
        }

        let protocolSource = try readRepoFile("Sources/Swarm/MCP/MCPProtocol.swift")
        #expect(protocolSource.contains("\"name\": .string(\"calculator\")"))
        #expect(protocolSource.contains("\"arguments\": .dictionary([\"expression\": .string(\"2 + 2\")])"))
    }

    @Test("README and workspace docs do not overstate usage paths")
    func readmeAndWorkspaceDocsDoNotOverstateUsagePaths() throws {
        let readme = try readRepoFile("README.md")
        let workspace = try readRepoFile("docs/guide/agent-workspace.md")

        #expect(readme.contains("await Swarm.configure(provider:"))
        #expect(!readme.contains("call `Swarm.configure(provider:"))
        #expect(!readme.contains(".thinking, .handoff, .observation, .iterationStarted"))

        #expect(!workspace.contains("bad skills are skipped"))
        #expect(workspace.contains("invalid listed `SKILL.md` files fail `Agent.spec`"))
        #expect(workspace.contains("malformed memory notes are skipped"))
    }

    @Test("CI and docs inputs required by clean clones are present")
    func cleanCloneWorkflowInputsExist() {
        let requiredPaths = [
            "package.json",
            "package-lock.json",
            ".swiftlint.yml",
            ".swiftformat",
            "Examples/CodeReviewer/Sources/CodeReviewer/main.swift",
            "scripts/ci/verify-remote-release.sh",
        ]

        for path in requiredPaths {
            let url = repoRoot.appendingPathComponent(path)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(path) should exist for clean-clone verification")
        }
    }

    @Test("docs workflow builds pull requests without deploying Pages")
    func docsWorkflowBuildsPullRequestsWithoutDeployingPages() throws {
        let workflow = try readRepoFile(".github/workflows/docs.yml")

        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("if: github.event_name == 'push' && github.ref == 'refs/heads/main'"))
        #expect(workflow.contains("npm run docs:build"))
    }

    @Test("release checklist includes docs and example pre-tag gates")
    func releaseChecklistIncludesDocsAndExamplePreTagGates() throws {
        let checklist = try readRepoFile("docs/release/release-checklist.md")

        #expect(checklist.contains("npm ci"))
        #expect(checklist.contains("npm run docs:build"))
        #expect(checklist.contains("SWARM_CORE_ONLY=1 swift test --package-path Examples/CodeReviewer"))
        #expect(checklist.contains("scripts/ci/verify-remote-release.sh"))
    }

    @Test("remote release verifier runs the standalone CodeReviewer example")
    func remoteReleaseVerifierRunsCodeReviewerExample() throws {
        let script = try readRepoFile("scripts/ci/verify-remote-release.sh")

        #expect(script.contains("SWARM_CORE_ONLY=1"))
        #expect(script.contains("swift test --package-path Examples/CodeReviewer"))
        #expect(script.contains("EXAMPLE_LOG="))
        #expect(script.contains("CodeReviewer test log"))
    }

    @Test("Linux workflow builds the default package graph")
    func linuxWorkflowBuildsDefaultPackageGraph() throws {
        let workflow = try readRepoFile(".github/workflows/swift.yml")

        #expect(workflow.contains("Build (Linux Core)"))
        #expect(workflow.contains("swift build"))
        #expect(workflow.contains("swift test --no-parallel"))
    }

    @Test("public Linux docs qualify default graph support")
    func publicLinuxDocsQualifyDefaultGraphSupport() throws {
        let checkedFiles = [
            "README.md",
            "docs/guide/getting-started.md",
        ]

        for file in checkedFiles {
            let text = try readRepoFile(file)
            #expect(text.contains("default Swarm graph is CI-tested on Ubuntu with Swift 6.2"), "\(file) should state the verified Linux lane")
            #expect(text.contains("Apple-only features such as Foundation Models, SwiftData, OSLog"), "\(file) should qualify platform-specific APIs")
        }
    }

    private func readRepoFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func lineNumber(containing needle: String, in text: String) throws -> Int {
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(needle) {
            return index + 1
        }
        throw DocumentationFreshnessError.missingLine(needle)
    }

    private func countPublicCatalogSourceFiles() throws -> Int {
        let sources = repoRoot.appendingPathComponent("Sources/Swarm")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw DocumentationFreshnessError.missingEnumerator
        }

        var count = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let relative = url.path.replacingOccurrences(of: sources.path + "/", with: "")
            guard !relative.hasPrefix("Internal/GraphRuntime/") else { continue }
            count += 1
        }
        return count
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum DocumentationFreshnessError: Error {
    case missingEnumerator
    case missingLine(String)
}
