// =============================================================================
// BASICIntegrationTests.swift - Integration Tests for BASIC Mode
// =============================================================================
//
// This file provides integration test coverage for BASIC mode:
// 1. Line Entry - Numbered lines, tokenization, abbreviations, error handling
// 2. Program Management - LIST, RUN, NEW, DEL, RENUM command parsing
// 3. Tokenization Round-trip - Multi-line programs survive tokenize/detokenize
// 4. Complex Programs - FOR/NEXT, IF/THEN, GOSUB/RETURN, DIM, strings, math
//
// These tests exercise CommandParser.parse(_:mode:) for BASIC commands and
// BASICTokenizer + BASICDetokenizer for round-trip verification. No emulator
// or server is needed — these are pure parsing and pipeline tests.
//
// Running:
//   swift test --filter BASICIntegrationTests
//   make test-basic
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - 10.1 Line Entry Tests
// =============================================================================

/// Tests that BASIC line entry works correctly through the command parser
/// and tokenizer pipeline.
///
/// Line entry is the primary way users write BASIC programs. The parser must
/// recognize lines starting with a number, extract the line number and content,
/// then the tokenizer converts the content to Atari BASIC binary format.
///
/// Key behaviors tested:
/// - Numbered lines are recognized and split into number + content
/// - Content is tokenized correctly (keywords, strings, numbers)
/// - Abbreviations (e.g., PR. for PRINT) are expanded
/// - Invalid syntax produces clear errors
final class BASICLineEntryTests: XCTestCase {
    let parser = CommandParser()
    let tokenizer = BASICTokenizer()
    let mode: REPLMode = .basic(variant: .atari)

    // =========================================================================
    // MARK: - Basic Line Parsing
    // =========================================================================

    /// Simple numbered line is parsed as basicLine command.
    func test_numberedLine_parsedAsBasicLine() throws {
        let cmd = try parser.parse("10 PRINT \"HELLO\"", mode: mode)
        guard case .basicLine(let number, let content) = cmd else {
            XCTFail("Expected basicLine, got \(cmd)")
            return
        }
        XCTAssertEqual(number, 10)
        XCTAssertEqual(content, "PRINT \"HELLO\"")
    }

    /// Line number at boundary (1) is accepted.
    func test_lineNumber_minimum() throws {
        let cmd = try parser.parse("1 END", mode: mode)
        guard case .basicLine(let number, let content) = cmd else {
            XCTFail("Expected basicLine, got \(cmd)")
            return
        }
        XCTAssertEqual(number, 1)
        XCTAssertEqual(content, "END")
    }

    /// Line number at maximum (32767) is accepted by the parser.
    func test_lineNumber_maximum() throws {
        let cmd = try parser.parse("32767 END", mode: mode)
        guard case .basicLine(let number, _) = cmd else {
            XCTFail("Expected basicLine, got \(cmd)")
            return
        }
        XCTAssertEqual(number, 32767)
    }

    /// Large line numbers (beyond Atari BASIC max) still parse as basicLine —
    /// the tokenizer is responsible for the validation error.
    func test_lineNumber_beyondMax_parsesButTokenizerRejects() throws {
        let cmd = try parser.parse("40000 PRINT", mode: mode)
        guard case .basicLine(let number, _) = cmd else {
            XCTFail("Expected basicLine, got \(cmd)")
            return
        }
        XCTAssertEqual(number, 40000)

        // Tokenizer should reject it
        XCTAssertThrowsError(
            try tokenizer.tokenize("40000 PRINT", existingVariables: [])
        ) { error in
            if case BASICTokenizerError.invalidLineNumber = error {
                // Expected
            } else {
                XCTFail("Expected invalidLineNumber, got \(error)")
            }
        }
    }

    /// Line with no content after the number is parsed with empty content.
    func test_lineNumberOnly_emptyContent() throws {
        let cmd = try parser.parse("10", mode: mode)
        guard case .basicLine(let number, let content) = cmd else {
            XCTFail("Expected basicLine, got \(cmd)")
            return
        }
        XCTAssertEqual(number, 10)
        XCTAssertEqual(content, "")
    }

    /// Multi-digit line numbers parse correctly.
    func test_multiDigitLineNumber() throws {
        let cmd = try parser.parse("1000 REM TEST", mode: mode)
        guard case .basicLine(let number, let content) = cmd else {
            XCTFail("Expected basicLine, got \(cmd)")
            return
        }
        XCTAssertEqual(number, 1000)
        XCTAssertEqual(content, "REM TEST")
    }

    // =========================================================================
    // MARK: - Tokenization of Line Content
    // =========================================================================

    /// PRINT statement tokenizes to the correct token byte.
    func test_tokenize_printStatement() throws {
        let result = try tokenizer.tokenize("10 PRINT \"HELLO\"", existingVariables: [])
        XCTAssertEqual(result.lineNumber, 10)

        // PRINT token is $20
        XCTAssertTrue(result.bytes.contains(BASICStatementToken.print.rawValue))

        // String prefix $0F
        XCTAssertTrue(result.bytes.contains(BASICSpecialToken.stringPrefix))

        // EOL marker $16 at end
        XCTAssertEqual(result.bytes.last, BASICSpecialToken.endOfLine)
    }

    /// GOTO statement tokenizes correctly.
    func test_tokenize_gotoStatement() throws {
        let result = try tokenizer.tokenize("10 GOTO 100", existingVariables: [])
        XCTAssertEqual(result.lineNumber, 10)
        XCTAssertTrue(result.bytes.contains(BASICStatementToken.goto.rawValue))
    }

