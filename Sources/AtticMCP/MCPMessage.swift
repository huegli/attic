// =============================================================================
// MCPMessage.swift - MCP Protocol Message Types
// =============================================================================
//
// This file defines the JSON-RPC 2.0 message types used by the Model Context
// Protocol (MCP). MCP allows AI assistants like Claude to interact with
// external tools and services.
//
// The protocol uses standard JSON-RPC 2.0 format:
// - Requests have: jsonrpc, id, method, params
// - Responses have: jsonrpc, id, result or error
// - Notifications have: jsonrpc, method, params (no id)
//
// =============================================================================

import Foundation

// MARK: - JSON-RPC Base Types

/// A JSON-RPC 2.0 request message.
struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: RequestID
    let method: String
    let params: AnyCodable?

    init(id: RequestID, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A JSON-RPC 2.0 response message.
struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: RequestID
    let result: AnyCodable?
    let error: JSONRPCError?

    init(id: RequestID, result: AnyCodable) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: RequestID, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

/// A JSON-RPC 2.0 error object.
struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?

    init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes
    static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}

/// Request ID can be string, number, or null.
enum RequestID: Codable, Equatable, Sendable {
    case string(String)
    case number(Int)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else {
            throw DecodingError.typeMismatch(RequestID.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string, number, or null"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .number(let n):
            try container.encode(n)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - MCP Protocol Types

/// MCP initialize request parameters.
struct InitializeParams: Codable, Sendable {
    let protocolVersion: String
    let capabilities: ClientCapabilities
    let clientInfo: ClientInfo
}

/// Client capabilities.
struct ClientCapabilities: Codable, Sendable {
    // Add specific capabilities as needed
}

/// Client information.
struct ClientInfo: Codable, Sendable {
    let name: String
    let version: String
}

/// MCP initialize response result.
struct InitializeResult: Codable, Sendable {
    let protocolVersion: String
    let capabilities: ServerCapabilities
    let serverInfo: ServerInfo
}

/// Server capabilities.
struct ServerCapabilities: Codable, Sendable {
    let tools: ToolsCapability?

    struct ToolsCapability: Codable, Sendable {
        // Empty for now, indicates tools are supported
    }
}

/// Server information.
struct ServerInfo: Codable, Sendable {
    let name: String
    let version: String
}

/// MCP tool definition.
struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONSchema
}

/// JSON Schema for tool parameters.
struct JSONSchema: Codable, Sendable {
    let type: String
    let properties: [String: PropertySchema]?
    let required: [String]?

    init(type: String = "object", properties: [String: PropertySchema]? = nil, required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Property schema for tool parameters.
struct PropertySchema: Codable, Sendable {
    let type: String
    let description: String
    let minimum: Int?
    let maximum: Int?
    let `default`: AnyCodable?

    init(type: String, description: String, minimum: Int? = nil, maximum: Int? = nil, default defaultValue: AnyCodable? = nil) {
        self.type = type
        self.description = description
        self.minimum = minimum
        self.maximum = maximum
        self.default = defaultValue
    }
}

/// Tool call result.
struct ToolCallResult: Codable, Sendable {
    let content: [ToolContent]
    let isError: Bool?

    init(text: String) {
        self.content = [ToolContent(type: "text", text: text)]
        self.isError = nil
    }

    init(error: String) {
        self.content = [ToolContent(type: "text", text: error)]
        self.isError = true
    }

    static func text(_ text: String) -> ToolCallResult {
        ToolCallResult(text: text)
    }

    static func error(_ message: String) -> ToolCallResult {
        ToolCallResult(error: message)
    }
}

/// Tool content item.
struct ToolContent: Codable, Sendable {
    let type: String
    let text: String
}

/// Tools list result.
struct ToolsListResult: Codable, Sendable {
    let tools: [ToolDefinition]
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for handling arbitrary JSON values.
/// Note: Marked as @unchecked Sendable because it contains Any, but in practice
/// we only store JSON-compatible value types (String, Int, Bool, Array, Dictionary).
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "Cannot encode value of type \(type(of: value))"
            ))
        }
    }

    // Helper accessors
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }
}
