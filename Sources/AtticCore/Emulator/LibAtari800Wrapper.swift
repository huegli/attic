// =============================================================================
// LibAtari800Wrapper.swift - Low-Level C Library Wrapper
// =============================================================================
//
// This file provides a Swift wrapper around the libatari800 C library.
// It handles all direct interaction with the C API, converting between
// Swift and C types as needed.
//
// The wrapper is designed to be used by EmulatorEngine, which adds
// thread-safety through the actor model. This class itself is NOT
// thread-safe and should only be accessed from a single thread.
//
// Key responsibilities:
// - Initialize and configure libatari800
// - Execute emulation frames
// - Read/write memory via direct pointer access
// - Get/set CPU registers via state save/restore
// - Handle frame buffer and audio buffer access
// - Manage disk mounting
//
// The libatari800 library uses a state-based approach where:
// - Memory is accessed via a pointer to the 64KB address space
// - CPU registers are extracted from a saved state structure
// - The screen buffer contains indexed color values (not RGB)
//
// =============================================================================

import Foundation
@preconcurrency import CAtari800

// =============================================================================
// MARK: - Atari Screen Constants
// =============================================================================

/// Constants for the Atari display.
///
/// The Atari 800 XL generates a 384x240 pixel display using the ANTIC
/// and GTIA chips. The screen buffer contains palette indices (0-255)
/// that must be converted to RGB for display.
public enum AtariScreen {
    /// Width of the screen in pixels.
    public static let width = 384

    /// Height of the screen in pixels.
    public static let height = 240

    /// Total number of pixels.
    public static let pixelCount = width * height

    /// Size of BGRA frame buffer in bytes (4 bytes per pixel).
    public static let bgraBufferSize = pixelCount * 4
}

// =============================================================================
// MARK: - LibAtari800Wrapper
// =============================================================================

/// Low-level wrapper around the libatari800 C library.
///
/// This class provides a Swift-friendly interface to the C emulation core.
/// It is NOT thread-safe - use EmulatorEngine for thread-safe access.
///
/// The wrapper manages:
/// - Emulator lifecycle (init, exit)
/// - Frame execution with input handling
/// - Memory access via pointer
/// - State save/restore for register access
/// - Screen and audio buffer access
/// - Disk mounting
///
/// Usage:
///
///     let wrapper = LibAtari800Wrapper()
///     try wrapper.initialize(romPath: romURL)
///
///     var input = InputState()
///     let result = wrapper.executeFrame(input: &input)
///
///     let screenData = wrapper.getScreenBuffer()
///
public final class LibAtari800Wrapper: @unchecked Sendable {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Whether the emulator has been initialized.
    private(set) public var isInitialized: Bool = false

    /// The current input state, updated each frame.
    private var currentInput = input_template_t()

    /// Cached emulator state for register access.
    /// This is expensive to compute, so we cache it.
    private var cachedState = emulator_state_t()

    /// Whether the cached state is valid.
    private var stateIsCached = false

    /// BGRA frame buffer for Metal texture upload.
    /// libatari800 provides indexed colors; we convert to BGRA here.
    private var bgraFrameBuffer: [UInt8]

    /// The NTSC color palette (256 colors, BGRA format).
    private let palette: [UInt32]

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new LibAtari800Wrapper instance.
    ///
    /// The wrapper is created in an uninitialized state. Call `initialize(romPath:)`
    /// before using any emulation functions.
    public init() {
        // Allocate BGRA frame buffer
        self.bgraFrameBuffer = [UInt8](repeating: 0, count: AtariScreen.bgraBufferSize)

        // Initialize NTSC palette
        self.palette = Self.createNTSCPalette()

        // Clear input structure
        libatari800_clear_input_array(&currentInput)
    }

