// =============================================================================
// CIOInterceptor.swift - Capture E: Device Output via Page 6 Stub
// =============================================================================
//
// This file intercepts Atari CIO (Central I/O) output to the E: (screen
// editor) device by patching IOCB #0's PUT vector to point to a small 6502
// stub in page 6 ($0600). The stub captures each character into a ring buffer
// before forwarding to the original handler.
//
// How It Works:
// -------------
// 1. The Atari's CIO subsystem routes PRINT output through IOCB #0
//    (the screen editor). The PUT handler address is stored at $0346-$0347.
//
// 2. We save the original handler address, write a 31-byte 6502 stub at
//    $0600, and redirect $0346-$0347 to our stub.
//
// 3. Each character passes through our stub, which stores it in a ring
//    buffer at $0630-$06FF (208 bytes), then jumps to the original handler.
//
// 4. The server calls drain() each frame to read new characters from the
//    ring buffer and convert them from ATASCII to UTF-8.
//
// Why Page 6?
// -----------
// Page 6 ($0600-$06FF) is conventionally reserved for user machine language
// on the Atari. BASIC programs typically don't use it, making it safe for
// our interceptor. However, some programs may conflict — the interceptor
// should be installed on demand, not permanently.
//
// ATASCII:
// --------
// The Atari uses ATASCII encoding (not ASCII). Most printable characters
// ($20-$7E) match ASCII, but control codes and special characters differ.
// The key difference is $9B for end-of-line (EOL) instead of $0A (LF).
//
// =============================================================================

import Foundation

