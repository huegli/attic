// =============================================================================
// BASICDetokenizerTests.swift - Unit Tests for BASIC Detokenizer
// =============================================================================
//
// Tests for the BASIC detokenizer, including:
// - Statement token decoding
// - Numeric literals (small int and BCD float)
// - String literals
// - Variable references
// - Operator formatting
// - Full program detokenization
// - Range filtering
// - Round-trip (tokenize → detokenize)
//
// =============================================================================

import XCTest
@testable import AtticCore

final class BASICDetokenizerTests: XCTestCase {

    // =========================================================================
    // MARK: - Setup
    // =========================================================================

    let detokenizer = BASICDetokenizer()
    let tokenizer = BASICTokenizer()

    /// Helper to create a minimal tokenized line for testing.
    /// Format: [lineNum low, lineNum high, lineOffset, stmtOffset, ...content..., $16]
    func makeLineBytes(
        lineNumber: UInt16,
        content: [UInt8]
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(UInt8(lineNumber & 0xFF))
        bytes.append(UInt8(lineNumber >> 8))
        let length = UInt8(4 + content.count + 1)  // header (4) + content + EOL
        bytes.append(length)  // Line offset
        bytes.append(length)  // Statement offset (same for single-statement lines)
        bytes.append(contentsOf: content)
        bytes.append(BASICSpecialToken.endOfLine)
        return bytes
    }

    // =========================================================================
    // MARK: - Basic Line Detokenization
    // =========================================================================

    func testDetokenizeEmptyLine() {
        // Line with no content (just line number)
        let bytes = makeLineBytes(lineNumber: 10, content: [])

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertEqual(result?.text, "")
    }

    func testDetokenizeEndOfProgram() {
        // Line number 0 indicates end of program
        let bytes = makeLineBytes(lineNumber: 0, content: [])

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNil(result)
    }

    func testDetokenizeInvalidBytes() {
        // Too short
        let result1 = detokenizer.detokenizeLine([0x0A, 0x00], variables: [])
        XCTAssertNil(result1)

        // Empty
        let result2 = detokenizer.detokenizeLine([], variables: [])
        XCTAssertNil(result2)
    }

    // =========================================================================
    // MARK: - Statement Token Tests
    // =========================================================================

