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
// - Read/write memory
// - Get/set CPU registers
// - Handle ROM loading
// - Manage frame buffer and audio buffer access
//
// NOTE: This is a stub implementation. The actual C function calls will be
// added once libatari800 is integrated. The interface is designed based on
// typical emulator library APIs.
//
// =============================================================================

import Foundation
// Import the C library module when available
// import CAtari800

/// Low-level wrapper around the libatari800 C library.
///
/// This class provides a Swift-friendly interface to the C emulation core.
/// It is NOT thread-safe - use EmulatorEngine for thread-safe access.
///
/// Usage:
///
///     let wrapper = LibAtari800Wrapper()
///     try wrapper.initialize(romPath: romURL)
///     wrapper.reset(cold: true)
///     wrapper.executeFrame()
///
public final class LibAtari800Wrapper: @unchecked Sendable {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Whether the emulator has been initialized.
    private(set) public var isInitialized: Bool = false

    /// The path to the ROM directory.
    private var romPath: URL?

    /// Frame buffer for video output (384x240 pixels, BGRA format).
    /// Each pixel is 4 bytes: Blue, Green, Red, Alpha.
    private var frameBuffer: [UInt8]

    /// Audio sample buffer (mono, 44100 Hz).
    private var audioBuffer: [Float]

    /// Size of the frame buffer in bytes.
    public static let frameBufferSize = 384 * 240 * 4

    /// Width of the frame in pixels.
    public static let frameWidth = 384

    /// Height of the frame in pixels.
    public static let frameHeight = 240

    /// Audio sample rate in Hz.
    public static let audioSampleRate = 44100

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new LibAtari800Wrapper instance.
    ///
    /// The wrapper is created in an uninitialized state. Call `initialize(romPath:)`
    /// before using any emulation functions.
    public init() {
        // Allocate frame buffer (384 x 240 x 4 bytes per pixel)
        self.frameBuffer = [UInt8](repeating: 0, count: Self.frameBufferSize)

        // Allocate audio buffer (enough for one frame at 60fps)
        // 44100 / 60 ≈ 735 samples per frame
        self.audioBuffer = [Float](repeating: 0, count: 1024)
    }

    /// Initializes the emulator with ROMs from the specified path.
    ///
    /// This must be called before any other emulation functions.
    /// The ROM directory should contain:
    /// - ATARIXL.ROM (16KB OS ROM)
    /// - ATARIBAS.ROM (8KB BASIC ROM)
    ///
    /// - Parameter romPath: URL to the directory containing ROM files.
    /// - Throws: AtticError if ROMs cannot be loaded.
    public func initialize(romPath: URL) throws {
        self.romPath = romPath

        // Verify ROMs exist
        let osRomPath = romPath.appendingPathComponent("ATARIXL.ROM")
        let basicRomPath = romPath.appendingPathComponent("ATARIBAS.ROM")

        guard FileManager.default.fileExists(atPath: osRomPath.path) else {
            throw AtticError.romNotFound(osRomPath.path)
        }

        guard FileManager.default.fileExists(atPath: basicRomPath.path) else {
            throw AtticError.romNotFound(basicRomPath.path)
        }

        // TODO: Call libatari800 initialization functions
        // libatari800_init()
        // libatari800_load_rom(osRomPath.path)
        // etc.

        isInitialized = true
    }

    // =========================================================================
    // MARK: - Emulation Control
    // =========================================================================

    /// Resets the emulator.
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    ///                   If false, performs a warm reset (like pressing RESET key).
    public func reset(cold: Bool) {
        guard isInitialized else { return }

        // TODO: Call libatari800 reset function
        // if cold {
        //     libatari800_cold_reset()
        // } else {
        //     libatari800_warm_reset()
        // }
    }

    /// Executes one frame of emulation (~1/60 second).
    ///
    /// This runs the 6502 CPU for approximately 29780 cycles (NTSC),
    /// updates the frame buffer, and generates audio samples.
    public func executeFrame() {
        guard isInitialized else { return }

        // TODO: Call libatari800 frame execution
        // libatari800_frame()
    }

    /// Executes a single CPU instruction.
    ///
    /// - Returns: The number of cycles consumed by the instruction.
    @discardableResult
    public func step() -> Int {
        guard isInitialized else { return 0 }

        // TODO: Call libatari800 single step function
        // return Int(libatari800_step())
        return 2  // Stub: return typical instruction cycle count
    }

    // =========================================================================
    // MARK: - Memory Access
    // =========================================================================

    /// Reads a byte from the specified memory address.
    ///
    /// - Parameter address: The 16-bit address to read from.
    /// - Returns: The byte value at that address.
    public func readMemory(at address: UInt16) -> UInt8 {
        guard isInitialized else { return 0 }

        // TODO: Call libatari800 memory read
        // return libatari800_read_memory(address)
        return 0  // Stub
    }

