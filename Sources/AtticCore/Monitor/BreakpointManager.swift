// =============================================================================
// BreakpointManager.swift - Enhanced Breakpoint Management with BRK Injection
// =============================================================================
//
// This file implements breakpoint management for the monitor/debugger. It
// supports two breakpoint mechanisms:
//
// 1. **BRK Injection (RAM)**: For addresses in RAM, the original byte is
//    saved and replaced with BRK ($00). When the CPU executes BRK, the
//    emulator detects a breakpoint hit.
//
// 2. **PC Polling (ROM)**: For addresses in ROM (which cannot be modified),
//    the emulator checks the PC against a list of ROM breakpoints after
//    each instruction. This is slower but necessary for ROM breakpoints.
//
// Why Two Mechanisms?
// ------------------
// The 6502 doesn't have hardware breakpoint support. The standard technique
// is to replace the target instruction with BRK ($00), which causes a
// software interrupt. However, this only works for writable memory.
//
// For ROM, we must use a "watch" approach where we check the PC after each
// instruction (or frame) to see if it matches a breakpoint address.
//
// Memory Map (Atari 800 XL):
// -------------------------
// $0000-$BFFF: RAM (potentially, with banking)
// $A000-$BFFF: BASIC ROM or RAM (controlled by PORTB)
// $C000-$CFFF: Self-test ROM or RAM
// $D000-$D7FF: Hardware I/O registers
// $D800-$FFFF: OS ROM
//
// For simplicity, we treat $C000+ as ROM territory. A more sophisticated
// implementation would check the actual memory banking state.
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Breakpoint Type
// =============================================================================

/// The type of breakpoint based on memory location.
public enum BreakpointType: String, Sendable {
    /// RAM breakpoint using BRK injection.
    /// The original byte is replaced with BRK ($00).
    case ram

    /// ROM breakpoint using PC watching.
    /// The emulator checks PC after each operation.
    case rom
}

// =============================================================================
// MARK: - Breakpoint Structure
// =============================================================================

/// Represents a single breakpoint.
public struct Breakpoint: Sendable, Equatable {
    /// The address of the breakpoint.
    public let address: UInt16

    /// The type of breakpoint (RAM or ROM).
    public let type: BreakpointType

    /// The original byte at this address (for RAM breakpoints).
    public let originalByte: UInt8?

    /// Number of times this breakpoint has been hit.
    public var hitCount: Int

    /// Whether this breakpoint is currently enabled.
    public var enabled: Bool

    /// Optional condition (for future conditional breakpoints).
    public var condition: String?

    /// Creates a new breakpoint.
    public init(address: UInt16, type: BreakpointType, originalByte: UInt8? = nil) {
        self.address = address
        self.type = type
        self.originalByte = originalByte
        self.hitCount = 0
        self.enabled = true
        self.condition = nil
    }

    public static func == (lhs: Breakpoint, rhs: Breakpoint) -> Bool {
        lhs.address == rhs.address
    }
}

// =============================================================================
// MARK: - Breakpoint Manager Errors
// =============================================================================

/// Errors that can occur during breakpoint operations.
public enum BreakpointError: Error, LocalizedError, Sendable {
    case alreadySet(UInt16)
    case notFound(UInt16)
    case cannotModifyROM(UInt16)
    case invalidAddress(UInt16)

    public var errorDescription: String? {
        switch self {
        case .alreadySet(let addr):
            return "Breakpoint already set at $\(String(format: "%04X", addr))"
        case .notFound(let addr):
            return "No breakpoint at $\(String(format: "%04X", addr))"
        case .cannotModifyROM(let addr):
            return "Cannot inject BRK at ROM address $\(String(format: "%04X", addr))"
        case .invalidAddress(let addr):
            return "Invalid breakpoint address $\(String(format: "%04X", addr))"
        }
    }
}

// =============================================================================
// MARK: - Memory Reader/Writer Protocol
// =============================================================================

/// Protocol for reading and writing memory.
///
/// This abstraction allows the breakpoint manager to work with any memory
/// implementation without depending directly on EmulatorEngine.
public protocol MemoryAccess: Sendable {
    /// Reads a byte from memory.
    func readMemory(at address: UInt16) async -> UInt8

    /// Writes a byte to memory.
    func writeMemory(at address: UInt16, value: UInt8) async
}

// =============================================================================
// MARK: - Breakpoint Manager
// =============================================================================

