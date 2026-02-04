// =============================================================================
// AtticMCP.swift - MCP Server Entry Point
// =============================================================================
//
// This is the main entry point for the Attic MCP (Model Context Protocol)
// server. This server allows AI assistants like Claude to interact with
// the Atari 800 XL emulator directly.
//
// The MCP server communicates over stdin/stdout using JSON-RPC 2.0.
// It connects to a running AtticServer instance via the CLI socket protocol
// to execute emulator operations.
//
// Usage:
//   swift run AtticMCP
//
// Prerequisites:
//   - AtticServer must be running
//
// For Claude Code integration, add to your MCP config:
//   {
//     "mcpServers": {
//       "attic": {
//         "command": "swift",
//         "args": ["run", "--package-path", "/path/to/attic", "AtticMCP"]
//       }
//     }
//   }
//
// =============================================================================

import Foundation

/// Main entry point for the AtticMCP server.
@main
struct AtticMCP {
    static func main() async {
        let server = MCPServer()
        await server.run()
    }
}
