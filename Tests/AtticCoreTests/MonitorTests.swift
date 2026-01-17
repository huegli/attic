// =============================================================================
// MonitorTests.swift - Unit Tests for Monitor/Debugger Components
// =============================================================================
//
// This file contains tests for Phase 11 components:
// - OpcodeTable: 6502 opcode lookup and instruction information
// - Assembler: MAC65-style 6502 assembler
// - Expression parser: Arithmetic and label expression evaluation
// - BreakpointManager: BRK injection and PC-polling breakpoints
//
// These tests verify the core functionality without requiring ROM files
// or a running emulator.
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - Opcode Table Tests
// =============================================================================

/// Tests for the OpcodeTable.
final class OpcodeTableTests: XCTestCase {
    /// Test looking up a valid opcode.
    func test_lookup_lda_immediate() {
        let info = OpcodeTable.lookup(0xA9)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.mnemonic, "LDA")
        XCTAssertEqual(info?.mode, .immediate)
        XCTAssertEqual(info?.bytes, 2)
        XCTAssertEqual(info?.cycles, 2)
    }

    /// Test looking up an absolute instruction.
    func test_lookup_sta_absolute() {
        let info = OpcodeTable.lookup(0x8D)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.mnemonic, "STA")
        XCTAssertEqual(info?.mode, .absolute)
        XCTAssertEqual(info?.bytes, 3)
    }

    /// Test looking up an implied instruction.
    func test_lookup_nop() {
        let info = OpcodeTable.lookup(0xEA)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.mnemonic, "NOP")
        XCTAssertEqual(info?.mode, .implied)
        XCTAssertEqual(info?.bytes, 1)
    }

    /// Test looking up a branch instruction.
    func test_lookup_bne() {
        let info = OpcodeTable.lookup(0xD0)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.mnemonic, "BNE")
        XCTAssertEqual(info?.mode, .relative)
        XCTAssertEqual(info?.bytes, 2)
    }

    /// Test looking up BRK instruction.
    func test_lookup_brk() {
        let info = OpcodeTable.lookup(0x00)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.mnemonic, "BRK")
        XCTAssertEqual(info?.mode, .implied)
        XCTAssertEqual(info?.bytes, 1)
    }

    /// Test instructionLength for valid opcode.
    func test_instructionLength_valid() {
        XCTAssertEqual(OpcodeTable.instructionLength(0xA9), 2)  // LDA #$nn
        XCTAssertEqual(OpcodeTable.instructionLength(0x8D), 3)  // STA $nnnn
        XCTAssertEqual(OpcodeTable.instructionLength(0xEA), 1)  // NOP
    }

    /// Test opcodesFor mnemonic.
    func test_opcodesFor_lda() {
        let opcodes = OpcodeTable.opcodesFor(mnemonic: "LDA")

        XCTAssertFalse(opcodes.isEmpty)
        XCTAssertEqual(opcodes[.immediate], 0xA9)
        XCTAssertEqual(opcodes[.absolute], 0xAD)
        XCTAssertEqual(opcodes[.zeroPage], 0xA5)
    }

    /// Test opcode lookup by mnemonic and mode.
    func test_opcode_mnemonicAndMode() {
        XCTAssertEqual(OpcodeTable.opcode(for: "LDA", mode: .immediate), 0xA9)
        XCTAssertEqual(OpcodeTable.opcode(for: "STA", mode: .absolute), 0x8D)
        XCTAssertEqual(OpcodeTable.opcode(for: "JMP", mode: .absolute), 0x4C)
        XCTAssertEqual(OpcodeTable.opcode(for: "JMP", mode: .indirect), 0x6C)
    }

    /// Test isBranch helper.
    func test_isBranch() {
        XCTAssertTrue(OpcodeTable.isBranch("BNE"))
        XCTAssertTrue(OpcodeTable.isBranch("BEQ"))
        XCTAssertTrue(OpcodeTable.isBranch("BCC"))
        XCTAssertTrue(OpcodeTable.isBranch("bcs"))  // Case insensitive
        XCTAssertFalse(OpcodeTable.isBranch("JMP"))
        XCTAssertFalse(OpcodeTable.isBranch("LDA"))
    }

    /// Test isJump helper.
    func test_isJump() {
        XCTAssertTrue(OpcodeTable.isJump("JMP"))
        XCTAssertTrue(OpcodeTable.isJump("JSR"))
        XCTAssertFalse(OpcodeTable.isJump("BNE"))
        XCTAssertFalse(OpcodeTable.isJump("RTS"))
    }

    /// Test isReturn helper.
    func test_isReturn() {
        XCTAssertTrue(OpcodeTable.isReturn("RTS"))
        XCTAssertTrue(OpcodeTable.isReturn("RTI"))
        XCTAssertFalse(OpcodeTable.isReturn("JMP"))
        XCTAssertFalse(OpcodeTable.isReturn("JSR"))
    }

    /// Test branchTarget calculation.
    func test_branchTarget_forward() {
        // Branch from $0600 with offset +10 (after instruction at $0600)
        // PC after fetch = $0602, branch target = $0602 + 10 = $060C
        let target = OpcodeTable.branchTarget(from: 0x0602, offset: 10)
        XCTAssertEqual(target, 0x060C)
    }

    /// Test branchTarget backward.
    func test_branchTarget_backward() {
        // Branch backward with negative offset
        let target = OpcodeTable.branchTarget(from: 0x0602, offset: -5)
        XCTAssertEqual(target, 0x05FD)
    }

    /// Test allMnemonics returns complete set.
    func test_allMnemonics_count() {
        let mnemonics = OpcodeTable.allMnemonics

        // 6502 has 56 official mnemonics
        XCTAssertTrue(mnemonics.count >= 50)
        XCTAssertTrue(mnemonics.contains("LDA"))
        XCTAssertTrue(mnemonics.contains("STA"))
        XCTAssertTrue(mnemonics.contains("NOP"))
        XCTAssertTrue(mnemonics.contains("BRK"))
    }
}