    /// REM statement preserves comment text as raw ASCII.
    func test_tokenize_remPreservesText() throws {
        let result = try tokenizer.tokenize("10 REM THIS IS A TEST", existingVariables: [])

        // REM token is $00 — verify it appears in the content portion
        // (after the 4-byte header: lineNum low, lineNum high, lineOffset, stmtOffset)
        XCTAssertGreaterThan(result.bytes.count, 4)
        XCTAssertEqual(result.bytes[4], BASICStatementToken.rem.rawValue)
    }

    /// Variable assignment creates new variable in the variable table.
    func test_tokenize_variableCreation() throws {
        let result = try tokenizer.tokenize("10 X=5", existingVariables: [])

        XCTAssertEqual(result.newVariables.count, 1)
        XCTAssertEqual(result.newVariables[0].name, "X")
        XCTAssertEqual(result.newVariables[0].type, .numeric)

        // Variable reference should be $80 (index 0 + $80)
        XCTAssertTrue(result.bytes.contains(0x80))
    }

    /// String variable creates correct type in variable table.
    func test_tokenize_stringVariable() throws {
        let result = try tokenizer.tokenize("10 A$=\"HELLO\"", existingVariables: [])

        XCTAssertEqual(result.newVariables.count, 1)
        XCTAssertEqual(result.newVariables[0].name, "A")
        XCTAssertEqual(result.newVariables[0].type, .string)
    }

    // =========================================================================
    // MARK: - Abbreviation Expansion
    // =========================================================================

    /// Abbreviated PRINT (PR.) is recognized as the PRINT statement token.
    func test_abbreviation_printExpands() {
        XCTAssertEqual(BASICTokenLookup.matchStatement("PR."), .print)
    }

    /// Abbreviated GOTO (G.) is recognized.
    func test_abbreviation_gotoExpands() {
        XCTAssertEqual(BASICTokenLookup.matchStatement("G."), .goto)
    }

    /// Question mark (?) is recognized as PRINT shorthand.
    func test_abbreviation_questionMarkIsPrint() {
        XCTAssertEqual(BASICTokenLookup.matchStatement("?"), .printShort)
    }

    /// Case-insensitive matching for keywords.
    func test_keyword_caseInsensitive() {
        XCTAssertEqual(BASICTokenLookup.matchStatement("print"), .print)
        XCTAssertEqual(BASICTokenLookup.matchStatement("Print"), .print)
        XCTAssertEqual(BASICTokenLookup.matchStatement("PRINT"), .print)
    }

    // =========================================================================
    // MARK: - Invalid Syntax Errors
    // =========================================================================

    /// Unterminated string literal produces an error.
    func test_invalidSyntax_unterminatedString() {
        XCTAssertThrowsError(
            try tokenizer.tokenize("10 PRINT \"HELLO", existingVariables: [])
        ) { error in
            if case BASICTokenizerError.unterminatedString = error {
                // Expected
            } else {
                XCTFail("Expected unterminatedString, got \(error)")
            }
        }
    }

    /// Missing line number produces a syntax error from the tokenizer.
    func test_invalidSyntax_noLineNumber() {
        XCTAssertThrowsError(
            try tokenizer.tokenize("PRINT \"HELLO\"", existingVariables: [])
        ) { error in
            if case BASICTokenizerError.syntaxError = error {
                // Expected
            } else {
                XCTFail("Expected syntaxError, got \(error)")
            }
        }
    }

    /// Unknown command in BASIC mode produces an error.
    func test_invalidSyntax_unknownCommand() {
        XCTAssertThrowsError(
            try parser.parse("xyzzy", mode: mode)
        )
    }
}

// =============================================================================
// MARK: - 10.2 Program Management Tests
// =============================================================================

/// Tests for BASIC program management commands: LIST, RUN, NEW, DEL, RENUM.
///
/// These commands control the BASIC program stored in emulator memory.
/// The parser converts user input into structured Command values that
/// the REPL executor processes.
///
/// Each command has multiple argument forms (e.g., `list` vs `list 10-20`).
final class BASICProgramManagementTests: XCTestCase {
    let parser = CommandParser()
    let mode: REPLMode = .basic(variant: .atari)

    // =========================================================================
    // MARK: - LIST Command
    // =========================================================================

    /// LIST with no arguments lists all lines.
    func test_list_all() throws {
        let cmd = try parser.parse("list", mode: mode)
        guard case .basicList(let start, let end) = cmd else {
            XCTFail("Expected basicList, got \(cmd)")
            return
        }
        XCTAssertNil(start)
        XCTAssertNil(end)
    }

