// =============================================================================
// MonitorController.swift - Central Monitor/Debugger Controller
// =============================================================================
//
// This file provides a unified interface for all monitor/debugger functionality.
// It integrates:
// - BreakpointManager: For setting/clearing breakpoints
// - MonitorStepper: For instruction-level stepping
// - Assembler: For interactive assembly
// - Disassembler interface (implemented in Phase 10)
//
// The MonitorController is used by:
// - AtticServer: For monitor commands via the CLI protocol
//
// This actor ensures thread-safe access to all monitor components and
// provides high-level methods for common debugging operations.
//
// Usage:
//
//     let monitor = MonitorController(emulator: engine)
//
//     // Set a breakpoint
//     let (bp, isROM) = try await monitor.setBreakpoint(at: 0x0600)
//
//     // Single step
//     let result = await monitor.step()
//
//     // Assemble a line
//     let bytes = try await monitor.assembleLine("LDA #$00")
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Monitor Controller
// =============================================================================

/// Central controller for monitor/debugger functionality.
///
/// This actor coordinates all debugging features and provides a clean API
/// for use by the REPL and CLI protocol handlers.
public actor MonitorController {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The emulator engine being debugged.
    private let emulator: EmulatorEngine

    /// Breakpoint manager.
    public let breakpoints: BreakpointManager

    /// Instruction stepper.
    private let stepper: MonitorStepper

    /// Interactive assembler (created on demand for each session).
    private var interactiveAssembler: InteractiveAssembler?

    /// Whether we're currently in interactive assembly mode.
    private var inAssemblyMode: Bool = false

    /// The starting address of the current assembly session.
    private var assemblyStartAddress: UInt16 = 0

    /// Memory adapter for breakpoint operations.
    private var memoryAdapter: EmulatorMemoryAdapter {
        EmulatorMemoryAdapter(emulator: emulator)
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new monitor controller.
    ///
    /// - Parameter emulator: The emulator engine to control.
    public init(emulator: EmulatorEngine) {
        self.emulator = emulator
        self.breakpoints = BreakpointManager()
        self.stepper = MonitorStepper(emulator: emulator, breakpoints: breakpoints)
    }

    // =========================================================================
    // MARK: - Breakpoint Management
    // =========================================================================

    /// Sets a breakpoint at the specified address.
    ///
    /// - Parameter address: The address to break at.
    /// - Returns: Tuple of (breakpoint, isROM warning flag).
    /// - Throws: BreakpointError on failure.
    public func setBreakpoint(at address: UInt16) async throws -> (Breakpoint, isROM: Bool) {
        try await breakpoints.setBreakpoint(at: address, memory: memoryAdapter)
    }

    /// Clears a breakpoint at the specified address.
    ///
    /// - Parameter address: The address to clear.
    /// - Throws: BreakpointError if no breakpoint exists.
    public func clearBreakpoint(at address: UInt16) async throws {
        try await breakpoints.clearBreakpoint(at: address, memory: memoryAdapter)
    }

    /// Clears all breakpoints.
    public func clearAllBreakpoints() async {
        await breakpoints.clearAllBreakpoints(memory: memoryAdapter)
    }

    /// Returns all active breakpoints.
    public func listBreakpoints() async -> [Breakpoint] {
        await breakpoints.getAllBreakpoints()
    }

    /// Checks if an address has a breakpoint.
    public func hasBreakpoint(at address: UInt16) async -> Bool {
        await breakpoints.hasBreakpoint(at: address)
    }

    // =========================================================================
    // MARK: - Stepping
    // =========================================================================

    /// Steps one instruction.
    ///
    /// - Returns: The result of the step operation.
    public func step() async -> MonitorStepResult {
        await stepper.step()
    }

    /// Steps multiple instructions.
    ///
    /// - Parameter count: Number of instructions to step.
    /// - Returns: The result after stepping.
    public func step(count: Int) async -> MonitorStepResult {
        await stepper.step(count: count)
    }

    /// Steps over a subroutine call.
    ///
    /// - Returns: The result of the step-over operation.
    public func stepOver() async -> MonitorStepResult {
        await stepper.stepOver()
    }

    /// Runs until the PC reaches a specific address.
    ///
    /// - Parameter address: The target address.
    /// - Returns: The result when stopped.
    public func runUntil(address: UInt16) async -> MonitorStepResult {
        await stepper.runUntil(address: address)
    }

    // =========================================================================
    // MARK: - Execution Control
    // =========================================================================

    /// Resumes execution (go).
    ///
    /// - Parameter address: Optional address to resume from.
    public func go(from address: UInt16? = nil) async {
        if let addr = address {
            var regs = await emulator.getRegisters()
            regs.pc = addr
            await emulator.setRegisters(regs)
        }
        await emulator.resume()
    }

    /// Pauses execution.
    public func pause() async {
        await emulator.pause()
    }

    /// Returns the current emulator state.
    public func getState() async -> EmulatorRunState {
        await emulator.state
    }

    /// Returns the current CPU registers.
    public func getRegisters() async -> CPURegisters {
        await emulator.getRegisters()
    }

    /// Sets CPU register values.
    ///
    /// - Parameter modifications: Array of (register name, value) tuples.
    public func setRegisters(_ modifications: [(String, UInt16)]) async {
        var regs = await emulator.getRegisters()

        for (name, value) in modifications {
            switch name.uppercased() {
            case "A": regs.a = UInt8(value & 0xFF)
            case "X": regs.x = UInt8(value & 0xFF)
            case "Y": regs.y = UInt8(value & 0xFF)
            case "S": regs.s = UInt8(value & 0xFF)
            case "P": regs.p = UInt8(value & 0xFF)
            case "PC": regs.pc = value
            default: break
            }
        }

        await emulator.setRegisters(regs)
    }

    // =========================================================================
    // MARK: - Memory Operations
    // =========================================================================

    /// Reads a byte from memory.
    ///
    /// If there's a breakpoint at the address, returns the original byte
    /// instead of the BRK instruction.
    public func readMemory(at address: UInt16) async -> UInt8 {
        // Check for breakpoint - return original byte if present
        if let original = await breakpoints.getOriginalByte(at: address) {
            return original
        }
        return await emulator.readMemory(at: address)
    }

    /// Reads a block of memory.
    ///
    /// Breakpoint bytes are replaced with their original values.
    public func readMemoryBlock(at address: UInt16, count: Int) async -> [UInt8] {
        var bytes = await emulator.readMemoryBlock(at: address, count: count)

        // Replace any breakpoint bytes with originals
        for i in 0..<count {
            let addr = address &+ UInt16(i)
            if let original = await breakpoints.getOriginalByte(at: addr) {
                bytes[i] = original
            }
        }

        return bytes
    }

    /// Writes a byte to memory.
    ///
    /// Note: Writing to a breakpoint address will update the "original byte"
    /// that gets restored when the breakpoint is cleared.
    public func writeMemory(at address: UInt16, value: UInt8) async {
        // TODO: Update breakpoint original byte if needed
        await emulator.writeMemory(at: address, value: value)
    }

    /// Writes a block of memory.
    public func writeMemoryBlock(at address: UInt16, bytes: [UInt8]) async {
        await emulator.writeMemoryBlock(at: address, bytes: bytes)
    }

    /// Fills a memory range with a value.
    public func fillMemory(from start: UInt16, to end: UInt16, value: UInt8) async {
        let count = Int(end) - Int(start) + 1
        let bytes = [UInt8](repeating: value, count: count)
        await emulator.writeMemoryBlock(at: start, bytes: bytes)
    }

    // =========================================================================
    // MARK: - Assembly
    // =========================================================================

    /// Enters interactive assembly mode at the specified address.
    ///
    /// - Parameter address: The starting address for assembly.
    public func enterAssemblyMode(at address: UInt16) {
        interactiveAssembler = InteractiveAssembler(startAddress: address)
        assemblyStartAddress = address
        inAssemblyMode = true
    }

    /// Returns whether we're in assembly mode.
    public var isInAssemblyMode: Bool {
        inAssemblyMode
    }

    /// Returns the current assembly address.
    public var currentAssemblyAddress: UInt16 {
        interactiveAssembler?.currentAddress ?? 0
    }

    /// Assembles a line in interactive mode.
    ///
    /// - Parameter line: The assembly instruction.
    /// - Returns: The formatted result string, or nil to exit assembly mode.
    /// - Throws: AssemblerError on failure.
    public func assembleInteractiveLine(_ line: String) async throws -> String? {
        guard inAssemblyMode, let assembler = interactiveAssembler else {
            throw AssemblerError.syntaxError("Not in assembly mode")
        }

        // Empty line exits assembly mode
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            let startAddr = assemblyStartAddress
            let endAddr = assembler.currentAddress
            let byteCount = Int(endAddr) - Int(startAddr)
            inAssemblyMode = false
            interactiveAssembler = nil
            return "Assembly complete: \(byteCount) bytes at $\(String(format: "%04X", startAddr))-$\(String(format: "%04X", endAddr &- 1))"
        }

        // Assemble the line
        let result = try assembler.assembleLine(line)

        // Write bytes to emulator memory
        if !result.bytes.isEmpty {
            await emulator.writeMemoryBlock(at: result.address, bytes: result.bytes)
        }

        // Format output
        return assembler.format(result)
    }

    /// Exits assembly mode without completing.
    public func exitAssemblyMode() {
        inAssemblyMode = false
        interactiveAssembler = nil
    }

    /// Assembles a single line and writes to memory (non-interactive).
    ///
    /// - Parameters:
    ///   - line: The assembly instruction.
    ///   - address: The address to assemble at.
    /// - Returns: The assembled bytes.
    /// - Throws: AssemblerError on failure.
    public func assembleLine(_ line: String, at address: UInt16) async throws -> [UInt8] {
        let assembler = Assembler(startAddress: address)
        let result = try assembler.assembleLine(line)

        // Write to memory
        if !result.bytes.isEmpty {
            await emulator.writeMemoryBlock(at: result.address, bytes: result.bytes)
        }

        return result.bytes
    }

    // =========================================================================
    // MARK: - Disassembly Interface
    // =========================================================================

    /// Disassembles instructions at the specified address.
    ///
    /// Note: Full disassembly is implemented in Phase 10. This provides
    /// a basic interface that can be used until then.
    ///
    /// - Parameters:
    ///   - address: Starting address (nil = current PC).
    ///   - lines: Number of lines to disassemble.
    /// - Returns: Formatted disassembly string.
    public func disassemble(at address: UInt16?, lines: Int) async -> String {
        let startAddr: UInt16
        if let addr = address {
            startAddr = addr
        } else {
            startAddr = await emulator.getRegisters().pc
        }
        var output: [String] = []
        var currentAddr = startAddr

        for _ in 0..<lines {
            let opcode = await readMemory(at: currentAddr)
            let info = OpcodeTable.lookup(opcode)
            let length = info.byteCount

            // Read instruction bytes
            var bytes: [UInt8] = [opcode]
            for i in 1..<length {
                bytes.append(await readMemory(at: currentAddr &+ UInt16(i)))
            }

            // Format: $XXXX  XX XX XX  MNEMONIC OPERAND
            let addrStr = String(format: "$%04X", currentAddr)
            let bytesStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            let paddedBytes = bytesStr.padding(toLength: 11, withPad: " ", startingAt: 0)

            let disasm: String
            if !info.isIllegal && info.mnemonic != "???" {
                disasm = formatInstruction(info: info, bytes: bytes, address: currentAddr)
            } else {
                disasm = String(format: "??? $%02X", opcode)
            }

            output.append("\(addrStr)  \(paddedBytes) \(disasm)")
            currentAddr = currentAddr &+ UInt16(length)
        }

        return output.joined(separator: "\n")
    }

    /// Formats a single instruction for display.
    private func formatInstruction(info: OpcodeInfo, bytes: [UInt8], address: UInt16) -> String {
        let mnemonic = info.mnemonic

        switch info.mode {
        case .implied:
            return mnemonic

        case .accumulator:
            return "\(mnemonic) A"

        case .immediate:
            return String(format: "%@ #$%02X", mnemonic, bytes[1])

        case .zeroPage:
            return String(format: "%@ $%02X", mnemonic, bytes[1])

        case .zeroPageX:
            return String(format: "%@ $%02X,X", mnemonic, bytes[1])

        case .zeroPageY:
            return String(format: "%@ $%02X,Y", mnemonic, bytes[1])

        case .absolute:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return String(format: "%@ $%04X", mnemonic, addr)

        case .absoluteX:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return String(format: "%@ $%04X,X", mnemonic, addr)

        case .absoluteY:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return String(format: "%@ $%04X,Y", mnemonic, addr)

        case .indirect:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return String(format: "%@ ($%04X)", mnemonic, addr)

        case .indexedIndirectX:
            return String(format: "%@ ($%02X,X)", mnemonic, bytes[1])

        case .indirectIndexedY:
            return String(format: "%@ ($%02X),Y", mnemonic, bytes[1])

        case .relative:
            let offset = Int8(bitPattern: bytes[1])
            let target = OpcodeTable.branchTarget(from: address + 2, offset: offset)
            return String(format: "%@ $%04X", mnemonic, target)

        case .unknown:
            return String(format: "??? $%02X", bytes[0])
        }
    }

    // =========================================================================
    // MARK: - Formatting Helpers
    // =========================================================================

    /// Formats a memory dump for display.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - bytes: Bytes to display.
    /// - Returns: Formatted hex dump string.
    public func formatMemoryDump(address: UInt16, bytes: [UInt8]) -> String {
        var output = ""
        var addr = address

        for chunk in stride(from: 0, to: bytes.count, by: 16) {
            let end = min(chunk + 16, bytes.count)
            let lineBytes = Array(bytes[chunk..<end])

            // Address
            output += String(format: "%04X: ", addr)

            // Hex bytes
            for (i, byte) in lineBytes.enumerated() {
                output += String(format: "%02X ", byte)
                if i == 7 { output += " " }
            }

            // Padding for incomplete line
            if lineBytes.count < 16 {
                let missing = 16 - lineBytes.count
                output += String(repeating: "   ", count: missing)
                if lineBytes.count < 8 { output += " " }
            }

            // ASCII representation
            output += " |"
            for byte in lineBytes {
                let char = (byte >= 0x20 && byte < 0x7F) ? Character(UnicodeScalar(byte)) : "."
                output.append(char)
            }
            output += "|\n"

            addr = addr &+ 16
        }

        return output.trimmingCharacters(in: .newlines)
    }

    /// Formats registers for display.
    public func formatRegisters(_ regs: CPURegisters) -> String {
        """
          \(regs.formatted)
          Flags: \(regs.flagsFormatted)
        """
    }

    /// Formats a step result for display.
    public func formatStepResult(_ result: MonitorStepResult) -> String {
        var output = ""

        if result.breakpointHit, let addr = result.breakpointAddress {
            output += "* Breakpoint hit at $\(String(format: "%04X", addr))\n"
        }

        if let error = result.errorMessage {
            output += "Error: \(error)\n"
        }

        output += formatRegisters(result.registers)

        return output
    }

    /// Formats a breakpoint for display.
    public func formatBreakpoint(_ bp: Breakpoint) -> String {
        bp.formatted
    }
}

// =============================================================================
// MARK: - Emulator Engine Extensions
// =============================================================================

extension EmulatorEngine {
    /// Creates a MonitorController for this emulator.
    public func createMonitor() -> MonitorController {
        MonitorController(emulator: self)
    }
}
