#!/usr/bin/env python3
"""Reference MCP server fixture for Swarm wire-protocol interop tests.

Speaks JSON-RPC 2.0 over newline-delimited stdio (default) or streamable HTTP
(`--http`). Implements initialize, tools/list, tools/call, and
notifications/initialized. Not a mock of Swarm types — a real MCP peer.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

SUPPORTED_VERSIONS = {
    "2024-11-05",
    "2025-03-26",
    "2025-06-18",
    "2025-11-25",
}
CURRENT_VERSION = "2025-11-25"
SESSION_ID = "swarm-fixture-session"


def handle_rpc(message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method")
    rpc_id = message.get("id")
    params = message.get("params") or {}

    if method == "notifications/initialized" or (method or "").startswith("notifications/"):
        return None

    if method == "initialize":
        requested = params.get("protocolVersion") or CURRENT_VERSION
        version = requested if requested in SUPPORTED_VERSIONS else CURRENT_VERSION
        return _result(
            rpc_id,
            {
                "protocolVersion": version,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "swarm-mcp-fixture", "version": "1.0.0"},
            },
        )

    if method == "tools/list":
        return _result(
            rpc_id,
            {
                "tools": [
                    {
                        "name": "echo",
                        "description": "Echoes the text argument",
                        "inputSchema": {
                            "type": "object",
                            "required": ["text"],
                            "properties": {
                                "text": {"type": "string", "description": "Text to echo"}
                            },
                        },
                    }
                ]
            },
        )

    if method == "tools/call":
        name = params.get("name") or ""
        arguments = params.get("arguments") or {}
        if not name:
            return _error(rpc_id, -32602, "Tool name must be non-empty")
        if name != "echo":
            return _error(rpc_id, -32601, f"Unknown tool '{name}'")
        text = arguments.get("text", "")
        return _result(
            rpc_id,
            {
                "content": [{"type": "text", "text": str(text)}],
                "isError": False,
            },
        )

    return _error(rpc_id, -32601, f"Method not found: {method}")


def _result(rpc_id: Any, result: dict[str, Any]) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": rpc_id, "result": result}


def _error(rpc_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": rpc_id, "error": {"code": code, "message": message}}


def run_stdio() -> None:
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            sys.stderr.write(f"invalid json: {exc}\n")
            sys.stderr.flush()
            continue
        response = handle_rpc(message)
        if response is None:
            continue
        sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
        sys.stdout.flush()


class MCPHTTPHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("http: " + (fmt % args) + "\n")

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length") or "0")
        body = self.rfile.read(length) if length else b""
        if not body:
            self._send(202, b"")
            return
        try:
            message = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send(400, b'{"error":"invalid json"}')
            return

        response = handle_rpc(message)
        if response is None:
            self._send(202, b"", content_type="application/json")
            return
        payload = json.dumps(response, separators=(",", ":")).encode("utf-8")
        self._send(200, payload, content_type="application/json")

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("MCP-Session-Id", SESSION_ID)
        self.end_headers()
        if body:
            self.wfile.write(body)


def run_http(port: int, port_file: str | None) -> None:
    server = ThreadingHTTPServer(("127.0.0.1", port), MCPHTTPHandler)
    chosen = server.server_address[1]
    if port_file:
        with open(port_file, "w", encoding="utf-8") as handle:
            handle.write(str(chosen))
    sys.stderr.write(f"MCP_FIXTURE_PORT={chosen}\n")
    sys.stderr.flush()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    thread.join()


def main() -> None:
    parser = argparse.ArgumentParser(description="Swarm MCP interop fixture")
    parser.add_argument("--http", type=int, nargs="?", const=0, default=None)
    parser.add_argument("--port-file", default=None)
    args = parser.parse_args()
    if args.http is None:
        run_stdio()
    else:
        run_http(args.http, args.port_file)


if __name__ == "__main__":
    main()
