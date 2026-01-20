// =============================================================================
// BASICTokenizerTests.swift - Unit Tests for BASIC Tokenizer
// =============================================================================
//
// Tests for the BASIC tokenizer, including:
// - BCD floating-point conversion
// - Lexer token recognition
// - Tokenizer output validation
// - Variable table management
// - Error handling
//
// =============================================================================

import XCTest
@testable import AtticCore

final class BASICTokenizerTests: XCTestCase {

    // =========================================================================
    // MARK: - BCD Float Tests
    // =========================================================================

    func testBCDZero() {
        let bcd = BCDFloat.encode(0)
        XCTAssertEqual(bcd.bytes, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertTrue(bcd.isZero)
        XCTAssertEqual(bcd.decode(), 0.0)
    }

    func testBCDOne() {
        let bcd = BCDFloat.encode(1)
        XCTAssertEqual(bcd.bytes[0] & 0x7F, 0x40)  // Exponent = 0 + 64 = 64 = $40
        XCTAssertEqual(bcd.bytes[1], 0x10)  // First digit is 1
        XCTAssertFalse(bcd.isNegative)

        let decoded = bcd.decode()
        XCTAssertEqual(decoded, 1.0, accuracy: 0.0001)
    }

    func testBCDTen() {
        let bcd = BCDFloat.encode(10)
        // Exponent should be 1 + 64 = 65 = $41
        XCTAssertEqual(bcd.bytes[0] & 0x7F, 0x41)

        let decoded = bcd.decode()
        XCTAssertEqual(decoded, 10.0, accuracy: 0.001)
    }

    func testBCDHundred() {
        let bcd = BCDFloat.encode(100)
        // Exponent should be 2 + 64 = 66 = $42
        XCTAssertEqual(bcd.bytes[0] & 0x7F, 0x42)

        let decoded = bcd.decode()
        XCTAssertEqual(decoded, 100.0, accuracy: 0.01)
    }

    func testBCDNegative() {
        let bcd = BCDFloat.encode(-1)
        XCTAssertTrue(bcd.isNegative)
        XCTAssertEqual(bcd.bytes[0] & 0x80, 0x80)  // Sign bit set

        let decoded = bcd.decode()
        XCTAssertEqual(decoded, -1.0, accuracy: 0.0001)
    }

    func testBCDPi() {
        let bcd = BCDFloat.encode(3.14159)
        let decoded = bcd.decode()
        XCTAssertEqual(decoded, 3.14159, accuracy: 0.00001)
    }

    func testBCDSmallIntOptimization() {
        // Test that small integers can be detected
        let bcd100 = BCDFloat.encode(100)
        XCTAssertEqual(bcd100.asSmallInt(), 100)

        let bcd255 = BCDFloat.encode(255)
        XCTAssertEqual(bcd255.asSmallInt(), 255)

        let bcd256 = BCDFloat.encode(256)
        XCTAssertNil(bcd256.asSmallInt())  // Too large

        let bcdNeg = BCDFloat.encode(-1)
        XCTAssertNil(bcdNeg.asSmallInt())  // Negative

        let bcdFrac = BCDFloat.encode(1.5)
        XCTAssertNil(bcdFrac.asSmallInt())  // Not integer
    }

    func testBCDNumericEncoding() {
        // Small int uses 2 bytes
        let encoding0 = BASICNumericEncoding.forValue(0)
        if case .smallInt(let v) = encoding0 {
            XCTAssertEqual(v, 0)
            XCTAssertEqual(encoding0.byteCount, 2)
        } else {
            XCTFail("Expected smallInt encoding for 0")
        }

        // Large number uses 7 bytes
        let encoding1000 = BASICNumericEncoding.forValue(1000)
        if case .bcdFloat = encoding1000 {
            XCTAssertEqual(encoding1000.byteCount, 7)
        } else {
            XCTFail("Expected bcdFloat encoding for 1000")
        }
    }

    func testBCDParsing() {
        // Integer
        XCTAssertNotNil(BCDFloat.parse("123"))

        // Decimal
        XCTAssertNotNil(BCDFloat.parse("3.14"))

        // Scientific notation
        XCTAssertNotNil(BCDFloat.parse("1E10"))
        XCTAssertNotNil(BCDFloat.parse("2.5E-3"))

        // Hex (Atari convention)
        let hexResult = BCDFloat.parse("$FF")
        XCTAssertNotNil(hexResult)
        if let bcd = hexResult {
            XCTAssertEqual(bcd.decode(), 255.0, accuracy: 0.001)
        }
    }

    // =========================================================================
    // MARK: - Variable Name Tests
    // =========================================================================

    func testVariableNameParsing() {
        // Simple numeric variable
        let x = BASICVariableName.parse("X")
        XCTAssertNotNil(x)
        XCTAssertEqual(x?.name, "X")
        XCTAssertEqual(x?.type, .numeric)

        // String variable
        let aStr = BASICVariableName.parse("A$")
        XCTAssertNotNil(aStr)
        XCTAssertEqual(aStr?.name, "A")
        XCTAssertEqual(aStr?.type, .string)

        // Numeric array
        let arr = BASICVariableName.parse("DATA(")
        XCTAssertNotNil(arr)
        XCTAssertEqual(arr?.name, "DATA")
        XCTAssertEqual(arr?.type, .numericArray)

        // String array
        let strArr = BASICVariableName.parse("NAMES$(")
        XCTAssertNotNil(strArr)
        XCTAssertEqual(strArr?.name, "NAMES")
        XCTAssertEqual(strArr?.type, .stringArray)

        // Long name
        let count = BASICVariableName.parse("COUNT123")
        XCTAssertNotNil(count)
        XCTAssertEqual(count?.name, "COUNT123")
    }

    func testVariableNameEncoding() {
        // Simple variable "X" encodes as 'X' with high bit set
        let x = BASICVariableName(name: "X", type: .numeric)
        let encoded = x.encodeForVNT()
        XCTAssertEqual(encoded, [UInt8(0x58 | 0x80)])  // 'X' = $58, with high bit = $D8

        // String variable "A$" encodes as 'A' with high bit + '$'
        let aStr = BASICVariableName(name: "A", type: .string)
        let encodedStr = aStr.encodeForVNT()
        XCTAssertEqual(encodedStr, [UInt8(0x41 | 0x80), 0x24])  // 'A' | $80, '$'

        // Multi-char variable "ABC"
        let abc = BASICVariableName(name: "ABC", type: .numeric)
        let encodedAbc = abc.encodeForVNT()
        XCTAssertEqual(encodedAbc, [0x41, 0x42, UInt8(0x43 | 0x80)])  // A, B, C|$80
    }

    func testInvalidVariableNames() {
        // Can't start with number
        XCTAssertNil(BASICVariableName.parse("1ABC"))

        // Empty name
        XCTAssertNil(BASICVariableName.parse(""))

        // Just suffix
        XCTAssertNil(BASICVariableName.parse("$"))
    }

    // =========================================================================
    // MARK: - Lexer Tests
    // =========================================================================

    func testLexerLineNumber() throws {
        var lexer = BASICLexer(source: "10 PRINT")
        let tokens = try lexer.lex()

        XCTAssertEqual(tokens.count, 3)  // lineNumber, keyword, endOfLine
        if case .lineNumber(let num) = tokens[0] {
            XCTAssertEqual(num, 10)
        } else {
            XCTFail("Expected lineNumber token")
        }
    }

    func testLexerKeywords() throws {
        var lexer = BASICLexer(source: "10 PRINT GOTO FOR NEXT")
        let tokens = try lexer.lex()

        XCTAssertEqual(tokens.count, 6)  // lineNumber + 4 keywords + endOfLine
        XCTAssertTrue(tokens[1] == .keyword("PRINT"))
        XCTAssertTrue(tokens[2] == .keyword("GOTO"))
        XCTAssertTrue(tokens[3] == .keyword("FOR"))
        XCTAssertTrue(tokens[4] == .keyword("NEXT"))
    }

    func testLexerStringLiteral() throws {
        var lexer = BASICLexer(source: "10 PRINT \"HELLO WORLD\"")
        let tokens = try lexer.lex()

        XCTAssertEqual(tokens.count, 4)  // lineNumber, keyword, string, endOfLine
        if case .stringLiteral(let str) = tokens[2] {
            XCTAssertEqual(str, "HELLO WORLD")
        } else {
            XCTFail("Expected stringLiteral token")
        }
    }

    func testLexerNumericLiterals() throws {
        var lexer = BASICLexer(source: "10 A=123")
        let tokens = try lexer.lex()

        var foundNumeric = false
        for token in tokens {
            if case .numericLiteral(let num) = token {
                XCTAssertEqual(num, "123")
                foundNumeric = true
            }
        }
        XCTAssertTrue(foundNumeric, "Should find numeric literal")
    }

    func testLexerOperators() throws {
        var lexer = BASICLexer(source: "10 A=B+C-D*E/F")
        let tokens = try lexer.lex()

        let operators = tokens.compactMap { token -> String? in
            if case .operatorSymbol(let op) = token {
                return op
            }
            return nil
        }

        XCTAssertTrue(operators.contains("="))
        XCTAssertTrue(operators.contains("+"))
        XCTAssertTrue(operators.contains("-"))
        XCTAssertTrue(operators.contains("*"))
        XCTAssertTrue(operators.contains("/"))
    }

    func testLexerREMComment() throws {
        var lexer = BASICLexer(source: "10 REM THIS IS A COMMENT")
        let tokens = try lexer.lex()

        var foundComment = false
        for token in tokens {
            if case .comment(let text) = token {
                XCTAssertEqual(text, "THIS IS A COMMENT")
                foundComment = true
            }
        }
        XCTAssertTrue(foundComment, "Should find comment")
    }

    func testLexerUnterminatedString() {
        var lexer = BASICLexer(source: "10 PRINT \"HELLO")
        XCTAssertThrowsError(try lexer.lex()) { error in
            if case BASICTokenizerError.unterminatedString = error {
                // Expected
            } else {
                XCTFail("Expected unterminatedString error")
            }
        }
    }

    // =========================================================================
    // MARK: - Tokenizer Tests
    // =========================================================================

    func testTokenizerSimplePrint() throws {
        let tokenizer = BASICTokenizer()
        let result = try tokenizer.tokenize("10 PRINT \"HELLO\"", existingVariables: [])

        XCTAssertEqual(result.lineNumber, 10)
        XCTAssertTrue(result.bytes.count > 0)

        // Check line number in bytes (little-endian)
        XCTAssertEqual(result.bytes[0], 0x0A)  // 10 low byte
        XCTAssertEqual(result.bytes[1], 0x00)  // 10 high byte

        // Check for PRINT token ($20)
        XCTAssertTrue(result.bytes.contains(0x20))

        // Check for string prefix ($0F)
        XCTAssertTrue(result.bytes.contains(0x0F))

        // Check for EOL marker ($16)
        XCTAssertEqual(result.bytes.last, 0x16)
    }

    func testTokenizerVariable() throws {
        let tokenizer = BASICTokenizer()
        let result = try tokenizer.tokenize("10 LET X=5", existingVariables: [])

        // Should have created variable X
        XCTAssertEqual(result.newVariables.count, 1)
        XCTAssertEqual(result.newVariables[0].name, "X")
        XCTAssertEqual(result.newVariables[0].type, .numeric)

        // Check for implied LET token ($36) or explicit LET ($06)
        XCTAssertTrue(result.bytes.contains(0x06) || result.bytes.contains(0x36))

        // Check for variable reference ($80 for first variable)
        XCTAssertTrue(result.bytes.contains(0x80))
    }

    func testTokenizerReuseVariable() throws {
        let tokenizer = BASICTokenizer()

        // First line creates variable X
        let result1 = try tokenizer.tokenize("10 X=5", existingVariables: [])
        XCTAssertEqual(result1.newVariables.count, 1)

        // Second line should reuse variable X
        let existingX = BASICVariable(name: result1.newVariables[0], index: 0)
        let result2 = try tokenizer.tokenize("20 PRINT X", existingVariables: [existingX])
        XCTAssertEqual(result2.newVariables.count, 0)  // No new variables

        // Both should reference $80
        XCTAssertTrue(result1.bytes.contains(0x80))
        XCTAssertTrue(result2.bytes.contains(0x80))
    }

    func testTokenizerInvalidLineNumber() {
        let tokenizer = BASICTokenizer()

        XCTAssertThrowsError(try tokenizer.tokenize("40000 PRINT", existingVariables: [])) { error in
            if case BASICTokenizerError.invalidLineNumber = error {
                // Expected
            } else {
                XCTFail("Expected invalidLineNumber error")
            }
        }
    }

    func testTokenizerNoLineNumber() {
        let tokenizer = BASICTokenizer()

        XCTAssertThrowsError(try tokenizer.tokenize("PRINT \"HELLO\"", existingVariables: [])) { error in
            if case BASICTokenizerError.syntaxError = error {
                // Expected - line must start with line number
            } else {
                XCTFail("Expected syntaxError for missing line number")
            }
        }
    }

    // =========================================================================
    // MARK: - Token Lookup Tests
    // =========================================================================

    func testStatementLookup() {
        // Exact match
        XCTAssertEqual(BASICTokenLookup.matchStatement("PRINT"), .print)
        XCTAssertEqual(BASICTokenLookup.matchStatement("GOTO"), .goto)
        XCTAssertEqual(BASICTokenLookup.matchStatement("FOR"), .forStatement)

        // Case insensitive
        XCTAssertEqual(BASICTokenLookup.matchStatement("print"), .print)
        XCTAssertEqual(BASICTokenLookup.matchStatement("Print"), .print)

        // Abbreviation
        XCTAssertEqual(BASICTokenLookup.matchStatement("PR."), .print)
        XCTAssertEqual(BASICTokenLookup.matchStatement("G."), .goto)

        // Special
        XCTAssertEqual(BASICTokenLookup.matchStatement("?"), .printShort)
    }

    func testFunctionLookup() {
        XCTAssertEqual(BASICTokenLookup.matchFunction("ABS"), .abs)
        XCTAssertEqual(BASICTokenLookup.matchFunction("SIN"), .sin)
        XCTAssertEqual(BASICTokenLookup.matchFunction("PEEK"), .peek)
        XCTAssertEqual(BASICTokenLookup.matchFunction("CHR$"), .chr)
        XCTAssertEqual(BASICTokenLookup.matchFunction("STR$"), .str)
    }

    func testKeywordSuggestion() {
        // Close typos should suggest corrections
        let suggestion1 = BASICTokenLookup.suggestKeyword("PRIMT")
        XCTAssertEqual(suggestion1, "PRINT")

        let suggestion2 = BASICTokenLookup.suggestKeyword("GOT")
        XCTAssertEqual(suggestion2, "GOTO")
    }

    // =========================================================================
    // MARK: - Memory Layout Tests
    // =========================================================================

    func testBASICPointerAddresses() {
        // Verify well-known addresses
        XCTAssertEqual(BASICPointers.lomem, 0x0080)
        XCTAssertEqual(BASICPointers.vntp, 0x0082)
        XCTAssertEqual(BASICPointers.vntd, 0x0084)
        XCTAssertEqual(BASICPointers.vvtp, 0x0086)
        XCTAssertEqual(BASICPointers.stmtab, 0x0088)
        XCTAssertEqual(BASICPointers.stmcur, 0x008A)
        XCTAssertEqual(BASICPointers.starp, 0x008C)
        XCTAssertEqual(BASICPointers.runstk, 0x008E)
        XCTAssertEqual(BASICPointers.memtop, 0x0090)
    }

    func testBASICMemoryDefaults() {
        XCTAssertEqual(BASICMemoryDefaults.defaultLOMEM, 0x0700)
        XCTAssertEqual(BASICMemoryDefaults.defaultMEMTOP, 0x9FFF)
        XCTAssertEqual(BASICMemoryDefaults.vvtEntrySize, 8)
        XCTAssertEqual(BASICMemoryDefaults.maxVariables, 128)
        XCTAssertEqual(BASICMemoryDefaults.maxLineNumber, 32767)
    }

    func testEmptyMemoryState() {
        let state = BASICMemoryState.empty()

        XCTAssertEqual(state.lomem, 0x0700)
        XCTAssertEqual(state.variableCount, 0)
        XCTAssertEqual(state.vntSize, 0)
    }
}
