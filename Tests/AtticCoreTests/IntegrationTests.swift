// =============================================================================
// IntegrationTests.swift - Integration Tests for Cross-Module Functionality
// =============================================================================
//
// This file contains integration tests that verify the interaction between
// multiple AtticCore components. These tests focus on end-to-end workflows
// that cross module boundaries.
//
// Test Categories:
// 1. BASIC Program Pipeline - Tokenizer → Detokenizer Round-Trip
// 2. State Persistence Cycle - Save → Modify → Load → Verify
// 3. Assembler + Disassembler Integration
// 4. REPL → EmulatorEngine Integration
//
// These tests use mocked or minimal emulator state where possible to
// avoid requiring ROM files.
//
// Running tests:
//   swift test --filter IntegrationTests
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - BASIC Program Pipeline Integration Tests
// =============================================================================

/// Integration tests for the BASIC tokenization and execution pipeline.
///
/// These tests verify that BASIC source code is correctly:
/// 1. Lexed into tokens
/// 2. Tokenized into Atari BASIC format
/// 3. Can round-trip through detokenization
final class BASICPipelineIntegrationTests: XCTestCase {
    let tokenizer = BASICTokenizer()
    let detokenizer = BASICDetokenizer()

    // =========================================================================
    // MARK: - Tokenizer → Detokenizer Round-Trip Tests
    // =========================================================================

    /// Test simple PRINT statement round-trip.
    func test_roundTrip_simplePrint() throws {
        let source = "10 PRINT \"HELLO\""

        // Tokenize
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        XCTAssertFalse(tokenized.bytes.isEmpty)

        // Detokenize
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        // Verify
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertTrue(result?.text.contains("PRINT") ?? false)
        XCTAssertTrue(result?.text.contains("HELLO") ?? false)
    }

    /// Test numeric expression round-trip.
    func test_roundTrip_numericExpression() throws {
        let source = "10 X=42"

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: tokenized.newVariables)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertTrue(result?.text.contains("X") ?? false)
        XCTAssertTrue(result?.text.contains("=") ?? false)
    }

    /// Test FOR/NEXT loop round-trip.
    func test_roundTrip_forLoop() throws {
        let source = "10 FOR I=1 TO 10"

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: tokenized.newVariables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("FOR") ?? false)
        XCTAssertTrue(result?.text.contains("I") ?? false)
        XCTAssertTrue(result?.text.contains("TO") ?? false)
    }

    /// Test GOTO statement round-trip.
    func test_roundTrip_goto() throws {
        let source = "10 GOTO 50"

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lineNumber, 10)
        XCTAssertTrue(result?.text.contains("GOTO") ?? false)
    }

    /// Test REM statement round-trip.
    func test_roundTrip_rem() throws {
        let source = "10 REM THIS IS A COMMENT"

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.hasPrefix("REM") ?? false)
        XCTAssertTrue(result?.text.contains("THIS IS A COMMENT") ?? false)
    }

    /// Test GOSUB/RETURN round-trip.
    func test_roundTrip_gosub() throws {
        let source = "10 GOSUB 100"

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("GOSUB") ?? false)
    }

    /// Test string variable round-trip.
    func test_roundTrip_stringVariable() throws {
        let source = "10 A$=\"TEST\""

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: tokenized.newVariables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("A$") ?? false)
        XCTAssertTrue(result?.text.contains("TEST") ?? false)
    }

    /// Test DIM statement round-trip.
    func test_roundTrip_dimArray() throws {
        let source = "10 DIM A(100)"

        let tokenized = try tokenizer.tokenize(source, existingVariables: [])
        let result = detokenizer.detokenizeLine(tokenized.bytes, variables: tokenized.newVariables)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.text.contains("DIM") ?? false)
        XCTAssertTrue(result?.text.contains("A(") ?? false)
    }

    /// Test expression with multiple variables.
    func test_roundTrip_expression() throws {
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

    // =========================================================================
    // MARK: - Token Format Validation Tests
    // =========================================================================

    /// Test that tokenized output has valid structure.
    func test_tokenFormat_hasValidStructure() throws {
        let source = "10 PRINT \"X\""
        let tokenized = try tokenizer.tokenize(source, existingVariables: [])

        // Minimum structure: lineNum (2) + length (1) + content + EOL
        XCTAssertGreaterThanOrEqual(tokenized.bytes.count, 4)

        // First two bytes are line number (little-endian)
        let lineNum = UInt16(tokenized.bytes[0]) | (UInt16(tokenized.bytes[1]) << 8)
        XCTAssertEqual(lineNum, 10)
    }

    /// Test that line numbers are preserved correctly.
    func test_tokenFormat_lineNumbersPreserved() throws {
        // Test various line numbers
        for lineNum in [1, 100, 1000, 10000, 32767] {
            let source = "\(lineNum) PRINT"
            let tokenized = try tokenizer.tokenize(source, existingVariables: [])
            let result = detokenizer.detokenizeLine(tokenized.bytes, variables: [])

            XCTAssertEqual(result?.lineNumber, UInt16(lineNum),
                           "Line number \(lineNum) should be preserved")
        }
    }

    // =========================================================================
    // MARK: - Error Handling Tests
    // =========================================================================

    /// Test tokenizer handles unterminated strings.
    func test_tokenizer_unterminatedString() {
        let badSource = "10 PRINT \"HELLO"  // Missing closing quote

        XCTAssertThrowsError(try tokenizer.tokenize(badSource, existingVariables: []))
    }

    /// Test detokenizer handles truncated data.
    func test_detokenizer_truncatedData() {
        let truncated: [UInt8] = [0x0A, 0x00]  // Just line number, no length

        let result = detokenizer.detokenizeLine(truncated, variables: [])
        XCTAssertNil(result)
    }

    /// Test detokenizer handles empty data.
    func test_detokenizer_emptyData() {
        let result = detokenizer.detokenizeLine([], variables: [])
        XCTAssertNil(result)
    }
}

