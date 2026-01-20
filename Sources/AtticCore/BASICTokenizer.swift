// =============================================================================
// BASICTokenizer.swift - Atari BASIC Lexer and Tokenizer
// =============================================================================
//
// This file implements the lexer and tokenizer for Atari BASIC. The process
// converts human-readable BASIC source code into the tokenized binary format
// that Atari BASIC stores in memory.
//
// The tokenization process has two stages:
//
// 1. Lexical Analysis (Lexer)
//    - Breaks the input into lexical tokens (keywords, identifiers, etc.)
//    - Handles abbreviations (e.g., "PR." for "PRINT")
//    - Recognizes string literals, numeric literals, operators
//
// 2. Token Encoding (Tokenizer)
//    - Converts lexical tokens to binary token bytes
//    - Manages variable references
//    - Builds the final tokenized line format
//
// The tokenizer is stateless - it receives the current variable list as input
// and returns any new variables that need to be added.
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Lexical Token Types
// =============================================================================

/// A lexical token produced by the lexer.
///
/// These represent the syntactic elements found in BASIC source code.
public enum LexToken: Sendable, Equatable {
    /// A line number at the start of a line.
    case lineNumber(Int)

    /// A BASIC keyword (statement or function).
    case keyword(String)

    /// A variable or identifier name.
    case identifier(String)

    /// A numeric literal (integer or floating-point).
    case numericLiteral(String)

    /// A string literal (including quotes in source, content only here).
    case stringLiteral(String)

    /// An operator symbol (+, -, *, /, etc.).
    case operatorSymbol(String)

    /// Punctuation character (comma, semicolon, etc.).
    case punctuation(Character)

    /// A REM comment (everything after REM to end of line).
    case comment(String)

    /// End of line.
    case endOfLine
}

// =============================================================================
// MARK: - Tokenizer Errors
// =============================================================================

/// Errors that can occur during tokenization.
public enum BASICTokenizerError: Error, Sendable, Equatable {
    /// Syntax error at a specific column.
    case syntaxError(column: Int, message: String, suggestion: String?)

    /// Unknown keyword.
    case unknownKeyword(column: Int, word: String, suggestion: String?)

    /// Unterminated string literal.
    case unterminatedString(column: Int)

    /// Invalid line number.
    case invalidLineNumber(value: Int)

    /// Line too long when tokenized.
    case lineTooLong(tokenizedLength: Int)

    /// Too many variables.
    case tooManyVariables(count: Int)

    /// Invalid character in source.
    case invalidCharacter(column: Int, character: Character)

    /// A user-friendly error message.
    public var message: String {
        switch self {
        case .syntaxError(let col, let msg, _):
            return "Syntax error at column \(col): \(msg)"
        case .unknownKeyword(let col, let word, let suggestion):
            var msg = "Unknown keyword '\(word)' at column \(col)"
            if let suggestion = suggestion {
                msg += ". Did you mean '\(suggestion)'?"
            }
            return msg
        case .unterminatedString(let col):
            return "Unterminated string literal starting at column \(col)"
        case .invalidLineNumber(let value):
            return "Invalid line number \(value). Must be 0-32767"
        case .lineTooLong(let length):
            return "Line too long (\(length) bytes). Maximum is 256 bytes"
        case .tooManyVariables(let count):
            return "Too many variables (\(count)). Maximum is 128"
        case .invalidCharacter(let col, let char):
            return "Invalid character '\(char)' at column \(col)"
        }
    }

    /// A suggestion for fixing the error.
    public var suggestion: String? {
        switch self {
        case .syntaxError(_, _, let sug): return sug
        case .unknownKeyword(_, _, let sug): return sug
        case .unterminatedString: return "Add closing quote"
        case .invalidLineNumber: return "Use a line number between 0 and 32767"
        case .lineTooLong: return "Split into multiple lines"
        case .tooManyVariables: return "Reduce the number of variables"
        case .invalidCharacter: return nil
        }
    }
}

// =============================================================================
// MARK: - Lexer
// =============================================================================

/// The BASIC lexer breaks source code into lexical tokens.
///
/// The lexer is the first stage of tokenization. It handles:
/// - Keyword recognition (including abbreviations like "PR." for "PRINT")
/// - String literal parsing (quoted strings)
/// - Numeric literal parsing (integers, decimals, scientific notation)
/// - Operator and punctuation recognition
/// - Comment handling (REM statements)
public struct BASICLexer: Sendable {
    /// The source code being lexed.
    private let source: String

    /// Current position in the source.
    private var index: String.Index

    /// Current column number (1-based, for error reporting).
    private var column: Int

