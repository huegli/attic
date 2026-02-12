// =============================================================================
// BCDFloat.swift - Atari BASIC BCD Floating-Point Conversion
// =============================================================================
//
// This file implements conversion between Swift Double values and Atari BASIC's
// 6-byte Binary Coded Decimal (BCD) floating-point format.
//
// BCD Format (6 bytes):
// ```
// Byte 0: Exponent
//         - Bits 0-6: Exponent value (excess-64 notation, powers of 100)
//         - Bit 7: Sign (0 = positive, 1 = negative)
//
// Bytes 1-5: Mantissa
//         - 5 BCD digit pairs (2 digits per byte, high nibble first)
//         - Each byte represents a value 00-99
//         - Byte 1 is the integer part (01-99 for normalized numbers)
//         - Bytes 2-5 are successive 1/100 fractional parts
//         - Value = mantissa × 100^exponent
// ```
//
// Range: Approximately ±9.99999999 × 10^97 to ±1.0 × 10^-98
// Precision: 10 decimal digits
//
// Examples:
//   0       → 00 00 00 00 00 00
//   1       → 40 01 00 00 00 00  (exp=0, mantissa=1, 1×100^0)
//   10      → 40 10 00 00 00 00  (exp=0, mantissa=10, 10×100^0)
//   37      → 40 37 00 00 00 00  (exp=0, mantissa=37, 37×100^0)
//   100     → 41 01 00 00 00 00  (exp=1, mantissa=1, 1×100^1)
//   3.14159 → 40 03 14 15 90 00  (exp=0, mantissa=3.141590)
//   0.02    → 3F 02 00 00 00 00  (exp=-1, mantissa=2, 2×100^-1)
//   -1      → C0 01 00 00 00 00  (exp=0, mantissa=1, negative)
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - BCD Float Structure
// =============================================================================

/// Represents an Atari BASIC 6-byte BCD floating-point number.
///
/// This struct provides conversion between Swift `Double` values and the
/// BCD format used internally by Atari BASIC.
public struct BCDFloat: Sendable, Equatable {
    /// The 6 raw bytes of the BCD representation.
    public let bytes: [UInt8]

    /// Creates a BCDFloat from raw bytes.
    ///
    /// - Parameter bytes: Exactly 6 bytes of BCD data.
    /// - Precondition: bytes.count == 6
    public init(bytes: [UInt8]) {
        precondition(bytes.count == 6, "BCD float must be exactly 6 bytes")
        self.bytes = bytes
    }

    // =========================================================================
    // MARK: - Zero Constant
    // =========================================================================