// =============================================================================
// MARK: - Addressing Mode Tests
// =============================================================================

/// Tests for AddressingMode enum.
final class AddressingModeTests: XCTestCase {
    /// Test byte counts for each mode.
    func test_bytes() {
        XCTAssertEqual(AddressingMode.implied.bytes, 1)
        XCTAssertEqual(AddressingMode.accumulator.bytes, 1)
        XCTAssertEqual(AddressingMode.immediate.bytes, 2)
        XCTAssertEqual(AddressingMode.zeroPage.bytes, 2)
        XCTAssertEqual(AddressingMode.absolute.bytes, 3)
        XCTAssertEqual(AddressingMode.indirect.bytes, 3)
        XCTAssertEqual(AddressingMode.relative.bytes, 2)
    }

    /// Test page-crossing modes.
    func test_canCrossPage() {
        XCTAssertTrue(AddressingMode.absoluteX.canCrossPage)
        XCTAssertTrue(AddressingMode.absoluteY.canCrossPage)
        XCTAssertTrue(AddressingMode.indirectIndexed.canCrossPage)
        XCTAssertFalse(AddressingMode.absolute.canCrossPage)
        XCTAssertFalse(AddressingMode.zeroPage.canCrossPage)
    }
}

// =============================================================================
// MARK: - Assembler Tests
// =============================================================================

/// Tests for the 6502 Assembler.
final class AssemblerTests: XCTestCase {
    var assembler: Assembler!

    override func setUp() {
        super.setUp()
        assembler = Assembler(startAddress: 0x0600)
    }

    /// Test assembling LDA immediate.
    func test_assembleLine_ldaImmediate() throws {
        let result = try assembler.assembleLine("LDA #$00")

        XCTAssertEqual(result.bytes, [0xA9, 0x00])
        XCTAssertEqual(result.address, 0x0600)
        XCTAssertEqual(result.length, 2)
    }

    /// Test assembling STA absolute.
    func test_assembleLine_staAbsolute() throws {
        let result = try assembler.assembleLine("STA $D400")

        XCTAssertEqual(result.bytes, [0x8D, 0x00, 0xD4])
        XCTAssertEqual(result.address, 0x0600)
    }

    /// Test assembling NOP.
    func test_assembleLine_nop() throws {
        let result = try assembler.assembleLine("NOP")

        XCTAssertEqual(result.bytes, [0xEA])
        XCTAssertEqual(result.length, 1)
    }