    /// Creates a lexer for the given source code.
    ///
    /// - Parameter source: The BASIC source line to lex.
    public init(source: String) {
        self.source = source
        self.index = source.startIndex
        self.column = 1
    }

    // =========================================================================
    // MARK: - Main Lexing
    // =========================================================================

    /// Lexes the entire source line into tokens.
    ///
    /// - Returns: An array of lexical tokens.
    /// - Throws: `BASICTokenizerError` if invalid syntax is encountered.
    public mutating func lex() throws -> [LexToken] {
        var tokens: [LexToken] = []

        skipWhitespace()

        // Check for line number at start
        if let lineNum = tryLineNumber() {
            tokens.append(.lineNumber(lineNum))
            skipWhitespace()
        }

        // Lex the rest of the line
        while !isAtEnd {
            skipWhitespace()
            if isAtEnd { break }

            let token = try lexToken()
            tokens.append(token)

            // If we hit a REM comment, stop lexing (rest is comment)
            if case .comment = token {
                break
            }
        }

        tokens.append(.endOfLine)
        return tokens
    }

    /// Lexes a single token.
    private mutating func lexToken() throws -> LexToken {
        let startColumn = column

        // String literal
        if currentChar == "\"" {
            return try lexStringLiteral()
        }

        // Numeric literal
        if currentChar?.isNumber == true || (currentChar == "." && peek()?.isNumber == true) {
            return lexNumericLiteral()
        }

        // Hexadecimal literal ($XX)
        if currentChar == "$" && peek()?.isHexDigit == true {
            return lexHexLiteral()
        }

        // Word (keyword or identifier)
        if currentChar?.isLetter == true {
            return try lexWord()
        }

        // Operators and punctuation
        if let op = tryOperator() {
            return .operatorSymbol(op)
        }

        if let punct = tryPunctuation() {
            return .punctuation(punct)
        }

        // Unknown character
        let char = currentChar ?? "?"
        throw BASICTokenizerError.invalidCharacter(column: startColumn, character: char)
    }

    // =========================================================================
    // MARK: - Token Lexing Helpers
    // =========================================================================

    /// Tries to lex a line number at the start of a line.
    private mutating func tryLineNumber() -> Int? {
        guard currentChar?.isNumber == true else { return nil }

        var numStr = ""
        while let c = currentChar, c.isNumber {
            numStr.append(c)
            advance()
        }

        return Int(numStr)
    }

    /// Lexes a string literal.
    private mutating func lexStringLiteral() throws -> LexToken {
        let startColumn = column
        advance()  // Skip opening quote

        var content = ""
        while !isAtEnd && currentChar != "\"" {
            content.append(currentChar!)
            advance()
        }

        if isAtEnd {
            throw BASICTokenizerError.unterminatedString(column: startColumn)
        }

        advance()  // Skip closing quote
        return .stringLiteral(content)
    }

    /// Lexes a numeric literal.
    private mutating func lexNumericLiteral() -> LexToken {
        var numStr = ""

        // Integer part
        while let c = currentChar, c.isNumber {
            numStr.append(c)
            advance()
        }

        // Decimal part
        if currentChar == "." {
            numStr.append(".")
            advance()
            while let c = currentChar, c.isNumber {
                numStr.append(c)
                advance()
            }
        }

        // Exponent part
        if currentChar == "E" || currentChar == "e" {
            numStr.append("E")
            advance()
            if currentChar == "+" || currentChar == "-" {
                numStr.append(currentChar!)
                advance()
            }
            while let c = currentChar, c.isNumber {
                numStr.append(c)
                advance()
            }
        }

        return .numericLiteral(numStr)
    }

    /// Lexes a hexadecimal literal ($XX).
    private mutating func lexHexLiteral() -> LexToken {
        var numStr = "$"
        advance()  // Skip $

        while let c = currentChar, c.isHexDigit {
            numStr.append(c)
            advance()
        }

        return .numericLiteral(numStr)
    }