// =============================================================================
// MARK: - State Persistence Integration Tests
// =============================================================================

/// Integration tests for the full state persistence cycle.
///
/// These tests verify the complete save/load workflow including:
/// - Metadata preservation
/// - State data integrity
/// - REPL mode restoration
/// - Error recovery
final class StatePersistenceIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Full Cycle Tests
    // =========================================================================

    /// Test complete save/load cycle preserves all data.
    func test_fullCycle_preservesAllData() throws {
        // Create original metadata
        let originalMetadata = StateMetadata(
            timestamp: "2025-01-19T12:00:00.000Z",
            replMode: REPLModeReference(from: .monitor),
            mountedDisks: [
                MountedDiskReference(drive: 1, path: "/test/disk1.atr", diskType: "SS/SD", readOnly: false),
                MountedDiskReference(drive: 2, path: "/test/disk2.atr", diskType: "SS/ED", readOnly: true)
            ],
            note: "Integration test state",
            appVersion: "1.0.0"
        )

        // Create state with specific data pattern
        var originalState = EmulatorState()
        originalState.tags.size = 2048
        originalState.tags.cpu = 0x100
        originalState.tags.pc = 0x0600
        originalState.flags.frameCount = 99999
        // Create recognizable data pattern
        originalState.data = (0..<256).map { UInt8($0) }

        // Save
        let testURL = tempDir.appendingPathComponent("cycle_test.attic")
        try StateFileHandler.write(to: testURL, metadata: originalMetadata, state: originalState)

        // Load
        let (loadedMetadata, loadedState) = try StateFileHandler.read(from: testURL)

        // Verify metadata
        XCTAssertEqual(loadedMetadata.timestamp, originalMetadata.timestamp)
        XCTAssertEqual(loadedMetadata.replMode.mode, "monitor")
        XCTAssertEqual(loadedMetadata.mountedDisks.count, 2)
        XCTAssertEqual(loadedMetadata.mountedDisks[0].drive, 1)
        XCTAssertEqual(loadedMetadata.mountedDisks[1].readOnly, true)
        XCTAssertEqual(loadedMetadata.note, "Integration test state")

        // Verify state
        XCTAssertEqual(loadedState.tags.size, originalState.tags.size)
        XCTAssertEqual(loadedState.tags.cpu, originalState.tags.cpu)
        XCTAssertEqual(loadedState.tags.pc, originalState.tags.pc)
        XCTAssertEqual(loadedState.flags.frameCount, originalState.flags.frameCount)
        XCTAssertEqual(loadedState.data, originalState.data)
    }

    /// Test multiple save/load cycles maintain integrity.
    func test_multipleCycles_maintainIntegrity() throws {
        var state = EmulatorState()
        state.data = Array(repeating: 0xAB, count: 1000)

        let testURL = tempDir.appendingPathComponent("multi_cycle.attic")

        // Perform 5 save/load cycles
        for i in 0..<5 {
            let metadata = StateMetadata.create(
                replMode: .basic(variant: .atari),
                mountedDisks: []
            )

            // Modify state slightly each cycle
            state.flags.frameCount = UInt32(i * 1000)

            try StateFileHandler.write(to: testURL, metadata: metadata, state: state)
            let (_, loaded) = try StateFileHandler.read(from: testURL)

            XCTAssertEqual(loaded.flags.frameCount, UInt32(i * 1000))
            XCTAssertEqual(loaded.data.count, 1000)
            XCTAssertTrue(loaded.data.allSatisfy { $0 == 0xAB })
        }
    }

    /// Test REPL mode is correctly restored.
    func test_replModeRestoration() throws {
        let modes: [REPLMode] = [
            .monitor,
            .basic(variant: .atari),
            .basic(variant: .turbo),
            .dos
        ]

        for mode in modes {
            let metadata = StateMetadata.create(replMode: mode, mountedDisks: [])
            var state = EmulatorState()
            state.data = [0x00]

            let testURL = tempDir.appendingPathComponent("mode_\(mode.name).attic")

            try StateFileHandler.write(to: testURL, metadata: metadata, state: state)
            let (loaded, _) = try StateFileHandler.read(from: testURL)

            let restoredMode = loaded.replMode.toREPLMode()
            XCTAssertEqual(restoredMode, mode, "Mode \(mode.name) should be preserved")
        }
    }

    // =========================================================================
    // MARK: - Large Data Tests
    // =========================================================================

    /// Test with realistic emulator state size (~210KB).
    func test_largeState_roundTrip() throws {
        var state = EmulatorState()
        state.tags.size = 210_000
        // Simulate realistic memory content
        state.data = (0..<210_000).map { UInt8($0 & 0xFF) }

        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let testURL = tempDir.appendingPathComponent("large_state.attic")

        try StateFileHandler.write(to: testURL, metadata: metadata, state: state)

        // Verify file size is reasonable
        let attrs = try FileManager.default.attributesOfItem(atPath: testURL.path)
        let fileSize = attrs[.size] as! UInt64
        XCTAssertGreaterThan(fileSize, 200_000)

        // Load and verify
        let (_, loaded) = try StateFileHandler.read(from: testURL)
        XCTAssertEqual(loaded.data.count, 210_000)

        // Spot check data integrity
        XCTAssertEqual(loaded.data[0], 0x00)
        XCTAssertEqual(loaded.data[255], 0xFF)
        XCTAssertEqual(loaded.data[256], 0x00)
    }
}