    /// Initializes the emulator with ROMs from the specified path.
    ///
    /// This must be called before any other emulation functions.
    /// The ROM directory should contain:
    /// - ATARIXL.ROM (16KB OS ROM)
    /// - ATARIBAS.ROM (8KB BASIC ROM)
    ///
    /// libatari800 is initialized with command-line arguments that specify
    /// the machine type and ROM paths.
    ///
    /// - Parameter romPath: URL to the directory containing ROM files.
    /// - Throws: AtticError if initialization fails.
    public func initialize(romPath: URL) throws {
        // Verify ROMs exist
        let osRomPath = romPath.appendingPathComponent("ATARIXL.ROM")
        let basicRomPath = romPath.appendingPathComponent("ATARIBAS.ROM")

        guard FileManager.default.fileExists(atPath: osRomPath.path) else {
            throw AtticError.romNotFound(osRomPath.path)
        }

        guard FileManager.default.fileExists(atPath: basicRomPath.path) else {
            throw AtticError.romNotFound(basicRomPath.path)
        }

        // Build command-line arguments for libatari800
        // These configure the emulator for Atari 800 XL with BASIC
        //
        // Note: libatari800 parses these like command-line arguments.
        // The library prints "Error opening" warnings for arguments it
        // doesn't recognize as file paths - these warnings are harmless
        // and occur because the library tries to open each argument as
        // a file before processing it as an option.
        let args = [
            "attic",                           // Program name (argv[0], required)
            "-xl",                             // Atari 800 XL machine type
            "-xlrom", osRomPath.path,          // Path to XL OS ROM
            "-basicrom", basicRomPath.path,    // Path to BASIC ROM
            "-basic",                          // Enable BASIC
            "-sound",                          // Enable sound
            "-audio16"                         // 16-bit audio
        ]

        // Convert Swift strings to C strings for libatari800_init
        let result = args.withCStrings { cStrings in
            // libatari800_init expects argc and argv like main()
            var argv = cStrings
            return libatari800_init(Int32(args.count), &argv)
        }

        if result == 0 {
            throw AtticError.initializationFailed(
                libatari800_error_message().map { String(cString: $0) } ?? "Unknown error"
            )
        }

        // Allow emulation to continue after BRK instruction (for debugging)
        libatari800_continue_emulation_on_brk(1)

        isInitialized = true
        stateIsCached = false
    }

    // =========================================================================
    // MARK: - Emulation Control
    // =========================================================================

    /// Executes one frame of emulation (~1/60 second).
    ///
    /// This runs the 6502 CPU for one complete video frame (approximately
    /// 29780 cycles for NTSC). The screen buffer and audio buffer are
    /// updated during this call.
    ///
    /// - Parameter input: The current input state (keys, joysticks, etc.)
    /// - Returns: Frame execution result indicating any special conditions.
    @discardableResult
    public func executeFrame(input: inout InputState) -> FrameResult {
        guard isInitialized else { return .notInitialized }

        // Convert Swift InputState to C input_template_t
        currentInput.keychar = input.keyChar
        currentInput.keycode = input.keyCode
        currentInput.shift = input.shift ? 1 : 0
        currentInput.control = input.control ? 1 : 0
        currentInput.start = input.start ? 1 : 0
        currentInput.select = input.select ? 1 : 0
        currentInput.option = input.option ? 1 : 0
        currentInput.joy0 = input.joystick0
        currentInput.trig0 = input.trigger0 ? 0 : 1  // 0 = pressed, 1 = released
        currentInput.joy1 = input.joystick1
        currentInput.trig1 = input.trigger1 ? 0 : 1

        // Execute one frame
        // libatari800_next_frame returns 1 on success, 0 on failure
        let result = libatari800_next_frame(&currentInput)

        // Invalidate cached state since emulation has progressed
        stateIsCached = false

        // Check for special conditions indicated by error_code
        // @preconcurrency import allows access to C globals
        //
        // Error codes from libatari800.h:
        // 0 = No error
        // 1 = UNIDENTIFIED_CART_TYPE
        // 2 = CPU_CRASH
        // 3 = BRK_INSTRUCTION
        // 4 = DLIST_ERROR (recoverable - display list issues during boot)
        // 5 = SELF_TEST
        // 6 = MEMO_PAD
        // 7 = INVALID_ESCAPE_OPCODE
        let errorCode = Int(libatari800_error_code)

        switch errorCode {
        case 3:  // LIBATARI800_BRK_INSTRUCTION
            return .breakpoint
        case 2:  // LIBATARI800_CPU_CRASH
            return .cpuCrash
        case 4, 5, 6:  // DLIST_ERROR, SELF_TEST, MEMO_PAD - recoverable
            // These are normal conditions during boot/operation
            return .ok
        case 0:
            // No error - check result
            return result != 0 ? .ok : .error
        default:
            // Unknown error or result indicates failure
            return result != 0 ? .ok : .error
        }
    }

