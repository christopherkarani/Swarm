// MCPFixtureSupport.swift
// SwarmTests
//
// Locates the reference MCP fixture script and python3 for interop tests.

import Foundation
import Testing

enum MCPFixtureSupport {
    static var scriptURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mcp_fixture_server.py")
    }

    static func requirePython3() throws -> String {
        let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus == 0, !path.isEmpty {
            return path
        }

        throw MCPFixtureError.python3Unavailable
    }

    static func waitForPortFile(_ url: URL, timeout: TimeInterval = 5) throws -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               port > 0 {
                return port
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw MCPFixtureError.portFileTimeout
    }
}

enum MCPFixtureError: Error, CustomStringConvertible {
    case python3Unavailable
    case portFileTimeout

    var description: String {
        switch self {
        case .python3Unavailable:
            "python3 is required for MCP interop tests"
        case .portFileTimeout:
            "MCP HTTP fixture did not write its port file in time"
        }
    }
}