// =============================================================================
// MARK: - Assembler + Disassembler Integration Tests
// =============================================================================

/// Integration tests for assembler and disassembler round-trip.
///
/// These tests verify that:
/// - Assembled code can be correctly disassembled
/// - All addressing modes work correctly
/// - Branch instructions calculate targets properly
final class AssemblerDisassemblerIntegrationTests: XCTestCase {

    /// Test assembling and then disassembling code produces consistent results.
    func test_assembleDisassemble_roundTrip() throws {
        let assembler = Assembler(startAddress: 0x0600)
        let disassembler = Disassembler(labels: AddressLabels())

        // Assemble a simple program
        let ldaResult = try assembler.assembleLine("LDA #$42")
        let staResult = try assembler.assembleLine("STA $D40A")
        let rtsResult = try assembler.assembleLine("RTS")

        // Disassemble each instruction individually
        let inst1 = disassembler.disassembleBytes(at: 0x0600, bytes: ldaResult.bytes)
        let inst2 = disassembler.disassembleBytes(at: 0x0602, bytes: staResult.bytes)
        let inst3 = disassembler.disassembleBytes(at: 0x0605, bytes: rtsResult.bytes)

        // Verify instructions match what was assembled
        XCTAssertNotNil(inst1)
        XCTAssertEqual(inst1?.mnemonic, "LDA")
        XCTAssertEqual(inst1?.addressingMode, .immediate)
        XCTAssertEqual(inst1?.bytes, ldaResult.bytes)

        XCTAssertNotNil(inst2)
        XCTAssertEqual(inst2?.mnemonic, "STA")
        XCTAssertEqual(inst2?.addressingMode, .absolute)
        XCTAssertEqual(inst2?.bytes, staResult.bytes)

        XCTAssertNotNil(inst3)
        XCTAssertEqual(inst3?.mnemonic, "RTS")
        XCTAssertEqual(inst3?.addressingMode, .implied)
        XCTAssertEqual(inst3?.bytes, rtsResult.bytes)
    }