    /// Reboots the emulator, optionally loading a file.
    ///
    /// - Parameter filePath: Optional path to a file to boot from (ATR, XEX, etc.)
    /// - Returns: true if successful.
    @discardableResult
    public func reboot(with filePath: String? = nil) -> Bool {
        guard isInitialized else { return false }

        stateIsCached = false

        if let path = filePath {
            return libatari800_reboot_with_file(path) != 0
        } else {
            // Reboot without file by passing empty string
            return libatari800_reboot_with_file("") != 0
        }
    }

    // =========================================================================
    // MARK: - Memory Access
    // =========================================================================

    /// Returns a pointer to the main 64KB memory space.
    ///
    /// This provides direct access to Atari memory. The pointer is valid
    /// as long as the emulator is initialized.
    ///
    /// Memory map:
    /// - $0000-$3FFF: RAM (16KB)
    /// - $4000-$7FFF: RAM (16KB, bank switched on 130XE)
    /// - $8000-$9FFF: RAM (8KB) or cartridge
    /// - $A000-$BFFF: BASIC ROM or RAM
    /// - $C000-$CFFF: OS ROM or RAM
    /// - $D000-$D7FF: Hardware registers (GTIA, POKEY, PIA, ANTIC)
    /// - $D800-$FFFF: OS ROM
    ///
    /// - Returns: Optional pointer to memory, nil if not initialized.
    public func getMemoryPointer() -> UnsafeMutablePointer<UInt8>? {
        guard isInitialized else { return nil }
        return libatari800_get_main_memory_ptr()
    }

    /// Reads a byte from the specified memory address.
    ///
    /// - Parameter address: The 16-bit address to read from.
    /// - Returns: The byte value at that address, or 0 if not initialized.
    public func readMemory(at address: UInt16) -> UInt8 {
        guard let memory = getMemoryPointer() else { return 0 }
        return memory[Int(address)]
    }

    /// Writes a byte to the specified memory address.
    ///
    /// Note: Writing to ROM or hardware register addresses may have no effect
    /// or may trigger hardware-specific behavior.
    ///
    /// - Parameters:
    ///   - address: The 16-bit address to write to.
    ///   - value: The byte value to write.
    public func writeMemory(at address: UInt16, value: UInt8) {
        guard let memory = getMemoryPointer() else { return }
        memory[Int(address)] = value
    }

