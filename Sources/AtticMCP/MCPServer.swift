// =============================================================================
// MCPServer.swift - MCP Protocol Server Implementation
// =============================================================================
//
// This file implements the Model Context Protocol (MCP) server for the Attic
// emulator. It provides a JSON-RPC interface over stdin/stdout that allows
// AI assistants like Claude to interact with the emulator.
//
// Protocol Flow:
// -------------
// 1. Server reads JSON-RPC requests from stdin (one per line)
// 2. Parses the request and dispatches to appropriate handler
// 3. Executes tool calls via MCPToolHandler
// 4. Returns JSON-RPC response to stdout
//
// Supported Methods:
// -----------------
// - initialize: Set up the protocol session
// - initialized: Client notification that init is complete
// - tools/list: Return available tool definitions
// - tools/call: Execute a tool and return results
//
// =============================================================================

import Foundation
import AtticCore

// MARK: - MCP Server

/// The MCP server that handles JSON-RPC communication with Claude Code.
///
/// This server communicates over stdin/stdout using the JSON-RPC 2.0 protocol.
/// It translates MCP tool calls into CLI protocol commands sent to AtticServer.
///
/// Usage:
///   AtticMCP
///
/// The server expects AtticServer to be running and listening on the default
/// CLI socket path.
final class MCPServer {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The CLI socket client for communicating with AtticServer.
    private var client: CLISocketClient?

    /// The tool handler for executing tool calls.
    private var toolHandler: MCPToolHandler?

    /// JSON encoder for responses.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// JSON decoder for requests.
    private let decoder = JSONDecoder()

    /// Whether the server has been initialized.
    private var isInitialized = false

    /// Server info for initialize response.
    private let serverInfo = ServerInfo(name: "AtticMCP", version: "0.1.0")

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    init() {}

    // =========================================================================
    // MARK: - Main Loop
    // =========================================================================

    /// Runs the MCP server main loop.
    ///
    /// This reads JSON-RPC requests from stdin and writes responses to stdout.
    /// The loop continues until stdin is closed or an error occurs.
    func run() async {
        // Set up unbuffered I/O for immediate response delivery
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        // Log startup to stderr (stdout is reserved for JSON-RPC)
        log("AtticMCP server starting...")

        // Read lines from stdin
        while let line = readLine() {
            // Skip empty lines
            guard !line.isEmpty else { continue }

            // Parse and handle the request
            await handleRequest(line)
        }

        log("AtticMCP server shutting down")
    }

    // =========================================================================
    // MARK: - Request Handling
    // =========================================================================

    /// Handles a single JSON-RPC request.
    private func handleRequest(_ json: String) async {
        guard let data = json.data(using: .utf8) else {
            sendError(id: .null, error: .parseError)
            return
        }

        // Try to decode the request
        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            log("Failed to parse request: \(error)")
            sendError(id: .null, error: .parseError)
            return
        }

        // Dispatch based on method
        switch request.method {
        case "initialize":
            await handleInitialize(request)

        case "initialized":
            // Client notification that initialization is complete - no response needed
            log("Client initialized")

        case "tools/list":
            handleToolsList(request)

        case "tools/call":
            await handleToolsCall(request)

        case "notifications/cancelled":
            // Client cancelled a request - just acknowledge
            log("Request cancelled")

        default:
            log("Unknown method: \(request.method)")
            sendError(id: request.id, error: .methodNotFound)
        }
    }

    /// Handles the initialize request.
    private func handleInitialize(_ request: JSONRPCRequest) async {
        log("Initializing MCP session...")

        // Connect to AtticServer via CLI socket
        do {
            // Create client first so we can use its discovery method
            client = CLISocketClient()

            // Discover running AtticServer socket (scans /tmp/attic-*.sock)
            guard let socketPath = client?.discoverSocket() else {
                log("No AtticServer socket found. Make sure AtticServer is running.")
                // Send initialize response even without connection - tools will error
                let result = InitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: ServerCapabilities(tools: .init()),
                    serverInfo: serverInfo
                )
                sendResult(id: request.id, result: AnyCodable(encodeResult(result)))
                return
            }

            log("Connecting to AtticServer at \(socketPath)")
            try await client?.connect(to: socketPath)

            // Create tool handler
            toolHandler = MCPToolHandler(client: client!)

            isInitialized = true
            log("Connected to AtticServer")
        } catch {
            log("Failed to connect to AtticServer: \(error)")
            // Continue anyway - tools will return errors when called
        }

        // Send initialize response
        let result = InitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: ServerCapabilities(tools: .init()),
            serverInfo: serverInfo
        )

        sendResult(id: request.id, result: AnyCodable(encodeResult(result)))
    }

    /// Handles the tools/list request.
    private func handleToolsList(_ request: JSONRPCRequest) {
        let tools = MCPToolDefinitions.allTools
        let result = ToolsListResult(tools: tools)
        sendResult(id: request.id, result: AnyCodable(encodeResult(result)))
    }

    /// Handles a tools/call request.
    private func handleToolsCall(_ request: JSONRPCRequest) async {
        // Extract tool name and arguments from params
        guard let params = request.params?.dictValue,
              let toolName = params["name"] as? String else {
            sendError(id: request.id, error: .invalidParams)
            return
        }

        let arguments: [String: AnyCodable]
        if let args = params["arguments"] as? [String: Any] {
            arguments = args.mapValues { AnyCodable($0) }
        } else {
            arguments = [:]
        }

        // Check if we're connected
        guard let handler = toolHandler else {
            let result = ToolCallResult.error("Not connected to AtticServer. Make sure AtticServer is running.")
            sendResult(id: request.id, result: AnyCodable(encodeResult(result)))
            return
        }

        // Execute the tool
        let result = await handler.execute(tool: toolName, arguments: arguments)
        sendResult(id: request.id, result: AnyCodable(encodeResult(result)))
    }

    // =========================================================================
    // MARK: - Response Sending
    // =========================================================================

    /// Sends a successful result response.
    private func sendResult(id: RequestID, result: AnyCodable) {
        let response = JSONRPCResponse(id: id, result: result)
        sendResponse(response)
    }

    /// Sends an error response.
    private func sendError(id: RequestID, error: JSONRPCError) {
        let response = JSONRPCResponse(id: id, error: error)
        sendResponse(response)
    }

    /// Sends a JSON-RPC response to stdout.
    private func sendResponse(_ response: JSONRPCResponse) {
        do {
            let data = try encoder.encode(response)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
                fflush(stdout)
            }
        } catch {
            log("Failed to encode response: \(error)")
        }
    }

    // =========================================================================
    // MARK: - Helper Functions
    // =========================================================================

    /// Encodes a Codable value to a dictionary for AnyCodable wrapping.
    private func encodeResult<T: Codable>(_ value: T) -> [String: Any] {
        do {
            let data = try encoder.encode(value)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
        } catch {
            log("Failed to encode result: \(error)")
        }
        return [:]
    }

    /// Logs a message to stderr (stdout is reserved for JSON-RPC).
    private func log(_ message: String) {
        FileHandle.standardError.write("[AtticMCP] \(message)\n".data(using: .utf8)!)
    }
}