    /// Lexes a word (keyword or identifier).
    private mutating func lexWord() throws -> LexToken {
        var word = ""

        // Collect alphanumeric characters
        while let c = currentChar, c.isLetter || c.isNumber {
            word.append(c)
            advance()
        }

        // Check for abbreviation (period)
        if currentChar == "." {
            word.append(".")
            advance()
        }

        // Check for type suffix ($ for strings)
        if currentChar == "$" {
            word.append("$")
            advance()
        }

        // Check for array indicator (opening paren after variable)
        // Note: We include this in the identifier for array variables
        if currentChar == "(" {
            // Peek ahead - if this looks like a function call or array access
            // we might want to include the paren
            // For now, keep the paren separate and let the tokenizer handle it
        }

        // Try to match as keyword
        let upperWord = word.uppercased().replacingOccurrences(of: ".", with: "")

        // Check for REM - rest of line is a comment
        if upperWord == "REM" || word == "." {
            let comment = String(source[index...]).trimmingCharacters(in: .whitespaces)
            index = source.endIndex  // Consume rest of line
            return .comment(comment)
        }

        // Check for statement keyword
        if let _ = BASICTokenLookup.matchStatement(word) {
            return .keyword(word.uppercased())
        }

        // Check for function keyword
        if let _ = BASICTokenLookup.matchFunction(word) {
            return .keyword(word.uppercased())
        }

        // Check for logical operators
        if BASICTokenLookup.logicalOperators[upperWord] != nil {
            return .keyword(upperWord)
        }

        // Must be an identifier (variable name)
        return .identifier(word)
    }

    /// Tries to match an operator.
    private mutating func tryOperator() -> String? {
        // Try two-character operators first
        if let c1 = currentChar, let c2 = peek() {
            let twoChar = String([c1, c2])
            if BASICTokenLookup.operatorSymbols[twoChar] != nil {
                advance()
                advance()
                return twoChar
            }
        }

        // Try single-character operators
        if let c = currentChar {
            let oneChar = String(c)
            if BASICTokenLookup.operatorSymbols[oneChar] != nil {
                advance()
                return oneChar
            }
        }

        return nil
    }

    /// Tries to match punctuation.
    private mutating func tryPunctuation() -> Character? {
        if let c = currentChar {
            switch c {
            case ",", ";", ":", "#", "(", ")":
                advance()
                return c
            default:
                break
            }
        }
        return nil
    }

    // =========================================================================
    // MARK: - Character Navigation
    // =========================================================================

    /// The current character, or nil if at end.
    private var currentChar: Character? {
        guard index < source.endIndex else { return nil }
        return source[index]
    }

    /// Peeks at the next character without advancing.
    private func peek() -> Character? {
        let nextIndex = source.index(after: index)
        guard nextIndex < source.endIndex else { return nil }
        return source[nextIndex]
    }

    /// Whether we've reached the end of the source.
    private var isAtEnd: Bool {
        index >= source.endIndex
    }

    /// Advances to the next character.
    private mutating func advance() {
        if index < source.endIndex {
            index = source.index(after: index)
            column += 1
        }
    }

    /// Skips whitespace characters.
    private mutating func skipWhitespace() {
        while let c = currentChar, c.isWhitespace {
            advance()
        }
    }
}

// =============================================================================
// MARK: - Character Extensions
// =============================================================================

extension Character {
    /// Whether this character is a hexadecimal digit.
    var isHexDigit: Bool {
        isNumber || ("A"..."F").contains(self) || ("a"..."f").contains(self)
    }
}

// =============================================================================
// MARK: - Tokenized Line Result
// =============================================================================

/// The result of tokenizing a BASIC line.
public struct TokenizedLine: Sendable {
    /// The line number.
    public let lineNumber: UInt16

    /// The tokenized bytes (including header and EOL).
    public let bytes: [UInt8]

    /// New variables that need to be added to the VNT.
    public let newVariables: [BASICVariableName]

    /// Creates a tokenized line result.
    public init(lineNumber: UInt16, bytes: [UInt8], newVariables: [BASICVariableName]) {
        self.lineNumber = lineNumber
        self.bytes = bytes
        self.newVariables = newVariables
    }

    /// The total length of this line in bytes.
    public var length: Int {
        bytes.count
    }
}

// =============================================================================
// MARK: - Tokenizer
// =============================================================================

/// The BASIC tokenizer converts lexical tokens to binary token bytes.
///
/// The tokenizer is stateless - it receives the current list of variables
/// and returns the tokenized bytes plus any new variables that need to be
/// added to the Variable Name Table.
public struct BASICTokenizer: Sendable {

    /// Creates a new tokenizer instance.
    public init() {}

    // =========================================================================
    // MARK: - Main Tokenization
    // =========================================================================

