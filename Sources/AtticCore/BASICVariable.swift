// =============================================================================
// BASICVariable.swift - Atari BASIC Variable Handling
// =============================================================================
//
// This file defines types for working with Atari BASIC's variable system.
// Atari BASIC maintains two tables in memory:
//
// 1. Variable Name Table (VNT) - Stores variable names with type indicators
// 2. Variable Value Table (VVT) - Stores 8-byte values for each variable
//
// Variable Types:
// - Numeric: Standard floating-point variable (e.g., X, COUNT)
// - String: String variable (e.g., A$, NAME$)
// - NumericArray: Array of numbers (e.g., A(10), GRID(5,5))
// - StringArray: Array of strings (e.g., A$(10))
//
// The VNT stores variable names with the last character having bit 7 set,
// followed by a type indicator byte. The VVT stores 8 bytes per variable
// regardless of type.
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Variable Type
// =============================================================================

/// The type of an Atari BASIC variable.
///
/// Atari BASIC determines variable type by suffix characters:
/// - No suffix: Numeric (floating-point)
/// - $ suffix: String
/// - ( suffix: Numeric array
/// - $( suffix: String array
public enum BASICVariableType: Sendable, Equatable {
    /// A numeric (floating-point) variable.
    /// Examples: X, COUNT, TOTAL
    case numeric

    /// A string variable.
    /// Examples: A$, NAME$, TITLE$
    case string

    /// A numeric array variable.
    /// Examples: A(10), GRID(5,5), DATA(100)
    case numericArray

    /// A string array variable.
    /// Examples: A$(10), NAMES$(50)
    case stringArray

    /// The suffix characters that indicate this type in source code.
    public var suffix: String {
        switch self {
        case .numeric: return ""
        case .string: return "$"
        case .numericArray: return "("
        case .stringArray: return "$("
        }
    }

    /// The type indicator byte stored in the VNT after the variable name.
    ///
    /// This byte follows the variable name (with its last character OR'd with $80)
    /// to indicate the variable type.
    public var vntIndicator: UInt8 {
        switch self {
        case .numeric: return 0x00      // No indicator for numeric
        case .string: return 0x80       // $ with high bit set
        case .numericArray: return 0x40 // ( indicator
        case .stringArray: return 0xC0  // Combined $( indicator
        }
    }

    /// Creates a variable type from VNT indicator byte.
    ///
    /// - Parameter indicator: The type indicator byte from VNT.
    /// - Returns: The corresponding variable type.
    public static func fromVNTIndicator(_ indicator: UInt8) -> BASICVariableType {
        switch indicator & 0xC0 {
        case 0x00: return .numeric
        case 0x80: return .string
        case 0x40: return .numericArray
        case 0xC0: return .stringArray
        default: return .numeric
        }
    }
}

// =============================================================================
// MARK: - Variable Name
// =============================================================================

/// Represents a parsed BASIC variable name with its type.
///
/// Variable names in Atari BASIC:
/// - Start with a letter (A-Z)
/// - Can contain letters and digits
/// - Maximum 128 characters (though practical limit is much lower)
/// - Case is preserved but comparison is case-insensitive
public struct BASICVariableName: Sendable, Equatable, Hashable {
    /// The variable name without type suffix (e.g., "X", "COUNT", "NAME").
    public let name: String

    /// The type of this variable.
    public let type: BASICVariableType

    /// Creates a variable name from a parsed identifier.
    ///
    /// - Parameters:
    ///   - name: The base name (without type suffixes).
    ///   - type: The variable type.
    public init(name: String, type: BASICVariableType) {
        self.name = name.uppercased()
        self.type = type
    }

    /// Parses a variable name from source code.
    ///
    /// Extracts the base name and determines type from suffixes:
    /// - `X` → numeric variable X
    /// - `X$` → string variable X$
    /// - `X(` → numeric array X (the `(` is a type indicator, not part of subscript)
    /// - `X$(` → string array X$
    ///
    /// - Parameter source: The variable reference from source code.
    /// - Returns: A parsed variable name, or nil if invalid.
    public static func parse(_ source: String) -> BASICVariableName? {
        var name = source.uppercased()

        // Determine type from suffixes
        let type: BASICVariableType
        if name.hasSuffix("$(") {
            type = .stringArray
            name = String(name.dropLast(2))
        } else if name.hasSuffix("$") {
            type = .string
            name = String(name.dropLast())
        } else if name.hasSuffix("(") {
            type = .numericArray
            name = String(name.dropLast())
        } else {
            type = .numeric
        }

        // Validate name
        guard !name.isEmpty else { return nil }
        guard let first = name.first, first.isLetter else { return nil }
        guard name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }

        return BASICVariableName(name: name, type: type)
    }

    /// The full name including type suffix (for display).
    public var fullName: String {
        name + type.suffix
    }

    /// Encodes the variable name for storage in the VNT.
    ///
    /// The ROM format stores the full name including type suffix characters
    /// (`$` for strings, `(` for arrays) as part of the name. The LAST
    /// character (which may be a suffix char) has bit 7 set.
    ///
    /// Examples:
    /// - Numeric `X` → [0xD8] (X|0x80)
    /// - String `A$` → [0x41, 0xA4] (A, $|0x80)
    /// - Numeric array `B(` → [0x42, 0xA8] (B, (|0x80)
    /// - String array `C$(` → [0x43, 0x24, 0xA8] (C, $, (|0x80)
    ///
    /// - Returns: The encoded bytes for this variable name.
    public func encodeForVNT() -> [UInt8] {
        var bytes: [UInt8] = []

        // Build the full name including type suffix
        let fullNameStr = fullName  // e.g., "X", "A$", "B(", "C$("
        let fullBytes = fullNameStr.map { UInt8(ascii: $0) }

        guard !fullBytes.isEmpty else { return bytes }

        // Add all but last character
        for i in 0..<(fullBytes.count - 1) {
            bytes.append(fullBytes[i])
        }

        // Add last character with high bit set
        bytes.append(fullBytes.last! | 0x80)

        return bytes
    }
}

// =============================================================================
// MARK: - Variable Entry
// =============================================================================

/// A variable entry with its index in the variable tables.
///
/// When a variable is referenced in a BASIC program, it's encoded as a single
/// byte: the variable's index (0-127) plus $80. This struct tracks both the
/// variable identity and its assigned index.
public struct BASICVariable: Sendable, Equatable {
    /// The variable name and type.
    public let name: BASICVariableName

    /// The index in the variable tables (0-127).
    ///
    /// When tokenized, this becomes the byte $80 + index.
    public let index: UInt8

    /// Creates a variable entry.
    ///
    /// - Parameters:
    ///   - name: The variable name.
    ///   - index: The table index (0-127).
    public init(name: BASICVariableName, index: UInt8) {
        self.name = name
        self.index = min(index, BASICSpecialToken.maxVariableIndex)
    }

    /// The token byte used to reference this variable.
    public var tokenByte: UInt8 {
        BASICSpecialToken.variableBase + index
    }
}

// =============================================================================
// MARK: - Variable Value
// =============================================================================

/// Represents the 8-byte value stored in the Variable Value Table.
///
/// Each VVT entry is 8 bytes. Bytes 0-1 are a header (variable number
/// and type flags); the remaining bytes 2-7 hold type-specific data:
/// - Numeric: bytes 0-1 = header, bytes 2-7 = 6-byte BCD float
/// - String: bytes 0-1 = header, 2-3 = buffer address, 4-5 = DIM capacity, 6-7 = current length
/// - Array: bytes 0-1 = header, 2-3 = offset from STARP, 4-7 = dimension info
public struct BASICVariableValue: Sendable {
    /// The raw 8 bytes of the value.
    public var bytes: [UInt8]

    /// Creates a variable value with the given bytes.
    ///
    /// - Parameter bytes: Exactly 8 bytes of value data.
    public init(bytes: [UInt8]) {
        precondition(bytes.count == 8, "Variable value must be exactly 8 bytes")
        self.bytes = bytes
    }

    /// Creates an uninitialized (zero) variable value.
    public static var zero: BASICVariableValue {
        BASICVariableValue(bytes: [0, 0, 0, 0, 0, 0, 0, 0])
    }

    /// Creates a numeric variable value from a variable number and BCD bytes.
    ///
    /// - Parameters:
    ///   - varNum: Variable number (index in VNT).
    ///   - bcd: 6-byte BCD floating-point representation.
    /// - Returns: An 8-byte VVT entry.
    public static func numeric(varNum: UInt8 = 0, bcd: [UInt8]) -> BASICVariableValue {
        precondition(bcd.count == 6, "BCD must be exactly 6 bytes")
        return BASICVariableValue(bytes: [varNum, 0] + bcd)
    }

    /// Creates a string variable value.
    ///
    /// - Parameters:
    ///   - varNum: Variable number (index in VNT).
    ///   - address: The address where string data is stored.
    ///   - capacity: The DIM'd capacity of the string.
    ///   - length: The current string length.
    /// - Returns: An 8-byte VVT entry.
    public static func string(varNum: UInt8 = 0, address: UInt16, capacity: UInt16 = 0, length: UInt16) -> BASICVariableValue {
        BASICVariableValue(bytes: [
            varNum, 0x80,
            UInt8(address & 0xFF),
            UInt8(address >> 8),
            UInt8(capacity & 0xFF),
            UInt8(capacity >> 8),
            UInt8(length & 0xFF),
            UInt8(length >> 8),
        ])
    }

    /// Extracts the string buffer address from a string VVT entry.
    public var stringAddress: UInt16 {
        UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
    }

    /// Extracts the DIM'd capacity from a string VVT entry.
    public var stringCapacity: UInt16 {
        UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
    }