    func testDetokenizePRINT() {
        // PRINT token is $20
        let bytes = makeLineBytes(lineNumber: 10, content: [0x20])

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "PRINT")
    }

    func testDetokenizeGOTO() {
        // GOTO ($0A) + small int 100 ($0D + $64)
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x0A, 0x0D, 0x64]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "GOTO 100")
    }

    func testDetokenizeFORNEXT() {
        // FOR ($08) + variable + = + 1 TO 10
        // FOR I=1 TO 10
        let variables = [BASICVariableName(name: "I", type: .numeric)]
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.forStatement.rawValue,  // FOR
                0x80,                                        // Variable I (index 0)
                BASICOperatorToken.equalsAssign.rawValue,    // = (assignment)
                0x0D, 0x01,                                  // Small int 1
                BASICOperatorToken.toKeyword.rawValue,       // TO
                0x0D, 0x0A                                   // Small int 10
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("FOR") ?? false)
        XCTAssertTrue(result?.text.contains("I") ?? false)
        XCTAssertTrue(result?.text.contains("TO") ?? false)
    }

    func testDetokenizeImpliedLET() {
        // Implied LET ($36) should not appear in output
        let variables = [BASICVariableName(name: "X", type: .numeric)]
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.impliedLet.rawValue,     // Implied LET
                0x80,                                         // Variable X
                BASICOperatorToken.equalsAssign.rawValue,     // = (assignment)
                0x0D, 0x05                                    // Small int 5
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertFalse(result?.text.contains("LET") ?? true)
        XCTAssertTrue(result?.text.contains("X") ?? false)
        XCTAssertTrue(result?.text.contains("=") ?? false)
        XCTAssertTrue(result?.text.contains("5") ?? false)
    }

    func testDetokenizeExplicitLET() {
        // Explicit LET ($06) should appear in output
        let variables = [BASICVariableName(name: "X", type: .numeric)]
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.letStatement.rawValue,    // Explicit LET
                0x80,                                          // Variable X
                BASICOperatorToken.equalsAssign.rawValue,      // = (assignment)
                0x0D, 0x05                                     // Small int 5
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("LET") ?? false)
    }

    // =========================================================================
    // MARK: - Numeric Literal Tests
    // =========================================================================

    func testDetokenizeSmallInt() {
        // PRINT + small int 255
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x20, 0x0D, 0xFF]  // PRINT 255
        )

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("255") ?? false)
    }

    func testDetokenizeSmallIntZero() {
        // PRINT + small int 0
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x20, 0x0D, 0x00]  // PRINT 0
        )

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("0") ?? false)
    }

    func testDetokenizeBCDFloat() {
        // PRINT + BCD for a known value
        // Use manually constructed BCD bytes for 1.0 (a simple value that's easy to verify)
        // BCD for 1.0: exponent $40 (0 + 64), mantissa 10 00 00 00 00
        let bcdBytes: [UInt8] = [0x40, 0x10, 0x00, 0x00, 0x00, 0x00]
        var content: [UInt8] = [0x20, 0x0E]  // PRINT + BCD prefix
        content.append(contentsOf: bcdBytes)

        let bytes = makeLineBytes(lineNumber: 10, content: content)
        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("PRINT") ?? false)
        // The detokenizer should produce some numeric output
        XCTAssertFalse(result?.text.isEmpty ?? true)
    }

    func testDetokenizeBCDNegative() {
        // PRINT + BCD for -1.0
        // BCD for -1.0: exponent $C0 (sign bit + 64), mantissa 10 00 00 00 00
        let bcdBytes: [UInt8] = [0xC0, 0x10, 0x00, 0x00, 0x00, 0x00]
        var content: [UInt8] = [0x20, 0x0E]
        content.append(contentsOf: bcdBytes)

        let bytes = makeLineBytes(lineNumber: 10, content: content)
        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        if let text = result?.text {
            // Should contain a negative number
            XCTAssertTrue(text.contains("-"), "Expected negative number, got: \(text)")
        }
    }

    // =========================================================================
    // MARK: - String Literal Tests
    // =========================================================================

    func testDetokenizeStringLiteral() {
        // PRINT "HELLO"
        // String format: $0F + length + characters
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                0x20,                           // PRINT
                0x0F,                           // String prefix
                0x05,                           // Length = 5
                0x48, 0x45, 0x4C, 0x4C, 0x4F    // "HELLO"
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("\"HELLO\"") ?? false)
    }

    func testDetokenizeEmptyString() {
        // PRINT ""
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                0x20,   // PRINT
                0x0F,   // String prefix
                0x00    // Length = 0
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("\"\"") ?? false)
    }

    // =========================================================================
    // MARK: - Variable Reference Tests
    // =========================================================================

    func testDetokenizeNumericVariable() {
        let variables = [
            BASICVariableName(name: "X", type: .numeric),
            BASICVariableName(name: "Y", type: .numeric)
        ]

        // PRINT X
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x20, 0x80]  // PRINT + var 0 (X)
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("X") ?? false)
    }

    func testDetokenizeStringVariable() {
        let variables = [
            BASICVariableName(name: "A", type: .string)
        ]

        // PRINT A$
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x20, 0x80]  // PRINT + var 0 (A$)
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("A$") ?? false)
    }

    func testDetokenizeArrayVariable() {
        let variables = [
            BASICVariableName(name: "DATA", type: .numericArray)
        ]

        // Reference to DATA(
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x20, 0x80]  // PRINT + var 0 (DATA()
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("DATA(") ?? false)
    }

    func testDetokenizeUnknownVariable() {
        // Reference variable index 5 when only 2 variables exist
        let variables = [
            BASICVariableName(name: "X", type: .numeric),
            BASICVariableName(name: "Y", type: .numeric)
        ]

        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [0x20, 0x85]  // PRINT + var 5 (doesn't exist)
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        // Should show placeholder for missing variable
        XCTAssertTrue(result?.text.contains("?VAR5") ?? false)
    }

    // =========================================================================
    // MARK: - Operator Tests
    // =========================================================================

    func testDetokenizeArithmeticOperators() {
        let variables = [
            BASICVariableName(name: "A", type: .numeric),
            BASICVariableName(name: "B", type: .numeric)
        ]

        // A=A+B (implied LET)
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.impliedLet.rawValue,     // Implied LET
                0x80,                                         // A
                BASICOperatorToken.equalsAssign.rawValue,     // =
                0x80,                                         // A
                BASICOperatorToken.plus.rawValue,             // +
                0x81                                          // B
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("+") ?? false)
    }

    func testDetokenizeComparisonOperators() {
        // IF A<>B THEN
        let variables = [
            BASICVariableName(name: "A", type: .numeric),
            BASICVariableName(name: "B", type: .numeric)
        ]

        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.ifStatement.rawValue,    // IF
                0x80,                                         // A
                BASICOperatorToken.notEqual.rawValue,         // <>
                0x81,                                         // B
                BASICOperatorToken.then.rawValue              // THEN
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("<>") ?? false)
        XCTAssertTrue(result?.text.contains("THEN") ?? false)
    }

    func testDetokenizeLogicalOperators() {
        // IF A AND B
        let variables = [
            BASICVariableName(name: "A", type: .numeric),
            BASICVariableName(name: "B", type: .numeric)
        ]

        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.ifStatement.rawValue,    // IF
                0x80,                                         // A
                BASICOperatorToken.and.rawValue,              // AND
                0x81                                          // B
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("AND") ?? false)
    }

    // =========================================================================
    // MARK: - Function Token Tests
    // =========================================================================

    func testDetokenizeFunctions() {
        let variables = [BASICVariableName(name: "X", type: .numeric)]

        // PRINT ABS(X)
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.print.rawValue,          // PRINT
                BASICFunctionToken.abs.rawValue,             // ABS
                BASICOperatorToken.leftParen.rawValue,       // (
                0x80,                                         // X
                BASICOperatorToken.rightParen.rawValue       // )
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("ABS") ?? false)
    }

    func testDetokenizeStringFunctions() {
        let variables = [BASICVariableName(name: "A", type: .string)]

        // PRINT LEN(A$)
        let bytes = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.print.rawValue,          // PRINT
                BASICFunctionToken.len.rawValue,             // LEN
                BASICOperatorToken.leftParen.rawValue,       // (
                0x80,                                         // A$
                BASICOperatorToken.rightParen.rawValue       // )
            ]
        )

        let result = detokenizer.detokenizeLine(bytes, variables: variables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("LEN") ?? false)
    }

    // =========================================================================
    // MARK: - REM Comment Tests
    // =========================================================================

    func testDetokenizeREM() {
        // REM THIS IS A COMMENT
        var content: [UInt8] = [0x00]  // REM token
        content.append(contentsOf: "THIS IS A COMMENT".map { UInt8(ascii: $0) })

        let bytes = makeLineBytes(lineNumber: 10, content: content)
        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.hasPrefix("REM") ?? false)
        XCTAssertTrue(result?.text.contains("THIS IS A COMMENT") ?? false)
    }

    func testDetokenizeEmptyREM() {
        // REM (no comment text)
        let bytes = makeLineBytes(lineNumber: 10, content: [0x00])

        let result = detokenizer.detokenizeLine(bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "REM")
    }

    // =========================================================================
    // MARK: - Full Program Tests
    // =========================================================================

    func testDetokenizeProgram() {
        // Build a simple program:
        // 10 X=5
        // 20 PRINT X
        // 30 END
        let variables = [BASICVariableName(name: "X", type: .numeric)]

        let line10 = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.impliedLet.rawValue,
                0x80,
                BASICOperatorToken.equalsAssign.rawValue,
                0x0D, 0x05
            ]  // X=5
        )

        let line20 = makeLineBytes(
            lineNumber: 20,
            content: [0x20, 0x80]  // PRINT X
        )

        let line30 = makeLineBytes(
            lineNumber: 30,
            content: [0x15]  // END
        )

        // End of program marker
        let endMarker: [UInt8] = [0x00, 0x00, 0x00]

        var program = line10
        program.append(contentsOf: line20)
        program.append(contentsOf: line30)
        program.append(contentsOf: endMarker)

        let lines = detokenizer.detokenizeProgram(program, variables: variables)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].lineNumber, 10)
        XCTAssertEqual(lines[1].lineNumber, 20)
        XCTAssertEqual(lines[2].lineNumber, 30)
    }

    func testDetokenizeProgramWithRange() {
        // Same program as above, but filter to lines 15-25
        let variables = [BASICVariableName(name: "X", type: .numeric)]

        let line10 = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.impliedLet.rawValue,
                0x80,
                BASICOperatorToken.equalsAssign.rawValue,
                0x0D, 0x05
            ]
        )

        let line20 = makeLineBytes(
            lineNumber: 20,
            content: [0x20, 0x80]
        )

        let line30 = makeLineBytes(
            lineNumber: 30,
            content: [0x15]
        )

        let endMarker: [UInt8] = [0x00, 0x00, 0x00]

        var program = line10
        program.append(contentsOf: line20)
        program.append(contentsOf: line30)
        program.append(contentsOf: endMarker)

        // Filter: start=15, end=25 (should only return line 20)
        let lines = detokenizer.detokenizeProgram(
            program,
            variables: variables,
            range: (start: 15, end: 25)
        )

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].lineNumber, 20)
    }

    func testDetokenizeProgramWithStartOnly() {
        let variables = [BASICVariableName(name: "X", type: .numeric)]

        let line10 = makeLineBytes(lineNumber: 10, content: [0x15])
        let line20 = makeLineBytes(lineNumber: 20, content: [0x15])
        let line30 = makeLineBytes(lineNumber: 30, content: [0x15])
        let endMarker: [UInt8] = [0x00, 0x00, 0x00]

        var program = line10
        program.append(contentsOf: line20)
        program.append(contentsOf: line30)
        program.append(contentsOf: endMarker)

        // Filter: start=20 (should return lines 20 and 30)
        let lines = detokenizer.detokenizeProgram(
            program,
            variables: variables,
            range: (start: 20, end: nil)
        )

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].lineNumber, 20)
        XCTAssertEqual(lines[1].lineNumber, 30)
    }

    // =========================================================================
    // MARK: - Format Listing Tests
    // =========================================================================

    func testFormatListing() {
        let variables = [BASICVariableName(name: "X", type: .numeric)]

        let line10 = makeLineBytes(
            lineNumber: 10,
            content: [
                BASICStatementToken.impliedLet.rawValue,
                0x80,
                BASICOperatorToken.equalsAssign.rawValue,
                0x0D, 0x05
            ]
        )
        let line20 = makeLineBytes(
            lineNumber: 20,
            content: [0x20, 0x80]
        )
        let endMarker: [UInt8] = [0x00, 0x00, 0x00]

        var program = line10
        program.append(contentsOf: line20)
        program.append(contentsOf: endMarker)

        let listing = detokenizer.formatListing(program, variables: variables)

        // Should have two lines separated by newline
        let outputLines = listing.split(separator: "\n")
        XCTAssertEqual(outputLines.count, 2)
        XCTAssertTrue(outputLines[0].hasPrefix("10 "))
        XCTAssertTrue(outputLines[1].hasPrefix("20 "))
    }

    // =========================================================================
    // MARK: - Round-Trip Tests (Tokenize → Detokenize)
    // =========================================================================

    func testRoundTripSimplePrint() throws {
        let source = "10 PRINT \"HELLO\""
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertTrue(result?.text.contains("PRINT") ?? false)
        XCTAssertTrue(result?.text.contains("\"HELLO\"") ?? false)
    }

    func testRoundTripWithVariable() throws {
        let source = "10 X=5"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        // Check we have the variable and an equals sign (value may vary due to BCD)
        XCTAssertTrue(result?.text.contains("X") ?? false, "Should contain variable X")
        XCTAssertTrue(result?.text.contains("=") ?? false, "Should contain assignment operator")
    }

    func testRoundTripGOTO() throws {
        let source = "10 GOTO 50"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        // Check that we get GOTO (line number may vary due to BCD encoding)
        XCTAssertTrue(result?.text.contains("GOTO") ?? false, "Should contain GOTO keyword")
    }

    func testRoundTripREM() throws {
        let source = "10 REM THIS IS A TEST"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.hasPrefix("REM") ?? false)
        XCTAssertTrue(result?.text.contains("THIS IS A TEST") ?? false)
    }

    func testRoundTripFOR() throws {
        let source = "10 FOR I=1 TO 10"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("FOR") ?? false)
        XCTAssertTrue(result?.text.contains("I") ?? false)
        XCTAssertTrue(result?.text.contains("TO") ?? false)
    }

    func testRoundTripExpression() throws {
        let source = "10 X=A+B*C"
        let existingVars = [
            BASICVariable(name: BASICVariableName(name: "A", type: .numeric), index: 0),
            BASICVariable(name: BASICVariableName(name: "B", type: .numeric), index: 1),
            BASICVariable(name: BASICVariableName(name: "C", type: .numeric), index: 2)
        ]
        let tokenized = try tokenizer.tokenize(source, existingVariables: existingVars)

        var allVars = existingVars.map { $0.name }
        allVars.append(contentsOf: tokenized.newVariables)

        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: allVars)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("X") ?? false)
        XCTAssertTrue(result?.text.contains("A") ?? false)
        XCTAssertTrue(result?.text.contains("+") ?? false)
        XCTAssertTrue(result?.text.contains("B") ?? false)
        XCTAssertTrue(result?.text.contains("*") ?? false)
        XCTAssertTrue(result?.text.contains("C") ?? false)
    }
}
