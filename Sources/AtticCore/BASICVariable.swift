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
    /// Format:
    /// - Characters of name (ATASCII)
    /// - Last character has bit 7 set (OR with $80)
    /// - For non-numeric types, type indicator byte follows
    ///
    /// - Returns: The encoded bytes for this variable name.
    public func encodeForVNT() -> [UInt8] {
        var bytes: [UInt8] = []

        // Convert name to ATASCII bytes
        let nameBytes = name.map { UInt8(ascii: $0) }

        // Add all but last character
        for i in 0..<(nameBytes.count - 1) {
            bytes.append(nameBytes[i])
        }

        // Add last character with high bit set
        if let lastByte = nameBytes.last {
            bytes.append(lastByte | 0x80)
        }

        // Add type indicator for non-numeric variables
        switch type {
        case .numeric:
            break  // No indicator byte
        case .string:
            bytes.append(0x24)  // '$' character
        case .numericArray:
            bytes.append(0x28)  // '(' character
        case .stringArray:
            bytes.append(0x24)  // '$'
            bytes.append(0x28)  // '('
        }

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
/// All variables use exactly 8 bytes in the VVT, regardless of type:
/// - Numeric: 6-byte BCD float + 2 unused bytes
/// - String: 2-byte length + 2-byte address + 4 unused bytes
/// - Array: 2-byte offset from STARP + 6 bytes dimension info
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

    /// Creates a numeric variable value from BCD bytes.
    ///
    /// - Parameter bcd: 6-byte BCD floating-point representation.
    /// - Returns: An 8-byte variable value.
    public static func numeric(bcd: [UInt8]) -> BASICVariableValue {
        precondition(bcd.count == 6, "BCD must be exactly 6 bytes")
        return BASICVariableValue(bytes: bcd + [0, 0])
    }

    /// Creates a string variable value.
    ///
    /// - Parameters:
    ///   - length: The string length (0-32767).
    ///   - address: The address where string data is stored.
    /// - Returns: An 8-byte variable value.
    public static func string(length: UInt16, address: UInt16) -> BASICVariableValue {
        BASICVariableValue(bytes: [
            UInt8(length & 0xFF),
            UInt8(length >> 8),
            UInt8(address & 0xFF),
            UInt8(address >> 8),
            0, 0, 0, 0
        ])
    }

    /// Extracts the string length from a string variable value.
    public var stringLength: UInt16 {
        UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    /// Extracts the string address from a string variable value.
    public var stringAddress: UInt16 {
        UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
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
    /// consists of the variable name (with last character OR'd with $80)
    /// followed by type indicator bytes for non-numeric variables.
    ///
    /// - Parameters:
    ///   - memory: The VNT memory bytes.
    ///   - startAddress: The address where VNT starts (for error reporting).
    /// - Returns: Array of parsed variable names in order.
    public static func parseVNT(from memory: [UInt8]) -> [BASICVariableName] {
        var variables: [BASICVariableName] = []
        var offset = 0

        while offset < memory.count {
            // Read variable name until we find byte with high bit set
            var nameBytes: [UInt8] = []
            while offset < memory.count {
                let byte = memory[offset]
                offset += 1

                if byte & 0x80 != 0 {
                    // Last character of name (high bit set)
                    nameBytes.append(byte & 0x7F)
                    break
                } else {
                    nameBytes.append(byte)
                }
            }

            guard !nameBytes.isEmpty else { break }

            // Convert to string
            let name = String(nameBytes.map { Character(UnicodeScalar($0)) })

            // Determine type from following bytes
            var type: BASICVariableType = .numeric

            if offset < memory.count {
                let nextByte = memory[offset]
                if nextByte == 0x24 {  // '$'
                    offset += 1
                    if offset < memory.count && memory[offset] == 0x28 {  // '('
                        type = .stringArray
                        offset += 1
                    } else {
                        type = .string
                    }
                } else if nextByte == 0x28 {  // '('
                    type = .numericArray
                    offset += 1
                }
            }

            variables.append(BASICVariableName(name: name, type: type))
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
    /// - Parameter variable: The variable name.
    /// - Returns: The number of bytes this variable uses in the VNT.
    public static func vntEntrySize(for variable: BASICVariableName) -> Int {
        var size = variable.name.count  // Name characters

        // Type indicator bytes
        switch variable.type {
        case .numeric:
            break
        case .string, .numericArray:
            size += 1
        case .stringArray:
            size += 2
        }

        return size
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