    /// Tokenizes a BASIC source line.
    ///
    /// - Parameters:
    ///   - source: The BASIC source code line.
    ///   - existingVariables: Variables already defined in the program.
    /// - Returns: The tokenized line with new variables.
    /// - Throws: `BASICTokenizerError` if tokenization fails.
    public func tokenize(
        _ source: String,
        existingVariables: [BASICVariable]
    ) throws -> TokenizedLine {
        // Lex the source into tokens
        var lexer = BASICLexer(source: source)
        let lexTokens = try lexer.lex()

        // Extract line number
        guard case .lineNumber(let lineNum) = lexTokens.first else {
            throw BASICTokenizerError.syntaxError(
                column: 1,
                message: "Line must start with a line number",
                suggestion: "Add a line number (e.g., 10 PRINT \"HELLO\")"
            )
        }

        // Validate line number
        guard lineNum >= 0 && lineNum <= BASICMemoryDefaults.maxLineNumber else {
            throw BASICTokenizerError.invalidLineNumber(value: lineNum)
        }

        // Convert lexical tokens to binary
        var context = TokenizerContext(existingVariables: existingVariables)
        let contentTokens = Array(lexTokens.dropFirst())  // Skip line number

        let tokenizedContent = try tokenizeTokens(contentTokens, context: &context)

        // Build the full line
        var bytes: [UInt8] = []

        // Line number (little-endian)
        bytes.append(UInt8(lineNum & 0xFF))
        bytes.append(UInt8(lineNum >> 8))

        // Line length (will be filled in)
        let lengthIndex = bytes.count
        bytes.append(0)  // Placeholder

        // Tokenized content
        bytes.append(contentsOf: tokenizedContent)

        // End of line marker
        bytes.append(BASICLineFormat.endOfLineMarker)

        // Fill in length
        let totalLength = bytes.count
        guard totalLength <= BASICMemoryDefaults.maxLineLength else {
            throw BASICTokenizerError.lineTooLong(tokenizedLength: totalLength)
        }
        bytes[lengthIndex] = UInt8(totalLength)

        return TokenizedLine(
            lineNumber: UInt16(lineNum),
            bytes: bytes,
            newVariables: context.newVariables
        )
    }

    // =========================================================================
    // MARK: - Token Processing
    // =========================================================================

    /// Context for tracking state during tokenization.
    private struct TokenizerContext {
        /// All variables (existing + new).
        var allVariables: [BASICVariable]

        /// New variables found during this tokenization.
        var newVariables: [BASICVariableName] = []

        /// Whether we're at the start of a statement.
        var atStatementStart: Bool = true

        /// Whether we're in an assignment (after = ).
        var inAssignment: Bool = false

        init(existingVariables: [BASICVariable]) {
            self.allVariables = existingVariables
        }

        /// Gets or creates a variable, returning its token byte.
        mutating func getVariableToken(for name: BASICVariableName) throws -> UInt8 {
            // Look for existing variable
            if let existing = BASICVariableTable.findVariable(named: name, in: allVariables) {
                return existing.tokenByte
            }

            // Create new variable
            let index = UInt8(allVariables.count)
            guard index <= BASICSpecialToken.maxVariableIndex else {
                throw BASICTokenizerError.tooManyVariables(count: Int(index) + 1)
            }

            let newVar = BASICVariable(name: name, index: index)
            allVariables.append(newVar)
            newVariables.append(name)

            return newVar.tokenByte
        }
    }

    /// Tokenizes an array of lexical tokens.
    private func tokenizeTokens(
        _ tokens: [LexToken],
        context: inout TokenizerContext
    ) throws -> [UInt8] {
        var result: [UInt8] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            switch token {
            case .lineNumber:
                // Shouldn't appear here (already extracted)
                break

            case .keyword(let kw):
                let bytes = try tokenizeKeyword(kw, context: &context)
                result.append(contentsOf: bytes)
                context.atStatementStart = false

            case .identifier(let name):
                let bytes = try tokenizeIdentifier(name, context: &context)
                result.append(contentsOf: bytes)
                context.atStatementStart = false

            case .numericLiteral(let lit):
                let bytes = tokenizeNumericLiteral(lit)
                result.append(contentsOf: bytes)
                context.atStatementStart = false

            case .stringLiteral(let str):
                let bytes = tokenizeStringLiteral(str)
                result.append(contentsOf: bytes)
                context.atStatementStart = false

            case .operatorSymbol(let op):
                let bytes = tokenizeOperator(op, context: &context)
                result.append(contentsOf: bytes)

            case .punctuation(let p):
                let bytes = tokenizePunctuation(p, context: &context)
                result.append(contentsOf: bytes)

            case .comment(let text):
                // REM token followed by comment text as string
                result.append(BASICStatementToken.rem.rawValue)
                // Comment text stored as raw bytes (not as string token)
                for char in text {
                    if let ascii = char.asciiValue {
                        result.append(ascii)
                    }
                }
                context.atStatementStart = false

            case .endOfLine:
                // Handled by caller
                break
            }

            index += 1
        }

