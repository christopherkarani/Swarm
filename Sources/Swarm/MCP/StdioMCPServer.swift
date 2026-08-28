// StdioMCPServer.swift
// Swarm Framework
//
// Stdio client transport: launch a child MCP server and speak newline-delimited JSON-RPC.

import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - StdioMCPServer

/// A stdio client for Model Context Protocol (MCP) servers.
///
/// `StdioMCPServer` launches a child process and speaks newline-delimited
/// JSON-RPC over the child's stdin/stdout — the deployment used by most
/// filesystem, git, and local MCP servers. Stderr is captured for
/// diagnostics. The process is terminated on ``close()`` and unexpected
/// exits fail in-flight requests.
///
/// ## Example
///
/// ```swift
/// let server = StdioMCPServer(
///     command: "npx",
///     arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
///     name: "filesystem"
/// )
/// let capabilities = try await server.initialize()
/// let tools = try await server.listTools()
/// try await server.close()
/// ```
///
/// ## Thread Safety
///
/// `StdioMCPServer` is an actor. All process and pipe state is isolated.
///
/// Stdio transport needs `Foundation.Process`, which exists on macOS and Linux
/// only. On iOS, tvOS, watchOS, and visionOS, ``initialize()`` throws
/// ``MCPError/internalError(_:)`` and tells the caller to use an HTTP MCP
/// server instead.
public actor StdioMCPServer: MCPServerConnection {
    // MARK: Public

    /// The name of this MCP server connection.
    public let name: String

    /// Capabilities cached after a successful ``initialize()``.
    public var capabilities: MCPCapabilities {
        cachedCapabilities ?? MCPCapabilities()
    }

    /// The protocol version negotiated during ``initialize()``.
    public var negotiatedProtocolVersion: String? {
        cachedProtocolVersion
    }

    /// Captured stderr from the child process, newest content last.
    ///
    /// Useful when initialize or a request fails and the server logged
    /// a diagnostic to stderr.
    public var stderrLog: String {
        String(data: stderrBuffer, encoding: .utf8) ?? ""
    }

    /// Creates a stdio MCP client that will launch `command` on initialize.
    ///
    /// - Parameters:
    ///   - command: The executable to launch. Looked up on `PATH` unless it
    ///     contains a path separator.
    ///   - arguments: Arguments passed to the executable.
    ///   - environment: Optional environment overlay. When `nil`, the child
    ///     inherits the current process environment.
    ///   - workingDirectory: Optional working directory for the child.
    ///   - name: A name for this connection (used for identification).
    ///   - timeout: Per-request timeout in seconds. Default: 30.0
    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        name: String,
        timeout: TimeInterval = 30.0
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.name = name
        self.timeout = timeout
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    // MARK: - MCPServerConnection

    /// Launches the child process (if needed), sends `initialize`, and
    /// negotiates the protocol version.
    ///
    /// - Returns: The capabilities advertised by the server.
    /// - Throws: `MCPError` if the process cannot be started, the handshake
    ///   fails, or the server speaks an unsupported protocol version.
    public func initialize() async throws -> MCPCapabilities {
        try startProcessIfNeeded()

        let request = try MCPRequest(method: "initialize", params: MCPWireCodec.initializeParameters())
        let response = try await sendRequest(request)
        let result = try requireResult(response, context: "initialize")
        let version = try MCPWireCodec.negotiatedVersion(from: result)
        let capabilities = try MCPWireCodec.parseCapabilities(from: result)

        cachedProtocolVersion = version
        try await sendNotification(try MCPNotification(method: "notifications/initialized"))
        cachedCapabilities = capabilities
        return capabilities
    }

    public func listTools() async throws -> [ToolSchema] {
        let response = try await sendRequest(try MCPRequest(method: "tools/list"))
        return try MCPWireCodec.parseTools(from: requireResult(response, context: "tools/list"))
    }

    /// Calls a tool and returns unwrapped content blocks.
    public func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        try await invokeTool(name: name, arguments: arguments, style: .unwrappedContent)
    }

    /// Calls a tool and returns the raw `tools/call` envelope.
    public func callToolRaw(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        try await invokeTool(name: name, arguments: arguments, style: .rawEnvelope)
    }

    public func listResources() async throws -> [MCPResource] {
        let response = try await sendRequest(try MCPRequest(method: "resources/list"))
        return try MCPWireCodec.parseResources(from: requireResult(response, context: "resources/list"))
    }

    public func readResource(uri: String) async throws -> MCPResourceContent {
        let response = try await sendRequest(
            try MCPRequest(method: "resources/read", params: ["uri": .string(uri)])
        )
        return try MCPWireCodec.parseResourceContent(from: requireResult(response, context: "resources/read"))
    }

    /// Terminates the child process and fails any in-flight requests.
    ///
    /// Sends SIGTERM, waits briefly, then SIGKILL if the process is still
    /// alive. Safe to call multiple times.
    public func close() async throws {
        failPending(MCPError.internalError("Stdio MCP connection closed"))
        readerTask?.cancel()
        readerTask = nil
        stderrTask?.cancel()
        stderrTask = nil

        stdinHandle?.closeFile()
        stdinHandle = nil
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle?.closeFile()
        stdoutHandle = nil
        stderrHandle?.readabilityHandler = nil
        stderrHandle?.closeFile()
        stderrHandle = nil

        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                killProcess(process)
            }
        }

        process = nil
        cachedCapabilities = nil
        cachedProtocolVersion = nil
        stdoutBuffer.removeAll()
    }

    // MARK: Private

    private let command: String
    private let arguments: [String]
    private let environment: [String: String]?
    private let workingDirectory: URL?
    private let timeout: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    #if os(macOS) || os(Linux)
        private var process: Process?
    #else
        private var process: StdioUnavailableProcess?
    #endif
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<MCPResponse, Error>] = [:]
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var cachedCapabilities: MCPCapabilities?
    private var cachedProtocolVersion: String?

    private func startProcessIfNeeded() throws {
        #if os(macOS) || os(Linux)
        if let process, process.isRunning {
            return
        }

        let child = Process()
        if command.contains("/") {
            child.executableURL = URL(fileURLWithPath: command)
            child.arguments = arguments
        } else {
            child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            child.arguments = [command] + arguments
        }
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            child.environment = merged
        }
        if let workingDirectory {
            child.currentDirectoryURL = workingDirectory
        }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr

        child.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { [weak self] in
                await self?.handleProcessExit(status: status)
            }
        }

        do {
            try child.run()
        } catch {
            throw MCPError.internalError("Failed to launch MCP stdio server '\(command)': \(error.localizedDescription)")
        }

        process = child
        stdinHandle = stdin.fileHandleForWriting
        stdoutHandle = stdout.fileHandleForReading
        stderrHandle = stderr.fileHandleForReading

        let stdoutStream = makeDataStream(from: stdout.fileHandleForReading)
        readerTask = Task { [weak self] in
            for await chunk in stdoutStream {
                await self?.consumeStdout(chunk)
            }
        }

        let stderrStream = makeDataStream(from: stderr.fileHandleForReading)
        stderrTask = Task { [weak self] in
            for await chunk in stderrStream {
                await self?.consumeStderr(chunk)
            }
        }
        #else
        throw MCPError.internalError(
            "Stdio MCP servers are unavailable on this platform. Use an HTTP MCP server instead."
        )
        #endif
    }

    private func makeDataStream(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            #if os(Linux)
            // FileHandle.readabilityHandler does not reliably deliver pipe
            // bytes on Linux. A blocking read on a detached thread is the
            // portable path; without it initialize() waits forever and the
            // actor-isolated write/timeout cannot make progress.
            Thread.detachNewThread {
                while true {
                    let data: Data
                    do {
                        data = try handle.read(upToCount: 4096) ?? Data()
                    } catch {
                        continuation.finish()
                        break
                    }
                    if data.isEmpty {
                        continuation.finish()
                        break
                    }
                    continuation.yield(data)
                }
            }
            #else
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if data.isEmpty {
                    continuation.finish()
                    fileHandle.readabilityHandler = nil
                } else {
                    continuation.yield(data)
                }
            }
            #endif
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    private func consumeStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        while let newline = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleMessage(Data(line))
        }
    }

    private func consumeStderr(_ chunk: Data) {
        stderrBuffer.append(chunk)
        if stderrBuffer.count > 16_384 {
            stderrBuffer = stderrBuffer.suffix(16_384)
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let response = try decoder.decode(MCPResponse.self, from: data)
            if let continuation = pending.removeValue(forKey: response.id) {
                continuation.resume(returning: response)
            }
        } catch {
            // Notifications or malformed lines are ignored at the session layer.
        }
    }

    private func handleProcessExit(status: Int32) {
        let detail = stderrLog.isEmpty
            ? "exit status \(status)"
            : "exit status \(status); stderr: \(stderrLog)"
        failPending(MCPError.internalError("MCP stdio server '\(name)' exited unexpectedly (\(detail))"))
        process = nil
    }

    private func failPending(_ error: MCPError) {
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting {
            continuation.resume(throwing: error)
        }
    }

    private func sendRequest(_ request: MCPRequest) async throws -> MCPResponse {
        try await withThrowingTaskGroup(of: MCPResponse.self) { group in
            group.addTask {
                try await self.performSend(request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.timeout))
                await self.cancelPending(
                    id: request.id,
                    error: MCPError.internalError(
                        "Timed out waiting for MCP stdio response to '\(request.method)'"
                    )
                )
                throw MCPError.internalError("Timed out waiting for MCP stdio response to '\(request.method)'")
            }
            guard let result = try await group.next() else {
                throw MCPError.internalError("MCP stdio request produced no response")
            }
            group.cancelAll()
            return result
        }
    }

    private func performSend(_ request: MCPRequest) async throws -> MCPResponse {
        try await withCheckedThrowingContinuation { continuation in
            if process?.isRunning != true {
                continuation.resume(
                    throwing: MCPError.internalError("MCP stdio server '\(name)' is not running")
                )
                return
            }
            pending[request.id] = continuation
            do {
                try writeLine(encoder.encode(request))
            } catch {
                pending.removeValue(forKey: request.id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func cancelPending(id: String, error: MCPError) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func sendNotification(_ notification: MCPNotification) async throws {
        try writeLine(encoder.encode(notification))
    }

    private func writeLine(_ data: Data) throws {
        guard let stdinHandle, process?.isRunning == true else {
            throw MCPError.internalError("MCP stdio server '\(name)' is not running")
        }
        var payload = data
        payload.append(UInt8(ascii: "\n"))
        do {
            stdinHandle.write(payload)
        } catch {
            throw MCPError.internalError("Failed to write to MCP stdio server '\(name)': \(error.localizedDescription)")
        }
    }

    private func invokeTool(
        name: String,
        arguments: [String: SendableValue],
        style: MCPToolResultStyle
    ) async throws -> SendableValue {
        try MCPWireCodec.requireToolName(name)
        let response = try await sendRequest(
            try MCPRequest(
                method: "tools/call",
                params: [
                    "name": .string(name),
                    "arguments": .dictionary(arguments)
                ]
            )
        )
        let result = try requireResult(response, context: "tools/call")
        return try MCPWireCodec.toolCallResult(result, toolName: name, style: style)
    }

    private func requireResult(_ response: MCPResponse, context: String) throws -> SendableValue {
        if let error = response.error {
            throw MCPError(code: error.code, message: error.message, data: error.data)
        }
        guard let result = response.result else {
            throw MCPError.internalError("No result in \(context) response")
        }
        return result
    }

    #if os(macOS) || os(Linux)
        private func killProcess(_ process: Process) {
            let pid = process.processIdentifier
            guard pid > 0 else { return }
            _ = kill(pid, SIGKILL)
        }
    #else
        private func killProcess(_ process: StdioUnavailableProcess) {
            _ = process
        }
    #endif
}

#if !os(macOS) && !os(Linux)
    /// `Foundation.Process` is unavailable on iOS, tvOS, watchOS, and visionOS.
    private struct StdioUnavailableProcess: Sendable {
        var isRunning: Bool { false }
        var processIdentifier: Int32 { 0 }
        func terminate() {}
    }
#endif
