// =============================================================================
// EmulatorEngine.swift - Thread-Safe Emulator Controller
// =============================================================================
//
// This file defines the EmulatorEngine actor, which provides thread-safe
// access to the libatari800 emulation core. In Swift, actors automatically
// serialize access to their mutable state, preventing data races.
//
// Why an Actor?
// -------------
// The emulator state (memory, CPU registers, frame buffer, etc.) can be
// accessed from multiple sources:
// - The emulation loop (running at 60fps)
// - The REPL commands (from CLI via socket)
// - The GUI (for state display and input)
//
// Using an actor ensures that all these accesses are serialized, preventing
// race conditions without requiring explicit locking.
//
// Usage Example:
//
//     let engine = EmulatorEngine()
//     try await engine.initialize(romPath: romURL)
//
//     // Start running (async)
//     await engine.run()
//
//     // Pause and inspect state
//     await engine.pause()
//     let regs = await engine.getRegisters()
//     print(regs.formatted)
//
//     // Step through code
//     let result = await engine.step(count: 5)
//
// =============================================================================

import Foundation

/// The running state of the emulator.
public enum EmulatorState: Sendable {
    /// Emulator is running at full speed.
    case running

    /// Emulator is paused (can be stepped).
    case paused

    /// Emulator hit a breakpoint.
    case breakpoint(address: UInt16)

    /// Emulator is not initialized.
    case uninitialized
}

/// Result of stepping the emulator.
public struct StepResult: Sendable {
    /// The CPU registers after stepping.
    public let registers: CPURegisters

    /// Total cycles executed.
    public let cyclesExecuted: Int

    /// Whether a breakpoint was hit.
    public let breakpointHit: Bool

    /// The breakpoint address, if one was hit.
    public let breakpointAddress: UInt16?
}

