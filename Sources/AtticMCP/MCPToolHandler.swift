// =============================================================================
// MCPToolHandler.swift - MCP Tool Execution Handler
// =============================================================================
//
// This file implements the logic for executing MCP tool calls by translating
// them into CLI protocol commands sent to AtticServer.
//
// Tool Execution Flow:
// --------------------
// 1. MCPServer receives a "tools/call" request from Claude Code
// 2. MCPToolHandler.execute() is called with tool name and arguments
// 3. Handler validates arguments and builds the appropriate CLI command
// 4. CLI command is sent to AtticServer via CLISocketClient
// 5. Response is parsed and formatted for MCP
// 6. Result is returned to MCPServer for delivery to Claude Code
//
// Error Handling:
// ---------------
// - Invalid arguments: Return error result with description
// - CLI command failure: Return error result with server message
// - Connection issues: Let MCPServer handle reconnection
//
// =============================================================================

import Foundation
import AtticCore

// MARK: - Tool Handler

/// Handles execution of MCP tool calls by translating them to CLI commands.
///
/// This class is the bridge between MCP tool definitions and the actual
/// emulator operations. Each tool is mapped to one or more CLI commands.
///
/// Swift Best Practice: Using a dedicated handler class separates the
/// protocol logic (MCPServer) from the business logic (tool execution).
final class MCPToolHandler: Sendable {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The CLI socket client for sending commands.
    private let client: CLISocketClient

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new tool handler.
    ///
    /// - Parameter client: The CLI socket client to use for commands.
    init(client: CLISocketClient) {
        self.client = client
    }

    // =========================================================================
    // MARK: - Tool Execution
    // =========================================================================

    /// Executes a tool call.
    ///
    /// - Parameters:
    ///   - tool: The tool name.
    ///   - arguments: The tool arguments as a dictionary.
    /// - Returns: The tool call result.
    func execute(tool: String, arguments: [String: AnyCodable]) async -> ToolCallResult {
        switch tool {
        // Emulator Control
        case "emulator_status":
            return await executeStatus()
        case "emulator_pause":
            return await executePause()
        case "emulator_resume":
            return await executeResume()
        case "emulator_reset":
            return await executeReset(arguments: arguments)
        case "emulator_boot_file":
            return await executeBootFile(arguments: arguments)

        // Memory Access
        case "emulator_read_memory":
            return await executeReadMemory(arguments: arguments)
        case "emulator_write_memory":
            return await executeWriteMemory(arguments: arguments)

        // CPU State
        case "emulator_get_registers":
            return await executeGetRegisters()
        case "emulator_set_registers":
            return await executeSetRegisters(arguments: arguments)

        // Execution
        case "emulator_execute_frames":
            return await executeFrames(arguments: arguments)

        // Debugging
        case "emulator_disassemble":
            return await executeDisassemble(arguments: arguments)
        case "emulator_set_breakpoint":
            return await executeSetBreakpoint(arguments: arguments)
        case "emulator_clear_breakpoint":
            return await executeClearBreakpoint(arguments: arguments)
        case "emulator_list_breakpoints":
            return await executeListBreakpoints()

        // Input
        case "emulator_press_key":
            return await executePressKey(arguments: arguments)

        // Display
        case "emulator_screenshot":
            return await executeScreenshot(arguments: arguments)

        // BASIC
        // NOTE: BASIC injection tools are disabled per attic-ahl (direct memory manipulation)
        case "emulator_enter_basic_line":
            return .error("BASIC line injection is disabled. Use emulator_press_key to type BASIC commands.")
        case "emulator_run_basic":
            return .error("BASIC run injection is disabled. Use emulator_press_key to type RUN.")
        case "emulator_new_basic":
            return .error("BASIC new injection is disabled. Use emulator_press_key to type NEW.")
        case "emulator_list_basic":
            return await executeListBasic()

        // Disk Operations
        case "emulator_mount_disk":
            return await executeMountDisk(arguments: arguments)
        case "emulator_unmount_disk":
            return await executeUnmountDisk(arguments: arguments)
        case "emulator_list_drives":
            return await executeListDrives()

        // Advanced Debugging
        case "emulator_step_over":
            return await executeStepOver()
        case "emulator_run_until":
            return await executeRunUntil(arguments: arguments)
        case "emulator_assemble":
            return await executeAssemble(arguments: arguments)
        case "emulator_fill_memory":
            return await executeFillMemory(arguments: arguments)

        // State Management
        case "emulator_save_state":
            return await executeSaveState(arguments: arguments)
        case "emulator_load_state":
            return await executeLoadState(arguments: arguments)

        default:
            return .error("Unknown tool: \(tool)")
        }
    }

