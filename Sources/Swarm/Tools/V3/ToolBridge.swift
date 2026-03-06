// ToolBridge.swift
// Swarm Framework
//
// Bridges V3 ToolV3 into the internal AnyJSONTool protocol.
// This adapter lets the legacy runtime consume new-style tools without rewriting
// the execution engine.

import Foundation

/// Bridges a V3 `ToolV3` into the internal `AnyJSONTool` protocol.
internal struct ToolV3Bridge<T: ToolV3>: AnyJSONTool, Sendable {
    var name: String { tool.name }
    var description: String { tool.description }
    var parameters: [ToolParameter] { extractParameters() }
    var inputGuardrails: [any ToolInputGuardrail] { [] }
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    private let tool: T

    init(_ tool: T) {
        self.tool = tool
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        // For tools with @ParameterV3 properties, populate them via Mirror.
        // For InlineToolV3, call() handles args internally.
        var mutableTool = tool
        populateParameters(&mutableTool, from: arguments)
        let result = try await mutableTool.call()
        return .string(result)
    }

    // MARK: - Private

    private func populateParameters(_ tool: inout T, from arguments: [String: SendableValue]) {
        let mirror = Mirror(reflecting: tool)
        for child in mirror.children {
            guard let label = child.label,
                  label.hasPrefix("_") else { continue }
            let paramName = String(label.dropFirst())
            guard let argValue = arguments[paramName] else { continue }

            // Use withUnsafeMutablePointer to set @ParameterV3 wrappedValue
            // This is a best-effort approach — the @Tool macro generates proper setters
            if var param = child.value as? ParameterV3<String>,
               let str = argValue.stringValue {
                param.wrappedValue = str
            } else if var param = child.value as? ParameterV3<Int>,
                      let intVal = argValue.intValue {
                param.wrappedValue = intVal
            } else if var param = child.value as? ParameterV3<Double>,
                      let dbl = argValue.doubleValue {
                param.wrappedValue = dbl
            } else if var param = child.value as? ParameterV3<Bool>,
                      let boolVal = argValue.boolValue {
                param.wrappedValue = boolVal
            }
        }
    }

    private func extractParameters() -> [ToolParameter] {
        let mirror = Mirror(reflecting: tool)
        return mirror.children.compactMap { child -> ToolParameter? in
            guard let label = child.label,
                  label.hasPrefix("_") else { return nil }
            let paramName = String(label.dropFirst())

            if let metadata = child.value as? ParameterMetadata {
                let type: ToolParameter.ParameterType = {
                    let t = metadata.parameterSwiftType
                    if t == String.self || t == String?.self { return .string }
                    if t == Int.self || t == Int?.self { return .int }
                    if t == Double.self || t == Double?.self { return .double }
                    if t == Bool.self || t == Bool?.self { return .bool }
                    return .string
                }()
                return ToolParameter(
                    name: paramName,
                    description: metadata.parameterDescription,
                    type: type,
                    isRequired: metadata.isRequired
                )
            }
            return nil
        }
    }
}

// MARK: - Convenience extension

extension ToolV3 {
    /// Converts this V3 tool to the internal AnyJSONTool protocol.
    internal func asAnyJSONTool() -> any AnyJSONTool {
        ToolV3Bridge(self)
    }
}