    /// Test zero page optimization.
    func test_assembleLine_zeroPageOptimization() throws {
        let result = try assembler.assembleLine("LDA $00")

        // Should use zero page mode, not absolute
        XCTAssertEqual(result.bytes, [0xA5, 0x00])
        XCTAssertEqual(result.length, 2)
    }

    /// Test absolute addressing when needed.
    func test_assembleLine_absoluteWhenNeeded() throws {
        let result = try assembler.assembleLine("LDA $0100")

        // Address > $FF requires absolute mode
        XCTAssertEqual(result.bytes, [0xAD, 0x00, 0x01])
        XCTAssertEqual(result.length, 3)
    }

    /// Test indexed addressing.
    func test_assembleLine_indexedX() throws {
        let result = try assembler.assembleLine("LDA $D400,X")

        XCTAssertEqual(result.bytes, [0xBD, 0x00, 0xD4])
    }

    /// Test indexed Y addressing.
    func test_assembleLine_indexedY() throws {
        let result = try assembler.assembleLine("LDA $D400,Y")

        XCTAssertEqual(result.bytes, [0xB9, 0x00, 0xD4])
    }

    /// Test indirect indexed addressing.
    func test_assembleLine_indirectIndexedY() throws {
        let result = try assembler.assembleLine("LDA ($80),Y")

        XCTAssertEqual(result.bytes, [0xB1, 0x80])
    }

    /// Test indexed indirect addressing.
    func test_assembleLine_indexedIndirectX() throws {
        let result = try assembler.assembleLine("LDA ($80,X)")

        XCTAssertEqual(result.bytes, [0xA1, 0x80])
    }

    /// Test accumulator addressing.
    func test_assembleLine_accumulator() throws {
        let result = try assembler.assembleLine("ASL A")

        XCTAssertEqual(result.bytes, [0x0A])
    }

    /// Test JMP indirect.
    func test_assembleLine_jmpIndirect() throws {
        let result = try assembler.assembleLine("JMP ($FFFC)")

        XCTAssertEqual(result.bytes, [0x6C, 0xFC, 0xFF])
    }

    /// Test branch instruction.
    func test_assembleLine_branch() throws {
        // First define a label, then branch to it
        try assembler.symbols.define("LOOP", value: 0x0600)
        assembler.setPC(0x060A)  // Branch from $060A to $0600 = offset -12

        let result = try assembler.assembleLine("BNE LOOP")

        XCTAssertEqual(result.bytes.count, 2)
        XCTAssertEqual(result.bytes[0], 0xD0)  // BNE opcode
        // Offset: target - (PC + 2) = $0600 - $060C = -12 = $F4
        XCTAssertEqual(result.bytes[1], 0xF4)
    }

    /// Test invalid instruction.
    func test_assembleLine_invalidInstruction() {
        XCTAssertThrowsError(try assembler.assembleLine("XYZ #$00"))
    }

    /// Test PC advancement.
    func test_pcAdvancement() throws {
        XCTAssertEqual(assembler.currentPC, 0x0600)

        _ = try assembler.assembleLine("LDA #$00")  // 2 bytes
        XCTAssertEqual(assembler.currentPC, 0x0602)

        _ = try assembler.assembleLine("STA $D400")  // 3 bytes
        XCTAssertEqual(assembler.currentPC, 0x0605)

        _ = try assembler.assembleLine("NOP")  // 1 byte
        XCTAssertEqual(assembler.currentPC, 0x0606)
    }

    /// Test hex numbers.
    func test_assembleLine_hexNumbers() throws {
        let result1 = try assembler.assembleLine("LDA #$FF")
        XCTAssertEqual(result1.bytes[1], 0xFF)

        let result2 = try assembler.assembleLine("LDA #$10")
        XCTAssertEqual(result2.bytes[1], 0x10)
    }

    /// Test decimal numbers.
    func test_assembleLine_decimalNumbers() throws {
        let result = try assembler.assembleLine("LDA #100")
        XCTAssertEqual(result.bytes[1], 100)
    }

    /// Test binary numbers.
    func test_assembleLine_binaryNumbers() throws {
        let result = try assembler.assembleLine("LDA #%10101010")
        XCTAssertEqual(result.bytes[1], 0xAA)
    }