    // =========================================================================
    // MARK: - Emulator Control Tools
    // =========================================================================

    /// Executes the status tool.
    private func executeStatus() async -> ToolCallResult {
        do {
            let response = try await client.send(.status)
            return formatResponse(response)
        } catch {
            return .error("Failed to get status: \(error.localizedDescription)")
        }
    }

    /// Executes the pause tool.
    private func executePause() async -> ToolCallResult {
        do {
            let response = try await client.send(.pause)
            return formatResponse(response)
        } catch {
            return .error("Failed to pause: \(error.localizedDescription)")
        }
    }

    /// Executes the resume tool.
    private func executeResume() async -> ToolCallResult {
        do {
            let response = try await client.send(.resume)
            return formatResponse(response)
        } catch {
            return .error("Failed to resume: \(error.localizedDescription)")
        }
    }

    /// Executes the reset tool.
    private func executeReset(arguments: [String: AnyCodable]) async -> ToolCallResult {
        let cold = arguments["cold"]?.boolValue ?? true

        do {
            let response = try await client.send(.reset(cold: cold))
            return formatResponse(response)
        } catch {
            return .error("Failed to reset: \(error.localizedDescription)")
        }
    }

    /// Executes the boot file tool.
    ///
    /// Sends a `boot <path>` command to the server via the CLI socket protocol.
    private func executeBootFile(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required parameter: path")
        }

