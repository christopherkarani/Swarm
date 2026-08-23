// RuntimeMetadata.swift
// Swarm Framework
//
// Shared runtime metadata keys for agent results.

import Foundation

enum RuntimeMetadata {
    /// Derived from the canonical typed key so the writer and reader sides of
    /// the runtime-engine seam cannot drift apart.
    static let runtimeEngineKey = MetadataKey<String>.runtimeEngine.name
    static let graphRuntimeEngineName = "graph"
    static let nativeRuntimeEngineName = "native"
}