    /// Reads a block of memory.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - count: Number of bytes to read.
    /// - Returns: Array of bytes, or empty array if not initialized.
    public func readMemoryBlock(at address: UInt16, count: Int) -> [UInt8] {
        guard let memory = getMemoryPointer() else { return [] }

        var result = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            let addr = Int(address) &+ i
            if addr < 0x10000 {
                result[i] = memory[addr]
            }
        }
        return result
    }

    /// Writes a block of memory.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - bytes: Bytes to write.
    public func writeMemoryBlock(at address: UInt16, bytes: [UInt8]) {
        guard let memory = getMemoryPointer() else { return }

        for (i, byte) in bytes.enumerated() {
            let addr = Int(address) &+ i
            if addr < 0x10000 {
                memory[addr] = byte
            }
        }
    }

    // =========================================================================
    // MARK: - CPU Registers
    // =========================================================================

    /// Gets the current CPU register state.
    ///
    /// This uses the state save mechanism to extract register values.
    /// The state is cached to avoid expensive repeated saves.
    ///
    /// - Returns: A CPURegisters struct with all register values.
    public func getRegisters() -> CPURegisters {
        guard isInitialized else { return CPURegisters() }

        // Update cached state if needed
        if !stateIsCached {
            libatari800_get_current_state(&cachedState)
            stateIsCached = true
        }

        // Extract CPU state from the state buffer using pointer arithmetic
        // Swift can't directly access the large state[] array, so we use withUnsafePointer
        return withUnsafePointer(to: &cachedState) { statePtr in
            // Get pointer to the start of the state data (after tags_storage and flags_storage)
            let basePtr = UnsafeRawPointer(statePtr)
            let stateDataPtr = basePtr.advanced(by: 256)  // 128 + 128 bytes for unions

            let cpuOffset = Int(cachedState.tags.cpu)
            let pcOffset = Int(cachedState.tags.pc)

            // Read CPU registers from state buffer
            // cpu_state_t layout: A, P, S, X, Y, IRQ (6 bytes)
            let cpuPtr = stateDataPtr.advanced(by: cpuOffset).assumingMemoryBound(to: UInt8.self)
            let a = cpuPtr[0]
            let p = cpuPtr[1]
            let s = cpuPtr[2]
            let x = cpuPtr[3]
            let y = cpuPtr[4]

            // Read PC from state buffer
            // pc_state_t layout: PC (2 bytes, little-endian)
            let pcPtr = stateDataPtr.advanced(by: pcOffset).assumingMemoryBound(to: UInt8.self)
            let pcLow = UInt16(pcPtr[0])
            let pcHigh = UInt16(pcPtr[1])
            let pc = pcLow | (pcHigh << 8)

            return CPURegisters(a: a, x: x, y: y, s: s, p: p, pc: pc)
        }
    }

    /// Sets CPU register values.
    ///
    /// This modifies the cached state and restores it to the emulator.
    /// Note: This is an expensive operation as it requires a full state restore.
    ///
    /// - Parameter registers: The register values to set.
    public func setRegisters(_ registers: CPURegisters) {
        guard isInitialized else { return }

        // Ensure we have current state
        if !stateIsCached {
            libatari800_get_current_state(&cachedState)
        }

        // Modify CPU registers in state buffer using pointer arithmetic
        withUnsafeMutablePointer(to: &cachedState) { statePtr in
            let basePtr = UnsafeMutableRawPointer(statePtr)
            let stateDataPtr = basePtr.advanced(by: 256)  // 128 + 128 bytes for unions

            let cpuOffset = Int(cachedState.tags.cpu)
            let pcOffset = Int(cachedState.tags.pc)

            // Write CPU registers
            let cpuPtr = stateDataPtr.advanced(by: cpuOffset).assumingMemoryBound(to: UInt8.self)
            cpuPtr[0] = registers.a
            cpuPtr[1] = registers.p
            cpuPtr[2] = registers.s
            cpuPtr[3] = registers.x
            cpuPtr[4] = registers.y

            // Write PC
            let pcPtr = stateDataPtr.advanced(by: pcOffset).assumingMemoryBound(to: UInt8.self)
            pcPtr[0] = UInt8(registers.pc & 0xFF)
            pcPtr[1] = UInt8(registers.pc >> 8)
        }

        // Restore modified state
        libatari800_restore_state(&cachedState)

        // State is still valid after restore
        stateIsCached = true
    }

    // =========================================================================
    // MARK: - Screen Buffer
    // =========================================================================

    /// Returns the raw screen buffer (indexed colors).
    ///
    /// The screen buffer contains palette indices (0-255) for each pixel.
    /// Use `getFrameBufferBGRA()` for RGB data suitable for display.
    ///
    /// - Returns: Pointer to screen buffer, or nil if not initialized.
    public func getScreenPointer() -> UnsafePointer<UInt8>? {
        guard isInitialized else { return nil }
        return UnsafePointer(libatari800_get_screen_ptr())
    }

    /// Returns the frame buffer in BGRA format for display.
    ///
    /// This converts the indexed color screen buffer to BGRA using the
    /// NTSC palette. The result is suitable for uploading to a Metal texture.
    ///
    /// - Returns: BGRA pixel data (384 x 240 x 4 bytes).
    public func getFrameBufferBGRA() -> [UInt8] {
        guard let screen = getScreenPointer() else {
            return [UInt8](repeating: 0, count: AtariScreen.bgraBufferSize)
        }

        // Convert indexed colors to BGRA
        for i in 0..<AtariScreen.pixelCount {
            let colorIndex = Int(screen[i])
            let bgra = palette[colorIndex]

            let offset = i * 4
            bgraFrameBuffer[offset] = UInt8(bgra & 0xFF)          // Blue
            bgraFrameBuffer[offset + 1] = UInt8((bgra >> 8) & 0xFF)  // Green
            bgraFrameBuffer[offset + 2] = UInt8((bgra >> 16) & 0xFF) // Red
            bgraFrameBuffer[offset + 3] = 255                        // Alpha
        }

        return bgraFrameBuffer
    }

    /// Provides direct access to the BGRA frame buffer.
    ///
    /// This is more efficient than `getFrameBufferBGRA()` when you need
    /// a pointer rather than a copy.
    ///
    /// - Parameter body: Closure that receives the buffer pointer.
    /// - Returns: The value returned by the closure.
    public func withFrameBuffer<T>(_ body: (UnsafeBufferPointer<UInt8>) -> T) -> T {
        // Update the BGRA buffer first
        _ = getFrameBufferBGRA()
        return bgraFrameBuffer.withUnsafeBufferPointer(body)
    }

    // =========================================================================
    // MARK: - Audio Buffer
    // =========================================================================

    /// Returns audio samples generated during the last frame.
    ///
    /// - Returns: Pointer to audio buffer and sample count.
    public func getAudioBuffer() -> (pointer: UnsafePointer<UInt8>?, count: Int) {
        guard isInitialized else { return (nil, 0) }

        let ptr = libatari800_get_sound_buffer()
        let count = Int(libatari800_get_sound_buffer_len())

        return (UnsafePointer(ptr), count)
    }

    /// Returns audio configuration.
    public var audioConfiguration: AudioConfiguration {
        AudioConfiguration(
            sampleRate: Int(libatari800_get_sound_frequency()),
            channels: Int(libatari800_get_num_sound_channels()),
            sampleSize: Int(libatari800_get_sound_sample_size())
        )
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
        guard isInitialized, drive >= 1, drive <= 8 else { return false }
        return libatari800_mount_disk(Int32(drive), path, readOnly ? 1 : 0) != 0
    }

    /// Unmounts the disk from the specified drive.
    ///
    /// - Parameter drive: Drive number (1-8).
    public func unmountDisk(drive: Int) {
        guard isInitialized, drive >= 1, drive <= 8 else { return }
        libatari800_unmount_disk(Int32(drive))
    }

    // =========================================================================
    // MARK: - State Save/Load
    // =========================================================================

    /// Saves the current emulator state.
    ///
    /// - Returns: State data that can be restored later.
    public func saveState() -> EmulatorState {
        guard isInitialized else { return EmulatorState() }

        var state = emulator_state_t()
        libatari800_get_current_state(&state)

        return EmulatorState(from: state)
    }

    /// Restores a previously saved emulator state.
    ///
    /// - Parameter state: State to restore.
    public func restoreState(_ state: EmulatorState) {
        guard isInitialized else { return }

        var cState = state.toCState()
        libatari800_restore_state(&cState)
        stateIsCached = false
    }

    // =========================================================================
    // MARK: - Cleanup
    // =========================================================================

    /// Shuts down the emulator.
    ///
    /// Call this before releasing the wrapper to clean up resources.
    public func shutdown() {
        if isInitialized {
            libatari800_exit()
            isInitialized = false
            stateIsCached = false
        }
    }

    deinit {
        shutdown()
    }

    // =========================================================================
    // MARK: - NTSC Palette
    // =========================================================================

    /// Creates the NTSC color palette.
    ///
    /// The Atari uses a 256-color palette based on 16 hues and 16 luminances.
    /// This generates an approximate NTSC palette.
    ///
    /// - Returns: Array of 256 BGRA color values.
    private static func createNTSCPalette() -> [UInt32] {
        // Standard Atari NTSC palette
        // Each entry is BGRA (matching Metal texture format)
        let paletteRGB: [(r: UInt8, g: UInt8, b: UInt8)] = [
            // Hue 0 (grayscale)
            (0, 0, 0), (17, 17, 17), (34, 34, 34), (51, 51, 51),
            (68, 68, 68), (85, 85, 85), (102, 102, 102), (119, 119, 119),
            (136, 136, 136), (153, 153, 153), (170, 170, 170), (187, 187, 187),
            (204, 204, 204), (221, 221, 221), (238, 238, 238), (255, 255, 255),
            // Hue 1 (gold/orange)
            (25, 11, 0), (49, 29, 0), (73, 47, 0), (97, 65, 0),
            (121, 83, 0), (145, 101, 0), (169, 119, 0), (193, 137, 7),
            (217, 155, 31), (233, 173, 55), (241, 191, 79), (249, 209, 103),
            (255, 227, 127), (255, 245, 151), (255, 255, 175), (255, 255, 199),
            // Hue 2 (orange)
            (40, 3, 0), (68, 19, 0), (96, 35, 0), (124, 51, 0),
            (152, 67, 0), (180, 83, 0), (208, 99, 0), (236, 115, 0),
            (255, 131, 17), (255, 149, 45), (255, 167, 73), (255, 185, 101),
            (255, 203, 129), (255, 221, 157), (255, 239, 185), (255, 255, 213),
            // Hue 3 (red-orange)
            (51, 0, 0), (79, 7, 0), (107, 23, 0), (135, 39, 0),
            (163, 55, 0), (191, 71, 0), (219, 87, 0), (247, 103, 5),
            (255, 119, 33), (255, 137, 61), (255, 155, 89), (255, 173, 117),
            (255, 191, 145), (255, 209, 173), (255, 227, 201), (255, 245, 229),
            // Hue 4 (pink/red)
            (55, 0, 8), (83, 0, 24), (111, 7, 40), (139, 23, 56),
            (167, 39, 72), (195, 55, 88), (223, 71, 104), (251, 87, 120),
            (255, 103, 136), (255, 121, 152), (255, 139, 168), (255, 157, 184),
            (255, 175, 200), (255, 193, 216), (255, 211, 232), (255, 229, 248),
            // Hue 5 (purple)
            (49, 0, 41), (77, 0, 57), (105, 0, 73), (133, 11, 89),
            (161, 27, 105), (189, 43, 121), (217, 59, 137), (245, 75, 153),
            (255, 91, 169), (255, 109, 185), (255, 127, 201), (255, 145, 217),
            (255, 163, 233), (255, 181, 249), (255, 199, 255), (255, 217, 255),
            // Hue 6 (purple-blue)
            (37, 0, 71), (61, 0, 87), (85, 0, 103), (109, 3, 119),
            (133, 19, 135), (157, 35, 151), (181, 51, 167), (205, 67, 183),
            (229, 83, 199), (245, 101, 215), (253, 119, 231), (255, 137, 247),
            (255, 155, 255), (255, 173, 255), (255, 191, 255), (255, 209, 255),
            // Hue 7 (blue)
            (20, 0, 93), (40, 0, 109), (60, 0, 125), (80, 0, 141),
            (100, 11, 157), (120, 27, 173), (140, 43, 189), (160, 59, 205),
            (180, 75, 221), (200, 93, 237), (220, 111, 253), (235, 129, 255),
            (245, 147, 255), (255, 165, 255), (255, 183, 255), (255, 201, 255),
            // Hue 8 (blue)
            (0, 0, 103), (15, 7, 119), (30, 23, 135), (45, 39, 151),
            (60, 55, 167), (75, 71, 183), (90, 87, 199), (105, 103, 215),
            (120, 119, 231), (140, 137, 247), (160, 155, 255), (180, 173, 255),
            (200, 191, 255), (220, 209, 255), (240, 227, 255), (255, 245, 255),
            // Hue 9 (blue-cyan)
            (0, 9, 97), (0, 25, 113), (0, 41, 129), (11, 57, 145),
            (27, 73, 161), (43, 89, 177), (59, 105, 193), (75, 121, 209),
            (91, 137, 225), (109, 155, 241), (127, 173, 255), (145, 191, 255),
            (163, 209, 255), (181, 227, 255), (199, 245, 255), (217, 255, 255),
            // Hue 10 (cyan)
            (0, 23, 77), (0, 39, 93), (0, 55, 109), (0, 71, 125),
            (7, 87, 141), (23, 103, 157), (39, 119, 173), (55, 135, 189),
            (71, 151, 205), (89, 169, 221), (107, 187, 237), (125, 205, 253),
            (143, 223, 255), (161, 241, 255), (179, 255, 255), (197, 255, 255),
            // Hue 11 (cyan-green)
            (0, 35, 51), (0, 51, 67), (0, 67, 83), (0, 83, 99),
            (0, 99, 115), (7, 115, 131), (23, 131, 147), (39, 147, 163),
            (55, 163, 179), (73, 181, 195), (91, 199, 211), (109, 217, 227),
            (127, 235, 243), (145, 253, 255), (163, 255, 255), (181, 255, 255),
            // Hue 12 (green)
            (0, 41, 23), (0, 57, 39), (0, 73, 55), (0, 89, 71),
            (0, 105, 87), (0, 121, 103), (11, 137, 119), (27, 153, 135),
            (43, 169, 151), (61, 187, 169), (79, 205, 187), (97, 223, 205),
            (115, 241, 223), (133, 255, 241), (151, 255, 255), (169, 255, 255),
            // Hue 13 (green)
            (0, 41, 0), (0, 57, 7), (0, 73, 23), (0, 89, 39),
            (0, 105, 55), (0, 121, 71), (7, 137, 87), (23, 153, 103),
            (39, 169, 119), (57, 187, 137), (75, 205, 155), (93, 223, 173),
            (111, 241, 191), (129, 255, 209), (147, 255, 227), (165, 255, 245),
            // Hue 14 (yellow-green)
            (0, 35, 0), (0, 51, 0), (0, 67, 0), (0, 83, 0),
            (7, 99, 0), (23, 115, 0), (39, 131, 0), (55, 147, 0),
            (71, 163, 11), (89, 181, 29), (107, 199, 47), (125, 217, 65),
            (143, 235, 83), (161, 253, 101), (179, 255, 119), (197, 255, 137),
            // Hue 15 (yellow)
            (11, 23, 0), (27, 39, 0), (43, 55, 0), (59, 71, 0),
            (75, 87, 0), (91, 103, 0), (107, 119, 0), (123, 135, 0),
            (139, 151, 7), (157, 169, 25), (175, 187, 43), (193, 205, 61),
            (211, 223, 79), (229, 241, 97), (247, 255, 115), (255, 255, 133),
        ]

        // Convert RGB to BGRA (UInt32)
        return paletteRGB.map { color in
            UInt32(color.b) | (UInt32(color.g) << 8) | (UInt32(color.r) << 16) | (0xFF << 24)
        }
    }
}

