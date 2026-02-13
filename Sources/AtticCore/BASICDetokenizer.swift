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
// Token Decoding is CONTEXT-AWARE:
//
// Statement name position (first byte of each statement, after colon):
// - $00-$36: Statement tokens (REM, PRINT, FOR, etc.)
//
// Expression position (all other bytes after the statement name):
// - $0E + 6 bytes: BCD floating-point constant
// - $0F + len + chars: String literal
// - $12-$37: Operator tokens (,  ;  =  TO  +  -  etc.)
// - $38-$4F: Function tokens (STR$, CHR$, PEEK, etc.)
// - $80-$FF: Variable reference (index into VNT)
//
// Operator byte values $12-$36 OVERLAP with statement tokens. The real
// Atari BASIC ROM disambiguates by position context, and so do we.
//
// Special Cases:
// - REM ($00): Remaining bytes until EOL are raw comment text
// - Implied LET ($36): Not output (wasn't in original source)
// - Colon ($14): Statement separator, followed by next-stmt offset byte
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
        // Minimum line: 2 bytes line number + 1 byte line offset + 1 byte stmt offset + 1 byte EOL = 5 bytes
        guard bytes.count >= 5 else { return nil }

        // Extract line number (little-endian)
        let lineNumber = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)

        // Line number 0 indicates end of program
        guard lineNumber > 0 else { return nil }

        // Line 32768 is the immediate mode line buffer - skip it
        guard lineNumber != BASICLineFormat.immediateModeLine else { return nil }

        // Extract line length
        let lineLength = Int(bytes[2])
        guard lineLength >= 5 && lineLength <= bytes.count else { return nil }

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
            // Check for end-of-program marker (line number 0) or immediate mode line (32768)
            if bytes.count - offset >= 2 {
                let lineNum = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                if lineNum == 0 || lineNum == BASICLineFormat.immediateModeLine {
                    break
                }
            }

            // Read line length
            guard offset + 2 < bytes.count else { break }
            let lineLength = Int(bytes[offset + 2])
            guard lineLength >= 5 && offset + lineLength <= bytes.count else { break }

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
    /// This is the core detokenization logic. It is CONTEXT-AWARE: the first
    /// byte of each statement is decoded as a STATEMENT NAME token (using the
    /// statement token table $00-$36), while all subsequent bytes are decoded
    /// as EXPRESSION tokens (operators $12-$37, functions $38-$4F, constants,
    /// and variable references $80-$FF).
    ///
    /// This context distinction is necessary because operator byte values
    /// overlap with statement byte values. For example, $2D means POSITION
    /// in statement-name position but means = (assignment) in expression
    /// position. The real Atari BASIC ROM disambiguates the same way.
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
        var expectStatementName = true  // First byte is always a statement name
        var afterStatement = false      // Track if we just output a statement keyword

        while index < bytes.count {
            let byte = bytes[index]

            if expectStatementName {
                // ── STATEMENT NAME POSITION ──
                // The first byte of each statement is the statement name token.

                // Check for REM - rest of line is raw comment text
                if byte == BASICStatementToken.rem.rawValue {
                    if !result.isEmpty && !result.hasSuffix(" ") && !result.hasSuffix(":") {
                        result += " "
                    }
                    result += "REM"
                    index += 1
                    if index < bytes.count {
                        result += " "
                        let commentBytes = Array(bytes[index...])
                        result += decodeRawText(commentBytes)
                    }
                    break
                }

                if let token = BASICStatementToken(rawValue: byte) {
                    // Implied LET ($36) - don't output the keyword
                    if token != .impliedLet {
                        if !result.isEmpty && !result.hasSuffix(" ") && !result.hasSuffix(":") {
                            result += " "
                        }
                        result += token.keyword
                        result += " "
                    }
                } else {
                    // Unknown statement token
                    result += String(format: "?$%02X", byte)
                }

                index += 1
                expectStatementName = false
                afterStatement = true

            } else {
                // ── EXPRESSION POSITION ──
                // All bytes after the statement name are expression tokens.
                let (text, consumed, needsLeadingSpace, needsTrailingSpace, isColon) =
                    decodeExpressionToken(
                        bytes: bytes,
                        at: index,
                        variables: variables,
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
                afterStatement = false

                // If we hit a colon (statement separator), the NEXT byte is
                // the next-statement offset byte (skip it), then a new statement
                // name token follows.
                if isColon {
                    if index < bytes.count {
                        index += 1  // Skip the next-statement offset byte
                    }
                    expectStatementName = true
                }
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Decodes a single expression token at the given position.
    ///
    /// Expression tokens use a different byte space than statement name tokens:
    /// - $0D + byte: Legacy small integer constant (our old format, kept for compat)
    /// - $0E + 6 bytes: BCD floating-point constant
    /// - $0F + len + chars: String literal
    /// - $12-$37: Operator tokens (comma, =, TO, +, -, etc.)
    /// - $38-$4F: Function tokens (STR$, CHR$, PEEK, etc.)
    /// - $80-$FF: Variable references
    ///
    /// - Parameters:
    ///   - bytes: The full content bytes.
    ///   - at: The current index.
    ///   - variables: The Variable Name Table.
    ///   - afterStatement: Whether we just processed a statement keyword.
    /// - Returns: Tuple of (text, bytesConsumed, needsLeadingSpace, needsTrailingSpace, isColon).
    private func decodeExpressionToken(
        bytes: [UInt8],
        at index: Int,
        variables: [BASICVariableName],
        afterStatement: Bool
    ) -> (String, Int, Bool, Bool, Bool) {
        let byte = bytes[index]

        // Variable reference ($80-$FF)
        if byte >= BASICSpecialToken.variableBase {
            let varIndex = Int(byte - BASICSpecialToken.variableBase)
            let varName = variableName(at: varIndex, variables: variables)
            return (varName, 1, !afterStatement, false, false)
        }

        // Legacy small integer constant ($0D + byte) - kept for backward compatibility
        // with our old tokenizer format. Real Atari BASIC does not use $0D.
        if byte == BASICSpecialToken.smallIntPrefix {
            guard index + 1 < bytes.count else {
                return ("?", 1, false, false, false)
            }
            let value = bytes[index + 1]
            return (String(value), 2, !afterStatement, false, false)
        }

        // BCD floating-point constant ($0E + 6 bytes)
        if byte == BASICSpecialToken.bcdFloatPrefix {
            guard index + 6 < bytes.count else {
                return ("?", 1, false, false, false)
            }
            let bcdBytes = Array(bytes[(index + 1)...(index + 6)])
            let bcd = BCDFloat(bytes: bcdBytes)
            return (bcd.decimalString, 7, !afterStatement, false, false)
        }

        // String literal ($0F + length + chars)
        if byte == BASICSpecialToken.stringPrefix {
            guard index + 1 < bytes.count else {
                return ("\"\"", 1, false, false, false)
            }
            let length = Int(bytes[index + 1])
            guard index + 1 + length < bytes.count else {
                return ("\"\"", 2, false, false, false)
            }
            let stringBytes = Array(bytes[(index + 2)..<(index + 2 + length)])
            let content = decodeRawText(stringBytes)
            return ("\"\(content)\"", 2 + length, !afterStatement, false, false)
        }

        // Operator tokens ($12-$37)
        if let token = BASICOperatorToken(rawValue: byte) {
            // EOL marker ($16) shouldn't appear in content, but handle gracefully
            if token == .endOfLine {
                return ("", 1, false, false, false)
            }

            let symbol = token.symbol
            let isColon = (token == .colon)
            let needsSpaces = operatorNeedsSpaces(token)
            return (symbol, 1, needsSpaces, needsSpaces, isColon)
        }

        // Function tokens ($38-$4F)
        if let token = BASICFunctionToken(rawValue: byte) {
            return (token.keyword, 1, !afterStatement, false, false)
        }

        // Unknown expression token - output as hex
        return (String(format: "?$%02X", byte), 1, false, false, false)
    }

    // =========================================================================
    // MARK: - Helper Methods
    // =========================================================================

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
            } else if byte >= 0x80 && byte != 0x9B {
                // Inverse video characters (bit 7 set) - strip bit 7
                // to map back to the base ASCII character.
                let base = byte & 0x7F
                if base >= 0x20 && base < 0x7F {
                    text.append(Character(UnicodeScalar(base)))
                } else {
                    // Inverse of a graphics char (0x80-0x9A) — no ASCII equivalent
                    text.append(".")
                }
            } else {
                // ATASCII graphics characters (0x00-0x1F) — no ASCII equivalent
                text.append(".")
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