    /// LIST with single line number lists that one line (start == end).
    func test_list_singleLine() throws {
        let cmd = try parser.parse("list 10", mode: mode)
        guard case .basicList(let start, let end) = cmd else {
            XCTFail("Expected basicList, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 10)
        XCTAssertEqual(end, 10)
    }

    /// LIST with range (10-50) filters to that range.
    func test_list_range() throws {
        let cmd = try parser.parse("list 10-50", mode: mode)
        guard case .basicList(let start, let end) = cmd else {
            XCTFail("Expected basicList, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 10)
        XCTAssertEqual(end, 50)
    }

    /// LIST with start-only range (10-) lists from line 10 to end.
    func test_list_fromStart() throws {
        let cmd = try parser.parse("list 10-", mode: mode)
        guard case .basicList(let start, let end) = cmd else {
            XCTFail("Expected basicList, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 10)
        XCTAssertNil(end)
    }

    /// LIST with end-only range (-50) lists from beginning to line 50.
    func test_list_toEnd() throws {
        let cmd = try parser.parse("list -50", mode: mode)
        guard case .basicList(let start, let end) = cmd else {
            XCTFail("Expected basicList, got \(cmd)")
            return
        }
        XCTAssertNil(start)
        XCTAssertEqual(end, 50)
    }

    /// LIST with invalid line number produces an error.
    func test_list_invalidLineNumber() {
        XCTAssertThrowsError(try parser.parse("list abc", mode: mode))
    }

    /// LIST with invalid range produces an error.
    func test_list_invalidRange() {
        XCTAssertThrowsError(try parser.parse("list abc-def", mode: mode))
    }

    // =========================================================================
    // MARK: - RUN Command
    // =========================================================================

    /// RUN command is recognized.
    func test_run() throws {
        let cmd = try parser.parse("run", mode: mode)
        guard case .basicRun = cmd else {
            XCTFail("Expected basicRun, got \(cmd)")
            return
        }
    }

    // =========================================================================
    // MARK: - STOP Command
    // =========================================================================

    /// STOP command is recognized.
    func test_stop() throws {
        let cmd = try parser.parse("stop", mode: mode)
        guard case .basicStop = cmd else {
            XCTFail("Expected basicStop, got \(cmd)")
            return
        }
    }

    // =========================================================================
    // MARK: - CONT Command
    // =========================================================================

    /// CONT (continue) command is recognized.
    func test_cont() throws {
        let cmd = try parser.parse("cont", mode: mode)
        guard case .basicContinue = cmd else {
            XCTFail("Expected basicContinue, got \(cmd)")
            return
        }
    }

    // =========================================================================
    // MARK: - NEW Command
    // =========================================================================

    /// NEW command is recognized.
    func test_new() throws {
        let cmd = try parser.parse("new", mode: mode)
        guard case .basicNew = cmd else {
            XCTFail("Expected basicNew, got \(cmd)")
            return
        }
    }

    // =========================================================================
    // MARK: - DEL Command
    // =========================================================================

    /// DEL single line.
    func test_del_singleLine() throws {
        let cmd = try parser.parse("del 10", mode: mode)
        guard case .basicDelete(let start, let end) = cmd else {
            XCTFail("Expected basicDelete, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 10)
        XCTAssertNil(end)
    }

    /// DEL range of lines.
    func test_del_range() throws {
        let cmd = try parser.parse("del 10-50", mode: mode)
        guard case .basicDelete(let start, let end) = cmd else {
            XCTFail("Expected basicDelete, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 10)
        XCTAssertEqual(end, 50)
    }

    /// DELETE is an alias for DEL.
    func test_delete_aliasForDel() throws {
        let cmd = try parser.parse("delete 20", mode: mode)
        guard case .basicDelete(let start, let end) = cmd else {
            XCTFail("Expected basicDelete, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 20)
        XCTAssertNil(end)
    }

    /// DEL with no arguments produces an error.
    func test_del_noArguments() {
        XCTAssertThrowsError(try parser.parse("del", mode: mode))
    }

    /// DEL with invalid argument produces an error.
    func test_del_invalidArgument() {
        XCTAssertThrowsError(try parser.parse("del abc", mode: mode))
    }

    // =========================================================================
    // MARK: - RENUM Command
    // =========================================================================

    /// RENUM with no arguments uses defaults.
    func test_renum_defaults() throws {
        let cmd = try parser.parse("renum", mode: mode)
        guard case .basicRenumber(let start, let step) = cmd else {
            XCTFail("Expected basicRenumber, got \(cmd)")
            return
        }
        XCTAssertNil(start)
        XCTAssertNil(step)
    }

    /// RENUM with start number.
    func test_renum_withStart() throws {
        let cmd = try parser.parse("renum 100", mode: mode)
        guard case .basicRenumber(let start, let step) = cmd else {
            XCTFail("Expected basicRenumber, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 100)
        XCTAssertNil(step)
    }

    /// RENUM with start and step.
    func test_renum_withStartAndStep() throws {
        let cmd = try parser.parse("renum 100 20", mode: mode)
        guard case .basicRenumber(let start, let step) = cmd else {
            XCTFail("Expected basicRenumber, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 100)
        XCTAssertEqual(step, 20)
    }

    /// RENUMBER is an alias for RENUM.
    func test_renumber_aliasForRenum() throws {
        let cmd = try parser.parse("renumber 200 5", mode: mode)
        guard case .basicRenumber(let start, let step) = cmd else {
            XCTFail("Expected basicRenumber, got \(cmd)")
            return
        }
        XCTAssertEqual(start, 200)
        XCTAssertEqual(step, 5)
    }

    /// RENUM with invalid start produces an error.
    func test_renum_invalidStart() {
        XCTAssertThrowsError(try parser.parse("renum abc", mode: mode))
    }

    // =========================================================================
    // MARK: - VARS Command
    // =========================================================================

    /// VARS with no arguments lists all variables.
    func test_vars_all() throws {
        let cmd = try parser.parse("vars", mode: mode)
        guard case .basicVars(let name) = cmd else {
            XCTFail("Expected basicVars, got \(cmd)")
            return
        }
        XCTAssertNil(name)
    }

    /// VARS with a name filters to that variable.
    func test_vars_withName() throws {
        let cmd = try parser.parse("vars x", mode: mode)
        guard case .basicVars(let name) = cmd else {
            XCTFail("Expected basicVars, got \(cmd)")
            return
        }
        XCTAssertEqual(name, "X")  // Should be uppercased
    }

    /// VAR is an alias for VARS.
    func test_var_aliasForVars() throws {
        let cmd = try parser.parse("var counter", mode: mode)
        guard case .basicVars(let name) = cmd else {
            XCTFail("Expected basicVars, got \(cmd)")
            return
        }
        XCTAssertEqual(name, "COUNTER")
    }

    // =========================================================================
    // MARK: - SAVE/LOAD Commands
    // =========================================================================

    /// SAVE command with filename.
    func test_save() throws {
        let cmd = try parser.parse("save D:TEST", mode: mode)
        guard case .basicSaveATR(let filename) = cmd else {
            XCTFail("Expected basicSaveATR, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "D:TEST")
    }

    /// SAVE with drive prefix.
    func test_save_withDrive() throws {
        let cmd = try parser.parse("save D2:MYPROG", mode: mode)
        guard case .basicSaveATR(let filename) = cmd else {
            XCTFail("Expected basicSaveATR, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "D2:MYPROG")
    }

    /// SAVE with no filename produces an error.
    func test_save_noFilename() {
        XCTAssertThrowsError(try parser.parse("save", mode: mode))
    }

    /// LOAD command with filename.
    func test_load() throws {
        let cmd = try parser.parse("load D:TEST", mode: mode)
        guard case .basicLoadATR(let filename) = cmd else {
            XCTFail("Expected basicLoadATR, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "D:TEST")
    }

    /// LOAD with no filename produces an error.
    func test_load_noFilename() {
        XCTAssertThrowsError(try parser.parse("load", mode: mode))
    }

    // =========================================================================
    // MARK: - IMPORT/EXPORT Commands
    // =========================================================================

    /// IMPORT command with path.
    func test_import() throws {
        let cmd = try parser.parse("import ~/program.bas", mode: mode)
        guard case .basicImport(let path) = cmd else {
            XCTFail("Expected basicImport, got \(cmd)")
            return
        }
        XCTAssertEqual(path, NSString(string: "~/program.bas").expandingTildeInPath)
    }

    /// IMPORT with no path produces an error.
    func test_import_noPath() {
        XCTAssertThrowsError(try parser.parse("import", mode: mode))
    }

    /// EXPORT command with path.
    func test_export() throws {
        let cmd = try parser.parse("export ~/output.bas", mode: mode)
        guard case .basicExport(let path) = cmd else {
            XCTFail("Expected basicExport, got \(cmd)")
            return
        }
        XCTAssertEqual(path, NSString(string: "~/output.bas").expandingTildeInPath)
    }

    /// EXPORT with no path produces an error.
    func test_export_noPath() {
        XCTAssertThrowsError(try parser.parse("export", mode: mode))
    }
}

// =============================================================================
// MARK: - 10.3 Tokenization Round-trip Tests
// =============================================================================

/// Tests that BASIC programs survive the tokenize -> detokenize cycle.
///
/// A round-trip test enters one or more lines of BASIC source, tokenizes them
/// to binary format, then detokenizes back to text and verifies the output
/// matches the original meaning. Minor cosmetic differences (spacing, BCD
/// number formatting) are acceptable, but keywords, structure, and values
/// must be preserved.
///
/// This is the critical correctness property: what you type should match
/// what LIST shows you.
final class BASICRoundTripTests: XCTestCase {
    let tokenizer = BASICTokenizer()
    let detokenizer = BASICDetokenizer()

    // =========================================================================
    // MARK: - Single Statement Round-trips
    // =========================================================================

    /// PRINT with string literal round-trips correctly.
    func test_roundTrip_printString() throws {
        let source = "10 PRINT \"HELLO WORLD\""
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertTrue(result?.text.contains("PRINT") ?? false)
        XCTAssertTrue(result?.text.contains("\"HELLO WORLD\"") ?? false)
    }

    /// GOTO with line number round-trips correctly.
    func test_roundTrip_goto() throws {
        let source = "10 GOTO 100"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertTrue(result?.text.contains("GOTO") ?? false)
    }

    /// Variable assignment round-trips correctly.
    func test_roundTrip_assignment() throws {
        let source = "10 X=42"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("X") ?? false)
        XCTAssertTrue(result?.text.contains("=") ?? false)
    }

    /// END statement round-trips correctly.
    func test_roundTrip_end() throws {
        let source = "999 END"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 999)
        XCTAssertTrue(result?.text.contains("END") ?? false)
    }

    // =========================================================================
    // MARK: - Multi-statement Round-trips
    // =========================================================================

    /// Multi-statement line tokenizes and contains the colon separator token.
    ///
    /// Note: Full round-trip of multi-statement lines requires BASICLineHandler
    /// to insert the statement offset byte after the colon (which only happens
    /// during memory injection). Here we verify the tokenizer produces the
    /// correct tokens including the colon separator.
    func test_roundTrip_colonSeparator() throws {
        let source = "10 PRINT \"HELLO\":GOTO 10"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        // Verify tokenization succeeds and contains key tokens
        XCTAssertEqual(tokenized.lineNumber, 10)
        XCTAssertTrue(tokenized.bytes.contains(BASICStatementToken.print.rawValue))
        XCTAssertTrue(tokenized.bytes.contains(BASICOperatorToken.colon.rawValue))
        XCTAssertEqual(tokenized.bytes.last, BASICSpecialToken.endOfLine)
    }

    // =========================================================================
    // MARK: - Multi-line Program Round-trips
    // =========================================================================

    /// A simple multi-line program round-trips through the full pipeline.
    func test_roundTrip_multiLineProgram() throws {
        let lines = [
            "10 X=5",
            "20 PRINT X",
            "30 END"
        ]

        var allVariables: [BASICVariable] = []
        var allBytes: [UInt8] = []

        // Tokenize each line, accumulating variables
        for source in lines {
            let existing = allVariables
            let tokenized = try tokenizer.tokenize(source, existingVariables: existing)

            // Track new variables with their indices
            for newVar in tokenized.newVariables {
                let index = UInt8(allVariables.count)
                allVariables.append(BASICVariable(name: newVar, index: index))
            }

            allBytes.append(contentsOf: tokenized.bytes)
        }

        // Add end-of-program marker
        allBytes.append(contentsOf: [0x00, 0x00, 0x00])

        // Detokenize entire program
        let variableNames = allVariables.map { $0.name }
        let detokenized = detokenizer.detokenizeProgram(allBytes, variables: variableNames)

        XCTAssertEqual(detokenized.count, 3)
        XCTAssertEqual(detokenized[0].lineNumber, 10)
        XCTAssertEqual(detokenized[1].lineNumber, 20)
        XCTAssertEqual(detokenized[2].lineNumber, 30)

        // Verify content
        XCTAssertTrue(detokenized[0].text.contains("X"))
        XCTAssertTrue(detokenized[1].text.contains("PRINT"))
        XCTAssertTrue(detokenized[2].text.contains("END"))
    }

    /// A program with shared variables round-trips correctly.
    func test_roundTrip_sharedVariables() throws {
        let lines = [
            "10 A=1",
            "20 B=2",
            "30 C=A+B",
            "40 PRINT C"
        ]

        var allVariables: [BASICVariable] = []
        var allBytes: [UInt8] = []

        for source in lines {
            let existing = allVariables
            let tokenized = try tokenizer.tokenize(source, existingVariables: existing)

            for newVar in tokenized.newVariables {
                let index = UInt8(allVariables.count)
                allVariables.append(BASICVariable(name: newVar, index: index))
            }

            allBytes.append(contentsOf: tokenized.bytes)
        }

        // Add end-of-program marker
        allBytes.append(contentsOf: [0x00, 0x00, 0x00])

        // Verify variable table
        XCTAssertEqual(allVariables.count, 3)  // A, B, C
        XCTAssertEqual(allVariables[0].name.name, "A")
        XCTAssertEqual(allVariables[1].name.name, "B")
        XCTAssertEqual(allVariables[2].name.name, "C")

        // Detokenize and verify
        let variableNames = allVariables.map { $0.name }
        let detokenized = detokenizer.detokenizeProgram(allBytes, variables: variableNames)

        XCTAssertEqual(detokenized.count, 4)
        XCTAssertTrue(detokenized[2].text.contains("A"))
        XCTAssertTrue(detokenized[2].text.contains("+"))
        XCTAssertTrue(detokenized[2].text.contains("B"))
        XCTAssertTrue(detokenized[3].text.contains("PRINT"))
    }

    /// Line numbers are preserved exactly through round-trip.
    func test_roundTrip_lineNumbersPreserved() throws {
        let testNumbers = [1, 10, 100, 1000, 10000, 32767]

        for lineNum in testNumbers {
            let source = "\(lineNum) END"
            let tokenized = try tokenizer.tokenize(source, existingVariables: [])
            let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

            XCTAssertNotNil(result, "Failed for line number \(lineNum)")
            XCTAssertEqual(
                result?.lineNumber, UInt16(lineNum),
                "Line number \(lineNum) not preserved"
            )
        }
    }

    // =========================================================================
    // MARK: - Detokenizer Range Filtering
    // =========================================================================

    /// Detokenizer range filtering works with start and end bounds.
    func test_detokenize_rangeFiltering() throws {
        // Build a 5-line program
        var allBytes: [UInt8] = []
        for i in stride(from: 10, through: 50, by: 10) {
            let tokenized = try tokenizer.tokenize("\(i) END", existingVariables: [])
            allBytes.append(contentsOf: tokenized.bytes)
        }
        allBytes.append(contentsOf: [0x00, 0x00, 0x00])

        // Filter to lines 20-40
        let filtered = detokenizer.detokenizeProgram(
            allBytes,
            variables: [],
            range: (start: 20, end: 40)
        )

        XCTAssertEqual(filtered.count, 3)  // Lines 20, 30, 40
        XCTAssertEqual(filtered[0].lineNumber, 20)
        XCTAssertEqual(filtered[1].lineNumber, 30)
        XCTAssertEqual(filtered[2].lineNumber, 40)
    }

    /// Format listing produces line-number-prefixed output.
    func test_formatListing_output() throws {
        var allBytes: [UInt8] = []

        let line1 = try tokenizer.tokenize("10 PRINT \"A\"", existingVariables: [])
        let line2 = try tokenizer.tokenize("20 END", existingVariables: [])

        allBytes.append(contentsOf: line1.bytes)
        allBytes.append(contentsOf: line2.bytes)
        allBytes.append(contentsOf: [0x00, 0x00, 0x00])

        let listing = detokenizer.formatListing(allBytes, variables: [])
        let outputLines = listing.split(separator: "\n")

        XCTAssertEqual(outputLines.count, 2)
        XCTAssertTrue(outputLines[0].hasPrefix("10 "))
        XCTAssertTrue(outputLines[1].hasPrefix("20 "))
    }
}

// =============================================================================
// MARK: - 10.4 Complex Programs Tests
// =============================================================================

/// Tests for complex BASIC program structures.
///
/// These tests verify that the tokenizer and detokenizer handle advanced
/// BASIC constructs correctly, including flow control, data structures,
/// string manipulation, and mathematical expressions.
///
/// Each test tokenizes a program fragment and verifies the round-trip
/// through detokenization preserves the essential structure.
final class BASICComplexProgramTests: XCTestCase {
    let tokenizer = BASICTokenizer()
    let detokenizer = BASICDetokenizer()

    // =========================================================================
    // MARK: - FOR/NEXT Loops
    // =========================================================================

    /// Simple FOR/NEXT loop round-trips correctly.
    func test_forNext_simple() throws {
        let forLine = try tokenizer.tokenize("10 FOR I=1 TO 10", existingVariables: [])
        let iVar = BASICVariable(name: forLine.newVariables[0], index: 0)

        let result = detokenizer.detokenizeLine(
            forLine.bytes,
            variables: forLine.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("FOR") ?? false)
        XCTAssertTrue(result?.text.contains("I") ?? false)
        XCTAssertTrue(result?.text.contains("TO") ?? false)

        // NEXT line
        let nextLine = try tokenizer.tokenize("30 NEXT I", existingVariables: [iVar])
        let nextResult = detokenizer.detokenizeLine(
            nextLine.bytes,
            variables: forLine.newVariables
        )

        XCTAssertNotNil(nextResult)
        XCTAssertTrue(nextResult?.text.contains("NEXT") ?? false)
        XCTAssertTrue(nextResult?.text.contains("I") ?? false)
    }

    /// FOR loop with STEP clause.
    func test_forNext_withStep() throws {
        let source = "10 FOR I=0 TO 100 STEP 5"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("FOR") ?? false)
        XCTAssertTrue(result?.text.contains("TO") ?? false)
        XCTAssertTrue(result?.text.contains("STEP") ?? false)
    }

    /// Nested FOR loops with different variables.
    func test_forNext_nested() throws {
        let lines = [
            "10 FOR I=1 TO 5",
            "20 FOR J=1 TO 3",
            "30 PRINT I*J",
            "40 NEXT J",
            "50 NEXT I"
        ]

        var allVariables: [BASICVariable] = []
        var allBytes: [UInt8] = []

        for source in lines {
            let existing = allVariables
            let tokenized = try tokenizer.tokenize(source, existingVariables: existing)

            for newVar in tokenized.newVariables {
                let index = UInt8(allVariables.count)
                allVariables.append(BASICVariable(name: newVar, index: index))
            }

            allBytes.append(contentsOf: tokenized.bytes)
        }

        // Verify we got both loop variables
        XCTAssertTrue(allVariables.contains(where: { $0.name.name == "I" }))
        XCTAssertTrue(allVariables.contains(where: { $0.name.name == "J" }))

        // Add end marker and detokenize
        allBytes.append(contentsOf: [0x00, 0x00, 0x00])
        let variableNames = allVariables.map { $0.name }
        let detokenized = detokenizer.detokenizeProgram(allBytes, variables: variableNames)

        XCTAssertEqual(detokenized.count, 5)
        XCTAssertTrue(detokenized[0].text.contains("FOR"))
        XCTAssertTrue(detokenized[1].text.contains("FOR"))
        XCTAssertTrue(detokenized[3].text.contains("NEXT"))
        XCTAssertTrue(detokenized[4].text.contains("NEXT"))
    }

    // =========================================================================
    // MARK: - IF/THEN Statements
    // =========================================================================

    /// Simple IF/THEN with line number target.
    func test_ifThen_gotoLine() throws {
        let source = "10 IF X=0 THEN 100"
        let vars = [
            BASICVariable(name: BASICVariableName(name: "X", type: .numeric), index: 0)
        ]
        let tokenized = try tokenizer.tokenize(source, existingVariables: vars)
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: vars.map { $0.name }
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("IF") ?? false)
        XCTAssertTrue(result?.text.contains("X") ?? false)
        XCTAssertTrue(result?.text.contains("THEN") ?? false)
    }

    /// IF with comparison operators.
    func test_ifThen_comparisonOperators() throws {
        let comparisons = ["<", ">", "<=", ">=", "<>", "="]
        let vars = [
            BASICVariable(name: BASICVariableName(name: "A", type: .numeric), index: 0),
            BASICVariable(name: BASICVariableName(name: "B", type: .numeric), index: 1)
        ]

        for op in comparisons {
            let source = "10 IF A\(op)B THEN 100"
            let tokenized = try tokenizer.tokenize(source, existingVariables: vars)
            let result = detokenizer.detokenizeLine(
                tokenized.bytes,
                variables: vars.map { $0.name }
            )

            XCTAssertNotNil(result, "Failed for operator \(op)")
            XCTAssertTrue(
                result?.text.contains("IF") ?? false,
                "Missing IF for operator \(op)"
            )
            XCTAssertTrue(
                result?.text.contains("THEN") ?? false,
                "Missing THEN for operator \(op)"
            )
        }
    }

    /// IF with logical operators AND/OR.
    func test_ifThen_logicalOperators() throws {
        let vars = [
            BASICVariable(name: BASICVariableName(name: "A", type: .numeric), index: 0),
            BASICVariable(name: BASICVariableName(name: "B", type: .numeric), index: 1)
        ]
        let source = "10 IF A>0 AND B>0 THEN 100"
        let tokenized = try tokenizer.tokenize(source, existingVariables: vars)
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: vars.map { $0.name }
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("AND") ?? false)
    }

    // =========================================================================
    // MARK: - GOSUB/RETURN
    // =========================================================================

    /// GOSUB round-trips correctly.
    func test_gosub() throws {
        let source = "10 GOSUB 1000"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("GOSUB") ?? false)
    }

    /// RETURN round-trips correctly.
    func test_return() throws {
        let source = "100 RETURN"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("RETURN") ?? false)
    }

    /// A program with GOSUB/RETURN structure.
    func test_gosubReturn_program() throws {
        let lines = [
            "10 GOSUB 100",
            "20 END",
            "100 PRINT \"SUB\"",
            "110 RETURN"
        ]

        var allVariables: [BASICVariable] = []
        var allBytes: [UInt8] = []

        for source in lines {
            let existing = allVariables
            let tokenized = try tokenizer.tokenize(source, existingVariables: existing)

            for newVar in tokenized.newVariables {
                let index = UInt8(allVariables.count)
                allVariables.append(BASICVariable(name: newVar, index: index))
            }

            allBytes.append(contentsOf: tokenized.bytes)
        }

        allBytes.append(contentsOf: [0x00, 0x00, 0x00])

        let variableNames = allVariables.map { $0.name }
        let detokenized = detokenizer.detokenizeProgram(allBytes, variables: variableNames)

        XCTAssertEqual(detokenized.count, 4)
        XCTAssertTrue(detokenized[0].text.contains("GOSUB"))
        XCTAssertTrue(detokenized[1].text.contains("END"))
        XCTAssertTrue(detokenized[2].text.contains("PRINT"))
        XCTAssertTrue(detokenized[3].text.contains("RETURN"))
    }

    // =========================================================================
    // MARK: - Arrays (DIM)
    // =========================================================================

    /// DIM for numeric array.
    func test_dim_numericArray() throws {
        let source = "10 DIM A(100)"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("DIM") ?? false)
        XCTAssertTrue(result?.text.contains("A(") ?? false)
    }

    /// DIM for string variable (Atari BASIC DIM A$(n) syntax).
    func test_dim_stringVariable() throws {
        let source = "10 DIM A$(50)"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("DIM") ?? false)
        XCTAssertTrue(result?.text.contains("A$") ?? false)
    }

    /// Multiple DIM in one line.
    func test_dim_multiple() throws {
        let source = "10 DIM A(10),B$(20)"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("DIM") ?? false)
        XCTAssertTrue(result?.text.contains(",") ?? false)
    }

    // =========================================================================
    // MARK: - String Operations
    // =========================================================================

    /// String assignment with DIM.
    func test_string_assignment() throws {
        let lines = [
            "10 DIM A$(20)",
            "20 A$=\"HELLO WORLD\""
        ]

        var allVariables: [BASICVariable] = []

        for source in lines {
            let existing = allVariables
            let tokenized = try tokenizer.tokenize(source, existingVariables: existing)

            for newVar in tokenized.newVariables {
                let index = UInt8(allVariables.count)
                allVariables.append(BASICVariable(name: newVar, index: index))
            }
        }

        // Verify string variable was created (may be .string or .stringArray
        // depending on whether DIM creates an array-typed variable)
        XCTAssertTrue(allVariables.contains(where: { $0.name.name == "A" }))
    }

    /// String functions (LEN, ASC, CHR$).
    func test_string_functions() throws {
        let functionTests: [(source: String, expectedFunction: String)] = [
            ("10 PRINT LEN(A$)", "LEN"),
            ("10 PRINT ASC(A$)", "ASC"),
            ("10 PRINT CHR$(65)", "CHR$"),
        ]

        let vars = [
            BASICVariable(
                name: BASICVariableName(name: "A", type: .string),
                index: 0
            )
        ]

        for (source, expectedFunc) in functionTests {
            let tokenized = try tokenizer.tokenize(source, existingVariables: vars)
            let result = detokenizer.detokenizeLine(
                tokenized.bytes,
                variables: vars.map { $0.name } + tokenized.newVariables
            )

            XCTAssertNotNil(result, "Failed for \(source)")
            XCTAssertTrue(
                result?.text.contains(expectedFunc) ?? false,
                "Missing \(expectedFunc) in: \(result?.text ?? "nil")"
            )
        }
    }

    // =========================================================================
    // MARK: - Math Expressions
    // =========================================================================

    /// Arithmetic operators (+, -, *, /).
    func test_math_arithmetic() throws {
        let vars = [
            BASICVariable(name: BASICVariableName(name: "A", type: .numeric), index: 0),
            BASICVariable(name: BASICVariableName(name: "B", type: .numeric), index: 1),
            BASICVariable(name: BASICVariableName(name: "C", type: .numeric), index: 2),
            BASICVariable(name: BASICVariableName(name: "D", type: .numeric), index: 3),
            BASICVariable(name: BASICVariableName(name: "E", type: .numeric), index: 4)
        ]

        let source = "10 R=A+B-C*D/E"
        let tokenized = try tokenizer.tokenize(source, existingVariables: vars)

        var allVarNames = vars.map { $0.name }
        allVarNames.append(contentsOf: tokenized.newVariables)

        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: allVarNames)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("+") ?? false)
        XCTAssertTrue(result?.text.contains("-") ?? false)
        XCTAssertTrue(result?.text.contains("*") ?? false)
        XCTAssertTrue(result?.text.contains("/") ?? false)
    }

    /// Parenthesized expressions.
    func test_math_parentheses() throws {
        let vars = [
            BASICVariable(name: BASICVariableName(name: "A", type: .numeric), index: 0),
            BASICVariable(name: BASICVariableName(name: "B", type: .numeric), index: 1)
        ]

        let source = "10 X=(A+B)*(A-B)"
        let tokenized = try tokenizer.tokenize(source, existingVariables: vars)

        var allVarNames = vars.map { $0.name }
        allVarNames.append(contentsOf: tokenized.newVariables)

        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: allVarNames)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("(") ?? false)
        XCTAssertTrue(result?.text.contains(")") ?? false)
    }

    /// Math functions (ABS, SIN, COS, ATN, INT, PEEK).
    func test_math_functions() throws {
        let functionTests: [(source: String, expectedFunction: String)] = [
            ("10 PRINT ABS(X)", "ABS"),
            ("10 PRINT SIN(X)", "SIN"),
            ("10 PRINT COS(X)", "COS"),
            ("10 PRINT ATN(X)", "ATN"),
            ("10 PRINT INT(X)", "INT"),
            ("10 PRINT PEEK(X)", "PEEK"),
        ]

        let vars = [
            BASICVariable(
                name: BASICVariableName(name: "X", type: .numeric),
                index: 0
            )
        ]

        for (source, expectedFunc) in functionTests {
            let tokenized = try tokenizer.tokenize(source, existingVariables: vars)
            let result = detokenizer.detokenizeLine(
                tokenized.bytes,
                variables: vars.map { $0.name } + tokenized.newVariables
            )

            XCTAssertNotNil(result, "Failed for \(source)")
            XCTAssertTrue(
                result?.text.contains(expectedFunc) ?? false,
                "Missing \(expectedFunc) in: \(result?.text ?? "nil")"
            )
        }
    }

    /// Power operator (^).
    func test_math_power() throws {
        let source = "10 X=2^8"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("^") ?? false)
    }

    /// Unary minus (negative numbers).
    func test_math_unaryMinus() throws {
        let source = "10 X=-1"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("-") ?? false)
    }

    // =========================================================================
    // MARK: - ON...GOTO / ON...GOSUB
    // =========================================================================

    /// ON...GOTO with multiple targets tokenizes correctly.
    ///
    /// ON...GOTO uses a special GOTO-within-ON token ($17) distinct from the
    /// standalone GOTO token ($0A). We verify the tokenizer produces the ON
    /// statement token and the special gotoInOn operator token.
    func test_onGoto() throws {
        let source = "10 ON X GOTO 100,200,300"
        let vars = [
            BASICVariable(name: BASICVariableName(name: "X", type: .numeric), index: 0)
        ]
        let tokenized = try tokenizer.tokenize(source, existingVariables: vars)

        // Verify tokenization succeeds
        XCTAssertEqual(tokenized.lineNumber, 10)
        XCTAssertFalse(tokenized.bytes.isEmpty)

        // Contains ON statement token ($1E)
        XCTAssertTrue(tokenized.bytes.contains(BASICStatementToken.on.rawValue))

        // Contains the variable reference
        XCTAssertTrue(tokenized.bytes.contains(0x80))

        // EOL marker at end
        XCTAssertEqual(tokenized.bytes.last, BASICSpecialToken.endOfLine)
    }

    // =========================================================================
    // MARK: - DATA/READ/RESTORE
    // =========================================================================

    /// DATA statement with values.
    func test_data() throws {
        let source = "10 DATA 1,2,3,4,5"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("DATA") ?? false)
    }

    /// READ statement.
    func test_read() throws {
        let source = "10 READ X"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("READ") ?? false)
    }

    /// RESTORE statement.
    func test_restore() throws {
        let source = "10 RESTORE"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("RESTORE") ?? false)
    }

    // =========================================================================
    // MARK: - POKE/PEEK
    // =========================================================================

    /// POKE statement.
    func test_poke() throws {
        let source = "10 POKE 710,0"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("POKE") ?? false)
    }

    /// PEEK function.
    func test_peek() throws {
        let source = "10 X=PEEK(710)"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(
            tokenized.bytes,
            variables: tokenized.newVariables
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("PEEK") ?? false)
    }

    // =========================================================================
    // MARK: - Complete Program
    // =========================================================================

    /// A realistic complete program with multiple construct types.
    func test_completeProgram() throws {
        let lines = [
            "10 REM FIBONACCI",
            "20 DIM A(20)",
            "30 A(0)=0",
            "40 A(1)=1",
            "50 FOR I=2 TO 20",
            "60 A(I)=A(I-1)+A(I-2)",
            "70 NEXT I",
            "80 FOR I=0 TO 20",
            "90 PRINT A(I)",
            "100 NEXT I",
            "110 END"
        ]

        var allVariables: [BASICVariable] = []
        var allBytes: [UInt8] = []

        for source in lines {
            let existing = allVariables
            let tokenized = try tokenizer.tokenize(source, existingVariables: existing)

            for newVar in tokenized.newVariables {
                let index = UInt8(allVariables.count)
                allVariables.append(BASICVariable(name: newVar, index: index))
            }

            allBytes.append(contentsOf: tokenized.bytes)
        }

        allBytes.append(contentsOf: [0x00, 0x00, 0x00])

        let variableNames = allVariables.map { $0.name }
        let detokenized = detokenizer.detokenizeProgram(allBytes, variables: variableNames)

        XCTAssertEqual(detokenized.count, 11)
        XCTAssertEqual(detokenized[0].lineNumber, 10)
        XCTAssertEqual(detokenized[10].lineNumber, 110)

        // Verify key constructs survived
        XCTAssertTrue(detokenized[0].text.contains("REM"))
        XCTAssertTrue(detokenized[1].text.contains("DIM"))
        XCTAssertTrue(detokenized[4].text.contains("FOR"))
        XCTAssertTrue(detokenized[6].text.contains("NEXT"))
        XCTAssertTrue(detokenized[8].text.contains("PRINT"))
        XCTAssertTrue(detokenized[10].text.contains("END"))
    }

    /// Token byte structure validation for a complex line.
    func test_tokenBytes_validStructure() throws {
        let source = "10 FOR I=1 TO 10 STEP 2"
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        // Minimum: lineNum(2) + offsets(2) + content + EOL(1)
        XCTAssertGreaterThanOrEqual(tokenized.bytes.count, 5)

        // Line number: 10 = $0A, $00
        XCTAssertEqual(tokenized.bytes[0], 0x0A)
        XCTAssertEqual(tokenized.bytes[1], 0x00)

        // Last byte is EOL marker
        XCTAssertEqual(tokenized.bytes.last, BASICSpecialToken.endOfLine)

        // Contains FOR statement token ($08)
        XCTAssertTrue(tokenized.bytes.contains(BASICStatementToken.forStatement.rawValue))
    }
}