// =============================================================================
// MARK: - Supporting Types
// =============================================================================

/// Result of executing a frame.
public enum FrameResult: Sendable {
    /// Frame executed normally.
    case ok
    /// Emulator not initialized.
    case notInitialized
    /// BRK instruction hit (breakpoint).
    case breakpoint
    /// CPU crashed (invalid instruction).
    case cpuCrash
    /// Other error occurred.
    case error
}

/// Input state for one frame.
///
/// This structure mirrors the input_template_t from libatari800.
public struct InputState: Sendable {
    /// ATASCII character code for keyboard input.
    public var keyChar: UInt8 = 0

    /// Internal key code.
    public var keyCode: UInt8 = 0

    /// Shift key state.
    public var shift: Bool = false

    /// Control key state.
    public var control: Bool = false

    /// START console key.
    public var start: Bool = false

    /// SELECT console key.
    public var select: Bool = false

    /// OPTION console key.
    public var option: Bool = false

    /// Joystick 0 direction (4-bit, RLDU).
    public var joystick0: UInt8 = 0x0F  // Centered

    /// Joystick 0 trigger.
    public var trigger0: Bool = false

    /// Joystick 1 direction.
    public var joystick1: UInt8 = 0x0F

    /// Joystick 1 trigger.
    public var trigger1: Bool = false

