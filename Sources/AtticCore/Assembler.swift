// =============================================================================
// Assembler.swift - MAC65-Style 6502 Assembler
// =============================================================================
//
// This file implements a 6502 assembler with syntax compatible with MAC65,
// the popular Atari 8-bit assembler. Features include:
//
// - All standard 6502 instructions
// - Labels (global and local)
// - Expressions with arithmetic and hi/lo byte operators
// - Pseudo-ops: ORG, EQU, DB/BYTE, DW/WORD, DS/BLOCK, END
// - Comments with semicolon
// - Decimal, hex ($), binary (%), and character ('x') literals
//
// MAC65 Syntax Reference:
// -----------------------
// Labels start at column 1 and end with optional colon
// Mnemonics are typically column 8+ (we're flexible)
// Operands follow mnemonics
// Comments start with semicolon
//
// Example:
//     ORG $0600
//     SCREEN = $D400
// START LDA #0
//     STA SCREEN
// LOOP  INX
//       BNE LOOP
//       RTS
//
// Expression Operators:
// - +, -, *, / : Arithmetic
// - < : Low byte of word (e.g., <LABEL)
// - > : High byte of word (e.g., >LABEL)
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Assembler Errors
// =============================================================================

/// Errors that can occur during assembly.
public enum AssemblerError: Error, LocalizedError, Sendable, Equatable {
    case invalidInstruction(String)
    case invalidOperand(String)
    case invalidAddressingMode(String, String)  // mnemonic, operand
    case undefinedLabel(String)
    case duplicateLabel(String)
    case invalidExpression(String)
    case valueOutOfRange(String, Int, Int, Int)  // context, value, min, max
    case invalidPseudoOp(String)
    case syntaxError(String)
    case branchOutOfRange(String, Int)  // label, offset

    public var errorDescription: String? {
        switch self {
        case .invalidInstruction(let instr):
            return "Invalid instruction '\(instr)'"
        case .invalidOperand(let operand):
            return "Invalid operand '\(operand)'"
        case .invalidAddressingMode(let mnemonic, let operand):
            return "Invalid addressing mode for \(mnemonic): \(operand)"
        case .undefinedLabel(let label):
            return "Undefined label '\(label)'"
        case .duplicateLabel(let label):
            return "Duplicate label '\(label)'"
        case .invalidExpression(let expr):
            return "Invalid expression '\(expr)'"
        case .valueOutOfRange(let context, let value, let min, let max):
            return "\(context): value \(value) out of range (\(min)...\(max))"
        case .invalidPseudoOp(let op):
            return "Invalid pseudo-op '\(op)'"
        case .syntaxError(let msg):
            return "Syntax error: \(msg)"
        case .branchOutOfRange(let label, let offset):
            return "Branch to '\(label)' out of range (offset \(offset))"
        }
    }
}

// =============================================================================
// MARK: - Assembly Result
// =============================================================================

/// The result of assembling a single instruction.
public struct AssemblyResult: Sendable {
    /// The assembled bytes.
    public let bytes: [UInt8]

    /// The address where these bytes should be placed.
    public let address: UInt16

    /// The source line that was assembled.
    public let sourceLine: String

    /// Any label defined on this line.
    public let label: String?

    /// Number of bytes generated.
    public var length: Int { bytes.count }
}

// =============================================================================
// MARK: - Symbol Table
// =============================================================================

/// Manages labels and their values during assembly.
public final class SymbolTable: @unchecked Sendable {
    /// Maps label names to their values.
    private var symbols: [String: UInt16] = [:]

    /// Labels that have been referenced but not yet defined.
    private var forwardReferences: Set<String> = []

    public init() {}

    /// Defines a label with a value.
    ///
    /// - Parameters:
    ///   - name: The label name.
    ///   - value: The value to assign.
    /// - Throws: AssemblerError.duplicateLabel if already defined.
    public func define(_ name: String, value: UInt16) throws {
        let upper = name.uppercased()
        if symbols[upper] != nil {
            throw AssemblerError.duplicateLabel(name)
        }
        symbols[upper] = value
        forwardReferences.remove(upper)
    }

    /// Looks up a label's value.
    ///
    /// - Parameter name: The label name.
    /// - Returns: The value, or nil if undefined.
    public func lookup(_ name: String) -> UInt16? {
        symbols[name.uppercased()]
    }

