import Foundation

public extension Agent {
    /// Creates an on-device agent with the recommended defaults and optional workspace-backed memory.
    static func onDevice(
        _ instructions: String,
        workspace: AgentWorkspace? = nil,
        configuration: AgentConfiguration = .onDeviceDefault,
        inferenceProvider: (any InferenceProvider)? = nil,
        @ToolBuilder tools: () -> ToolCollection = { .empty }
    ) throws -> Agent {
        let builtTools = tools().storage
        let globalInstructions = try workspace?.loadAgentInstructions() ?? ""
        let combinedInstructions = [globalInstructions, instructions]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let workspaceMemory = workspace.map { WorkspaceMemory(workspace: $0, activatedSkills: []) }
        return try Agent(
            tools: builtTools,
            instructions: combinedInstructions,
            configuration: configuration,
            memory: workspaceMemory,
            inferenceProvider: inferenceProvider
        )
    }

    /// Creates an on-device agent from an AgentWorkspace spec file.
    static func spec(
        _ id: String,
        in workspace: AgentWorkspace,
        configuration: AgentConfiguration = .onDeviceDefault,
        inferenceProvider: (any InferenceProvider)? = nil,
        @ToolBuilder tools: () -> ToolCollection = { .empty }
    ) throws -> Agent {
        let spec = try workspace.loadAgentSpec(id: id)
        let skills = try workspace.loadSkills(named: spec.skills)
        let globalInstructions = try workspace.loadAgentInstructions()
        let builtTools = tools().storage

        let combinedInstructions = [globalInstructions, spec.body]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return try Agent(
            tools: filterTools(builtTools, using: skills),
            instructions: combinedInstructions,
            configuration: configuration.name(spec.title),
            memory: WorkspaceMemory(workspace: workspace, activatedSkills: skills),
            inferenceProvider: inferenceProvider
        )
    }
}

private extension Agent {
    static func filterTools(_ tools: [any AnyJSONTool], using skills: [WorkspaceSkill]) -> [any AnyJSONTool] {
        let constrainedSkillLists = skills
            .map(\.allowedTools)
            .filter { !$0.isEmpty }

        guard !constrainedSkillLists.isEmpty else {
            return tools
        }

        let allowedToolNames = Set(constrainedSkillLists.flatMap(\.self))

        return tools.filter { allowedToolNames.contains($0.name) }
    }
}
