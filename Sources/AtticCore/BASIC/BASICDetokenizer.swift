// =============================================================================
// BASICDetokenizer.swift - Atari BASIC Detokenizer
// =============================================================================
//
// This file implements the detokenizer that converts tokenized BASIC programs
// stored in emulator memory back into human-readable text. This is the inverse
// operation of tokenization (BASICTokenizer.swift).
//
// The detokenizer is used for:
// - LIST command (displaying program lines)
// - VARS command (showing variable names)
// - Export to .BAS text files
//
// Token Decoding Overview:
// - $00-$36: Statement tokens (REM, PRINT, FOR, etc.)
// - $37-$5C: Operator tokens (arithmetic, comparison, logical)
// - $5D-$74: Function tokens (STR$, CHR$, ABS, etc.)
// - $0D + byte: Small integer constant (0-255)
// - $0E + 6 bytes: BCD floating-point constant
// - $0F + len + chars: String literal
// - $16: End of line marker
// - $80-$FF: Variable reference (index into VNT)
//
// Special Cases:
// - REM ($00): Remaining bytes until EOL are raw comment text
// - Implied LET ($36): Not output (wasn't in original source)
// - Keywords need trailing space, most operators don't
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Detokenized Line Result
// =============================================================================

/// Represents a single detokenized BASIC program line.
///
/// This struct holds both the human-readable text representation and metadata
/// about the line, such as its number and byte length in memory.
public struct DetokenizedLine: Sendable, Equatable {
    /// The BASIC line number (0-32767).
    public let lineNumber: UInt16

    /// The human-readable text representation of the line (without line number).
    public let text: String

    /// The total number of bytes this line occupies in memory.
    /// Includes the 3-byte header (line number + length) and EOL marker.
    public let byteLength: Int

    /// Creates a detokenized line result.
    ///
    /// - Parameters:
    ///   - lineNumber: The BASIC line number.
    ///   - text: The human-readable text.
    ///   - byteLength: The number of bytes in memory.
    public init(lineNumber: UInt16, text: String, byteLength: Int) {
        self.lineNumber = lineNumber
        self.text = text
        self.byteLength = byteLength
    }

    /// The complete line as it would appear in a listing (number + text).
    public var fullLine: String {
        "\(lineNumber) \(text)"
    }
}

// =============================================================================
// MARK: - Detokenizer
// =============================================================================

/// Converts tokenized BASIC program bytes back to human-readable text.
///
/// The detokenizer processes raw tokenized bytes from emulator memory and
/// produces readable BASIC source code. It requires access to the Variable
/// Name Table (VNT) to resolve variable references.
///
/// Usage Example:
/// ```swift
/// let detokenizer = BASICDetokenizer()
/// let variables = [BASICVariableName(name: "X", type: .numeric)]
/// let line = detokenizer.detokenizeLine(bytes, variables: variables)
/// print(line?.fullLine)  // "10 LET X=5"
/// ```
public struct BASICDetokenizer: Sendable {

    /// Creates a new detokenizer instance.
    public init() {}

    // =========================================================================
    // MARK: - Single Line Detokenization
    // =========================================================================

    /// Detokenizes a single BASIC line from its tokenized bytes.
    ///
    /// The input bytes should include the complete line structure:
    /// - Bytes 0-1: Line number (little-endian)
    /// - Byte 2: Line length (total bytes including header)
    /// - Bytes 3+: Tokenized content
    /// - Last byte: EOL marker ($16)
    ///
    /// - Parameters:
    ///   - bytes: The raw tokenized bytes for one line.
    ///   - variables: The Variable Name Table entries for resolving references.
    /// - Returns: The detokenized line, or nil if the bytes are invalid.
    public func detokenizeLine(
        _ bytes: [UInt8],
        variables: [BASICVariableName]
    ) -> DetokenizedLine? {
        // Minimum line: 2 bytes line number + 1 byte length + 1 byte EOL = 4 bytes
        guard bytes.count >= 4 else { return nil }

        // Extract line number (little-endian)
        let lineNumber = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)

        // Line number 0 indicates end of program
        guard lineNumber > 0 else { return nil }

        // Extract line length
        let lineLength = Int(bytes[2])
        guard lineLength >= 4 && lineLength <= bytes.count else { return nil }

        // Extract content bytes (skip header, exclude EOL marker)
        let contentStart = BASICLineFormat.contentOffset
        let contentEnd = lineLength - 1  // Exclude EOL marker

        guard contentEnd > contentStart else {
            // Empty line content (just line number)
            return DetokenizedLine(lineNumber: lineNumber, text: "", byteLength: lineLength)
        }

        let contentBytes = Array(bytes[contentStart..<contentEnd])

        // Detokenize the content
        let text = detokenizeContent(contentBytes, variables: variables)