    /// Marks a label as referenced (for forward reference tracking).
    public func reference(_ name: String) {
        let upper = name.uppercased()
        if symbols[upper] == nil {
            forwardReferences.insert(upper)
        }
    }

    /// Returns any unresolved forward references.
    public var unresolvedReferences: Set<String> {
        forwardReferences
    }

    /// Clears all symbols.
    public func clear() {
        symbols.removeAll()
        forwardReferences.removeAll()
    }

    /// Returns all defined symbols.
    public var allSymbols: [String: UInt16] {
        symbols
    }
}

// =============================================================================
// MARK: - Expression Parser
// =============================================================================

/// Parses and evaluates MAC65-style expressions.
///
/// Supported expressions:
/// - Decimal numbers: 123
/// - Hex numbers: $1234 or 0x1234
/// - Binary numbers: %10101010
/// - Character literals: 'A' (ASCII value)
/// - Labels: MYLABEL
/// - Operators: +, -, *, /
/// - Hi/Lo byte: >LABEL (high byte), <LABEL (low byte)
/// - Parentheses for grouping
/// - Current location counter: *
///
public struct ExpressionParser: Sendable {
    private let symbols: SymbolTable
    private let currentPC: UInt16

    public init(symbols: SymbolTable, currentPC: UInt16) {
        self.symbols = symbols
        self.currentPC = currentPC
    }

    /// Evaluates an expression string.
    ///
    /// - Parameter expression: The expression to evaluate.
    /// - Returns: The evaluated value.
    /// - Throws: AssemblerError if the expression is invalid.
    public func evaluate(_ expression: String) throws -> Int {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else {
            throw AssemblerError.invalidExpression(expression)
        }

        var index = expr.startIndex
        return try parseAddSub(expr, &index)
    }

    // MARK: - Recursive Descent Parser

    // Addition and subtraction (lowest precedence)
    private func parseAddSub(_ expr: String, _ index: inout String.Index) throws -> Int {
        var left = try parseMulDiv(expr, &index)

        while index < expr.endIndex {
            skipWhitespace(expr, &index)
            guard index < expr.endIndex else { break }

            let char = expr[index]
            if char == "+" {
                index = expr.index(after: index)
                let right = try parseMulDiv(expr, &index)
                left = left + right
            } else if char == "-" {
                index = expr.index(after: index)
                let right = try parseMulDiv(expr, &index)
                left = left - right
            } else {
                break
            }
        }

        return left
    }

    // Multiplication and division (higher precedence)
    private func parseMulDiv(_ expr: String, _ index: inout String.Index) throws -> Int {
        var left = try parseUnary(expr, &index)

        while index < expr.endIndex {
            skipWhitespace(expr, &index)
            guard index < expr.endIndex else { break }

            let char = expr[index]
            if char == "*" && isOperator(expr, index) {
                index = expr.index(after: index)
                let right = try parseUnary(expr, &index)
                left = left * right
            } else if char == "/" {
                index = expr.index(after: index)
                let right = try parseUnary(expr, &index)
                guard right != 0 else {
                    throw AssemblerError.invalidExpression("Division by zero")
                }
                left = left / right
            } else {
                break
            }
        }

        return left
    }

    // Check if * is multiplication operator (not location counter)
    private func isOperator(_ expr: String, _ index: String.Index) -> Bool {
        // * is an operator if there's something before it that's not an operator
        guard index > expr.startIndex else { return false }
        let prevIndex = expr.index(before: index)
        let prevChar = expr[prevIndex]
        return prevChar.isNumber || prevChar.isLetter || prevChar == ")" || prevChar == "'"
    }

    // Unary operators: <, >, -, + (hi/lo byte, negation)
    private func parseUnary(_ expr: String, _ index: inout String.Index) throws -> Int {
        skipWhitespace(expr, &index)
        guard index < expr.endIndex else {
            throw AssemblerError.invalidExpression("Unexpected end of expression")
        }

        let char = expr[index]

        // Low byte operator
        if char == "<" {
            index = expr.index(after: index)
            let value = try parseUnary(expr, &index)
            return value & 0xFF
        }

        // High byte operator
        if char == ">" {
            index = expr.index(after: index)
            let value = try parseUnary(expr, &index)
            return (value >> 8) & 0xFF
        }

        // Unary minus
        if char == "-" {
            index = expr.index(after: index)
            let value = try parseUnary(expr, &index)
            return -value
        }

        // Unary plus (no-op)
        if char == "+" {
            index = expr.index(after: index)
            return try parseUnary(expr, &index)
        }

        return try parsePrimary(expr, &index)
    }