    /// The BCD representation of zero.
    public static let zero = BCDFloat(bytes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Whether this value is zero.
    public var isZero: Bool {
        bytes[0] == 0x00 && bytes[1] == 0x00
    }

    /// Whether this value is negative.
    public var isNegative: Bool {
        (bytes[0] & 0x80) != 0
    }

    /// The exponent value (excess-64 notation, without sign bit).
    public var exponent: Int {
        Int(bytes[0] & 0x7F) - 64
    }

    // =========================================================================
    // MARK: - Encoding from Double
    // =========================================================================

    /// Creates a BCD float from a Swift Double.
    ///
    /// Atari BASIC uses a power-of-100 BCD format where each mantissa byte
    /// holds a two-digit BCD pair (00-99). The exponent represents powers
    /// of 100 in excess-64 notation.
    ///
    /// The conversion process:
    /// 1. Handle special case of zero
    /// 2. Determine sign and work with absolute value
    /// 3. Normalize mantissa to [1, 100)
    /// 4. Calculate exponent as power of 100
    /// 5. Extract BCD digit pairs (2 digits per byte)
    /// 6. Pack into 6-byte format
    ///
    /// Examples:
    ///   1       → [40, 01, 00, 00, 00, 00]  (1 × 100^0)
    ///   10      → [40, 10, 00, 00, 00, 00]  (10 × 100^0)
    ///   37      → [40, 37, 00, 00, 00, 00]  (37 × 100^0)
    ///   100     → [41, 01, 00, 00, 00, 00]  (1 × 100^1)
    ///   3.14159 → [40, 03, 14, 15, 90, 00]  (3.14159 × 100^0)
    ///   0.02    → [3F, 02, 00, 00, 00, 00]  (2 × 100^-1)
    ///   -1      → [C0, 01, 00, 00, 00, 00]  (1 × 100^0, negative)
    ///
    /// - Parameter value: The Double value to convert.
    /// - Returns: A BCDFloat representing the value.
    public static func encode(_ value: Double) -> BCDFloat {
        // Handle zero specially
        if value == 0 || value.isNaN {
            return .zero
        }

        // Handle infinity as max value
        if value.isInfinite {
            let sign: UInt8 = value < 0 ? 0x80 : 0x00
            return BCDFloat(bytes: [0x7F | sign, 0x99, 0x99, 0x99, 0x99, 0x99])
        }

        let isNegative = value < 0
        var mantissa = abs(value)

        // Normalize mantissa to [1, 100) using powers of 100.
        // Each exponent unit represents one factor of 100.
        // For example: 460312 → mantissa=46.0312, exponent=2 (46.0312 × 100^2)
        var exponent = 0

        if mantissa >= 100.0 {
            while mantissa >= 100.0 {
                mantissa /= 100.0
                exponent += 1
            }
        } else if mantissa < 1.0 {
            while mantissa < 1.0 {
                mantissa *= 100.0
                exponent -= 1
            }
        }

        // Now mantissa is in [1.0, 100.0) and value = mantissa × 100^exponent

        // Clamp exponent to valid range (-64 to 63)
        exponent = max(-64, min(63, exponent))

        // Build the 6-byte result
        var result: [UInt8] = []

        // Byte 0: Exponent with sign (excess-64 notation)
        var expByte = UInt8((exponent + 64) & 0x7F)
        if isNegative {
            expByte |= 0x80
        }
        result.append(expByte)

        // Bytes 1-5: BCD digit pairs. Each byte holds a two-digit value (00-99).
        // Byte 1 is the integer part of the mantissa (01-99 for normalized).
        // Bytes 2-5 are successive fractional pairs (each ×1/100 of previous).
        var m = mantissa
        for _ in 0..<5 {
            let pair = min(99, max(0, Int(m)))
            let highDigit = pair / 10
            let lowDigit = pair % 10
            result.append(UInt8((highDigit << 4) | lowDigit))
            m = (m - Double(pair)) * 100.0
        }

        return BCDFloat(bytes: result)
    }

    /// Creates a BCD float from a small integer (0-255).
    ///
    /// This is optimized for the common case of small integer constants.
    /// In tokenized BASIC, these can use the $0D prefix instead of full BCD.
    ///
    /// - Parameter value: An integer in the range 0-255.
    /// - Returns: A BCDFloat representing the value.
    public static func encodeSmallInt(_ value: UInt8) -> BCDFloat {
        if value == 0 {
            return .zero
        }

        // For small integers, use the standard encoding
        return encode(Double(value))
    }

    // =========================================================================
    // MARK: - Decoding to Double
    // =========================================================================

    /// Converts this BCD float to a Swift Double.
    ///
    /// The conversion process:
    /// 1. Handle zero case
    /// 2. Extract sign and exponent (excess-64, powers of 100)
    /// 3. Unpack BCD digit pairs to build mantissa
    /// 4. Apply exponent and sign
    ///
    /// Each mantissa byte holds a two-digit BCD pair (00-99):
    /// - Byte 1: integer part of mantissa (01-99 for normalized)
    /// - Bytes 2-5: fractional pairs, each worth 1/100 of previous
    ///
    /// Value = mantissa × 100^exponent
    ///
    /// - Returns: The Double value represented by this BCD float.
    public func decode() -> Double {
        // Handle zero
        if isZero {
            return 0.0
        }

        // Extract exponent (excess-64 notation, powers of 100)
        let exp = Int(bytes[0] & 0x7F) - 64
        let negative = isNegative

        // Unpack BCD digit pairs to build mantissa.
        // Byte 1 is the integer part, bytes 2-5 are fractional pairs.
        // mantissa = byte1 + byte2/100 + byte3/10000 + byte4/1000000 + byte5/100000000
        var mantissa = 0.0
        var place = 1.0  // Byte 1 contributes at the ones place

        for byteIndex in 1...5 {
            let byte = bytes[byteIndex]
            let highDigit = Int(byte >> 4)
            let lowDigit = Int(byte & 0x0F)
            let byteValue = Double(highDigit * 10 + lowDigit)

            mantissa += byteValue * place
            place /= 100.0  // Each byte pair covers 2 decimal places
        }

        // Apply exponent (powers of 100)
        // Value = mantissa × 100^exp where mantissa is in [1, 100)
        var result = mantissa * pow(100.0, Double(exp))

        // Apply sign
        if negative {
            result = -result
        }

        return result
    }

    // =========================================================================
    // MARK: - Integer Detection
    // =========================================================================

    /// Checks if this BCD value represents an integer in the range 0-255.
    ///
    /// This is useful for determining if the compact $0D encoding can be used
    /// instead of the full 6-byte BCD encoding.
    ///
    /// - Returns: The integer value if representable as 0-255, nil otherwise.
    public func asSmallInt() -> UInt8? {
        let value = decode()

        // Check if it's a non-negative integer in range
        guard value >= 0 && value <= 255 else { return nil }

        // Use a small tolerance for floating-point comparison
        // to handle precision issues from BCD conversion
        let rounded = value.rounded()
        guard abs(value - rounded) < 0.0001 else { return nil }

        return UInt8(rounded)
    }

    // =========================================================================
    // MARK: - String Representation
    // =========================================================================

    /// A human-readable representation of the BCD bytes.
    public var hexString: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// The value as a decimal string.
    public var decimalString: String {
        let value = decode()
        if value == value.rounded() && abs(value) < 1e10 {
            return String(format: "%.0f", value)
        } else {
            return String(value)
        }
    }
}

// =============================================================================
// MARK: - Numeric Literal Parsing
// =============================================================================

/// Extension for parsing numeric literals from BASIC source code.
extension BCDFloat {
    /// Parses a numeric literal from BASIC source code.
    ///
    /// Supports various formats:
    /// - Integer: 123, 0, 65535
    /// - Decimal: 3.14159
    /// - Scientific: 1E10, 2.5E-3
    /// - Hexadecimal: $FF, $1A2B (Atari convention)
    ///
    /// - Parameter literal: The source code string.
    /// - Returns: A BCDFloat, or nil if parsing fails.
    public static func parse(_ literal: String) -> BCDFloat? {
        var str = literal.trimmingCharacters(in: .whitespaces)

        // Handle hexadecimal ($XX)
        if str.hasPrefix("$") {
            str.removeFirst()
            guard let value = UInt64(str, radix: 16) else { return nil }
            return encode(Double(value))
        }

        // Handle standard decimal/scientific notation
        guard let value = Double(str) else { return nil }
        return encode(value)
    }