/// Manages breakpoints for the monitor/debugger.
///
/// This actor provides thread-safe breakpoint management with support for
/// both RAM (BRK injection) and ROM (PC watching) breakpoints.
///
/// Usage:
///
///     let manager = BreakpointManager()
///
///     // Set a RAM breakpoint (will inject BRK)
///     try await manager.setBreakpoint(at: 0x0600, memory: emulator)
///
///     // Set a ROM breakpoint (will use PC watching)
///     try await manager.setBreakpoint(at: 0xE477, memory: emulator)
///     // Warning: ROM breakpoints use slower PC watching
///
///     // Check if PC hit a breakpoint
///     if let bp = await manager.checkBreakpoint(at: pc) {
///         // Breakpoint hit!
///     }
///
public actor BreakpointManager {
    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// The BRK opcode used for breakpoint injection.
    public static let brkOpcode: UInt8 = 0x00

    /// Start of ROM territory (simplified - actual banking is more complex).
    /// Addresses at or above this are treated as ROM.
    public static let romStartAddress: UInt16 = 0xC000

    /// Hardware I/O region start (cannot set breakpoints here).
    public static let ioStartAddress: UInt16 = 0xD000

    /// Hardware I/O region end.
    public static let ioEndAddress: UInt16 = 0xD7FF

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// All active breakpoints, keyed by address.
    private var breakpoints: [UInt16: Breakpoint] = [:]

    /// Set of ROM breakpoint addresses (for fast PC checking).
    private var romBreakpointAddresses: Set<UInt16> = []

    /// Callback invoked when a breakpoint is hit.
    public var onBreakpointHit: (@Sendable (Breakpoint) async -> Void)?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    public init() {}

    // =========================================================================
    // MARK: - Breakpoint Classification
    // =========================================================================

    /// Determines the breakpoint type for an address.
    ///
    /// - Parameter address: The address to classify.
    /// - Returns: The breakpoint type (RAM or ROM).
    public func classifyAddress(_ address: UInt16) -> BreakpointType {
        // Hardware I/O area - treat as ROM (can't breakpoint here meaningfully)
        if address >= Self.ioStartAddress && address <= Self.ioEndAddress {
            return .rom
        }

        // ROM area
        if address >= Self.romStartAddress {
            return .rom
        }

        // Everything else is RAM
        return .ram
    }

    /// Returns true if the address is in ROM.
    public func isROMAddress(_ address: UInt16) -> Bool {
        classifyAddress(address) == .rom
    }

    // =========================================================================
    // MARK: - Setting Breakpoints
    // =========================================================================

    /// Sets a breakpoint at the specified address.
    ///
    /// For RAM addresses, this injects a BRK instruction.
    /// For ROM addresses, this sets up PC watching.
    ///
    /// - Parameters:
    ///   - address: The address to break at.
    ///   - memory: Memory access for reading/writing (for BRK injection).
    /// - Returns: The created breakpoint, and whether it's a ROM breakpoint (warning).
    /// - Throws: BreakpointError if the breakpoint cannot be set.
    @discardableResult
    public func setBreakpoint(at address: UInt16, memory: MemoryAccess) async throws -> (Breakpoint, isROM: Bool) {
        // Check if already set
        if breakpoints[address] != nil {
            throw BreakpointError.alreadySet(address)
        }

        let type = classifyAddress(address)
        var breakpoint: Breakpoint

        switch type {
        case .ram:
            // Read and save original byte
            let originalByte = await memory.readMemory(at: address)

            // Inject BRK
            await memory.writeMemory(at: address, value: Self.brkOpcode)

            breakpoint = Breakpoint(address: address, type: .ram, originalByte: originalByte)

        case .rom:
            // ROM breakpoint - just track for PC watching
            breakpoint = Breakpoint(address: address, type: .rom)
            romBreakpointAddresses.insert(address)
        }

        breakpoints[address] = breakpoint
        return (breakpoint, type == .rom)
    }

    /// Sets a breakpoint without memory modification (for initialization).
    ///
    /// This is used when restoring breakpoints from saved state or when
    /// the memory is already set up.
    public func setBreakpointTracking(at address: UInt16, originalByte: UInt8?) {
        let type = classifyAddress(address)
        let breakpoint = Breakpoint(address: address, type: type, originalByte: originalByte)
        breakpoints[address] = breakpoint

        if type == .rom {
            romBreakpointAddresses.insert(address)
        }
    }

    // =========================================================================
    // MARK: - Clearing Breakpoints
    // =========================================================================

    /// Clears a breakpoint at the specified address.
    ///
    /// For RAM breakpoints, this restores the original byte.
    ///
    /// - Parameters:
    ///   - address: The address to clear.
    ///   - memory: Memory access for restoring original byte.
    /// - Throws: BreakpointError if no breakpoint exists.
    public func clearBreakpoint(at address: UInt16, memory: MemoryAccess) async throws {
        guard let breakpoint = breakpoints[address] else {
            throw BreakpointError.notFound(address)
        }

        // Restore original byte for RAM breakpoints
        if breakpoint.type == .ram, let original = breakpoint.originalByte {
            await memory.writeMemory(at: address, value: original)
        }

        breakpoints.removeValue(forKey: address)
        romBreakpointAddresses.remove(address)
    }

    /// Clears all breakpoints.
    ///
    /// - Parameter memory: Memory access for restoring original bytes.
    public func clearAllBreakpoints(memory: MemoryAccess) async {
        // Restore all RAM breakpoints
        for (_, breakpoint) in breakpoints {
            if breakpoint.type == .ram, let original = breakpoint.originalByte {
                await memory.writeMemory(at: breakpoint.address, value: original)
            }
        }

        breakpoints.removeAll()
        romBreakpointAddresses.removeAll()
    }

    // =========================================================================
    // MARK: - Querying Breakpoints
    // =========================================================================

    /// Returns the breakpoint at an address, if any.
    public func getBreakpoint(at address: UInt16) -> Breakpoint? {
        breakpoints[address]
    }

    /// Returns true if a breakpoint exists at the address.
    public func hasBreakpoint(at address: UInt16) -> Bool {
        breakpoints[address] != nil
    }

    /// Returns all breakpoints.
    public func getAllBreakpoints() -> [Breakpoint] {
        Array(breakpoints.values).sorted { $0.address < $1.address }
    }

    /// Returns all breakpoint addresses.
    public func getAllAddresses() -> [UInt16] {
        Array(breakpoints.keys).sorted()
    }

    /// Returns true if there are any ROM breakpoints active.
    ///
    /// When ROM breakpoints are active, the emulator should check
    /// the PC after each instruction for performance reasons.
    public var hasROMBreakpoints: Bool {
        !romBreakpointAddresses.isEmpty
    }

    /// Returns the set of ROM breakpoint addresses for fast checking.
    public var romBreakpoints: Set<UInt16> {
        romBreakpointAddresses
    }

    // =========================================================================
    // MARK: - Breakpoint Hit Detection
    // =========================================================================

    /// Checks if the PC matches a breakpoint (for ROM breakpoints).
    ///
    /// This should be called after each instruction when ROM breakpoints
    /// are active. For RAM breakpoints, the BRK instruction itself
    /// triggers the breakpoint.
    ///
    /// - Parameter pc: The current program counter.
    /// - Returns: The hit breakpoint, or nil if no hit.
    public func checkROMBreakpoint(at pc: UInt16) -> Breakpoint? {
        guard romBreakpointAddresses.contains(pc) else { return nil }
        return breakpoints[pc]
    }

    /// Records a breakpoint hit and increments the hit counter.
    ///
    /// - Parameter address: The breakpoint address that was hit.
    public func recordHit(at address: UInt16) {
        if var bp = breakpoints[address] {
            bp.hitCount += 1
            breakpoints[address] = bp
        }
    }

    /// Gets the original byte at a breakpoint address.
    ///
    /// This is used when disassembling or stepping through code that
    /// has a BRK injected - we need to show the original instruction.
    ///
    /// - Parameter address: The address to check.
    /// - Returns: The original byte if a RAM breakpoint exists, nil otherwise.
    public func getOriginalByte(at address: UInt16) -> UInt8? {
        guard let bp = breakpoints[address], bp.type == .ram else {
            return nil
        }
        return bp.originalByte
    }

    // =========================================================================
    // MARK: - Temporary Breakpoint for Stepping
    // =========================================================================

    /// A temporary breakpoint used for single-stepping.
    private var temporaryBreakpoint: (address: UInt16, originalByte: UInt8)?

    /// Sets a temporary breakpoint for stepping.
    ///
    /// This is used to implement single-instruction stepping by placing
    /// a temporary BRK at the next instruction address.
    ///
    /// - Parameters:
    ///   - address: The address to break at.
    ///   - memory: Memory access for BRK injection.
    public func setTemporaryBreakpoint(at address: UInt16, memory: MemoryAccess) async {
        // Don't overwrite existing breakpoints
        guard breakpoints[address] == nil else { return }

        // Don't set temporary breakpoints in ROM
        guard classifyAddress(address) == .ram else {
            // For ROM, add to ROM breakpoints temporarily
            romBreakpointAddresses.insert(address)
            temporaryBreakpoint = (address, 0)  // 0 indicates ROM temp BP
            return
        }

        let original = await memory.readMemory(at: address)
        await memory.writeMemory(at: address, value: Self.brkOpcode)
        temporaryBreakpoint = (address, original)
    }

    /// Clears the temporary breakpoint.
    ///
    /// - Parameter memory: Memory access for restoring original byte.
    public func clearTemporaryBreakpoint(memory: MemoryAccess) async {
        guard let temp = temporaryBreakpoint else { return }

        if temp.originalByte == 0 && classifyAddress(temp.address) == .rom {
            // ROM temp breakpoint
            romBreakpointAddresses.remove(temp.address)
        } else {
            // RAM temp breakpoint
            await memory.writeMemory(at: temp.address, value: temp.originalByte)
        }

        temporaryBreakpoint = nil
    }

    /// Returns true if the address matches the temporary breakpoint.
    public func isTemporaryBreakpoint(at address: UInt16) -> Bool {
        temporaryBreakpoint?.address == address
    }

    // =========================================================================
    // MARK: - Suspend/Resume Breakpoints
    // =========================================================================

    /// Temporarily suspends a breakpoint by restoring the original byte.
    ///
    /// This is used when continuing from a breakpoint - we need to execute
    /// the original instruction before re-enabling the breakpoint.
    ///
    /// - Parameters:
    ///   - address: The breakpoint address.
    ///   - memory: Memory access.
    public func suspendBreakpoint(at address: UInt16, memory: MemoryAccess) async {
        guard let bp = breakpoints[address],
              bp.type == .ram,
              let original = bp.originalByte else { return }

        await memory.writeMemory(at: address, value: original)
    }

    /// Re-enables a suspended breakpoint by injecting BRK.
    ///
    /// - Parameters:
    ///   - address: The breakpoint address.
    ///   - memory: Memory access.
    public func resumeBreakpoint(at address: UInt16, memory: MemoryAccess) async {
        guard let bp = breakpoints[address], bp.type == .ram else { return }
        await memory.writeMemory(at: address, value: Self.brkOpcode)
    }

    // =========================================================================
    // MARK: - Enable/Disable
    // =========================================================================

    /// Disables a breakpoint without removing it.
    ///
    /// For RAM breakpoints, this restores the original byte.
    public func disableBreakpoint(at address: UInt16, memory: MemoryAccess) async {
        guard var bp = breakpoints[address] else { return }

        if bp.type == .ram, let original = bp.originalByte {
            await memory.writeMemory(at: address, value: original)
        }

        if bp.type == .rom {
            romBreakpointAddresses.remove(address)
        }

        bp.enabled = false
        breakpoints[address] = bp
    }

    /// Enables a previously disabled breakpoint.
    ///
    /// For RAM breakpoints, this re-injects BRK.
    public func enableBreakpoint(at address: UInt16, memory: MemoryAccess) async {
        guard var bp = breakpoints[address], !bp.enabled else { return }

        if bp.type == .ram {
            await memory.writeMemory(at: address, value: Self.brkOpcode)
        }

        if bp.type == .rom {
            romBreakpointAddresses.insert(address)
        }

        bp.enabled = true
        breakpoints[address] = bp
    }
}

// =============================================================================
// MARK: - Breakpoint Formatting
// =============================================================================

extension Breakpoint {
    /// Formats the breakpoint for display.
    public var formatted: String {
        var result = "$\(String(format: "%04X", address))"

        switch type {
        case .ram:
            result += " (RAM)"
        case .rom:
            result += " (ROM watch)"
        }

        if hitCount > 0 {
            result += " hits: \(hitCount)"
        }

        if !enabled {
            result += " [disabled]"
        }

        return result
    }
}