    // Primary values: numbers, labels, parentheses, location counter
    private func parsePrimary(_ expr: String, _ index: inout String.Index) throws -> Int {
        skipWhitespace(expr, &index)
        guard index < expr.endIndex else {
            throw AssemblerError.invalidExpression("Unexpected end of expression")
        }

        let char = expr[index]

        // Parenthesized expression
        if char == "(" {
            index = expr.index(after: index)
            let value = try parseAddSub(expr, &index)
            skipWhitespace(expr, &index)
            guard index < expr.endIndex && expr[index] == ")" else {
                throw AssemblerError.invalidExpression("Missing closing parenthesis")
            }
            index = expr.index(after: index)
            return value
        }

        // Location counter
        if char == "*" && !isOperator(expr, index) {
            index = expr.index(after: index)
            return Int(currentPC)
        }

        // Hex number ($xxxx or 0xXXXX)
        if char == "$" {
            index = expr.index(after: index)
            return try parseHexNumber(expr, &index)
        }
        if char == "0" && index < expr.index(before: expr.endIndex) {
            let nextIndex = expr.index(after: index)
            if expr[nextIndex] == "x" || expr[nextIndex] == "X" {
                index = expr.index(after: nextIndex)
                return try parseHexNumber(expr, &index)
            }
        }

        // Binary number (%xxxxxxxx)
        if char == "%" {
            index = expr.index(after: index)
            return try parseBinaryNumber(expr, &index)
        }

        // Character literal ('x')
        if char == "'" {
            index = expr.index(after: index)
            guard index < expr.endIndex else {
                throw AssemblerError.invalidExpression("Unclosed character literal")
            }
            let charValue = Int(expr[index].asciiValue ?? 0)
            index = expr.index(after: index)
            // Handle closing quote if present
            if index < expr.endIndex && expr[index] == "'" {
                index = expr.index(after: index)
            }
            return charValue
        }

        // Decimal number
        if char.isNumber {
            return try parseDecimalNumber(expr, &index)
        }

        // Label
        if char.isLetter || char == "_" {
            return try parseLabel(expr, &index)
        }

        throw AssemblerError.invalidExpression("Unexpected character '\(char)'")
    }

    private func parseHexNumber(_ expr: String, _ index: inout String.Index) throws -> Int {
        var numStr = ""
        while index < expr.endIndex && expr[index].isHexDigit {
            numStr.append(expr[index])
            index = expr.index(after: index)
        }
        guard !numStr.isEmpty, let value = Int(numStr, radix: 16) else {
            throw AssemblerError.invalidExpression("Invalid hex number")
        }
        return value
    }

    private func parseBinaryNumber(_ expr: String, _ index: inout String.Index) throws -> Int {
        var numStr = ""
        while index < expr.endIndex && (expr[index] == "0" || expr[index] == "1") {
            numStr.append(expr[index])
            index = expr.index(after: index)
        }
        guard !numStr.isEmpty, let value = Int(numStr, radix: 2) else {
            throw AssemblerError.invalidExpression("Invalid binary number")
        }
        return value
    }

    private func parseDecimalNumber(_ expr: String, _ index: inout String.Index) throws -> Int {
        var numStr = ""
        while index < expr.endIndex && expr[index].isNumber {
            numStr.append(expr[index])
            index = expr.index(after: index)
        }
        guard !numStr.isEmpty, let value = Int(numStr) else {
            throw AssemblerError.invalidExpression("Invalid decimal number")
        }
        return value
    }

    private func parseLabel(_ expr: String, _ index: inout String.Index) throws -> Int {
        var labelName = ""
        while index < expr.endIndex && (expr[index].isLetter || expr[index].isNumber || expr[index] == "_") {
            labelName.append(expr[index])
            index = expr.index(after: index)
        }

        symbols.reference(labelName)

        guard let value = symbols.lookup(labelName) else {
            throw AssemblerError.undefinedLabel(labelName)
        }

        return Int(value)
    }

    private func skipWhitespace(_ expr: String, _ index: inout String.Index) {
        while index < expr.endIndex && expr[index].isWhitespace {
            index = expr.index(after: index)
        }
    }
}

// =============================================================================
// MARK: - Parsed Operand
// =============================================================================

