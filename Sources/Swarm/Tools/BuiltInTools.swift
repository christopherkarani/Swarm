// BuiltInTools.swift
// Swarm Framework
//
// Built-in tools for common agent operations.

import Foundation

#if canImport(Darwin)

    // MARK: - Calculator Tool

    /// A calculator tool that evaluates mathematical expressions.
    ///
    /// **Platform Availability**: Apple platforms only (macOS, iOS, watchOS, tvOS, visionOS).
    /// Not available on Linux due to NSExpression dependency.
    ///
    /// Supports basic arithmetic operations: +, -, *, /, and parentheses.
    /// Uses NSExpression on Apple platforms and a pure Swift parser on Linux
    /// for safe evaluation without code injection risks.
    ///
    /// Example:
    /// ```swift
    /// let calc = CalculatorTool()
    /// let result = try await calc.execute(arguments: ["expression": "2 + 3 * 4"])
    /// // result == .double(14.0)
    /// ```
    public struct CalculatorTool: AnyJSONTool, Sendable {
        // MARK: Public

        /// The unique identifier for this tool: "calculator".
        public let name = "calculator"

        /// Describes the calculator tool's capabilities to the LLM.
        public let description = """
        Evaluates a mathematical expression and returns the result. \
        Supports +, -, *, /, parentheses, and decimal numbers.
        """

        /// The parameters accepted by the calculator: a single "expression" string.
        public let parameters: [ToolParameter] = [
            ToolParameter(
                name: "expression",
                description: "The mathematical expression to evaluate (e.g., '2 + 3 * 4', '(10 + 5) / 3')",
                type: .string,
                isRequired: true
            )
        ]

        /// Creates a new calculator tool.
        public init() {}

        /// Executes the mathematical expression and returns the result.
        ///
        /// - Parameter arguments: Must contain an "expression" key with a string value.
        /// - Returns: The result as a `.double` value.
        /// - Throws: `AgentError.invalidToolArguments` if the expression is missing or contains invalid characters.
        public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
            guard let expression = arguments["expression"]?.stringValue else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Missing required parameter 'expression'"
                )
            }

            let result = try evaluate(expression)
            return .double(result)
        }

        // MARK: Private

        /// Evaluates a simple mathematical expression safely.
        private func evaluate(_ expression: String) throws -> Double {
            // Sanitize the expression to only allow safe characters
            let allowedCharacters = CharacterSet(charactersIn: "0123456789.+-*/() ")
            let trimmed = expression.trimmingCharacters(in: .whitespaces)

            guard trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Expression contains invalid characters. Only numbers and operators (+, -, *, /, parentheses) are allowed."
                )
            }

            guard !trimmed.isEmpty else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Expression is empty"
                )
            }

            // Use pure Swift ArithmeticParser on all platforms for consistency
            // NSExpression is unavailable on Linux (swift-corelibs-foundation)
            do {
                return try ArithmeticParser.evaluate(trimmed)
            } catch let error as ArithmeticParser.ParserError {
                throw AgentError.toolExecutionFailed(
                    toolName: name,
                    underlyingError: "Failed to evaluate expression: \(error)"
                )
            }
        }
    }
#endif // canImport(Darwin)

// MARK: - DateTimeTool

/// A tool that provides current date and time information.
///
/// Supports various formats including full, date-only, time-only, ISO8601,
/// and custom format strings.
///
/// Example:
/// ```swift
/// let dt = DateTimeTool()
/// let result = try await dt.execute(arguments: ["format": "iso8601"])
/// // result == .string("2024-01-15T10:30:45Z")
/// ```
public struct DateTimeTool: AnyJSONTool, Sendable {
    /// The unique identifier for this tool: "datetime".
    public let name = "datetime"

    /// Describes the date/time tool's capabilities to the LLM.
    public let description = "Gets the current date and time in various formats."

    /// The parameters accepted by the date/time tool.
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "format",
            description: """
            The date format: 'full' (default), 'date', 'time', 'iso8601', \
            or a custom format string (e.g., 'yyyy-MM-dd')
            """,
            type: .string,
            isRequired: false,
            defaultValue: .string("full")
        ),
        ToolParameter(
            name: "timezone",
            description: "The timezone identifier (e.g., 'America/New_York', 'UTC'). Defaults to the current timezone.",
            type: .string,
            isRequired: false
        )
    ]

    /// Creates a new date/time tool.
    public init() {}

    /// Executes the date/time query and returns formatted results.
    ///
    /// - Parameter arguments: May contain "format" (default: "full") and "timezone" (optional).
    ///   Supported formats: "full", "date", "time", "iso8601", "unix", or custom format strings.
    /// - Returns: The formatted date/time as a `.string`, or Unix timestamp as `.double`.
    /// - Throws: `AgentError.invalidToolArguments` if the timezone identifier is invalid.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let formatString = arguments["format"]?.stringValue ?? "full"
        let timezoneId = arguments["timezone"]?.stringValue

        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        // Set timezone if specified
        if let tzId = timezoneId {
            if let tz = TimeZone(identifier: tzId) {
                formatter.timeZone = tz
            } else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Invalid timezone identifier: \(tzId)"
                )
            }
        }

        // Handle format
        switch formatString.lowercased() {
        case "full":
            formatter.dateStyle = .full
            formatter.timeStyle = .full
        case "date":
            formatter.dateStyle = .long
            formatter.timeStyle = .none
        case "time":
            formatter.dateStyle = .none
            formatter.timeStyle = .long
        case "short":
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        case "iso8601":
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            formatter.timeZone = TimeZone(identifier: "UTC")
        case "unix":
            return .double(now.timeIntervalSince1970)
        default:
            // Custom format string
            formatter.dateFormat = formatString
        }

        let result = formatter.string(from: now)
        return .string(result)
    }
}