        do {
            let response = try await client.send(.boot(path: path))
            return formatResponse(response)
        } catch {
            return .error("Failed to boot file: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Memory Access Tools
    // =========================================================================

    /// Executes the read memory tool.
    private func executeReadMemory(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let address = arguments["address"]?.intValue else {
            return .error("Missing required parameter: address")
        }

        let count = arguments["count"]?.intValue ?? 16

        // Validate address range
        guard address >= 0 && address <= 65535 else {
            return .error("Address must be between 0 and 65535")
        }

        // Validate count
        guard count >= 1 && count <= 256 else {
            return .error("Count must be between 1 and 256")
        }

        do {
            let response = try await client.send(.read(address: UInt16(address), count: UInt16(count)))
            return formatResponse(response)
        } catch {
            return .error("Failed to read memory: \(error.localizedDescription)")
        }
    }

    /// Executes the write memory tool.
    private func executeWriteMemory(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let address = arguments["address"]?.intValue else {
            return .error("Missing required parameter: address")
        }

        guard let dataStr = arguments["data"]?.stringValue else {
            return .error("Missing required parameter: data")
        }

        // Validate address range
        guard address >= 0 && address <= 65535 else {
            return .error("Address must be between 0 and 65535")
        }

        // Parse hex data (supports comma-separated or space-separated)
        let bytes = parseHexBytes(dataStr)
        guard !bytes.isEmpty else {
            return .error("Invalid hex data format. Use comma or space-separated hex bytes (e.g., 'A9,00,8D' or 'A9 00 8D')")
        }

        do {
            let response = try await client.send(.write(address: UInt16(address), data: bytes))
            return formatResponse(response)
        } catch {
            return .error("Failed to write memory: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - CPU State Tools
    // =========================================================================

    /// Executes the get registers tool.
    private func executeGetRegisters() async -> ToolCallResult {
        do {
            let response = try await client.send(.registers(modifications: nil))
            return formatResponse(response)
        } catch {
            return .error("Failed to get registers: \(error.localizedDescription)")
        }
    }

    /// Executes the set registers tool.
    private func executeSetRegisters(arguments: [String: AnyCodable]) async -> ToolCallResult {
        var modifications: [(String, UInt16)] = []

        // Build modifications list from provided arguments
        if let a = arguments["a"]?.intValue {
            modifications.append(("A", UInt16(a & 0xFF)))
        }
        if let x = arguments["x"]?.intValue {
            modifications.append(("X", UInt16(x & 0xFF)))
        }
        if let y = arguments["y"]?.intValue {
            modifications.append(("Y", UInt16(y & 0xFF)))
        }
        if let s = arguments["s"]?.intValue {
            modifications.append(("S", UInt16(s & 0xFF)))
        }
        if let p = arguments["p"]?.intValue {
            modifications.append(("P", UInt16(p & 0xFF)))
        }
        if let pc = arguments["pc"]?.intValue {
            modifications.append(("PC", UInt16(pc & 0xFFFF)))
        }

        if modifications.isEmpty {
            return .error("No register values specified. Provide at least one of: a, x, y, s, p, pc")
        }

        do {
            let response = try await client.send(.registers(modifications: modifications))
            return formatResponse(response)
        } catch {
            return .error("Failed to set registers: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Execution Tools
    // =========================================================================

    /// Executes the execute frames tool.
    private func executeFrames(arguments: [String: AnyCodable]) async -> ToolCallResult {
        let count = arguments["count"]?.intValue ?? 1

        // Validate count
        guard count >= 1 && count <= 3600 else {
            return .error("Count must be between 1 and 3600")
        }

        do {
            let response = try await client.send(.step(count: count))
            return formatResponse(response)
        } catch {
            return .error("Failed to execute frames: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Debugging Tools
    // =========================================================================

    /// Executes the disassemble tool.
    private func executeDisassemble(arguments: [String: AnyCodable]) async -> ToolCallResult {
        let address = arguments["address"]?.intValue
        let lines = arguments["lines"]?.intValue ?? 16

        // Validate lines
        guard lines >= 1 && lines <= 64 else {
            return .error("Lines must be between 1 and 64")
        }

        // Validate address if provided
        if let addr = address {
            guard addr >= 0 && addr <= 65535 else {
                return .error("Address must be between 0 and 65535")
            }
        }

        do {
            let response = try await client.send(.disassemble(
                address: address.map { UInt16($0) },
                lines: lines
            ))
            return formatDisassemblyResponse(response)
        } catch {
            return .error("Failed to disassemble: \(error.localizedDescription)")
        }
    }

    /// Executes the set breakpoint tool.
    private func executeSetBreakpoint(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let address = arguments["address"]?.intValue else {
            return .error("Missing required parameter: address")
        }

        guard address >= 0 && address <= 65535 else {
            return .error("Address must be between 0 and 65535")
        }

        do {
            let response = try await client.send(.breakpointSet(address: UInt16(address)))
            return formatResponse(response)
        } catch {
            return .error("Failed to set breakpoint: \(error.localizedDescription)")
        }
    }

    /// Executes the clear breakpoint tool.
    private func executeClearBreakpoint(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let address = arguments["address"]?.intValue else {
            return .error("Missing required parameter: address")
        }

        guard address >= 0 && address <= 65535 else {
            return .error("Address must be between 0 and 65535")
        }

        do {
            let response = try await client.send(.breakpointClear(address: UInt16(address)))
            return formatResponse(response)
        } catch {
            return .error("Failed to clear breakpoint: \(error.localizedDescription)")
        }
    }

    /// Executes the list breakpoints tool.
    private func executeListBreakpoints() async -> ToolCallResult {
        do {
            let response = try await client.send(.breakpointList)
            return formatResponse(response)
        } catch {
            return .error("Failed to list breakpoints: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Input Tools
    // =========================================================================

    /// Executes the press key tool.
    private func executePressKey(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let key = arguments["key"]?.stringValue else {
            return .error("Missing required parameter: key")
        }

        // Convert key string to inject keys command
        // The inject keys command handles the translation to Atari key codes
        let keyText = translateKey(key)

        do {
            let response = try await client.send(.injectKeys(text: keyText))
            return formatResponse(response)
        } catch {
            return .error("Failed to press key: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Display Tools
    // =========================================================================

    /// Executes the screenshot tool.
    private func executeScreenshot(arguments: [String: AnyCodable]) async -> ToolCallResult {
        let path = arguments["path"]?.stringValue

        do {
            let response = try await client.send(.screenshot(path: path))
            return formatResponse(response)
        } catch {
            return .error("Failed to take screenshot: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - BASIC Tools
    // =========================================================================

    /// Executes the enter BASIC line tool.
    private func executeEnterBasicLine(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let line = arguments["line"]?.stringValue else {
            return .error("Missing required parameter: line")
        }

        do {
            let response = try await client.send(.basicLine(line: line))
            return formatResponse(response)
        } catch {
            return .error("Failed to enter BASIC line: \(error.localizedDescription)")
        }
    }

    /// Executes the run BASIC tool.
    private func executeRunBasic() async -> ToolCallResult {
        do {
            let response = try await client.send(.basicRun)
            return formatResponse(response)
        } catch {
            return .error("Failed to run BASIC: \(error.localizedDescription)")
        }
    }

    /// Executes the list BASIC tool.
    private func executeListBasic() async -> ToolCallResult {
        do {
            let response = try await client.send(.basicList(atascii: false, start: nil, end: nil))
            return formatListingResponse(response)
        } catch {
            return .error("Failed to list BASIC: \(error.localizedDescription)")
        }
    }

    /// Executes the new BASIC tool.
    private func executeNewBasic() async -> ToolCallResult {
        do {
            let response = try await client.send(.basicNew)
            return formatResponse(response)
        } catch {
            return .error("Failed to clear BASIC: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Disk Operation Tools
    // =========================================================================

    /// Executes the mount disk tool.
    ///
    /// Sends a `mount <drive> <path>` command to mount an ATR disk image.
    private func executeMountDisk(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let drive = arguments["drive"]?.intValue else {
            return .error("Missing required parameter: drive")
        }

        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required parameter: path")
        }

        guard drive >= 1 && drive <= 8 else {
            return .error("Drive must be between 1 and 8")
        }

        do {
            let response = try await client.send(.mount(drive: drive, path: path))
            return formatResponse(response)
        } catch {
            return .error("Failed to mount disk: \(error.localizedDescription)")
        }
    }

    /// Executes the unmount disk tool.
    ///
    /// Sends an `unmount <drive>` command to remove a disk from a drive.
    private func executeUnmountDisk(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let drive = arguments["drive"]?.intValue else {
            return .error("Missing required parameter: drive")
        }

        guard drive >= 1 && drive <= 8 else {
            return .error("Drive must be between 1 and 8")
        }

        do {
            let response = try await client.send(.unmount(drive: drive))
            return formatResponse(response)
        } catch {
            return .error("Failed to unmount disk: \(error.localizedDescription)")
        }
    }

    /// Executes the list drives tool.
    ///
    /// Sends a `drives` command to list all mounted disk images.
    private func executeListDrives() async -> ToolCallResult {
        do {
            let response = try await client.send(.drives)
            return formatResponse(response)
        } catch {
            return .error("Failed to list drives: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Advanced Debugging Tools
    // =========================================================================

    /// Executes the step over tool.
    ///
    /// Steps over a JSR instruction, running the subroutine to completion.
    private func executeStepOver() async -> ToolCallResult {
        do {
            let response = try await client.send(.stepOver)
            return formatResponse(response)
        } catch {
            return .error("Failed to step over: \(error.localizedDescription)")
        }
    }

    /// Executes the run until tool.
    ///
    /// Runs the emulator until PC reaches the specified address.
    private func executeRunUntil(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let address = arguments["address"]?.intValue else {
            return .error("Missing required parameter: address")
        }

        guard address >= 0 && address <= 65535 else {
            return .error("Address must be between 0 and 65535")
        }

        do {
            let response = try await client.send(.runUntil(address: UInt16(address)))
            return formatResponse(response)
        } catch {
            return .error("Failed to run until address: \(error.localizedDescription)")
        }
    }

    /// Executes the assemble tool.
    ///
    /// Assembles a single 6502 instruction and writes it to memory.
    private func executeAssemble(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let address = arguments["address"]?.intValue else {
            return .error("Missing required parameter: address")
        }

        guard let instruction = arguments["instruction"]?.stringValue else {
            return .error("Missing required parameter: instruction")
        }

        guard address >= 0 && address <= 65535 else {
            return .error("Address must be between 0 and 65535")
        }

        do {
            let response = try await client.send(.assembleLine(address: UInt16(address), instruction: instruction))
            return formatResponse(response)
        } catch {
            return .error("Failed to assemble: \(error.localizedDescription)")
        }
    }

    /// Executes the fill memory tool.
    ///
    /// Fills a range of memory with a single byte value.
    private func executeFillMemory(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let start = arguments["start"]?.intValue else {
            return .error("Missing required parameter: start")
        }

        guard let end = arguments["end"]?.intValue else {
            return .error("Missing required parameter: end")
        }

        guard let value = arguments["value"]?.intValue else {
            return .error("Missing required parameter: value")
        }

        guard start >= 0 && start <= 65535 else {
            return .error("Start address must be between 0 and 65535")
        }

        guard end >= 0 && end <= 65535 else {
            return .error("End address must be between 0 and 65535")
        }

        guard end >= start else {
            return .error("End address must be >= start address")
        }

        guard value >= 0 && value <= 255 else {
            return .error("Value must be between 0 and 255")
        }

        do {
            let response = try await client.send(.memoryFill(start: UInt16(start), end: UInt16(end), value: UInt8(value)))
            return formatResponse(response)
        } catch {
            return .error("Failed to fill memory: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - State Management Tools
    // =========================================================================

    /// Executes the save state tool.
    ///
    /// Saves the complete emulator state to a file.
    private func executeSaveState(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required parameter: path")
        }

        do {
            let response = try await client.send(.stateSave(path: path))
            return formatResponse(response)
        } catch {
            return .error("Failed to save state: \(error.localizedDescription)")
        }
    }

    /// Executes the load state tool.
    ///
    /// Loads a previously saved emulator state from a file.
    private func executeLoadState(arguments: [String: AnyCodable]) async -> ToolCallResult {
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required parameter: path")
        }

        do {
            let response = try await client.send(.stateLoad(path: path))
            return formatResponse(response)
        } catch {
            return .error("Failed to load state: \(error.localizedDescription)")
        }
    }

    // =========================================================================
    // MARK: - Response Formatting
    // =========================================================================

    /// Formats a CLI response into a tool result.
    private func formatResponse(_ response: CLIResponse) -> ToolCallResult {
        switch response {
        case .ok(let data):
            return .text(data)
        case .error(let message):
            return .error(message)
        }
    }

    /// Formats a disassembly response with proper line breaks.
    private func formatDisassemblyResponse(_ response: CLIResponse) -> ToolCallResult {
        switch response {
        case .ok(let data):
            // Convert multi-line separator to actual newlines
            let formatted = data.replacingOccurrences(of: CLIProtocolConstants.multiLineSeparator, with: "\n")
            return .text(formatted)
        case .error(let message):
            return .error(message)
        }
    }

    /// Formats a BASIC listing response with proper line breaks.
    private func formatListingResponse(_ response: CLIResponse) -> ToolCallResult {
        switch response {
        case .ok(let data):
            // Convert multi-line separator to actual newlines
            let formatted = data.replacingOccurrences(of: CLIProtocolConstants.multiLineSeparator, with: "\n")
            return .text(formatted)
        case .error(let message):
            return .error(message)
        }
    }

    // =========================================================================
    // MARK: - Helper Functions
    // =========================================================================

    /// Parses a hex byte string into an array of bytes.
    ///
    /// Supports both comma-separated and space-separated formats:
    /// - "A9,00,8D,00,D4"
    /// - "A9 00 8D 00 D4"
    /// - "$A9,$00,$8D"
    private func parseHexBytes(_ str: String) -> [UInt8] {
        // First split by comma, then by space
        var parts: [String] = []

        if str.contains(",") {
            parts = str.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        } else {
            parts = str.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        var bytes: [UInt8] = []

        for part in parts {
            // Remove $ prefix if present
            let hexStr = part.hasPrefix("$") ? String(part.dropFirst()) : part

            // Try to parse as hex
            guard let byte = UInt8(hexStr, radix: 16) else {
                return []  // Invalid byte, return empty array
            }
            bytes.append(byte)
        }

        return bytes
    }

    /// Translates a key name to the appropriate text for injection.
    ///
    /// Handles special keys and modifiers:
    /// - RETURN, SPACE, BREAK, ESC, TAB, DELETE
    /// - SHIFT+key, CTRL+key
    private func translateKey(_ key: String) -> String {
        let upper = key.uppercased()

        // Handle special keys
        switch upper {
        case "RETURN", "ENTER":
            return "\n"
        case "SPACE":
            return " "
        case "TAB":
            return "\t"
        case "ESC", "ESCAPE":
            return "\u{1B}"
        case "DELETE", "BACKSPACE":
            return "\u{7F}"
        case "BREAK":
            // Break key - this is a special case that needs OS-level handling
            // For now, just return the character
            return "\u{03}"  // Ctrl+C equivalent
        default:
            break
        }

        // Handle modifiers (SHIFT+X, CTRL+X)
        if upper.hasPrefix("SHIFT+") {
            let char = String(upper.dropFirst(6))
            // For shift, just return the character - shift is implicit for uppercase
            if char.count == 1 {
                return char.uppercased()
            }
        } else if upper.hasPrefix("CTRL+") {
            let char = String(upper.dropFirst(5))
            // Convert to control character (Ctrl+A = 0x01, etc.)
            if char.count == 1, let ascii = char.uppercased().first?.asciiValue {
                let controlChar = ascii - 64  // A=65, Ctrl+A=1
                if controlChar >= 1 && controlChar <= 26 {
                    return String(UnicodeScalar(controlChar))
                }
            }
        }

        // Regular character - return as-is
        if key.count == 1 {
            return key
        }

        // Unknown key - return as-is and let the emulator handle it
        return key
    }
}