/// Represents a parsed assembly operand.
public enum ParsedOperand: Sendable, Equatable {
    /// No operand (implied addressing).
    case none

    /// Accumulator operand (ASL A, etc.).
    case accumulator

    /// Immediate value (#$xx or #value).
    case immediate(Int)

    /// Zero page address ($xx).
    case zeroPage(Int)

    /// Zero page indexed by X ($xx,X).
    case zeroPageX(Int)

    /// Zero page indexed by Y ($xx,Y).
    case zeroPageY(Int)

    /// Absolute address ($xxxx).
    case absolute(Int)

    /// Absolute indexed by X ($xxxx,X).
    case absoluteX(Int)

    /// Absolute indexed by Y ($xxxx,Y).
    case absoluteY(Int)

    /// Indirect address (JMP only).
    case indirect(Int)

    /// Indexed indirect ($xx,X).
    case indexedIndirect(Int)

    /// Indirect indexed ($xx),Y.
    case indirectIndexed(Int)

    /// Relative (branch target).
    case relative(Int)

    /// The preferred addressing mode for this operand.
    public var mode: AddressingMode {
        switch self {
        case .none: return .implied
        case .accumulator: return .accumulator
        case .immediate: return .immediate
        case .zeroPage: return .zeroPage
        case .zeroPageX: return .zeroPageX
        case .zeroPageY: return .zeroPageY
        case .absolute: return .absolute
        case .absoluteX: return .absoluteX
        case .absoluteY: return .absoluteY
        case .indirect: return .indirect
        case .indexedIndirect: return .indexedIndirectX
        case .indirectIndexed: return .indirectIndexedY
        case .relative: return .relative
        }
    }

    /// The value/address contained in this operand.
    public var value: Int {
        switch self {
        case .none, .accumulator:
            return 0
        case .immediate(let v), .zeroPage(let v), .zeroPageX(let v), .zeroPageY(let v),
             .absolute(let v), .absoluteX(let v), .absoluteY(let v),
             .indirect(let v), .indexedIndirect(let v), .indirectIndexed(let v),
             .relative(let v):
            return v
        }
    }
}

// =============================================================================
// MARK: - Main Assembler
// =============================================================================

/// MAC65-style 6502 assembler.
///
/// Usage:
///
///     let assembler = Assembler()
///
///     // Assemble a single line
///     let result = try assembler.assembleLine("LDA #$00", at: 0x0600)
///
///     // Assemble multiple lines (for label resolution)
///     let results = try assembler.assemble("""
///         ORG $0600
///         LDA #$00
///     LOOP: INX
///         BNE LOOP
///     """)
///
public final class Assembler: @unchecked Sendable {
    /// Symbol table for labels.
    public let symbols: SymbolTable

    /// Current assembly address (location counter).
    private var pc: UInt16

    /// Whether we're in the first pass (collecting labels).
    private var firstPass: Bool = false

    /// Initializes the assembler.
    ///
    /// - Parameter startAddress: Initial program counter (default 0).
    public init(startAddress: UInt16 = 0) {
        self.symbols = SymbolTable()
        self.pc = startAddress
    }

    /// Resets the assembler state.
    public func reset(startAddress: UInt16 = 0) {
        symbols.clear()
        pc = startAddress
        firstPass = false
    }

    /// Gets the current program counter.
    public var currentPC: UInt16 {
        pc
    }

    /// Sets the current program counter.
    public func setPC(_ value: UInt16) {
        pc = value
    }

    // =========================================================================
    // MARK: - Single Line Assembly
    // =========================================================================