/// Thread-safe emulator controller using Swift's actor model.
///
/// EmulatorEngine wraps LibAtari800Wrapper and provides async/await methods
/// for all emulator operations. The actor model ensures thread-safe access
/// without explicit locking.
///
/// This is the primary interface for controlling the emulator from both
/// the CLI and GUI.
public actor EmulatorEngine {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The underlying C library wrapper.
    private let wrapper: LibAtari800Wrapper

    /// Current emulator state.
    private(set) public var state: EmulatorState = .uninitialized

    /// Set of active breakpoint addresses.
    private var breakpoints: Set<UInt16> = []

    /// Whether the emulation loop should continue running.
    private var shouldRun: Bool = false

    /// Callback invoked when a breakpoint is hit.
    /// Set this to be notified asynchronously of breakpoint events.
    public var onBreakpointHit: ((UInt16, CPURegisters) async -> Void)?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new EmulatorEngine instance.
    public init() {
        self.wrapper = LibAtari800Wrapper()
    }

    /// Initializes the emulator with ROMs from the specified path.
    ///
    /// - Parameter romPath: URL to the directory containing ROM files.
    /// - Throws: AtticError if initialization fails.
    public func initialize(romPath: URL) async throws {
        try wrapper.initialize(romPath: romPath)
        state = .paused
    }

    /// Returns true if the emulator has been initialized.
    public var isInitialized: Bool {
        wrapper.isInitialized
    }

    // =========================================================================
    // MARK: - Emulation Control
    // =========================================================================

    /// Starts or resumes emulation.
    ///
    /// The emulator will run at approximately 60fps until paused or a
    /// breakpoint is hit.
    public func resume() async {
        guard wrapper.isInitialized else { return }
        shouldRun = true
        state = .running
    }

    /// Pauses emulation.
    ///
    /// The emulator stops after completing the current instruction.
    public func pause() async {
        shouldRun = false
        if case .running = state {
            state = .paused
        }
    }

    /// Performs a reset.
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    ///                   If false, performs a warm reset (RESET key).
    public func reset(cold: Bool) async {
        wrapper.reset(cold: cold)
        if cold {
            // Clear breakpoints on cold reset (optional behavior)
            // breakpoints.removeAll()
        }
    }

    /// Executes the emulation loop.
    ///
    /// This method runs frames until `pause()` is called or a breakpoint is hit.
    /// It should be called from a background task.
    ///
    /// Usage:
    ///
    ///     Task {
    ///         await engine.runLoop()
    ///     }
    ///
    public func runLoop() async {
        while shouldRun {
            // Execute one frame
            wrapper.executeFrame()

            // Check for breakpoints (simplified - real implementation would
            // check during execution, not after)
            let pc = wrapper.getRegisters().pc
            if breakpoints.contains(pc) {
                shouldRun = false
                state = .breakpoint(address: pc)
                let regs = wrapper.getRegisters()
                await onBreakpointHit?(pc, regs)
                break
            }

            // Yield to allow other operations
            await Task.yield()
        }
    }

    /// Steps the emulator by a specified number of instructions.
    ///
    /// - Parameter count: Number of instructions to execute (default 1).
    /// - Returns: StepResult containing register state and execution info.
    public func step(count: Int = 1) async -> StepResult {
        var totalCycles = 0
        var hitBreakpoint = false
        var breakpointAddr: UInt16? = nil

        for _ in 0..<count {
            let cycles = wrapper.step()
            totalCycles += cycles

            let pc = wrapper.getRegisters().pc
            if breakpoints.contains(pc) {
                hitBreakpoint = true
                breakpointAddr = pc
                state = .breakpoint(address: pc)
                break
            }
        }

        let regs = wrapper.getRegisters()

        return StepResult(
            registers: regs,
            cyclesExecuted: totalCycles,
            breakpointHit: hitBreakpoint,
            breakpointAddress: breakpointAddr
        )
    }

    // =========================================================================
    // MARK: - Memory Access
    // =========================================================================

    /// Reads a byte from memory.
    ///
    /// - Parameter address: The address to read from.
    /// - Returns: The byte value at that address.
    public func readMemory(at address: UInt16) -> UInt8 {
        wrapper.readMemory(at: address)
    }

    /// Writes a byte to memory.
    ///
    /// - Parameters:
    ///   - address: The address to write to.
    ///   - value: The byte value to write.
    public func writeMemory(at address: UInt16, value: UInt8) {
        wrapper.writeMemory(at: address, value: value)
    }

    /// Reads a block of memory.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - count: Number of bytes to read.
    /// - Returns: Array of bytes.
    public func readMemoryBlock(at address: UInt16, count: Int) -> [UInt8] {
        wrapper.readMemoryBlock(at: address, count: count)
    }

    /// Writes a block of memory.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - bytes: Bytes to write.
    public func writeMemoryBlock(at address: UInt16, bytes: [UInt8]) {
        wrapper.writeMemoryBlock(at: address, bytes: bytes)
    }

    // =========================================================================
    // MARK: - CPU Registers
    // =========================================================================

    /// Gets the current CPU register state.
    public func getRegisters() -> CPURegisters {
        wrapper.getRegisters()
    }

    /// Sets CPU register values.
    ///
    /// - Parameter registers: The new register values.
    public func setRegisters(_ registers: CPURegisters) {
        wrapper.setRegisters(registers)
    }

    // =========================================================================
    // MARK: - Breakpoints
    // =========================================================================

    /// Sets a breakpoint at the specified address.
    ///
    /// - Parameter address: The address to break at.
    /// - Returns: True if the breakpoint was set, false if it already existed.
    @discardableResult
    public func setBreakpoint(at address: UInt16) -> Bool {
        let (inserted, _) = breakpoints.insert(address)
        return inserted
    }

    /// Clears a breakpoint at the specified address.
    ///
    /// - Parameter address: The address to clear.
    /// - Returns: True if a breakpoint was cleared, false if none existed.
    @discardableResult
    public func clearBreakpoint(at address: UInt16) -> Bool {
        breakpoints.remove(address) != nil
    }

    /// Clears all breakpoints.
    public func clearAllBreakpoints() {
        breakpoints.removeAll()
    }

    /// Returns all active breakpoint addresses.
    public func getBreakpoints() -> [UInt16] {
        Array(breakpoints).sorted()
    }

    // =========================================================================
    // MARK: - Frame Buffer & Audio
    // =========================================================================

    /// Returns a copy of the current frame buffer.
    public func getFrameBuffer() -> [UInt8] {
        wrapper.getFrameBuffer()
    }

    /// Returns audio samples from the last frame.
    public func getAudioSamples() -> [Float] {
        wrapper.getAudioSamples()
    }

    // =========================================================================
    // MARK: - State Persistence
    // =========================================================================

    /// Saves the current emulator state.
    ///
    /// - Returns: The serialized state data.
    /// - Throws: AtticError if saving fails.
    public func saveState() async throws -> Data {
        try wrapper.saveState()
    }

    /// Loads a previously saved state.
    ///
    /// - Parameter data: The serialized state data.
    /// - Throws: AtticError if loading fails.
    public func loadState(_ data: Data) async throws {
        try wrapper.loadState(data)
    }
}