// MARK: - StringTool

/// A tool for string manipulation operations.
///
/// Supports operations: length, uppercase, lowercase, trim, split, replace, contains, reverse.
///
/// Example:
/// ```swift
/// let str = StringTool()
/// let result = try await str.execute(arguments: [
///     "operation": "replace",
///     "input": "hello world",
///     "pattern": "world",
///     "replacement": "Swift"
/// ])
/// // result == .string("hello Swift")
/// ```
public struct StringTool: AnyJSONTool, Sendable {
    /// The unique identifier for this tool: "string".
    public let name = "string"

    /// Describes the string tool's capabilities to the LLM.
    public let description = """
    Performs string operations: length, uppercase, lowercase, trim, split, \
    replace, contains, reverse, substring.
    """

    /// The parameters accepted by the string tool.
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "operation",
            description: "The operation to perform",
            type: .oneOf([
                "length", "uppercase", "lowercase", "trim", "split",
                "replace", "contains", "reverse", "substring"
            ]),
            isRequired: true
        ),
        ToolParameter(
            name: "input",
            description: "The input string to operate on",
            type: .string,
            isRequired: true
        ),
        ToolParameter(
            name: "pattern",
            description: "Pattern for split/replace/contains operations",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "replacement",
            description: "Replacement string for replace operation",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "start",
            description: "Start index for substring operation",
            type: .int,
            isRequired: false
        ),
        ToolParameter(
            name: "end",
            description: "End index for substring operation",
            type: .int,
            isRequired: false
        )
    ]

    /// Creates a new string tool.
    public init() {}

    /// Executes the string operation and returns the result.
    ///
    /// - Parameter arguments: Must contain "operation" and "input" keys.
    ///   Additional keys depend on the operation (pattern, replacement, start, end).
    /// - Returns: The operation result as a `.string` or `.int` value.
    /// - Throws: `AgentError.invalidToolArguments` if required arguments are missing
    ///   or if indices are out of bounds for substring operations.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let operation = arguments["operation"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'operation'"
            )
        }

        guard let input = arguments["input"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'input'"
            )
        }

        switch operation.lowercased() {
        case "length":
            return .int(input.count)

        case "uppercase":
            return .string(input.uppercased())

        case "lowercase":
            return .string(input.lowercased())

        case "trim":
            return .string(input.trimmingCharacters(in: .whitespacesAndNewlines))

        case "split":
            let pattern = arguments["pattern"]?.stringValue ?? " "
            let parts = input.components(separatedBy: pattern)
            return .array(parts.map { .string($0) })

        case "replace":
            guard let pattern = arguments["pattern"]?.stringValue else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Replace operation requires 'pattern' parameter"
                )
            }
            let replacement = arguments["replacement"]?.stringValue ?? ""
            return .string(input.replacingOccurrences(of: pattern, with: replacement))

        case "contains":
            guard let pattern = arguments["pattern"]?.stringValue else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Contains operation requires 'pattern' parameter"
                )
            }
            return .bool(input.contains(pattern))

        case "reverse":
            return .string(String(input.reversed()))

        case "substring":
            let start = arguments["start"]?.intValue ?? 0
            let end = arguments["end"]?.intValue ?? input.count

            guard start >= 0, start <= input.count else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Start index out of bounds"
                )
            }
            guard end >= start, end <= input.count else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "End index out of bounds"
                )
            }

            let startIndex = input.index(input.startIndex, offsetBy: start)
            let endIndex = input.index(input.startIndex, offsetBy: end)
            return .string(String(input[startIndex..<endIndex]))

        default:
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Unknown operation: \(operation). Valid operations: length, uppercase, lowercase, trim, split, replace, contains, reverse, substring"
            )
        }
    }
}

// MARK: - WebSearchTool

/// A tool that performs web searches using the Tavily API.
///
/// Requires a Tavily API key.
public extension WebSearchTool {
    /// Initializer for use as a built-in tool with an environment-provided key.
    static func fromEnvironment() -> WebSearchTool {
        let key = ProcessInfo.processInfo.environment["TAVILY_API_KEY"] ?? ""
        return WebSearchTool(apiKey: key)
    }
}

// MARK: - BuiltInTools

/// Provides access to all built-in tools.
///
/// **Note**: The calculator tool is only available on Apple platforms (macOS, iOS, etc.).
/// On Linux, only date/time and string tools are available.
///
/// Example:
/// ```swift
/// let agent = Agent(tools: BuiltInTools.all)
/// ```
public enum BuiltInTools {
    #if canImport(Darwin)
        /// The calculator tool for math expressions.
        ///
        /// **Platform Availability**: Apple platforms only.
        public static let calculator = CalculatorTool()
    #endif

    /// The date/time tool for current time.
    public static let dateTime = DateTimeTool()

    /// The string manipulation tool.
    public static let string = StringTool()

    /// The semantic compaction and summarization tool.
    public static let semanticCompactor = SemanticCompactorTool()

    /// All available built-in tools for the current platform.
    ///
    /// - Apple platforms: calculator, dateTime, string, semanticCompactor
    /// - Linux: dateTime, string, semanticCompactor
    public static var all: [any AnyJSONTool] {
        var tools: [any AnyJSONTool] = [dateTime, string, bridgeToolToAnyJSON(SemanticCompactorTool())]
        #if canImport(Darwin)
        tools.append(calculator)
        #endif
        return tools
    }
}