/// Intercepts CIO E: device output by patching IOCB #0's PUT vector
/// to route through a 6502 stub that captures characters into a ring buffer.
///
/// This is an actor because the interceptor state (read index, installed flag)
/// is accessed from multiple contexts: the frame loop calls drain(), while
/// CLI commands call install()/uninstall(). The actor model serializes these
/// accesses without explicit locking.
///
/// Usage:
///
///     let interceptor = CIOInterceptor(emulator: engine)
///     try await interceptor.install()
///     // ... run frames ...
///     let text = await interceptor.drain()
///     try await interceptor.uninstall()
///
public actor CIOInterceptor {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The emulator engine to read/write memory on.
    private let emulator: EmulatorEngine

    /// Whether the interceptor stub is currently installed.
    private(set) public var isInstalled: Bool = false

    /// Consumer's read position in the ring buffer.
    /// Advances as drain() reads characters, wrapping at bufferSize.
    private var readIndex: UInt8 = 0

    // =========================================================================
    // MARK: - Memory Layout Constants
    // =========================================================================

    /// Base address of the 6502 interceptor stub in page 6.
    private static let stubBase: UInt16 = 0x0600

    /// Address of the write index byte (updated by the 6502 stub).
    private static let writeIndex: UInt16 = 0x0620

    /// Address where the original PUT handler address is stored (for JMP indirect).
    private static let originalPut: UInt16 = 0x0622

    /// Temp storage for A register (used by stub to preserve registers).
    private static let tempA: UInt16 = 0x0624

    /// Temp storage for X register (used by stub to preserve registers).
    private static let tempX: UInt16 = 0x0625

    /// Base address of the ring buffer (characters stored here by the stub).
    private static let bufferBase: UInt16 = 0x0630

    /// Size of the ring buffer in bytes (208 = $D0).
    /// This fits ~3.5 lines of 60-character text, which is enough at 60fps.
    private static let bufferSize: UInt8 = 0xD0

    // =========================================================================
    // MARK: - IOCB #0 Addresses
    // =========================================================================

    /// IOCB #0 PUT handler low byte ($0346).
    /// CIO calls through this address when writing a character to the E: device.
    private static let icptl: UInt16 = 0x0346

    /// IOCB #0 PUT handler high byte ($0347).
    private static let icpth: UInt16 = 0x0347

    // =========================================================================
    // MARK: - 6502 Stub Machine Code
    // =========================================================================

    /// The 31-byte 6502 interceptor stub.
    ///
    /// This code runs on the emulated 6502 CPU every time BASIC PRINTs a
    /// character. It stores the character in the ring buffer, then jumps
    /// to the original E: handler so the character still appears on screen.
    ///
    /// Assembly listing:
    /// ```
    /// $0600: STA $0624       ; Save A to temp
    /// $0603: STX $0625       ; Save X to temp
    /// $0606: LDX $0620       ; Load write index
    /// $0609: STA $0630,X     ; Store char in buffer
    /// $060C: INX             ; Advance write index
    /// $060D: CPX #$D0        ; Past 208 bytes?
    /// $060F: BCC $0613       ; No -> skip wrap
    /// $0611: LDX #$00        ; Wrap to 0
    /// $0613: STX $0620       ; Save write index
    /// $0616: LDX $0625       ; Restore X
    /// $0619: LDA $0624       ; Restore A
    /// $061C: JMP ($0622)     ; Jump to original handler
    /// ```
    private static let stubCode: [UInt8] = [
        0x8D, 0x24, 0x06,  // STA $0624
        0x8E, 0x25, 0x06,  // STX $0625
        0xAE, 0x20, 0x06,  // LDX $0620
        0x9D, 0x30, 0x06,  // STA $0630,X
        0xE8,              // INX
        0xE0, 0xD0,        // CPX #$D0
        0x90, 0x02,        // BCC +2
        0xA2, 0x00,        // LDX #$00
        0x8E, 0x20, 0x06,  // STX $0620
        0xAE, 0x25, 0x06,  // LDX $0625
        0xAD, 0x24, 0x06,  // LDA $0624
        0x6C, 0x22, 0x06,  // JMP ($0622)
    ]

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new CIO interceptor for the given emulator engine.
    ///
    /// - Parameter emulator: The emulator engine to intercept output from.
    public init(emulator: EmulatorEngine) {
        self.emulator = emulator
    }

    // =========================================================================
    // MARK: - Install / Uninstall
    // =========================================================================

    /// Installs the interceptor by patching IOCB #0's PUT vector.
    ///
    /// This writes the 6502 stub to page 6, saves the original handler address,
    /// and redirects CIO to route through our stub. The emulator must be paused
    /// or the caller must ensure no frames are executing concurrently.
    ///
    /// - Throws: CIOInterceptorError if already installed.
    public func install() async throws {
        guard !isInstalled else {
            throw CIOInterceptorError.alreadyInstalled
        }

        // 1. Read the original PUT handler address from IOCB #0.
        //    This is stored as a little-endian 16-bit address at $0346-$0347.
        let origLow = await emulator.readMemory(at: Self.icptl)
        let origHigh = await emulator.readMemory(at: Self.icpth)

        // 2. Write the 31-byte stub at $0600.
        await emulator.writeMemoryBlock(at: Self.stubBase, bytes: Self.stubCode)

        // 3. Store the original PUT address at $0622-$0623 for JMP ($0622).
        await emulator.writeMemory(at: Self.originalPut, value: origLow)
        await emulator.writeMemory(at: Self.originalPut + 1, value: origHigh)

        // 4. Zero the write index at $0620.
        await emulator.writeMemory(at: Self.writeIndex, value: 0)

        // 5. Redirect IOCB #0 PUT vector to our stub at $0600.
        await emulator.writeMemory(at: Self.icptl, value: 0x00)  // Low byte of $0600
        await emulator.writeMemory(at: Self.icpth, value: 0x06)  // High byte of $0600

        // 6. Reset our consumer read index.
        readIndex = 0
        isInstalled = true
    }

    /// Uninstalls the interceptor by restoring the original PUT vector.
    ///
    /// - Throws: CIOInterceptorError if not currently installed.
    public func uninstall() async throws {
        guard isInstalled else {
            throw CIOInterceptorError.notInstalled
        }

        // Read the original PUT address we saved at $0622-$0623.
        let origLow = await emulator.readMemory(at: Self.originalPut)
        let origHigh = await emulator.readMemory(at: Self.originalPut + 1)

        // Restore IOCB #0 PUT vector to the original handler.
        await emulator.writeMemory(at: Self.icptl, value: origLow)
        await emulator.writeMemory(at: Self.icpth, value: origHigh)

        isInstalled = false
    }

    // =========================================================================
    // MARK: - Drain (Read Captured Output)
    // =========================================================================

    /// Reads new characters from the ring buffer and returns them as a string.
    ///
    /// Call this each frame (or periodically) to consume captured output.
    /// Returns an empty string if no new characters are available.
    ///
    /// The ring buffer at $0630-$06FF is written by the 6502 stub (producer)
    /// and read by this method (consumer). The write index at $0620 is updated
    /// by the stub; our readIndex tracks how far we've consumed.
    ///
    /// - Returns: New text output converted from ATASCII to UTF-8.
    public func drain() async -> String {
        guard isInstalled else { return "" }

        // Read the current write index from the emulator.
        let writeIdx = await emulator.readMemory(at: Self.writeIndex)

        // If read == write, nothing new to consume.
        guard writeIdx != readIndex else { return "" }

        // Collect new bytes from the ring buffer, handling wrap-around.
        var bytes: [UInt8] = []
        var idx = readIndex

        while idx != writeIdx {
            let address = Self.bufferBase + UInt16(idx)
            let byte = await emulator.readMemory(at: address)
            bytes.append(byte)
            idx = idx &+ 1
            if idx >= Self.bufferSize {
                idx = 0
            }
        }

        // Advance our read position to match the write position.
        readIndex = writeIdx

        // Convert ATASCII bytes to a Swift string.
        return Self.atasciiToString(bytes)
    }

    // =========================================================================
    // MARK: - ATASCII Conversion
    // =========================================================================

    /// Converts an array of ATASCII bytes to a UTF-8 string.
    ///
    /// ATASCII is the Atari's native character encoding. Key differences
    /// from ASCII:
    /// - $9B is end-of-line (EOL), equivalent to newline
    /// - $7D is clear screen
    /// - $7E is backspace
    /// - $7F is tab
    /// - $80-$FF are inverse video versions of $00-$7F
    /// - $00-$1F are control characters (cursor movement, etc.)
    ///
    /// For text capture, we convert printable characters and EOL, and skip
    /// most control codes since they're cursor movement commands that don't
    /// represent meaningful text output.
    ///
    /// - Parameter bytes: ATASCII-encoded bytes.
    /// - Returns: UTF-8 string representation.
    public static func atasciiToString(_ bytes: [UInt8]) -> String {
        var result = ""
        result.reserveCapacity(bytes.count)

        for byte in bytes {
            // Strip inverse video bit (bit 7) to get the base character.
            let base = byte & 0x7F

            switch base {
            case 0x20...0x7C:
                // Standard printable ASCII range ($20-$7C maps 1:1).
                result.append(Character(UnicodeScalar(base)))

            case 0x9B & 0x7F:
                // This handles $1B (ESC) — skip it.
                // $9B (EOL) is handled below before stripping bit 7.
                break

            default:
                break
            }

            // Handle $9B (EOL) specially — it has bit 7 set, so check
            // the original byte value before the inverse strip.
            if byte == 0x9B {
                result.append("\n")
            }
        }

        return result
    }
}

// =============================================================================
// MARK: - Error Types
// =============================================================================

/// Errors that can occur during CIO interceptor operations.
public enum CIOInterceptorError: Error, LocalizedError {
    /// The interceptor is already installed.
    case alreadyInstalled

    /// The interceptor is not currently installed.
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .alreadyInstalled:
            return "CIO interceptor is already installed"
        case .notInstalled:
            return "CIO interceptor is not installed"
        }
    }
}
