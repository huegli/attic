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
// =============================================================================

import Foundation

/// The running state of the emulator.
///
/// This enum tracks what the emulator is currently doing, which affects
/// what operations are valid. For example, you can only step when paused.
public enum EmulatorRunState: Sendable, Equatable {
    /// Emulator is running at full speed.
    case running

    /// Emulator is paused (can be stepped or inspected).
    case paused

    /// Emulator hit a breakpoint and stopped.
    case breakpoint(address: UInt16)

    /// Emulator is not initialized (no ROMs loaded).
    case uninitialized
}

/// Result of stepping the emulator.
///
/// Contains information about what happened during stepping, including
/// the final register state and whether any breakpoints were hit.
public struct StepResult: Sendable {
    /// The CPU registers after stepping.
    public let registers: CPURegisters

    /// Total cycles executed.
    public let cyclesExecuted: Int

    /// Whether a breakpoint was hit.
    public let breakpointHit: Bool

    /// The breakpoint address, if one was hit.
    public let breakpointAddress: UInt16?

    /// The frame result from the last executed frame.
    public let frameResult: FrameResult
}

/// Thread-safe emulator controller using Swift's actor model.
///
/// EmulatorEngine wraps LibAtari800Wrapper and provides async/await methods
/// for all emulator operations. The actor model ensures thread-safe access
/// without explicit locking.
///
/// This is the primary interface for controlling the emulator from both
/// the CLI and GUI.
///
/// Key Responsibilities:
/// - Initialize and manage the emulator lifecycle
/// - Execute frames with input handling
/// - Provide thread-safe memory and register access
/// - Manage breakpoints for debugging
/// - Handle state save/restore
///
public actor EmulatorEngine {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The underlying C library wrapper.
    private let wrapper: LibAtari800Wrapper

    /// Current emulator run state.
    private(set) public var state: EmulatorRunState = .uninitialized

    /// Current input state, updated each frame.
    private var inputState = InputState()

    /// Whether a key release is pending.
    /// This implements "key latching" - a key press must be seen by at least
    /// one frame before being released. This prevents missed keys when
    /// keyDown and keyUp events arrive within the same frame period.
    private var keyReleasePending: Bool = false

    /// Set of active breakpoint addresses.
    private var breakpoints: Set<UInt16> = []

    /// Original bytes at breakpoint locations (for BRK injection).
    private var breakpointOriginalBytes: [UInt16: UInt8] = [:]

    /// Whether the emulation loop should continue running.
    private var shouldRun: Bool = false

    /// Frame counter for timing.
    private var frameCount: UInt64 = 0

    /// Path to ROM directory, stored for cold reset reinitialization.
    private var romPath: URL?

    /// Callback invoked when a breakpoint is hit.
    /// Set this to be notified asynchronously of breakpoint events.
    public var onBreakpointHit: (@Sendable (UInt16, CPURegisters) async -> Void)?

    /// Callback invoked after each frame for screen updates.
    public var onFrameComplete: (@Sendable ([UInt8]) async -> Void)?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new EmulatorEngine instance.
    ///
    /// The engine is created in an uninitialized state. Call `initialize(romPath:)`
    /// before using emulation functions.
    public init() {
        self.wrapper = LibAtari800Wrapper()
    }

    /// Initializes the emulator with ROMs from the specified path.
    ///
    /// This loads the Atari OS and BASIC ROMs and prepares the emulator
    /// for execution. After initialization, the emulator is in a paused state.
    ///
    /// - Parameter romPath: URL to the directory containing ROM files.
    ///   The directory should contain ATARIXL.ROM and ATARIBAS.ROM.
    /// - Throws: AtticError if initialization fails.
    public func initialize(romPath: URL) async throws {
        self.romPath = romPath
        try wrapper.initialize(romPath: romPath)
        state = .paused
        frameCount = 0
    }

    /// Returns true if the emulator has been initialized.
    public var isInitialized: Bool {
        wrapper.isInitialized
    }

    /// Shuts down the emulator and releases resources.
    public func shutdown() {
        shouldRun = false
        wrapper.shutdown()
        state = .uninitialized
    }

    // =========================================================================
    // MARK: - Emulation Control
    // =========================================================================

    /// Starts or resumes emulation.
    ///
    /// The emulator will run at approximately 60fps until paused or a
    /// breakpoint is hit. Call `runLoop()` in a background task to actually
    /// execute frames.
    public func resume() async {
        guard wrapper.isInitialized else { return }
        shouldRun = true
        state = .running
    }

    /// Pauses emulation.
    ///
    /// The emulator stops after completing the current frame.
    public func pause() async {
        shouldRun = false
        if case .running = state {
            state = .paused
        }
    }

    /// Performs a reset (reboot).
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    ///                   If false, performs a warm reset (RESET key).
    public func reset(cold: Bool) async {
        // Preserve the running state - reset should not pause emulation
        // (matches real Atari behavior where RESET continues running)
        let wasRunning = state == .running

        if cold {
            // Cold reset - full power cycle by shutting down and reinitializing
            // This completely resets the emulator state including all RAM.
            guard let romPath = romPath else {
                // If we don't have a ROM path (shouldn't happen), fall back to reboot
                wrapper.reboot(with: nil)
                var input = InputState()
                for _ in 0..<150 {
                    _ = wrapper.executeFrame(input: &input)
                }
                clearBASICProgram()
                state = wasRunning ? .running : .paused
                return
            }

            // Shutdown the emulator
            wrapper.shutdown()

            // Reinitialize with the same ROM path
            do {
                try wrapper.initialize(romPath: romPath)

                // Run frames to complete boot sequence.
                // The Atari needs ~120 frames (~2 seconds) to complete boot.
                var input = InputState()
                for _ in 0..<150 {
                    _ = wrapper.executeFrame(input: &input)
                }

                // Clear breakpoints and frame counter
                breakpoints.removeAll()
                breakpointOriginalBytes.removeAll()
                frameCount = 0

            } catch {
                // If reinitialization fails, leave emulator in uninitialized state
                state = .uninitialized
                return
            }
        } else {
            // Warm reset - like pressing RESET key on the Atari.
            // Preserves RAM but restarts from RESET vector.
            wrapper.warmstart()
        }

        // Restore previous state - if emulator was running, keep it running
        state = wasRunning ? .running : .paused
    }

    /// Clears the BASIC program from memory by resetting pointers.
    ///
    /// This is equivalent to issuing the NEW command in BASIC.
    /// It resets all BASIC memory pointers to their empty state.
    private func clearBASICProgram() {
        // Read current LOMEM (defines start of BASIC memory region)
        let lomem = UInt16(wrapper.readMemory(at: BASICPointers.lomem)) |
                   (UInt16(wrapper.readMemory(at: BASICPointers.lomem + 1)) << 8)

        // Read RAMTOP ($6A) which is the reliable source for top of RAM.
        // RAMTOP is a single byte representing the number of 256-byte pages.
        // Multiply by 256 to get the actual address.
        // Note: We use RAMTOP instead of BASIC's MEMTOP ($90-91) because
        // MEMTOP may not be correctly initialized after reboot.
        let ramtopPages = UInt16(wrapper.readMemory(at: 0x006A))
        let memtop = ramtopPages * 256

        // Calculate empty state pointers
        let emptyState = BASICMemoryState.empty(lomem: lomem, memtop: memtop)

        // Helper to write 16-bit value
        func writeWord(_ address: UInt16, _ value: UInt16) {
            wrapper.writeMemory(at: address, value: UInt8(value & 0xFF))
            wrapper.writeMemory(at: address + 1, value: UInt8(value >> 8))
        }

        // Reset all BASIC pointers
        writeWord(BASICPointers.vntp, emptyState.vntp)
        writeWord(BASICPointers.vntd, emptyState.vntd)
        writeWord(BASICPointers.vvtp, emptyState.vvtp)
        writeWord(BASICPointers.stmtab, emptyState.stmtab)
        writeWord(BASICPointers.stmcur, emptyState.stmcur)
        writeWord(BASICPointers.starp, emptyState.starp)
        writeWord(BASICPointers.runstk, emptyState.runstk)
        writeWord(BASICPointers.memtop, emptyState.memtop)

        // Write the end-of-program marker at STMTAB
        wrapper.writeMemoryBlock(at: emptyState.stmtab, bytes: BASICLineFormat.endOfProgramMarker)

        // Write VNT terminator
        wrapper.writeMemory(at: lomem, value: 0x00)
    }

    /// Reboots the emulator with an optional file to load.
    ///
    /// - Parameter filePath: Path to a file to load (ATR, XEX, etc.), or nil for plain boot.
    public func reboot(with filePath: String? = nil) async {
        wrapper.reboot(with: filePath)
        state = .paused
    }

    /// Executes the emulation loop.
    ///
    /// This method runs frames until `pause()` is called or a breakpoint is hit.
    /// It should be called from a background task.
    ///
    /// Usage:
    ///
    ///     Task {
    ///         await engine.resume()
    ///         await engine.runLoop()
    ///     }
    ///
    public func runLoop() async {
        guard wrapper.isInitialized else { return }

        while shouldRun {
            // Execute one frame with current input
            var input = inputState
            let result = wrapper.executeFrame(input: &input)

            frameCount += 1

            // Check frame result for special conditions
            switch result {
            case .breakpoint:
                let pc = wrapper.getRegisters().pc
                shouldRun = false
                state = .breakpoint(address: pc)
                let regs = wrapper.getRegisters()
                await onBreakpointHit?(pc, regs)
                return

            case .cpuCrash:
                shouldRun = false
                state = .paused
                return

            case .notInitialized, .error:
                shouldRun = false
                state = .paused
                return

            case .ok:
                break
            }

            // Check for software breakpoints
            let pc = wrapper.getRegisters().pc
            if breakpoints.contains(pc) {
                shouldRun = false
                state = .breakpoint(address: pc)
                let regs = wrapper.getRegisters()
                await onBreakpointHit?(pc, regs)
                return
            }

            // Notify frame complete for display update
            if let callback = onFrameComplete {
                let frameBuffer = wrapper.getFrameBufferBGRA()
                await callback(frameBuffer)
            }

            // Yield to allow other operations and maintain ~60fps
            // In a real implementation, you'd use a display link or precise timing
            try? await Task.sleep(nanoseconds: 16_666_667)  // ~60fps
        }
    }

    /// Executes a single frame of emulation.
    ///
    /// This is useful for headless operation or when you want to control
    /// frame timing externally.
    ///
    /// Note: This method implements key latching. If a key release is pending,
    /// the key state is cleared AFTER the frame executes, ensuring every key
    /// press is seen by at least one frame.
    ///
    /// - Returns: The frame execution result.
    @discardableResult
    public func executeFrame() async -> FrameResult {
        guard wrapper.isInitialized else { return .notInitialized }

        var input = inputState
        let result = wrapper.executeFrame(input: &input)
        frameCount += 1

        // Handle pending key release AFTER the frame has processed the input.
        // This ensures every key press is seen by at least one frame.
        if keyReleasePending {
            inputState.keyChar = 0
            inputState.keyCode = 0
            // Note: We don't clear shift/control here as they're modifier states
            // that should persist based on physical key state
            keyReleasePending = false
        }

        if result == .breakpoint {
            let pc = wrapper.getRegisters().pc
            state = .breakpoint(address: pc)
        }

        return result
    }

    /// Returns the current frame count since initialization.
    public var currentFrameCount: UInt64 {
        frameCount
    }

    // =========================================================================
    // MARK: - Input Handling
    // =========================================================================

    /// Updates the current input state.
    ///
    /// The input state is applied on the next frame execution.
    ///
    /// - Parameter input: The new input state.
    public func setInput(_ input: InputState) {
        self.inputState = input
    }

    /// Gets the current input state.
    public func getInput() -> InputState {
        inputState
    }

    /// Sends a key press event.
    ///
    /// The key will be held until `releaseKey()` is called. Key latching ensures
    /// that even if releaseKey() is called very quickly (within the same frame),
    /// the key press will still be seen by at least one frame of emulation.
    ///
    /// - Parameters:
    ///   - keyChar: ATASCII character code (0 for special keys like arrows).
    ///   - keyCode: Internal Atari key code (AKEY_* constant).
    ///   - shift: Shift key state.
    ///   - control: Control key state.
    public func pressKey(keyChar: UInt8, keyCode: UInt8, shift: Bool = false, control: Bool = false) {
        inputState.keyChar = keyChar
        inputState.keyCode = keyCode
        inputState.shift = shift
        inputState.control = control
        // Cancel any pending release since we have a new key press
        keyReleasePending = false
    }

    /// Releases the current key input.
    ///
    /// This marks the key for release, but the actual clearing happens after
    /// the next frame executes. This ensures every key press is processed by
    /// at least one frame, preventing missed keypresses when typing quickly.
    public func releaseKey() {
        // Don't clear immediately - mark for release after next frame
        // This implements key latching to prevent missed keypresses
        keyReleasePending = true
    }

    /// Sets console key states (START, SELECT, OPTION).
    public func setConsoleKeys(start: Bool = false, select: Bool = false, option: Bool = false) {
        inputState.start = start
        inputState.select = select
        inputState.option = option
    }

    /// Sets joystick state.
    ///
    /// - Parameters:
    ///   - port: Joystick port (0 or 1).
    ///   - direction: Direction bits (4-bit, RLDU format).
    ///   - trigger: Trigger button state.
    public func setJoystick(port: Int, direction: UInt8, trigger: Bool) {
        if port == 0 {
            inputState.joystick0 = direction
            inputState.trigger0 = trigger
        } else if port == 1 {
            inputState.joystick1 = direction
            inputState.trigger1 = trigger
        }
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
    /// Breakpoints cause the emulator to pause when the PC reaches the
    /// specified address.
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
        breakpointOriginalBytes.removeAll()
    }

    /// Returns all active breakpoint addresses.
    public func getBreakpoints() -> [UInt16] {
        Array(breakpoints).sorted()
    }

    /// Checks if an address has a breakpoint set.
    public func hasBreakpoint(at address: UInt16) -> Bool {
        breakpoints.contains(address)
    }

    // =========================================================================
    // MARK: - Frame Buffer & Audio
    // =========================================================================

    /// Returns the current frame buffer in BGRA format.
    ///
    /// The buffer is 384 x 240 pixels, 4 bytes per pixel (BGRA).
    public func getFrameBuffer() -> [UInt8] {
        wrapper.getFrameBufferBGRA()
    }

    /// Returns a pointer to the raw screen buffer (indexed colors).
    ///
    /// This is the original Atari screen data before palette conversion.
    /// Use `getFrameBuffer()` for display-ready BGRA data.
    public func getScreenPointer() -> UnsafePointer<UInt8>? {
        wrapper.getScreenPointer()
    }

    /// Returns audio buffer information.
    ///
    /// - Returns: Tuple containing pointer to audio data and sample count.
    public func getAudioBuffer() -> (pointer: UnsafePointer<UInt8>?, count: Int) {
        wrapper.getAudioBuffer()
    }

    /// Returns the audio samples as a byte array.
    ///
    /// This method copies the audio data into a Swift array, which is Sendable
    /// and can safely be passed across actor boundaries. Use this method when
    /// accessing audio from a different actor context.
    ///
    /// - Returns: Array of audio bytes (format depends on audioConfiguration).
    public func getAudioSamples() -> [UInt8] {
        let (pointer, count) = wrapper.getAudioBuffer()
        guard let pointer = pointer, count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Returns the audio configuration.
    public func getAudioConfiguration() -> AudioConfiguration {
        wrapper.audioConfiguration
    }

    // =========================================================================
    // MARK: - Disk Management
    // =========================================================================

    /// Mounts a disk image to the specified drive.
    ///
    /// - Parameters:
    ///   - drive: Drive number (1-8).
    ///   - path: Path to the ATR file.
    ///   - readOnly: If true, mount as read-only.
    /// - Returns: true if successful.
    @discardableResult
    public func mountDisk(drive: Int, path: String, readOnly: Bool = false) -> Bool {
        wrapper.mountDisk(drive: drive, path: path, readOnly: readOnly)
    }

    /// Unmounts the disk from the specified drive.
    ///
    /// - Parameter drive: Drive number (1-8).
    public func unmountDisk(drive: Int) {
        wrapper.unmountDisk(drive: drive)
    }

    // =========================================================================
    // MARK: - State Persistence
    // =========================================================================

    /// Saves the current emulator state (in-memory only).
    ///
    /// This captures the raw emulator state without metadata. Use
    /// `saveState(to:metadata:)` to save to a file with full metadata.
    ///
    /// - Returns: The emulator state snapshot.
    public func saveState() -> EmulatorState {
        wrapper.saveState()
    }

    /// Restores a previously saved state (in-memory only).
    ///
    /// This restores raw emulator state. Use `loadState(from:)` to load
    /// from a file and get metadata back.
    ///
    /// - Parameter state: The state to restore.
    public func restoreState(_ state: EmulatorState) {
        wrapper.restoreState(state)
    }

    /// Saves the current state to a file with metadata (v2 format).
    ///
    /// This is the primary method for saving emulator state. It writes
    /// a v2 format file that includes:
    /// - Session metadata (timestamp, REPL mode, mounted disks)
    /// - Full libatari800 state (~210KB)
    ///
    /// - Parameters:
    ///   - url: The file URL to save to.
    ///   - metadata: The session metadata to include.
    /// - Throws: AtticError if saving fails.
    public func saveState(to url: URL, metadata: StateMetadata) throws {
        let state = wrapper.saveState()

        // Determine file flags
        var flags = StateFileFlags()
        if self.state == .paused {
            flags.insert(.wasPaused)
        }

        do {
            try StateFileHandler.write(to: url, metadata: metadata, state: state, flags: flags)
        } catch let error as StateFileError {
            throw AtticError.stateSaveFailed(error.localizedDescription)
        } catch {
            throw AtticError.stateSaveFailed(error.localizedDescription)
        }
    }

    /// Loads a state from a file and returns metadata (v2 format).
    ///
    /// This is the primary method for loading emulator state. It reads
    /// a v2 format file and returns the metadata for the caller to process
    /// (e.g., restore REPL mode, display disk info).
    ///
    /// Note: Breakpoints are cleared automatically when loading state,
    /// as the RAM contents change and BRK injections become invalid.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: The metadata from the state file.
    /// - Throws: AtticError if loading fails.
    @discardableResult
    public func loadState(from url: URL) throws -> StateMetadata {
        do {
            let (metadata, state) = try StateFileHandler.read(from: url)
            wrapper.restoreState(state)
            return metadata
        } catch let error as StateFileError {
            throw AtticError.stateLoadFailed(error.localizedDescription)
        } catch {
            throw AtticError.stateLoadFailed(error.localizedDescription)
        }
    }

    /// Reads only the metadata from a state file without loading.
    ///
    /// This is useful for displaying state file info without the overhead
    /// of loading the full ~210KB state data.
    ///
    /// - Parameter url: The file URL to read.
    /// - Returns: The metadata from the state file.
    /// - Throws: AtticError if reading fails.
    public static func readStateMetadata(from url: URL) throws -> StateMetadata {
        do {
            return try StateFileHandler.readMetadata(from: url)
        } catch let error as StateFileError {
            throw AtticError.stateLoadFailed(error.localizedDescription)
        } catch {
            throw AtticError.stateLoadFailed(error.localizedDescription)
        }
    }
}