    /// Test character literals.
    func test_assembleLine_characterLiteral() throws {
        let result = try assembler.assembleLine("LDA #'A")
        XCTAssertEqual(result.bytes[1], 65)  // ASCII 'A'
    }

    /// Test label on line.
    func test_assembleLine_withLabel() throws {
        let result = try assembler.assembleLine("START LDA #$00")

        XCTAssertEqual(result.label, "START")
        XCTAssertEqual(result.bytes, [0xA9, 0x00])
        XCTAssertEqual(assembler.symbols.lookup("START"), 0x0600)
    }

    /// Test label with colon.
    func test_assembleLine_labelWithColon() throws {
        let result = try assembler.assembleLine("LOOP: INX")

        XCTAssertEqual(result.label, "LOOP")
        XCTAssertEqual(result.bytes, [0xE8])
    }
}

// =============================================================================
// MARK: - Pseudo-Op Tests
// =============================================================================

/// Tests for assembler pseudo-ops.
final class AssemblerPseudoOpTests: XCTestCase {
    var assembler: Assembler!

    override func setUp() {
        super.setUp()
        assembler = Assembler(startAddress: 0x0600)
    }

    /// Test ORG pseudo-op.
    func test_org() throws {
        let result = try assembler.assembleLine("ORG $0800")

        XCTAssertTrue(result.bytes.isEmpty)
        XCTAssertEqual(assembler.currentPC, 0x0800)
    }

    /// Test DB/BYTE pseudo-op.
    func test_byte() throws {
        let result = try assembler.assembleLine("DB $A9, $00, $8D")

        XCTAssertEqual(result.bytes, [0xA9, 0x00, 0x8D])
    }

    /// Test DW/WORD pseudo-op.
    func test_word() throws {
        let result = try assembler.assembleLine("DW $1234, $5678")

        // Little-endian
        XCTAssertEqual(result.bytes, [0x34, 0x12, 0x78, 0x56])
    }

    /// Test DS/BLOCK pseudo-op.
    func test_block() throws {
        let result = try assembler.assembleLine("DS 5")

        XCTAssertEqual(result.bytes, [0, 0, 0, 0, 0])
        XCTAssertEqual(result.bytes.count, 5)
    }

    /// Test HEX pseudo-op.
    func test_hex() throws {
        let result = try assembler.assembleLine("HEX A9008D00D4")

        XCTAssertEqual(result.bytes, [0xA9, 0x00, 0x8D, 0x00, 0xD4])
    }

    /// Test ASC pseudo-op.
    func test_asc() throws {
        let result = try assembler.assembleLine("ASC \"HELLO\"")

        XCTAssertEqual(result.bytes, [72, 69, 76, 76, 79])  // ASCII values
    }
}

// =============================================================================
// MARK: - Expression Parser Tests
// =============================================================================

/// Tests for expression parsing.
final class ExpressionParserTests: XCTestCase {
    var symbols: SymbolTable!

    override func setUp() {
        super.setUp()
        symbols = SymbolTable()
    }

    /// Test simple hex number.
    func test_hexNumber() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("$1234"), 0x1234)
    }

    /// Test simple decimal number.
    func test_decimalNumber() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("100"), 100)
    }

    /// Test binary number.
    func test_binaryNumber() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("%11110000"), 0xF0)
    }

    /// Test addition.
    func test_addition() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("$100+$10"), 0x110)
    }

    /// Test subtraction.
    func test_subtraction() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("$100-$10"), 0xF0)
    }

    /// Test multiplication.
    func test_multiplication() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("$10*$10"), 0x100)
    }

    /// Test division.
    func test_division() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("$100/$10"), 0x10)
    }

    /// Test low byte operator.
    func test_lowByte() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("<$1234"), 0x34)
    }

    /// Test high byte operator.
    func test_highByte() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate(">$1234"), 0x12)
    }

    /// Test parentheses.
    func test_parentheses() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        // (1 + 2) * 3 = 9
        XCTAssertEqual(try parser.evaluate("(1+2)*3"), 9)
        // Without parens: 1 + (2 * 3) = 7
        XCTAssertEqual(try parser.evaluate("1+2*3"), 7)
    }

    /// Test location counter.
    func test_locationCounter() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0x0600)
        XCTAssertEqual(try parser.evaluate("*"), 0x0600)
        XCTAssertEqual(try parser.evaluate("*+$10"), 0x0610)
    }

    /// Test label lookup.
    func test_labelLookup() throws {
        try symbols.define("SCREEN", value: 0xD400)
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("SCREEN"), 0xD400)
    }

    /// Test label in expression.
    func test_labelInExpression() throws {
        try symbols.define("BASE", value: 0x0600)
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("BASE+$10"), 0x0610)
    }

    /// Test undefined label throws.
    func test_undefinedLabel() {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertThrowsError(try parser.evaluate("UNDEFINED"))
    }

    /// Test character literal.
    func test_characterLiteral() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("'A"), 65)
    }
}