    /// Extracts the current string length from a string VVT entry.
    public var stringLength: UInt16 {
        UInt16(bytes[6]) | (UInt16(bytes[7]) << 8)
    }
}

// =============================================================================
// MARK: - Variable Table Operations
// =============================================================================

/// Helper functions for reading and writing variable tables in emulator memory.
///
/// These functions work with raw memory bytes to parse and construct the
/// Variable Name Table (VNT) and Variable Value Table (VVT).
public enum BASICVariableTable {

    /// Parses all variables from the Variable Name Table in memory.
    ///
    /// The VNT is a contiguous block of variable name entries. Each entry
    /// consists of the variable name characters with the LAST character
    /// having bit 7 set. The variable type is determined by the name itself:
    ///
    /// - Name ends with `$` and `(`: string array (e.g., "A$(")
    /// - Name ends with `$`: string (e.g., "A$")
    /// - Name ends with `(`: numeric array (e.g., "A(")
    /// - Otherwise: numeric scalar (e.g., "A")
    ///
    /// The ROM stores the `$` and `(` type suffixes as part of the variable
    /// name in the VNT, with the last character (including suffix chars)
    /// having bit 7 set. There are NO separate type indicator bytes.
    ///
    /// - Parameters:
    ///   - memory: The VNT memory bytes.
    ///   - startAddress: The address where VNT starts (for error reporting).
    /// - Returns: Array of parsed variable names in order.
    public static func parseVNT(from memory: [UInt8]) -> [BASICVariableName] {
        var variables: [BASICVariableName] = []
        var offset = 0

        while offset < memory.count {
            // Read variable name until we find byte with high bit set.
            // The high bit marks the LAST character of the name (including
            // any type suffix like $ or ().
            var nameBytes: [UInt8] = []
            while offset < memory.count {
                let byte = memory[offset]
                offset += 1

                if byte & 0x80 != 0 {
                    // Last character of name (high bit set) — strip the bit
                    nameBytes.append(byte & 0x7F)
                    break
                } else {
                    nameBytes.append(byte)
                }
            }

            guard !nameBytes.isEmpty else { break }

            // Convert to string — this includes any type suffix chars
            let fullName = String(nameBytes.map { Character(UnicodeScalar($0)) })

            // Determine type from the suffix characters in the name.
            // The ROM stores "$(" for string arrays, "$" for strings,
            // "(" for numeric arrays, and nothing for numeric scalars.
            let type: BASICVariableType
            let baseName: String

            if fullName.hasSuffix("$(") {
                type = .stringArray
                baseName = String(fullName.dropLast(2))
            } else if fullName.hasSuffix("$") {
                type = .string
                baseName = String(fullName.dropLast())
            } else if fullName.hasSuffix("(") {
                type = .numericArray
                baseName = String(fullName.dropLast())
            } else {
                type = .numeric
                baseName = fullName
            }

            variables.append(BASICVariableName(name: baseName, type: type))
        }

        return variables
    }

    /// Encodes a list of variables into VNT format.
    ///
    /// - Parameter variables: The variables to encode.
    /// - Returns: The encoded VNT bytes.
    public static func encodeVNT(variables: [BASICVariableName]) -> [UInt8] {
        var bytes: [UInt8] = []
        for variable in variables {
            bytes.append(contentsOf: variable.encodeForVNT())
        }
        return bytes
    }

    /// Calculates the size of a VNT entry for a given variable.
    ///
    /// The size is the length of the full name including type suffix
    /// characters (`$`, `(`). The last byte has bit 7 set but still
    /// counts as one byte.
    ///
    /// - Parameter variable: The variable name.
    /// - Returns: The number of bytes this variable uses in the VNT.
    public static func vntEntrySize(for variable: BASICVariableName) -> Int {
        // Full name includes base name + type suffix (e.g., "A$(" = 3 bytes)
        return variable.fullName.count
    }

    /// Finds a variable by name in a list of existing variables.
    ///
    /// - Parameters:
    ///   - name: The variable name to find.
    ///   - variables: The list of existing variables.
    /// - Returns: The matching variable entry, or nil if not found.
    public static func findVariable(
        named name: BASICVariableName,
        in variables: [BASICVariable]
    ) -> BASICVariable? {
        variables.first { $0.name == name }
    }
}

// =============================================================================
// MARK: - ATASCII Extension
// =============================================================================

/// Extension to convert between Swift characters and ATASCII bytes.
extension UInt8 {
    /// Creates an ATASCII byte from an ASCII character.
    ///
    /// ATASCII is mostly compatible with ASCII for printable characters.
    /// This initializer handles the basic A-Z, 0-9 range used in variable names.
    ///
    /// - Parameter ascii: A character in the ASCII range.
    init(ascii character: Character) {
        if let scalar = character.asciiValue {
            self = scalar
        } else {
            self = 0x3F  // '?' for unknown characters
        }
    }
}