        return DetokenizedLine(
            lineNumber: lineNumber,
            text: text,
            byteLength: lineLength
        )
    }

    // =========================================================================
    // MARK: - Full Program Detokenization
    // =========================================================================

    /// Detokenizes an entire BASIC program from memory.
    ///
    /// - Parameters:
    ///   - bytes: The raw program bytes from STMTAB to STARP.
    ///   - variables: The Variable Name Table entries.
    ///   - range: Optional line number range filter (start, end).
    ///            nil means all lines, partial values filter accordingly.
    /// - Returns: Array of detokenized lines in order.
    public func detokenizeProgram(
        _ bytes: [UInt8],
        variables: [BASICVariableName],
        range: (start: Int?, end: Int?)? = nil
    ) -> [DetokenizedLine] {
        var lines: [DetokenizedLine] = []
        var offset = 0

        while offset < bytes.count {
            // Check for end-of-program marker (line number 0)
            if bytes.count - offset >= 2 {
                let lineNum = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                if lineNum == 0 {
                    break
                }
            }

            // Read line length
            guard offset + 2 < bytes.count else { break }
            let lineLength = Int(bytes[offset + 2])
            guard lineLength >= 4 && offset + lineLength <= bytes.count else { break }

            // Extract line bytes
            let lineBytes = Array(bytes[offset..<(offset + lineLength)])

            // Detokenize the line
            if let line = detokenizeLine(lineBytes, variables: variables) {
                // Apply range filter
                let lineNum = Int(line.lineNumber)
                let startOK = range?.start == nil || lineNum >= range!.start!
                let endOK = range?.end == nil || lineNum <= range!.end!

                if startOK && endOK {
                    lines.append(line)
                }
            }

            // Move to next line
            offset += lineLength
        }

        return lines
    }

    // =========================================================================
    // MARK: - Content Detokenization
    // =========================================================================

    /// Detokenizes the content portion of a line (after header, before EOL).
    ///
    /// This is the core detokenization logic that converts token bytes to text.
    ///
    /// - Parameters:
    ///   - bytes: The content bytes (excluding line header and EOL).
    ///   - variables: The Variable Name Table for variable lookups.
    /// - Returns: The human-readable text.
    private func detokenizeContent(
        _ bytes: [UInt8],
        variables: [BASICVariableName]
    ) -> String {
        var result = ""
        var index = 0
        var isFirstToken = true
        var afterStatement = false  // Track if we just output a statement keyword

        while index < bytes.count {
            let byte = bytes[index]

            // Check for REM statement - rest of line is raw comment text
            if byte == BASICStatementToken.rem.rawValue {
                if !isFirstToken && !afterStatement {
                    result += " "
                }
                result += "REM"

                // Read remaining bytes as raw comment text
                index += 1
                if index < bytes.count {
                    result += " "
                    let commentBytes = Array(bytes[index...])
                    result += decodeRawText(commentBytes)
                }
                break
            }

            // Determine token type and decode
            let (text, consumed, needsLeadingSpace, needsTrailingSpace) = decodeToken(
                bytes: bytes,
                at: index,
                variables: variables,
                isFirstToken: isFirstToken,
                afterStatement: afterStatement
            )

            // Add spacing as needed
            if needsLeadingSpace && !result.isEmpty && !result.hasSuffix(" ") {
                result += " "
            }

            result += text

            if needsTrailingSpace {
                result += " "
            }

            index += consumed
            isFirstToken = false

            // Track if this was a statement keyword for spacing decisions
            afterStatement = isStatementToken(byte)
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Decodes a single token at the given position.
    ///
    /// - Parameters:
    ///   - bytes: The full content bytes.
    ///   - at: The current index.
    ///   - variables: The Variable Name Table.
    ///   - isFirstToken: Whether this is the first token on the line.
    ///   - afterStatement: Whether we just processed a statement keyword.
    /// - Returns: Tuple of (text, bytesConsumed, needsLeadingSpace, needsTrailingSpace).
    private func decodeToken(
        bytes: [UInt8],
        at index: Int,
        variables: [BASICVariableName],
        isFirstToken: Bool,
        afterStatement: Bool
    ) -> (String, Int, Bool, Bool) {
        let byte = bytes[index]

        // Variable reference ($80-$FF)
        if byte >= BASICSpecialToken.variableBase {
            let varIndex = Int(byte - BASICSpecialToken.variableBase)
            let varName = variableName(at: varIndex, variables: variables)
            return (varName, 1, !isFirstToken && !afterStatement, false)
        }

        // Small integer constant ($0D + byte)
        if byte == BASICSpecialToken.smallIntPrefix {
            guard index + 1 < bytes.count else {
                return ("?", 1, false, false)
            }
            let value = bytes[index + 1]
            return (String(value), 2, !afterStatement, false)
        }

        // BCD floating-point constant ($0E + 6 bytes)
        if byte == BASICSpecialToken.bcdFloatPrefix {
            guard index + 6 < bytes.count else {
                return ("?", 1, false, false)
            }
            let bcdBytes = Array(bytes[(index + 1)...(index + 6)])
            let bcd = BCDFloat(bytes: bcdBytes)
            return (bcd.decimalString, 7, !afterStatement, false)
        }

        // String literal ($0F + length + chars)
        if byte == BASICSpecialToken.stringPrefix {
            guard index + 1 < bytes.count else {
                return ("\"\"", 1, false, false)
            }
            let length = Int(bytes[index + 1])
            guard index + 1 + length < bytes.count else {
                return ("\"\"", 2, false, false)
            }
            let stringBytes = Array(bytes[(index + 2)..<(index + 2 + length)])
            let content = decodeRawText(stringBytes)
            return ("\"\(content)\"", 2 + length, !afterStatement, false)
        }

        // Statement tokens ($00-$36)
        if byte <= 0x36 {
            if let token = BASICStatementToken(rawValue: byte) {
                let keyword = token.keyword

                // Implied LET ($36) - don't output the keyword
                if token == .impliedLet {
                    return ("", 1, false, false)
                }

                // Other statements need trailing space
                return (keyword, 1, !isFirstToken, true)
            }
        }

        // Operator tokens ($37-$5C)
        if byte >= 0x37 && byte <= 0x5C {
            if let token = BASICOperatorToken(rawValue: byte) {
                let symbol = token.symbol
                let needsSpaces = operatorNeedsSpaces(token)
                return (symbol, 1, needsSpaces, needsSpaces)
            }
        }

        // Function tokens ($5D-$74)
        if byte >= 0x5D && byte <= 0x74 {
            if let token = BASICFunctionToken(rawValue: byte) {
                return (token.keyword, 1, !afterStatement, false)
            }
        }

        // EOL marker ($16) - shouldn't appear in content, but handle it
        if byte == BASICSpecialToken.endOfLine {
            return ("", 1, false, false)
        }

        // Unknown token - output as hex
        return (String(format: "?$%02X", byte), 1, false, false)
    }

    // =========================================================================
    // MARK: - Helper Methods
    // =========================================================================

    /// Checks if a byte is a statement token.
    private func isStatementToken(_ byte: UInt8) -> Bool {
        byte <= 0x36 && BASICStatementToken(rawValue: byte) != nil
    }

    /// Determines if an operator token needs surrounding spaces.
    ///
    /// Most operators like +, -, *, / don't need spaces.
    /// Keywords like TO, STEP, THEN, AND, OR, NOT need spaces.
    private func operatorNeedsSpaces(_ token: BASICOperatorToken) -> Bool {
        switch token {
        case .toKeyword, .step, .then, .gotoInOn, .gosubInOn,
             .not, .or, .and:
            return true
        default:
            return false
        }
    }

    /// Looks up a variable name by its index.
    ///
    /// - Parameters:
    ///   - index: The variable index (0-127).
    ///   - variables: The Variable Name Table.
    /// - Returns: The full variable name with type suffix, or "?VARn" if not found.
    private func variableName(
        at index: Int,
        variables: [BASICVariableName]
    ) -> String {
        guard index >= 0 && index < variables.count else {
            return "?VAR\(index)"
        }
        return variables[index].fullName
    }

    /// Decodes raw bytes as text (ATASCII to ASCII).
    ///
    /// - Parameter bytes: The raw bytes to decode.
    /// - Returns: The decoded text string.
    private func decodeRawText(_ bytes: [UInt8]) -> String {
        var text = ""
        for byte in bytes {
            // Standard printable ASCII range
            if byte >= 0x20 && byte < 0x7F {
                text.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x9B {
                // ATASCII EOL - convert to newline (shouldn't appear in strings)
                text.append("\n")
            } else {
                // Non-printable - keep as-is for compatibility
                text.append(Character(UnicodeScalar(byte)))
            }
        }
        return text
    }
}

// =============================================================================
// MARK: - Program Listing Helper
// =============================================================================

/// Extension providing convenient methods for generating program listings.
extension BASICDetokenizer {

    /// Formats a complete program listing as a single string.
    ///
    /// - Parameters:
    ///   - bytes: The program bytes from memory.
    ///   - variables: The Variable Name Table.
    ///   - range: Optional line number range filter.
    /// - Returns: The formatted listing with one line per output line.
    public func formatListing(
        _ bytes: [UInt8],
        variables: [BASICVariableName],
        range: (start: Int?, end: Int?)? = nil
    ) -> String {
        let lines = detokenizeProgram(bytes, variables: variables, range: range)
        return lines.map { $0.fullLine }.joined(separator: "\n")
    }
}