    /// Assembles a single line of assembly code.
    ///
    /// - Parameters:
    ///   - line: The assembly source line.
    ///   - address: The address to assemble at (overrides PC if provided).
    /// - Returns: The assembly result.
    /// - Throws: AssemblerError on failure.
    public func assembleLine(_ line: String, at address: UInt16? = nil) throws -> AssemblyResult {
        if let addr = address {
            pc = addr
        }

        let parsed = parseLine(line)

        // Handle label if present
        var definedLabel: String? = nil
        if let label = parsed.label {
            try symbols.define(label, value: pc)
            definedLabel = label
        }

        // No instruction? Return empty result (label-only line or comment)
        guard let mnemonic = parsed.mnemonic else {
            return AssemblyResult(bytes: [], address: pc, sourceLine: line, label: definedLabel)
        }

        let upperMnemonic = mnemonic.uppercased()

        // Check for pseudo-ops
        if let pseudoResult = try handlePseudoOp(upperMnemonic, operand: parsed.operand, line: line, label: definedLabel) {
            return pseudoResult
        }

        // Regular instruction
        let bytes = try assembleInstruction(upperMnemonic, operand: parsed.operand)
        let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: definedLabel)
        pc = pc &+ UInt16(bytes.count)
        return result
    }

    // =========================================================================
    // MARK: - Multi-Line Assembly
    // =========================================================================

    /// Assembles multiple lines of source code.
    ///
    /// This method performs two passes:
    /// 1. First pass: Collect all label addresses
    /// 2. Second pass: Assemble with resolved labels
    ///
    /// - Parameter source: The assembly source code.
    /// - Returns: Array of assembly results for each line.
    /// - Throws: AssemblerError on failure.
    public func assemble(_ source: String) throws -> [AssemblyResult] {
        let lines = source.components(separatedBy: .newlines)

        // First pass: collect labels
        reset()
        firstPass = true
        for line in lines {
            _ = try? assembleLine(line)
        }

        // Check for unresolved forward references
        let unresolved = symbols.unresolvedReferences
        if !unresolved.isEmpty && !firstPass {
            throw AssemblerError.undefinedLabel(unresolved.first!)
        }

        // Second pass: generate code
        // Keep the symbols from first pass, just reset PC
        pc = 0
        firstPass = false

        var results: [AssemblyResult] = []
        for line in lines {
            let result = try assembleLine(line)
            if !result.bytes.isEmpty || result.label != nil {
                results.append(result)
            }
        }

        return results
    }

    // =========================================================================
    // MARK: - Line Parsing
    // =========================================================================

    /// Parsed components of an assembly line.
    private struct ParsedLine {
        var label: String?
        var mnemonic: String?
        var operand: String?
        var comment: String?
    }

    /// Parses an assembly source line into its components.
    private func parseLine(_ line: String) -> ParsedLine {
        var result = ParsedLine()

        // Remove comment
        var workLine = line
        if let commentIndex = line.firstIndex(of: ";") {
            result.comment = String(line[commentIndex...])
            workLine = String(line[..<commentIndex])
        }

        workLine = workLine.trimmingCharacters(in: .whitespaces)
        guard !workLine.isEmpty else { return result }

        // Check for label (starts at column 0 or ends with :)
        var parts = workLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        if !parts.isEmpty {
            let firstPart = String(parts[0])

            // Label ends with colon
            if firstPart.hasSuffix(":") {
                result.label = String(firstPart.dropLast())
                parts = parts.count > 1 ?
                    parts[1].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true) : []
            }
            // Label at start (no leading whitespace, not a mnemonic)
            else if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !isMnemonic(firstPart) && !isPseudoOp(firstPart) {
                result.label = firstPart
                parts = parts.count > 1 ?
                    parts[1].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true) : []
            }
        }

        // Mnemonic
        if !parts.isEmpty {
            result.mnemonic = String(parts[0])
            // Operand is everything after the mnemonic
            if parts.count > 1 {
                result.operand = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        return result
    }

    private func isMnemonic(_ str: String) -> Bool {
        OpcodeTable.allMnemonics.contains(str.uppercased())
    }

    private func isPseudoOp(_ str: String) -> Bool {
        let pseudoOps: Set<String> = ["ORG", "EQU", "=", "DB", "BYTE", "DFB", "DW", "WORD", "DFW",
                                       "DS", "BLOCK", "END", "HEX", "ASC", "DCI"]
        return pseudoOps.contains(str.uppercased())
    }

    // =========================================================================
    // MARK: - Pseudo-Op Handling
    // =========================================================================

    /// Handles pseudo-ops (assembler directives).
    ///
    /// - Returns: AssemblyResult if this is a pseudo-op, nil otherwise.
    private func handlePseudoOp(_ mnemonic: String, operand: String?, line: String, label: String?) throws -> AssemblyResult? {
        switch mnemonic {
        case "ORG", "*":
            // Set origin (program counter)
            guard let op = operand else {
                throw AssemblerError.invalidPseudoOp("ORG requires an address")
            }
            let parser = ExpressionParser(symbols: symbols, currentPC: pc)
            let value = try parser.evaluate(op)
            pc = UInt16(truncatingIfNeeded: value)
            return AssemblyResult(bytes: [], address: pc, sourceLine: line, label: label)

        case "EQU", "=":
            // Define symbol value
            guard let labelName = label else {
                throw AssemblerError.invalidPseudoOp("EQU requires a label")
            }
            guard let op = operand else {
                throw AssemblerError.invalidPseudoOp("EQU requires a value")
            }
            // Remove the auto-defined label (at PC), redefine with expression value
            symbols.clear() // Note: This is simplified - a real impl would handle this better
            let parser = ExpressionParser(symbols: symbols, currentPC: pc)
            let value = try parser.evaluate(op)
            try symbols.define(labelName, value: UInt16(truncatingIfNeeded: value))
            return AssemblyResult(bytes: [], address: pc, sourceLine: line, label: labelName)

        case "DB", "BYTE", "DFB":
            // Define bytes
            let bytes = try parseByteList(operand ?? "")
            let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: label)
            pc = pc &+ UInt16(bytes.count)
            return result

        case "DW", "WORD", "DFW":
            // Define words (16-bit, little-endian)
            let words = try parseWordList(operand ?? "")
            var bytes: [UInt8] = []
            for word in words {
                bytes.append(UInt8(word & 0xFF))
                bytes.append(UInt8((word >> 8) & 0xFF))
            }
            let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: label)
            pc = pc &+ UInt16(bytes.count)
            return result

        case "DS", "BLOCK":
            // Define storage (reserve bytes)
            guard let op = operand else {
                throw AssemblerError.invalidPseudoOp("DS requires a size")
            }
            let parser = ExpressionParser(symbols: symbols, currentPC: pc)
            let size = try parser.evaluate(op)
            let bytes = [UInt8](repeating: 0, count: max(0, size))
            let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: label)
            pc = pc &+ UInt16(bytes.count)
            return result

        case "HEX":
            // Hex string without $ prefix
            let bytes = try parseHexString(operand ?? "")
            let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: label)
            pc = pc &+ UInt16(bytes.count)
            return result

        case "ASC":
            // ASCII string
            let bytes = try parseAsciiString(operand ?? "")
            let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: label)
            pc = pc &+ UInt16(bytes.count)
            return result

        case "DCI":
            // ASCII string with last byte having high bit set
            var bytes = try parseAsciiString(operand ?? "")
            if !bytes.isEmpty {
                bytes[bytes.count - 1] |= 0x80
            }
            let result = AssemblyResult(bytes: bytes, address: pc, sourceLine: line, label: label)
            pc = pc &+ UInt16(bytes.count)
            return result

        case "END":
            // End of assembly
            return AssemblyResult(bytes: [], address: pc, sourceLine: line, label: label)

        default:
            return nil
        }
    }

    /// Parses a comma-separated list of byte values.
    private func parseByteList(_ operand: String) throws -> [UInt8] {
        let parser = ExpressionParser(symbols: symbols, currentPC: pc)
        var bytes: [UInt8] = []

        for part in operand.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)

            // String literal
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
                let quote = trimmed.first!
                let content = trimmed.dropFirst()
                for char in content {
                    if char == quote { break }
                    bytes.append(char.asciiValue ?? 0)
                }
            } else {
                let value = try parser.evaluate(trimmed)
                if value < -128 || value > 255 {
                    throw AssemblerError.valueOutOfRange("byte", value, -128, 255)
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            }
        }

        return bytes
    }

    /// Parses a comma-separated list of word values.
    private func parseWordList(_ operand: String) throws -> [UInt16] {
        let parser = ExpressionParser(symbols: symbols, currentPC: pc)
        var words: [UInt16] = []

        for part in operand.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let value = try parser.evaluate(trimmed)
            if value < -32768 || value > 65535 {
                throw AssemblerError.valueOutOfRange("word", value, -32768, 65535)
            }
            words.append(UInt16(truncatingIfNeeded: value))
        }

        return words
    }

    /// Parses a hex string (e.g., "A9008D00D4").
    private func parseHexString(_ operand: String) throws -> [UInt8] {
        let hex = operand.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []

        var i = hex.startIndex
        while i < hex.endIndex {
            let nextIndex = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteStr = String(hex[i..<nextIndex])
            guard let byte = UInt8(byteStr, radix: 16) else {
                throw AssemblerError.invalidExpression("Invalid hex byte '\(byteStr)'")
            }
            bytes.append(byte)
            i = nextIndex
        }

        return bytes
    }

    /// Parses an ASCII string literal.
    private func parseAsciiString(_ operand: String) throws -> [UInt8] {
        let trimmed = operand.trimmingCharacters(in: .whitespaces)
        var bytes: [UInt8] = []

        // Handle quoted string
        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            let quote = trimmed.first!
            var i = trimmed.index(after: trimmed.startIndex)
            while i < trimmed.endIndex && trimmed[i] != quote {
                bytes.append(trimmed[i].asciiValue ?? 0)
                i = trimmed.index(after: i)
            }
        } else {
            // Unquoted - just convert characters
            for char in trimmed {
                bytes.append(char.asciiValue ?? 0)
            }
        }

        return bytes
    }

    // =========================================================================
    // MARK: - Instruction Assembly
    // =========================================================================

    /// Assembles a single instruction.
    private func assembleInstruction(_ mnemonic: String, operand: String?) throws -> [UInt8] {
        // Parse the operand to determine addressing mode
        let parsedOperand = try parseOperand(operand, mnemonic: mnemonic)

        // Get available addressing modes for this mnemonic
        let availableModes = OpcodeTable.opcodesFor(mnemonic: mnemonic)
        guard !availableModes.isEmpty else {
            throw AssemblerError.invalidInstruction(mnemonic)
        }

        // Try to find a matching opcode
        var mode = parsedOperand.mode
        let value = parsedOperand.value

        // Handle zero page optimization: if absolute but value fits in ZP, try ZP mode
        if mode == .absolute && value <= 0xFF {
            if availableModes[.zeroPage] != nil {
                mode = .zeroPage
            }
        }
        if mode == .absoluteX && value <= 0xFF {
            if availableModes[.zeroPageX] != nil {
                mode = .zeroPageX
            }
        }
        if mode == .absoluteY && value <= 0xFF {
            if availableModes[.zeroPageY] != nil {
                mode = .zeroPageY
            }
        }

        // Look up the opcode - try alternate modes if the exact mode isn't available
        var finalOpcode = availableModes[mode]

        if finalOpcode == nil {
            // e.g., for branches, relative mode is used
            if OpcodeTable.isBranch(mnemonic) && availableModes[.relative] != nil {
                mode = .relative
                finalOpcode = availableModes[mode]
            }
        }

        guard let opcode = finalOpcode else {
            throw AssemblerError.invalidAddressingMode(mnemonic, operand ?? "(none)")
        }

        // Build the instruction bytes
        var bytes: [UInt8] = [opcode]

        switch mode {
        case .implied, .accumulator:
            // No operand bytes
            break

        case .immediate, .zeroPage, .zeroPageX, .zeroPageY,
             .indexedIndirectX, .indirectIndexedY:
            // One operand byte
            if value < -128 || value > 255 {
                throw AssemblerError.valueOutOfRange("operand", value, -128, 255)
            }
            bytes.append(UInt8(truncatingIfNeeded: value))

        case .absolute, .absoluteX, .absoluteY, .indirect:
            // Two operand bytes (little-endian)
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8((value >> 8) & 0xFF))

        case .relative:
            // Calculate relative offset
            let targetAddr = value
            let nextPC = Int(pc) + 2  // PC after this instruction
            let offset = targetAddr - nextPC

            if offset < -128 || offset > 127 {
                throw AssemblerError.branchOutOfRange(operand ?? "target", offset)
            }
            bytes.append(UInt8(bitPattern: Int8(offset)))

        case .unknown:
            // Unknown addressing mode - should not happen during assembly
            throw AssemblerError.invalidAddressingMode(operand ?? "", "unknown")
        }

        return bytes
    }

    /// Parses an operand string into a ParsedOperand.
    private func parseOperand(_ operand: String?, mnemonic: String) throws -> ParsedOperand {
        guard let operand = operand, !operand.isEmpty else {
            return .none
        }

        let trimmed = operand.trimmingCharacters(in: .whitespaces).uppercased()
        let parser = ExpressionParser(symbols: symbols, currentPC: pc)

        // Accumulator: "A"
        if trimmed == "A" {
            return .accumulator
        }

        // Immediate: "#value"
        if trimmed.hasPrefix("#") {
            let expr = String(trimmed.dropFirst())
            let value = try parser.evaluate(expr)
            return .immediate(value)
        }

        // Indirect modes: ($xx,X) or ($xx),Y or ($xxxx)
        if trimmed.hasPrefix("(") {
            return try parseIndirectOperand(trimmed, parser: parser)
        }

        // Indexed modes: addr,X or addr,Y
        if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",", maxSplits: 1)
            let addrExpr = String(parts[0])
            let index = String(parts[1]).trimmingCharacters(in: .whitespaces)

            let value = try parser.evaluate(addrExpr)

            if index == "X" {
                return value <= 0xFF ? .zeroPageX(value) : .absoluteX(value)
            } else if index == "Y" {
                return value <= 0xFF ? .zeroPageY(value) : .absoluteY(value)
            } else {
                throw AssemblerError.invalidOperand(operand)
            }
        }

        // Branch instruction - operand is target address
        if OpcodeTable.isBranch(mnemonic) {
            let value = try parser.evaluate(trimmed)
            return .relative(value)
        }

        // Plain address or value
        let value = try parser.evaluate(trimmed)
        return value <= 0xFF ? .zeroPage(value) : .absolute(value)
    }

    /// Parses indirect operand modes.
    private func parseIndirectOperand(_ operand: String, parser: ExpressionParser) throws -> ParsedOperand {
        var work = operand.trimmingCharacters(in: .whitespaces)

        // Must start with (
        guard work.hasPrefix("(") else {
            throw AssemblerError.invalidOperand(operand)
        }
        work = String(work.dropFirst())

        // Check for ),Y pattern (indirect indexed)
        if work.contains("),Y") {
            let addrExpr = String(work.split(separator: ")")[0])
            let value = try parser.evaluate(addrExpr)
            if value > 0xFF {
                throw AssemblerError.valueOutOfRange("indirect", value, 0, 255)
            }
            return .indirectIndexed(value)
        }

        // Check for ,X) pattern (indexed indirect)
        if work.contains(",X)") {
            let addrExpr = String(work.split(separator: ",")[0])
            let value = try parser.evaluate(addrExpr)
            if value > 0xFF {
                throw AssemblerError.valueOutOfRange("indirect", value, 0, 255)
            }
            return .indexedIndirect(value)
        }

        // Plain indirect: (addr)
        guard work.hasSuffix(")") else {
            throw AssemblerError.invalidOperand(operand)
        }
        let addrExpr = String(work.dropLast())
        let value = try parser.evaluate(addrExpr)
        return .indirect(value)
    }
}