    /// Test key addressing modes assemble and disassemble correctly.
    func test_addressingModes_roundTrip() throws {
        let assembler = Assembler(startAddress: 0x0600)
        let disassembler = Disassembler(labels: AddressLabels())

        let testCases: [(source: String, expectedMode: AddressingMode)] = [
            ("LDA #$FF", .immediate),
            ("LDA $00", .zeroPage),
            ("LDA $1234", .absolute),
            ("LDA $10,X", .zeroPageX),
            ("LDA $1234,X", .absoluteX),
            ("LDA $1234,Y", .absoluteY),
            ("LDA ($10,X)", .indexedIndirectX),
            ("LDA ($10),Y", .indirectIndexedY),
            ("ASL A", .accumulator),
            ("NOP", .implied),
            ("JMP ($FFFC)", .indirect)
        ]

        for (source, expectedMode) in testCases {
            assembler.setPC(0x0600)
            let result = try assembler.assembleLine(source)

            let instruction = disassembler.disassembleBytes(at: 0x0600, bytes: result.bytes)

            XCTAssertNotNil(instruction, "Failed to disassemble '\(source)'")
            XCTAssertEqual(instruction?.addressingMode, expectedMode,
                           "Mode mismatch for '\(source)'")
        }
    }

    /// Test branch instructions with labels.
    func test_branchInstructions() throws {
        let assembler = Assembler(startAddress: 0x0600)
        let disassembler = Disassembler(labels: AddressLabels())

        // Define a label
        try assembler.symbols.define("TARGET", value: 0x0620)

        // Assemble a branch to the label
        let result = try assembler.assembleLine("BNE TARGET")

        XCTAssertEqual(result.bytes.count, 2)
        XCTAssertEqual(result.bytes[0], 0xD0)  // BNE opcode

        // Disassemble and verify
        let instruction = disassembler.disassembleBytes(at: 0x0600, bytes: result.bytes)

        XCTAssertNotNil(instruction)
        XCTAssertEqual(instruction?.mnemonic, "BNE")
        XCTAssertEqual(instruction?.addressingMode, .relative)
        // Target should be $0620
        XCTAssertEqual(instruction?.targetAddress, 0x0620)
    }

    /// Test multiple branch types.
    func test_allBranchTypes() throws {
        let assembler = Assembler(startAddress: 0x0600)
        let disassembler = Disassembler(labels: AddressLabels())

        let branches = ["BEQ", "BNE", "BCS", "BCC", "BMI", "BPL", "BVS", "BVC"]

        for branch in branches {
            assembler.setPC(0x0600)

            // Forward branch (+10)
            let result = try assembler.assembleLine("\(branch) $060C")

            XCTAssertEqual(result.bytes.count, 2, "\(branch) should be 2 bytes")

            let instruction = disassembler.disassembleBytes(at: 0x0600, bytes: result.bytes)
            XCTAssertEqual(instruction?.mnemonic, branch)
            XCTAssertEqual(instruction?.addressingMode, .relative)
        }
    }

    /// Test PC advancement during assembly.
    func test_pcAdvancement() throws {
        let assembler = Assembler(startAddress: 0x0600)

        XCTAssertEqual(assembler.currentPC, 0x0600)

        _ = try assembler.assembleLine("LDA #$00")  // 2 bytes
        XCTAssertEqual(assembler.currentPC, 0x0602)

        _ = try assembler.assembleLine("STA $D400")  // 3 bytes
        XCTAssertEqual(assembler.currentPC, 0x0605)

        _ = try assembler.assembleLine("NOP")  // 1 byte
        XCTAssertEqual(assembler.currentPC, 0x0606)

        _ = try assembler.assembleLine("RTS")  // 1 byte
        XCTAssertEqual(assembler.currentPC, 0x0607)
    }
}

// =============================================================================
// MARK: - REPL Engine Integration Tests
// =============================================================================