    /// Writes a byte to the specified memory address.
    ///
    /// - Parameters:
    ///   - address: The 16-bit address to write to.
    ///   - value: The byte value to write.
    public func writeMemory(at address: UInt16, value: UInt8) {
        guard isInitialized else { return }

        // TODO: Call libatari800 memory write
        // libatari800_write_memory(address, value)
    }

    /// Reads a block of memory.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - count: Number of bytes to read.
    /// - Returns: Array of bytes.
    public func readMemoryBlock(at address: UInt16, count: Int) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(count)

        for i in 0..<count {
            let addr = address &+ UInt16(i)
            result.append(readMemory(at: addr))
        }

        return result
    }

    /// Writes a block of memory.
    ///
    /// - Parameters:
    ///   - address: Starting address.
    ///   - bytes: Bytes to write.
    public func writeMemoryBlock(at address: UInt16, bytes: [UInt8]) {
        for (i, byte) in bytes.enumerated() {
            let addr = address &+ UInt16(i)
            writeMemory(at: addr, value: byte)
        }
    }

    // =========================================================================
    // MARK: - CPU Registers
    // =========================================================================

    /// Gets the current CPU register state.
    ///
    /// - Returns: A CPURegisters struct with all register values.
    public func getRegisters() -> CPURegisters {
        guard isInitialized else { return CPURegisters() }

        // TODO: Read registers from libatari800
        // var regs = CPURegisters()
        // regs.a = libatari800_get_a()
        // regs.x = libatari800_get_x()
        // etc.
        // return regs

        return CPURegisters()  // Stub
    }

    /// Sets CPU register values.
    ///
    /// - Parameter registers: The register values to set.
    public func setRegisters(_ registers: CPURegisters) {
        guard isInitialized else { return }

        // TODO: Write registers to libatari800
        // libatari800_set_a(registers.a)
        // libatari800_set_x(registers.x)
        // etc.
    }

    // =========================================================================
    // MARK: - Frame Buffer Access
    // =========================================================================

    /// Returns a copy of the current frame buffer.
    ///
    /// The buffer is in BGRA format, 384x240 pixels.
    /// Each pixel is 4 consecutive bytes: Blue, Green, Red, Alpha.
    ///
    /// - Returns: Copy of the frame buffer data.
    public func getFrameBuffer() -> [UInt8] {
        // TODO: Copy frame buffer from libatari800
        // libatari800_get_frame_buffer(&frameBuffer)
        return frameBuffer
    }

    /// Provides direct access to the frame buffer for Metal texture upload.
    ///
    /// - Parameter body: Closure that receives a pointer to the frame buffer.
    /// - Returns: The value returned by the closure.
    public func withFrameBuffer<T>(_ body: (UnsafeBufferPointer<UInt8>) -> T) -> T {
        frameBuffer.withUnsafeBufferPointer(body)
    }

    // =========================================================================
    // MARK: - Audio Access
    // =========================================================================

    /// Returns audio samples generated during the last frame.
    ///
    /// - Returns: Array of audio samples (mono, Float, -1.0 to 1.0 range).
    public func getAudioSamples() -> [Float] {
        // TODO: Get audio samples from libatari800
        // var sampleCount = 0
        // libatari800_get_audio(&audioBuffer, &sampleCount)
        // return Array(audioBuffer.prefix(sampleCount))
        return audioBuffer  // Stub
    }

    // =========================================================================
    // MARK: - State Save/Load
    // =========================================================================

    /// Saves the current emulator state to a Data object.
    ///
    /// - Returns: Serialized state data.
    /// - Throws: AtticError if state cannot be saved.
    public func saveState() throws -> Data {
        guard isInitialized else {
            throw AtticError.notInitialized
        }

        // TODO: Get state from libatari800
        // var stateSize = 0
        // libatari800_get_state_size(&stateSize)
        // var stateData = Data(count: stateSize)
        // stateData.withUnsafeMutableBytes { ptr in
        //     libatari800_save_state(ptr.baseAddress)
        // }
        // return stateData

        return Data()  // Stub
    }

    /// Loads emulator state from a Data object.
    ///
    /// - Parameter data: Previously saved state data.
    /// - Throws: AtticError if state cannot be loaded.
    public func loadState(_ data: Data) throws {
        guard isInitialized else {
            throw AtticError.notInitialized
        }

        // TODO: Load state into libatari800
        // data.withUnsafeBytes { ptr in
        //     libatari800_load_state(ptr.baseAddress, data.count)
        // }
    }

    // =========================================================================
    // MARK: - Cleanup
    // =========================================================================

    deinit {
        // TODO: Call libatari800 cleanup
        // if isInitialized {
        //     libatari800_shutdown()
        // }
    }
}