// =============================================================================
// MARK: - Interactive Assembly Mode
// =============================================================================

/// Interactive assembly mode for line-by-line assembly.
///
/// This class manages an interactive assembly session where users enter
/// one instruction at a time, similar to monitor-style assembly.
///
/// Usage:
///
///     let interactive = InteractiveAssembler(startAddress: 0x0600)
///
///     // Assemble line
///     let result = try interactive.assembleLine("LDA #$00")
///     print(result.formattedResult)  // "$0600: A9 00     LDA #$00"
///
///     // Get current address for prompt
///     print(interactive.currentAddress)  // 0x0602
///
public final class InteractiveAssembler: @unchecked Sendable {
    private let assembler: Assembler

    /// The current assembly address.
    public var currentAddress: UInt16 {
        assembler.currentPC
    }

    /// Initializes the interactive assembler.
    ///
    /// - Parameter startAddress: The starting assembly address.
    public init(startAddress: UInt16) {
        self.assembler = Assembler(startAddress: startAddress)
    }

    /// Assembles a single line and returns a formatted result.
    ///
    /// - Parameter line: The assembly instruction.
    /// - Returns: Assembly result with formatted output.
    /// - Throws: AssemblerError on failure.
    public func assembleLine(_ line: String) throws -> AssemblyResult {
        try assembler.assembleLine(line)
    }

    /// Formats an assembly result for display.
    ///
    /// - Parameter result: The assembly result.
    /// - Returns: Formatted string like "$0600: A9 00     LDA #$00"
    public func format(_ result: AssemblyResult) -> String {
        let addrStr = String(format: "$%04X", result.address)
        let bytesStr = result.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let paddedBytes = bytesStr.padding(toLength: 11, withPad: " ", startingAt: 0)
        return "\(addrStr): \(paddedBytes) \(result.sourceLine)"
    }

    /// Resets the assembler to a new address.
    public func reset(to address: UInt16) {
        assembler.reset(startAddress: address)
    }

    /// Gets the symbol table for label access.
    public var symbols: SymbolTable {
        assembler.symbols
    }
}