// =============================================================================
// MARK: - Symbol Table Tests
// =============================================================================

/// Tests for the SymbolTable.
final class SymbolTableTests: XCTestCase {
    var symbols: SymbolTable!

    override func setUp() {
        super.setUp()
        symbols = SymbolTable()
    }

    /// Test defining and looking up a symbol.
    func test_defineAndLookup() throws {
        try symbols.define("TEST", value: 0x1234)
        XCTAssertEqual(symbols.lookup("TEST"), 0x1234)
    }

    /// Test case insensitivity.
    func test_caseInsensitive() throws {
        try symbols.define("Test", value: 0x1234)
        XCTAssertEqual(symbols.lookup("TEST"), 0x1234)
        XCTAssertEqual(symbols.lookup("test"), 0x1234)
    }

    /// Test duplicate definition throws.
    func test_duplicateDefinition() throws {
        try symbols.define("TEST", value: 0x1234)
        XCTAssertThrowsError(try symbols.define("TEST", value: 0x5678))
    }

    /// Test lookup undefined returns nil.
    func test_lookupUndefined() {
        XCTAssertNil(symbols.lookup("UNDEFINED"))
    }

    /// Test clear.
    func test_clear() throws {
        try symbols.define("TEST", value: 0x1234)
        symbols.clear()
        XCTAssertNil(symbols.lookup("TEST"))
    }

    /// Test forward reference tracking.
    func test_forwardReferences() {
        symbols.reference("FORWARD")
        XCTAssertTrue(symbols.unresolvedReferences.contains("FORWARD"))

        try? symbols.define("FORWARD", value: 0x1234)
        XCTAssertFalse(symbols.unresolvedReferences.contains("FORWARD"))
    }
}

// =============================================================================
// MARK: - Breakpoint Tests
// =============================================================================

/// Tests for the BreakpointManager.
final class BreakpointManagerTests: XCTestCase {
    /// Test classifying RAM address.
    func test_classifyAddress_ram() async {
        let manager = BreakpointManager()

        XCTAssertEqual(await manager.classifyAddress(0x0600), .ram)
        XCTAssertEqual(await manager.classifyAddress(0x0000), .ram)
        XCTAssertEqual(await manager.classifyAddress(0xBFFF), .ram)
    }

    /// Test classifying ROM address.
    func test_classifyAddress_rom() async {
        let manager = BreakpointManager()

        XCTAssertEqual(await manager.classifyAddress(0xE000), .rom)
        XCTAssertEqual(await manager.classifyAddress(0xFFFC), .rom)
        XCTAssertEqual(await manager.classifyAddress(0xC000), .rom)
    }

    /// Test isROMAddress helper.
    func test_isROMAddress() async {
        let manager = BreakpointManager()

        XCTAssertFalse(await manager.isROMAddress(0x0600))
        XCTAssertTrue(await manager.isROMAddress(0xE000))
    }