        return result
    }

    // =========================================================================
    // MARK: - Individual Token Encoding
    // =========================================================================

    /// Tokenizes a keyword.
    private func tokenizeKeyword(
        _ keyword: String,
        context: inout TokenizerContext
    ) throws -> [UInt8] {
        let upper = keyword.uppercased()

        // Check for statement token
        if let statementToken = BASICTokenLookup.matchStatement(upper) {
            // Handle special cases
            if statementToken == .letStatement && !context.atStatementStart {
                // LET is often implied - but if explicitly stated, use it
                return [statementToken.rawValue]
            }
            context.atStatementStart = false
            return [statementToken.rawValue]
        }

        // Check for function token
        if let functionToken = BASICTokenLookup.matchFunction(upper) {
            return [functionToken.rawValue]
        }

        // Check for logical/keyword operators
        if let opToken = BASICTokenLookup.logicalOperators[upper] {
            return [opToken.rawValue]
        }

        // Unknown keyword
        let suggestion = BASICTokenLookup.suggestKeyword(upper)
        throw BASICTokenizerError.unknownKeyword(column: 0, word: keyword, suggestion: suggestion)
    }

    /// Tokenizes an identifier (variable reference).
    private func tokenizeIdentifier(
        _ identifier: String,
        context: inout TokenizerContext
    ) throws -> [UInt8] {
        // Check if this is actually a keyword we missed
        if let _ = BASICTokenLookup.matchStatement(identifier) {
            return try tokenizeKeyword(identifier, context: &context)
        }
        if let _ = BASICTokenLookup.matchFunction(identifier) {
            return try tokenizeKeyword(identifier, context: &context)
        }

        // Parse as variable name
        guard let varName = BASICVariableName.parse(identifier) else {
            throw BASICTokenizerError.syntaxError(
                column: 0,
                message: "Invalid variable name '\(identifier)'",
                suggestion: "Variable names must start with a letter"
            )
        }

        // Get or create the variable
        let tokenByte = try context.getVariableToken(for: varName)

        // If this is at statement start, add implied LET
        var bytes: [UInt8] = []
        if context.atStatementStart {
            bytes.append(BASICStatementToken.impliedLet.rawValue)
        }
        bytes.append(tokenByte)

        return bytes
    }

    /// Tokenizes a numeric literal.
    private func tokenizeNumericLiteral(_ literal: String) -> [UInt8] {
        guard let encoding = BASICNumericEncoding.parse(literal) else {
            // Fallback to zero if parsing fails
            return BASICNumericEncoding.smallInt(0).tokenBytes
        }
        return encoding.tokenBytes
    }

    /// Tokenizes a string literal.
    private func tokenizeStringLiteral(_ content: String) -> [UInt8] {
        var bytes: [UInt8] = [BASICSpecialToken.stringPrefix]

        // Length byte (limited to 255)
        let length = min(content.count, 255)
        bytes.append(UInt8(length))

        // String content as ATASCII
        for (i, char) in content.enumerated() {
            if i >= 255 { break }
            if let ascii = char.asciiValue {
                bytes.append(ascii)
            } else {
                bytes.append(0x3F)  // '?' for non-ASCII
            }
        }

        return bytes
    }

    /// Tokenizes an operator.
    private func tokenizeOperator(
        _ op: String,
        context: inout TokenizerContext
    ) -> [UInt8] {
        // Handle = specially based on context
        if op == "=" {
            if context.atStatementStart || !context.inAssignment {
                context.inAssignment = true
                return [BASICOperatorToken.equalsAssign.rawValue]
            } else {
                return [BASICOperatorToken.equalsCompare.rawValue]
            }
        }

        if let token = BASICTokenLookup.matchOperator(op) {
            return [token.rawValue]
        }

        // Unknown operator - shouldn't happen if lexer is correct
        return []
    }

    /// Tokenizes punctuation.
    private func tokenizePunctuation(
        _ punct: Character,
        context: inout TokenizerContext
    ) -> [UInt8] {
        switch punct {
        case ",":
            return [BASICOperatorToken.comma.rawValue]
        case ";":
            return [BASICOperatorToken.semicolon.rawValue]
        case ":":
            context.atStatementStart = true
            context.inAssignment = false
            return [BASICOperatorToken.colon.rawValue]
        case "#":
            return [BASICOperatorToken.pound.rawValue]
        case "(":
            return [BASICOperatorToken.leftParen.rawValue]
        case ")":
            return [BASICOperatorToken.rightParen.rawValue]
        default:
            return []
        }
    }
}
