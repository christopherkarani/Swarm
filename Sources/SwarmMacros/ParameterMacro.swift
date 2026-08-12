// ParameterMacro.swift
// SwarmMacros
//
// Implementation of the @Parameter macro for declaring tool parameters.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - ParameterMacro

/// The `@Parameter` macro marks a property as a tool parameter.
///
/// Usage:
/// ```swift
/// @Parameter("The city name")
/// var location: String
///
/// @Parameter("Temperature units", default: "celsius")
/// var units: String = "celsius"
///
/// @Parameter("Output format", oneOf: ["json", "xml", "text"])
/// var format: String
/// ```
///
/// The macro itself doesn't generate code - it's a marker that the @Tool macro
/// uses to collect parameter information.
public struct ParameterMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // @Parameter is a marker macro - it doesn't generate peer declarations
        // The @Tool macro reads these attributes to generate the parameters array
        []
    }
}