    /// Test breakpoint tracking (without actual memory).
    func test_setBreakpointTracking() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0600, originalByte: 0xA9)

        let bp = await manager.getBreakpoint(at: 0x0600)
        XCTAssertNotNil(bp)
        XCTAssertEqual(bp?.address, 0x0600)
        XCTAssertEqual(bp?.originalByte, 0xA9)
    }

    /// Test hasBreakpoint.
    func test_hasBreakpoint() async {
        let manager = BreakpointManager()

        XCTAssertFalse(await manager.hasBreakpoint(at: 0x0600))

        await manager.setBreakpointTracking(at: 0x0600, originalByte: nil)

        XCTAssertTrue(await manager.hasBreakpoint(at: 0x0600))
    }

    /// Test getAllBreakpoints.
    func test_getAllBreakpoints() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0600, originalByte: nil)
        await manager.setBreakpointTracking(at: 0x0700, originalByte: nil)
        await manager.setBreakpointTracking(at: 0x0800, originalByte: nil)

        let breakpoints = await manager.getAllBreakpoints()

        XCTAssertEqual(breakpoints.count, 3)
    }

    /// Test getAllAddresses returns sorted.
    func test_getAllAddresses_sorted() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0800, originalByte: nil)
        await manager.setBreakpointTracking(at: 0x0600, originalByte: nil)
        await manager.setBreakpointTracking(at: 0x0700, originalByte: nil)

        let addresses = await manager.getAllAddresses()

        XCTAssertEqual(addresses, [0x0600, 0x0700, 0x0800])
    }

    /// Test ROM breakpoints are tracked separately.
    func test_romBreakpoints() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0xE477, originalByte: nil)

        XCTAssertTrue(await manager.hasROMBreakpoints)
        XCTAssertTrue(await manager.romBreakpoints.contains(0xE477))
    }

    /// Test checkROMBreakpoint.
    func test_checkROMBreakpoint() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0xE477, originalByte: nil)

        let bp = await manager.checkROMBreakpoint(at: 0xE477)
        XCTAssertNotNil(bp)
        XCTAssertEqual(bp?.address, 0xE477)

        let noBP = await manager.checkROMBreakpoint(at: 0xE000)
        XCTAssertNil(noBP)
    }

    /// Test hit counter.
    func test_recordHit() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0600, originalByte: nil)

        let bp1 = await manager.getBreakpoint(at: 0x0600)
        XCTAssertEqual(bp1?.hitCount, 0)

        await manager.recordHit(at: 0x0600)

        let bp2 = await manager.getBreakpoint(at: 0x0600)
        XCTAssertEqual(bp2?.hitCount, 1)
    }

    /// Test breakpoint formatting.
    func test_breakpointFormatted() {
        let ramBP = Breakpoint(address: 0x0600, type: .ram, originalByte: 0xA9)
        XCTAssertTrue(ramBP.formatted.contains("$0600"))
        XCTAssertTrue(ramBP.formatted.contains("RAM"))

        let romBP = Breakpoint(address: 0xE477, type: .rom)
        XCTAssertTrue(romBP.formatted.contains("$E477"))
        XCTAssertTrue(romBP.formatted.contains("ROM watch"))
    }
}

// =============================================================================
// MARK: - Interactive Assembler Tests
// =============================================================================

/// Tests for the InteractiveAssembler.
final class InteractiveAssemblerTests: XCTestCase {
    /// Test basic usage.
    func test_basicUsage() throws {
        let ia = InteractiveAssembler(startAddress: 0x0600)

        XCTAssertEqual(ia.currentAddress, 0x0600)

        let result1 = try ia.assembleLine("LDA #$00")
        XCTAssertEqual(result1.bytes, [0xA9, 0x00])
        XCTAssertEqual(ia.currentAddress, 0x0602)

        let result2 = try ia.assembleLine("STA $D400")
        XCTAssertEqual(result2.bytes, [0x8D, 0x00, 0xD4])
        XCTAssertEqual(ia.currentAddress, 0x0605)
    }

    /// Test format output.
    func test_format() throws {
        let ia = InteractiveAssembler(startAddress: 0x0600)
        let result = try ia.assembleLine("LDA #$00")

        let formatted = ia.format(result)

        XCTAssertTrue(formatted.contains("$0600"))
        XCTAssertTrue(formatted.contains("A9 00"))
        XCTAssertTrue(formatted.contains("LDA #$00"))
    }

    /// Test reset.
    func test_reset() throws {
        let ia = InteractiveAssembler(startAddress: 0x0600)

        _ = try ia.assembleLine("LDA #$00")
        XCTAssertEqual(ia.currentAddress, 0x0602)

        ia.reset(to: 0x0800)
        XCTAssertEqual(ia.currentAddress, 0x0800)
    }
}