    /// Checks if a character can be part of a numeric literal.
    ///
    /// - Parameter char: The character to check.
    /// - Returns: True if the character can appear in a numeric literal.
    public static func isNumericChar(_ char: Character) -> Bool {
        char.isNumber || char == "." || char == "-" || char == "+" ||
        char == "E" || char == "e" || char == "$"
    }
}

// =============================================================================
// MARK: - Small Integer Optimization
// =============================================================================

/// Helper for encoding numeric constants in tokenized BASIC.
///
/// Atari BASIC uses two encodings for numeric constants:
/// - $0D + 1 byte: Small integers 0-255
/// - $0E + 6 bytes: Full BCD floating-point
///
/// This enum helps choose the appropriate encoding.
public enum BASICNumericEncoding {
    /// Small integer encoding ($0D + value).
    case smallInt(UInt8)

    /// Full BCD encoding ($0E + 6 bytes).
    case bcdFloat(BCDFloat)

    /// Creates the appropriate encoding for a value.
    ///
    /// Real Atari BASIC always uses $0E + 6-byte BCD for all numeric constants.
    /// There is no small integer prefix ($0D) in standard Atari BASIC.
    ///
    /// - Parameter value: The numeric value to encode.
    /// - Returns: The BCD encoding for this value.
    public static func forValue(_ value: Double) -> BASICNumericEncoding {
        return .bcdFloat(BCDFloat.encode(value))
    }

    /// Creates the appropriate encoding from a parsed literal.
    ///
    /// Always produces BCD encoding to match real Atari BASIC format.
    ///
    /// - Parameter literal: The source code string.
    /// - Returns: The encoding, or nil if parsing fails.
    public static func parse(_ literal: String) -> BASICNumericEncoding? {
        guard let bcd = BCDFloat.parse(literal) else { return nil }
        return .bcdFloat(bcd)
    }

    /// The tokenized bytes for this encoding.
    public var tokenBytes: [UInt8] {
        switch self {
        case .smallInt(let value):
            return [BASICSpecialToken.smallIntPrefix, value]
        case .bcdFloat(let bcd):
            return [BASICSpecialToken.bcdFloatPrefix] + bcd.bytes
        }
    }

    /// The number of bytes this encoding uses.
    public var byteCount: Int {
        switch self {
        case .smallInt:
            return 2  // $0D + value
        case .bcdFloat:
            return 7  // $0E + 6 bytes
        }
    }
}