/// Integration tests for REPL engine command processing.
///
/// These tests verify that REPL commands are correctly:
/// - Parsed
/// - Executed against the emulator
/// - Formatted for output
final class REPLEngineIntegrationTests: XCTestCase {
    var engine: EmulatorEngine!
    var repl: REPLEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = EmulatorEngine()
        repl = REPLEngine(emulator: engine, initialMode: .monitor)
    }

    // =========================================================================
    // MARK: - Mode Switching Tests
    // =========================================================================

    /// Test switching between all modes.
    func test_modeSwitching() async {
        // Start in monitor mode
        var mode = await repl.mode
        XCTAssertEqual(mode, .monitor)

        // Switch to BASIC
        let output1 = await repl.execute(".basic")
        XCTAssertNotNil(output1)
        mode = await repl.mode
        if case .basic = mode { } else { XCTFail("Should be in BASIC mode") }

        // Switch to DOS
        let output2 = await repl.execute(".dos")
        XCTAssertNotNil(output2)
        mode = await repl.mode
        XCTAssertEqual(mode, .dos)

        // Switch back to monitor
        let output3 = await repl.execute(".monitor")
        XCTAssertNotNil(output3)
        mode = await repl.mode
        XCTAssertEqual(mode, .monitor)
    }

    /// Test prompt changes with mode.
    func test_promptChangesWithMode() async {
        // Monitor prompt includes PC
        let monitorPrompt = await repl.prompt
        XCTAssertTrue(monitorPrompt.contains("[monitor]"))
        XCTAssertTrue(monitorPrompt.contains("$"))

        // Switch to BASIC
        _ = await repl.execute(".basic")
        let basicPrompt = await repl.prompt
        XCTAssertTrue(basicPrompt.contains("[basic]"))

        // Switch to DOS
        _ = await repl.execute(".dos")
        let dosPrompt = await repl.prompt
        XCTAssertTrue(dosPrompt.contains("[dos]"))
        XCTAssertTrue(dosPrompt.contains("D"))
    }

    // =========================================================================
    // MARK: - Monitor Command Tests
    // =========================================================================

    /// Test registers command.
    func test_monitor_registersCommand() async {
        let output = await repl.execute("r")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("A=") ?? false)
        XCTAssertTrue(output?.contains("X=") ?? false)
        XCTAssertTrue(output?.contains("Y=") ?? false)
        XCTAssertTrue(output?.contains("PC=") ?? false)
    }

    /// Test help command.
    func test_helpCommand() async {
        let output = await repl.execute("help")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Commands") ?? false ||
                      output?.contains("commands") ?? false ||
                      output?.contains("help") ?? false)
    }

    /// Test status command.
    func test_statusCommand() async {
        let output = await repl.execute("status")

        XCTAssertNotNil(output)
        // Should contain emulator state info
        XCTAssertTrue((output?.count ?? 0) > 0)
    }

    // =========================================================================
    // MARK: - Error Handling Tests
    // =========================================================================

    /// Test invalid command produces error.
    func test_invalidCommand_producesError() async {
        let output = await repl.execute("xyzzy")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.lowercased().contains("error") ??
                      output?.lowercased().contains("unknown") ?? false)
    }
}

// =============================================================================
// MARK: - Expression Evaluator Integration Tests
// =============================================================================

/// Integration tests for expression evaluation in assembler/monitor context.
final class ExpressionEvaluatorIntegrationTests: XCTestCase {

    /// Test numeric expressions through assembler.
    func test_numericExpressions() throws {
        let assembler = Assembler(startAddress: 0x0600)

        // Hex number
        let result1 = try assembler.assembleLine("LDA #$FF")
        XCTAssertEqual(result1.bytes[1], 0xFF)

        // Decimal number
        let result2 = try assembler.assembleLine("LDA #100")
        XCTAssertEqual(result2.bytes[1], 100)

        // Binary number
        let result3 = try assembler.assembleLine("LDA #%10101010")
        XCTAssertEqual(result3.bytes[1], 0xAA)
    }

    /// Test address expressions.
    func test_addressExpressions() throws {
        let assembler = Assembler(startAddress: 0x0600)

        // Define symbols
        try assembler.symbols.define("BASE", value: 0x1000)
        try assembler.symbols.define("OFFSET", value: 0x10)

        // Use symbol in instruction
        let result = try assembler.assembleLine("LDA BASE")
        XCTAssertEqual(result.bytes, [0xAD, 0x00, 0x10])  // LDA $1000
    }

    /// Test character literals.
    func test_characterLiterals() throws {
        let assembler = Assembler(startAddress: 0x0600)

        let result = try assembler.assembleLine("LDA #'A")
        XCTAssertEqual(result.bytes[1], 65)  // ASCII 'A'
    }
}
