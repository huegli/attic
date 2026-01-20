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
//         - Bits 0-6: Exponent value (excess-64 notation)
//         - Bit 7: Sign (0 = positive, 1 = negative)
//
// Bytes 1-5: Mantissa
//         - 10 BCD digits (2 per byte, high nibble first)
//         - Normalized: first digit is always 1-9 (except for zero)
// ```
//
// Range: Approximately ±9.99999999 × 10^62 to ±1.0 × 10^-63
// Precision: 10 decimal digits
//
// Examples:
//   0       → 00 00 00 00 00 00
//   1       → 40 10 00 00 00 00  (exp=0, mantissa=1.0)
//   10      → 41 10 00 00 00 00  (exp=1, mantissa=1.0)
//   100     → 42 10 00 00 00 00  (exp=2, mantissa=1.0)
//   3.14159 → 40 31 41 59 00 00  (exp=0, mantissa=3.14159)
//   -1      → C0 10 00 00 00 00  (exp=0, mantissa=1.0, negative)
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
    /// The conversion process:
    /// 1. Handle special case of zero
    /// 2. Determine sign and work with absolute value
    /// 3. Calculate exponent (power of 10)
    /// 4. Normalize mantissa to [1, 10)
    /// 5. Extract BCD digits
    /// 6. Pack into 6-byte format
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

        // Calculate the decimal exponent
        // We normalize mantissa to the range [1, 10) so the first digit is always 1-9
        var exponent = 0

        if mantissa >= 10.0 {
            // Value is >= 10, divide until < 10
            while mantissa >= 10.0 {
                mantissa /= 10.0
                exponent += 1
            }
        } else if mantissa < 1.0 {
            // Value is < 1, multiply until >= 1
            while mantissa < 1.0 {
                mantissa *= 10.0
                exponent -= 1
            }
        }

        // Now mantissa is in range [1.0, 10.0) and value = mantissa * 10^exponent
        // The exponent byte uses excess-64 notation

        // Clamp exponent to valid range (-64 to 63)
        exponent = max(-64, min(63, exponent))

        // Extract 10 BCD digits from mantissa
        // The mantissa is in [1, 10), so the first digit is the integer part
        var digits: [UInt8] = []
        var m = mantissa
        for i in 0..<10 {
            let digit: Int
            if i == 0 {
                // First digit: integer part of mantissa (1-9)
                digit = Int(m)
            } else {
                // Subsequent digits: fractional parts
                m = (m - Double(Int(m))) * 10.0
                digit = Int(m)
            }
            digits.append(UInt8(min(9, max(0, digit))))
        }

        // Build the 6-byte result
        var result: [UInt8] = []

        // Byte 0: Exponent with sign (excess-64 notation)
        var expByte = UInt8((exponent + 64) & 0x7F)
        if isNegative {
            expByte |= 0x80
        }
        result.append(expByte)

        // Bytes 1-5: Packed BCD mantissa (2 digits per byte, high nibble first)
        for i in stride(from: 0, to: 10, by: 2) {
            let high = digits[i]
            let low = i + 1 < digits.count ? digits[i + 1] : 0
            result.append((high << 4) | low)
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
    /// 2. Extract sign and exponent
    /// 3. Unpack BCD digits to build mantissa in [1, 10)
    /// 4. Apply exponent (power of 10) and sign
    ///
    /// - Returns: The Double value represented by this BCD float.
    public func decode() -> Double {
        // Handle zero
        if isZero {
            return 0.0
        }

        // Extract exponent (excess-64 notation)
        let exp = Int(bytes[0] & 0x7F) - 64
        let negative = isNegative

        // Unpack BCD digits to build mantissa
        // First digit is in the units place (1-9), subsequent digits are fractional
        var mantissa = 0.0
        var place = 1.0  // Start at units place

        for byteIndex in 1...5 {
            let byte = bytes[byteIndex]
            let highDigit = Int(byte >> 4)
            let lowDigit = Int(byte & 0x0F)

            mantissa += Double(highDigit) * place
            place /= 10.0
            mantissa += Double(lowDigit) * place
            place /= 10.0
        }

        // Apply exponent (powers of 10)
        // Value = mantissa * 10^exp where mantissa is in [1, 10)
        var result = mantissa * pow(10.0, Double(exp))

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
    /// - Parameter value: The numeric value to encode.
    /// - Returns: The most efficient encoding.
    public static func forValue(_ value: Double) -> BASICNumericEncoding {
        // Check if it's a small non-negative integer
        if value >= 0 && value <= 255 && value == value.rounded() {
            return .smallInt(UInt8(value))
        }

        // Use full BCD encoding
        return .bcdFloat(BCDFloat.encode(value))
    }

    /// Creates the appropriate encoding from a parsed literal.
    ///
    /// - Parameter literal: The source code string.
    /// - Returns: The encoding, or nil if parsing fails.
    public static func parse(_ literal: String) -> BASICNumericEncoding? {
        guard let bcd = BCDFloat.parse(literal) else { return nil }

        // Check if it can use small int encoding
        if let smallInt = bcd.asSmallInt() {
            return .smallInt(smallInt)
        }

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