    public init() {}
}

/// Audio configuration from the emulator.
public struct AudioConfiguration: Sendable {
    /// Sample rate in Hz (typically 44100).
    public let sampleRate: Int

    /// Number of channels (1 for mono, 2 for stereo).
    public let channels: Int

    /// Bits per sample (8 or 16).
    public let sampleSize: Int

    /// Creates an audio configuration with the specified parameters.
    ///
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz (e.g., 44100).
    ///   - channels: Number of channels (1 for mono, 2 for stereo).
    ///   - sampleSize: Bytes per sample (1 for 8-bit, 2 for 16-bit).
    public init(sampleRate: Int, channels: Int, sampleSize: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.sampleSize = sampleSize
    }
}

/// Emulator state snapshot for save/restore.
public struct EmulatorState: Sendable {
    /// Raw state data.
    public var data: [UInt8]

    /// State tags for locating components.
    public var tags: StateTags

    /// State flags.
    public var flags: StateFlags

    public init() {
        self.data = []
        self.tags = StateTags()
        self.flags = StateFlags()
    }

    init(from cState: emulator_state_t) {
        let state = cState

        self.tags = StateTags(
            size: state.tags.size,
            cpu: state.tags.cpu,
            pc: state.tags.pc,
            baseRam: state.tags.base_ram,
            antic: state.tags.antic,
            gtia: state.tags.gtia,
            pia: state.tags.pia,
            pokey: state.tags.pokey
        )

        self.flags = StateFlags(
            selfTestEnabled: state.flags.selftest_enabled != 0,
            frameCount: state.flags.nframes
        )

        // Copy state data using pointer arithmetic
        // Swift can't directly access the large state[] array
        let size = Int(state.tags.size)
        var mutableState = state
        self.data = withUnsafePointer(to: &mutableState) { statePtr in
            let basePtr = UnsafeRawPointer(statePtr)
            let stateDataPtr = basePtr.advanced(by: 256).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: stateDataPtr, count: min(size, 210000)))
        }
    }

    func toCState() -> emulator_state_t {
        var state = emulator_state_t()

        state.tags.size = tags.size
        state.tags.cpu = tags.cpu
        state.tags.pc = tags.pc
        state.tags.base_ram = tags.baseRam
        state.tags.antic = tags.antic
        state.tags.gtia = tags.gtia
        state.tags.pia = tags.pia
        state.tags.pokey = tags.pokey

        state.flags.selftest_enabled = flags.selfTestEnabled ? 1 : 0
        state.flags.nframes = flags.frameCount

        // Copy state data back using pointer arithmetic
        withUnsafeMutablePointer(to: &state) { statePtr in
            let basePtr = UnsafeMutableRawPointer(statePtr)
            let stateDataPtr = basePtr.advanced(by: 256).assumingMemoryBound(to: UInt8.self)
            for (i, byte) in data.enumerated() where i < 210000 {
                stateDataPtr[i] = byte
            }
        }

        return state
    }
}

/// State component offsets.
public struct StateTags: Sendable {
    public var size: UInt32 = 0
    public var cpu: UInt32 = 0
    public var pc: UInt32 = 0
    public var baseRam: UInt32 = 0
    public var antic: UInt32 = 0
    public var gtia: UInt32 = 0
    public var pia: UInt32 = 0
    public var pokey: UInt32 = 0
}

/// State flags.
public struct StateFlags: Sendable {
    public var selfTestEnabled: Bool = false
    public var frameCount: UInt32 = 0
}

// =============================================================================
// MARK: - C String Helper
// =============================================================================

/// Extension to convert an array of Swift strings to C strings.
extension Array where Element == String {
    /// Calls a closure with an array of C string pointers.
    func withCStrings<R>(_ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
        var cStrings = [UnsafeMutablePointer<CChar>?]()
        defer {
            for ptr in cStrings {
                ptr?.deallocate()
            }
        }

        for string in self {
            let cString = strdup(string)
            cStrings.append(cString)
        }
        cStrings.append(nil)  // Null terminator for argv

        return body(cStrings)
    }
}
