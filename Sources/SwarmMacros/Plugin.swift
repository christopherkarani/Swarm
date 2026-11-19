// Plugin.swift
// SwarmMacros
//
// Compiler plugin entry point for Swarm macros.

import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin that provides all Swarm macros.
@main
struct SwarmMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ToolMacro.self,
        ParameterMacro.self,
        AgentMacro.self,
        TraceableMacro.self,
        PromptMacro.self,
        BuilderMacro.self,
        InlineToolMacro.self,
        IntentToolMacro.self,
        AgentIntentMacro.self,
    ]
}
