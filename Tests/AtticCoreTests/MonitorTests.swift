// =============================================================================
// MonitorTests.swift - Unit Tests for Monitor/Debugger Components
// =============================================================================
//
// This file contains tests for Phase 11 components:
// - Assembler: MAC65-style 6502 assembler
// - Expression parser: Arithmetic and label expression evaluation
// - BreakpointManager: BRK injection and PC-polling breakpoints
//
// Note: OpcodeTable and AddressingMode tests are in DisassemblerTests.swift
// since those types are shared between Disassembler and Monitor.
//
// These tests verify the core functionality without requiring ROM files
// or a running emulator.
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - Opcode Table Helper Tests (Monitor-specific functionality)
// =============================================================================

/// Tests for monitor-specific OpcodeTable helper functions.
final class MonitorOpcodeTableHelperTests: XCTestCase {
    /// Test looking up a valid opcode.
    func test_lookup_lda_immediate() {
        let info = OpcodeTable.lookup(0xA9)

        XCTAssertEqual(info.mnemonic, "LDA")
        XCTAssertEqual(info.mode, .immediate)
        XCTAssertEqual(info.byteCount, 2)
        XCTAssertEqual(info.cycles, 2)
    }

    /// Test looking up an absolute instruction.
    func test_lookup_sta_absolute() {
        let info = OpcodeTable.lookup(0x8D)

        XCTAssertEqual(info.mnemonic, "STA")
        XCTAssertEqual(info.mode, .absolute)
        XCTAssertEqual(info.byteCount, 3)
    }

    /// Test looking up an implied instruction.
    func test_lookup_nop() {
        let info = OpcodeTable.lookup(0xEA)

        XCTAssertEqual(info.mnemonic, "NOP")
        XCTAssertEqual(info.mode, .implied)
        XCTAssertEqual(info.byteCount, 1)
    }

    /// Test looking up a branch instruction.
    func test_lookup_bne() {
        let info = OpcodeTable.lookup(0xD0)

        XCTAssertEqual(info.mnemonic, "BNE")
        XCTAssertEqual(info.mode, .relative)
        XCTAssertEqual(info.byteCount, 2)
    }

    /// Test looking up BRK instruction.
    func test_lookup_brk() {
        let info = OpcodeTable.lookup(0x00)

        XCTAssertEqual(info.mnemonic, "BRK")
        XCTAssertEqual(info.mode, .implied)
        XCTAssertEqual(info.byteCount, 1)
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

    /// Test looking up an illegal opcode returns OpcodeInfo with isIllegal = true.
    func test_lookup_illegalOpcode() {
        // 0x02 is a JAM opcode (halts CPU)
        let info = OpcodeTable.lookup(0x02)
        XCTAssertTrue(info.isIllegal)
        XCTAssertEqual(info.mnemonic, "JAM")

        // 0xFF is ISC (illegal INC + SBC)
        let info2 = OpcodeTable.lookup(0xFF)
        XCTAssertTrue(info2.isIllegal)
        XCTAssertEqual(info2.mnemonic, "ISC")
    }

    /// Test instructionLength for illegal opcode.
    func test_instructionLength_illegalOpcode() {
        // JAM opcodes have length 1 (implied)
        XCTAssertEqual(OpcodeTable.instructionLength(0x02), 1)
        // ISC absolute,X has length 3
        XCTAssertEqual(OpcodeTable.instructionLength(0xFF), 3)
    }

    /// Test isSubroutineCall helper.
    func test_isSubroutineCall() {
        XCTAssertTrue(OpcodeTable.isSubroutineCall("JSR"))
        XCTAssertTrue(OpcodeTable.isSubroutineCall("jsr"))  // Case insensitive
        XCTAssertFalse(OpcodeTable.isSubroutineCall("JMP"))
        XCTAssertFalse(OpcodeTable.isSubroutineCall("RTS"))
        XCTAssertFalse(OpcodeTable.isSubroutineCall("BNE"))
    }

    /// Test all branch mnemonics are recognized.
    func test_allBranchMnemonics() {
        let branches = ["BCC", "BCS", "BEQ", "BMI", "BNE", "BPL", "BVC", "BVS"]
        for branch in branches {
            XCTAssertTrue(OpcodeTable.isBranch(branch), "\(branch) should be recognized as branch")
        }
    }

    /// Test opcodesFor returns empty for invalid mnemonic.
    func test_opcodesFor_invalidMnemonic() {
        let opcodes = OpcodeTable.opcodesFor(mnemonic: "XXX")
        XCTAssertTrue(opcodes.isEmpty)
    }

    /// Test opcode lookup with invalid mnemonic/mode combination.
    func test_opcode_invalidCombination() {
        // NOP doesn't have an immediate mode
        XCTAssertNil(OpcodeTable.opcode(for: "NOP", mode: .immediate))
        // Invalid mnemonic
        XCTAssertNil(OpcodeTable.opcode(for: "XXX", mode: .implied))
    }

    /// Test looking up stack operations.
    func test_lookup_stackOps() {
        // PHA
        let pha = OpcodeTable.lookup(0x48)
        XCTAssertEqual(pha.mnemonic, "PHA")
        XCTAssertEqual(pha.mode, .implied)

        // PLA
        let pla = OpcodeTable.lookup(0x68)
        XCTAssertEqual(pla.mnemonic, "PLA")
    }

    /// Test branchTarget with page crossing.
    func test_branchTarget_pageCrossing() {
        // Branch that crosses page boundary
        let target = OpcodeTable.branchTarget(from: 0x10FE, offset: 10)
        XCTAssertEqual(target, 0x1108)
    }
}

// =============================================================================
// MARK: - OpcodeInfo Usage Tests (Monitor-specific)
// =============================================================================
// Note: Core AddressingMode tests are in DisassemblerTests.swift.
// These tests verify Monitor-specific usage patterns.

/// Tests for OpcodeInfo usage in Monitor context.
final class MonitorOpcodeInfoUsageTests: XCTestCase {
    /// Test OpcodeInfo pageCrossCycles property.
    func test_pageCrossCycles() {
        // LDA absolute,X has page cross penalty
        let ldaAbsX = OpcodeTable.lookup(0xBD)
        XCTAssertEqual(ldaAbsX.pageCrossCycles, 1)

        // LDA absolute does not have page cross penalty
        let ldaAbs = OpcodeTable.lookup(0xAD)
        XCTAssertEqual(ldaAbs.pageCrossCycles, 0)
    }

    /// Test OpcodeInfo cycles property.
    func test_cycles() {
        let nop = OpcodeTable.lookup(0xEA)
        XCTAssertEqual(nop.cycles, 2)

        let ldaImm = OpcodeTable.lookup(0xA9)
        XCTAssertEqual(ldaImm.cycles, 2)

        let ldaAbs = OpcodeTable.lookup(0xAD)
        XCTAssertEqual(ldaAbs.cycles, 4)
    }

    /// Test byteCount derived from mode.
    func test_byteCount() {
        let nop = OpcodeTable.lookup(0xEA)
        XCTAssertEqual(nop.byteCount, 1)

        let ldaImm = OpcodeTable.lookup(0xA9)
        XCTAssertEqual(ldaImm.byteCount, 2)

        let jmpAbs = OpcodeTable.lookup(0x4C)
        XCTAssertEqual(jmpAbs.byteCount, 3)
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

    /// Test DCI pseudo-op (ASCII with high bit set on last byte).
    func test_dci() throws {
        let result = try assembler.assembleLine("DCI \"HI\"")

        // "HI" = 72, 73 but last byte has high bit set: 72, 73 | 0x80 = 72, 201
        XCTAssertEqual(result.bytes, [72, UInt8(73 | 0x80)])
    }

    /// Test DS with fill value (reserves zero-filled space).
    func test_ds_reserve() throws {
        let result = try assembler.assembleLine("DS 3")

        XCTAssertEqual(result.bytes, [0, 0, 0])
        XCTAssertEqual(assembler.currentPC, 0x0603)
    }

    /// Test END pseudo-op.
    func test_end() throws {
        let result = try assembler.assembleLine("END")

        XCTAssertTrue(result.bytes.isEmpty)
    }
}

// =============================================================================
// MARK: - Assembler Error Tests
// =============================================================================

/// Tests for assembler error handling.
final class AssemblerErrorTests: XCTestCase {
    var assembler: Assembler!

    override func setUp() {
        super.setUp()
        assembler = Assembler(startAddress: 0x0600)
    }

    /// Test invalid instruction error.
    func test_invalidInstruction() {
        // Need leading space so "XYZ" is treated as instruction, not label
        XCTAssertThrowsError(try assembler.assembleLine(" XYZ")) { error in
            guard case AssemblerError.invalidInstruction(let instr) = error else {
                XCTFail("Expected invalidInstruction error")
                return
            }
            XCTAssertEqual(instr, "XYZ")
        }
    }

    /// Test invalid addressing mode error.
    func test_invalidAddressingMode() {
        // NOP doesn't support immediate mode
        XCTAssertThrowsError(try assembler.assembleLine("NOP #$00")) { error in
            guard case AssemblerError.invalidAddressingMode = error else {
                XCTFail("Expected invalidAddressingMode error")
                return
            }
        }
    }

    /// Test branch out of range error.
    func test_branchOutOfRange() {
        // Define a label far away
        try? assembler.symbols.define("FAR", value: 0x1000)

        XCTAssertThrowsError(try assembler.assembleLine("BNE FAR")) { error in
            guard case AssemblerError.branchOutOfRange = error else {
                XCTFail("Expected branchOutOfRange error")
                return
            }
        }
    }

    /// Test value out of range error for immediate.
    func test_valueOutOfRange_immediate() {
        XCTAssertThrowsError(try assembler.assembleLine("LDA #$1FF")) { error in
            guard case AssemblerError.valueOutOfRange = error else {
                XCTFail("Expected valueOutOfRange error")
                return
            }
        }
    }

    /// Test invalid pseudo-op error.
    func test_invalidPseudoOp_orgWithoutAddress() {
        XCTAssertThrowsError(try assembler.assembleLine("ORG")) { error in
            guard case AssemblerError.invalidPseudoOp = error else {
                XCTFail("Expected invalidPseudoOp error")
                return
            }
        }
    }

    /// Test AssemblerError error descriptions.
    func test_errorDescriptions() {
        XCTAssertNotNil(AssemblerError.invalidInstruction("XYZ").errorDescription)
        XCTAssertNotNil(AssemblerError.invalidOperand("bad").errorDescription)
        XCTAssertNotNil(AssemblerError.invalidAddressingMode("LDA", "#$FFF").errorDescription)
        XCTAssertNotNil(AssemblerError.undefinedLabel("UNKNOWN").errorDescription)
        XCTAssertNotNil(AssemblerError.duplicateLabel("DUP").errorDescription)
        XCTAssertNotNil(AssemblerError.invalidExpression("???").errorDescription)
        XCTAssertNotNil(AssemblerError.valueOutOfRange("byte", 300, 0, 255).errorDescription)
        XCTAssertNotNil(AssemblerError.invalidPseudoOp("BAD").errorDescription)
        XCTAssertNotNil(AssemblerError.syntaxError("test").errorDescription)
        XCTAssertNotNil(AssemblerError.branchOutOfRange("FAR", 200).errorDescription)
    }

    /// Test AssemblerError equatable conformance.
    func test_errorEquatable() {
        let err1 = AssemblerError.invalidInstruction("XYZ")
        let err2 = AssemblerError.invalidInstruction("XYZ")
        let err3 = AssemblerError.invalidInstruction("ABC")

        XCTAssertEqual(err1, err2)
        XCTAssertNotEqual(err1, err3)
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

    /// Test unary minus.
    func test_unaryMinus() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("-5"), -5)
        XCTAssertEqual(try parser.evaluate("-$10"), -16)
    }

    /// Test unary plus.
    func test_unaryPlus() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("+5"), 5)
        XCTAssertEqual(try parser.evaluate("+$10"), 16)
    }

    /// Test nested parentheses.
    func test_nestedParentheses() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        // ((1 + 2) * (3 + 4)) = 3 * 7 = 21
        XCTAssertEqual(try parser.evaluate("((1+2)*(3+4))"), 21)
    }

    /// Test complex expression with multiple operators.
    func test_complexExpression() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        // 10 + 20 * 2 - 5 = 10 + 40 - 5 = 45
        XCTAssertEqual(try parser.evaluate("10+20*2-5"), 45)
    }

    /// Test division by zero throws error.
    func test_divisionByZero() {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertThrowsError(try parser.evaluate("10/0")) { error in
            guard case AssemblerError.invalidExpression(let msg) = error else {
                XCTFail("Expected invalidExpression error")
                return
            }
            XCTAssertTrue(msg.contains("zero"))
        }
    }

    /// Test 0x prefix for hex numbers.
    func test_0xHexPrefix() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("0xFF"), 255)
        XCTAssertEqual(try parser.evaluate("0x1234"), 0x1234)
    }

    /// Test whitespace handling.
    func test_whitespaceHandling() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("  $10  +  $20  "), 0x30)
    }

    /// Test location counter with arithmetic.
    func test_locationCounterArithmetic() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0x1000)
        XCTAssertEqual(try parser.evaluate("* - $100"), 0x0F00)
    }

    /// Test missing closing parenthesis error.
    func test_missingClosingParen() {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertThrowsError(try parser.evaluate("(1+2"))
    }

    /// Test empty expression error.
    func test_emptyExpression() {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertThrowsError(try parser.evaluate(""))
        XCTAssertThrowsError(try parser.evaluate("   "))
    }

    /// Test low/high byte with complex expression.
    func test_lowHighByteComplex() throws {
        try symbols.define("ADDR", value: 0xABCD)
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)

        XCTAssertEqual(try parser.evaluate("<ADDR"), 0xCD)
        XCTAssertEqual(try parser.evaluate(">ADDR"), 0xAB)
        XCTAssertEqual(try parser.evaluate("<(ADDR+1)"), 0xCE)
    }

    /// Test character literal with closing quote.
    func test_characterLiteralWithClosingQuote() throws {
        let parser = ExpressionParser(symbols: symbols, currentPC: 0)
        XCTAssertEqual(try parser.evaluate("'A'"), 65)
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

        let class1 = await manager.classifyAddress(0x0600)
        let class2 = await manager.classifyAddress(0x0000)
        let class3 = await manager.classifyAddress(0xBFFF)
        XCTAssertEqual(class1, .ram)
        XCTAssertEqual(class2, .ram)
        XCTAssertEqual(class3, .ram)
    }

    /// Test classifying ROM address.
    func test_classifyAddress_rom() async {
        let manager = BreakpointManager()

        let class1 = await manager.classifyAddress(0xE000)
        let class2 = await manager.classifyAddress(0xFFFC)
        let class3 = await manager.classifyAddress(0xC000)
        XCTAssertEqual(class1, .rom)
        XCTAssertEqual(class2, .rom)
        XCTAssertEqual(class3, .rom)
    }

    /// Test isROMAddress helper.
    func test_isROMAddress() async {
        let manager = BreakpointManager()

        let isROM1 = await manager.isROMAddress(0x0600)
        let isROM2 = await manager.isROMAddress(0xE000)
        XCTAssertFalse(isROM1)
        XCTAssertTrue(isROM2)
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

        let hasBP1 = await manager.hasBreakpoint(at: 0x0600)
        XCTAssertFalse(hasBP1)

        await manager.setBreakpointTracking(at: 0x0600, originalByte: nil)

        let hasBP2 = await manager.hasBreakpoint(at: 0x0600)
        XCTAssertTrue(hasBP2)
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

        let hasROMBPs = await manager.hasROMBreakpoints
        XCTAssertTrue(hasROMBPs)
        let romBps = await manager.romBreakpoints
        XCTAssertTrue(romBps.contains(0xE477))
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

    /// Test breakpoint formatting with hit count.
    func test_breakpointFormatted_withHitCount() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0600, originalByte: 0xA9)
        await manager.recordHit(at: 0x0600)
        await manager.recordHit(at: 0x0600)

        let bp = await manager.getBreakpoint(at: 0x0600)
        XCTAssertNotNil(bp)
        XCTAssertTrue(bp!.formatted.contains("hits: 2"))
    }

    /// Test getOriginalByte returns nil for ROM breakpoints.
    func test_getOriginalByte_rom() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0xE477, originalByte: nil)

        let original = await manager.getOriginalByte(at: 0xE477)
        XCTAssertNil(original)
    }

    /// Test getOriginalByte returns correct value for RAM breakpoints.
    func test_getOriginalByte_ram() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0600, originalByte: 0xA9)

        let original = await manager.getOriginalByte(at: 0x0600)
        XCTAssertEqual(original, 0xA9)
    }

    /// Test isTemporaryBreakpoint.
    func test_isTemporaryBreakpoint() async {
        let manager = BreakpointManager()
        let mockMemory = MockMemoryAccess()

        // Before setting temporary breakpoint
        let isTempBefore = await manager.isTemporaryBreakpoint(at: 0x0600)
        XCTAssertFalse(isTempBefore)

        // Set temporary breakpoint
        await manager.setTemporaryBreakpoint(at: 0x0600, memory: mockMemory)

        let isTempAfter = await manager.isTemporaryBreakpoint(at: 0x0600)
        let isTempOther = await manager.isTemporaryBreakpoint(at: 0x0601)
        XCTAssertTrue(isTempAfter)
        XCTAssertFalse(isTempOther)

        // Clear it
        await manager.clearTemporaryBreakpoint(memory: mockMemory)

        let isTempAfterClear = await manager.isTemporaryBreakpoint(at: 0x0600)
        XCTAssertFalse(isTempAfterClear)
    }

    /// Test temporary breakpoint in ROM uses PC watching.
    func test_temporaryBreakpoint_rom() async {
        let manager = BreakpointManager()
        let mockMemory = MockMemoryAccess()

        await manager.setTemporaryBreakpoint(at: 0xE477, memory: mockMemory)

        // ROM breakpoint should be in the ROM breakpoints set
        let isTemp = await manager.isTemporaryBreakpoint(at: 0xE477)
        XCTAssertTrue(isTemp)
        let romBps = await manager.romBreakpoints
        XCTAssertTrue(romBps.contains(0xE477))

        // Clear it
        await manager.clearTemporaryBreakpoint(memory: mockMemory)

        let romBpsAfter = await manager.romBreakpoints
        XCTAssertFalse(romBpsAfter.contains(0xE477))
    }

    /// Test clearing breakpoint tracking.
    func test_clearBreakpointTracking() async {
        let manager = BreakpointManager()

        await manager.setBreakpointTracking(at: 0x0600, originalByte: 0xA9)
        await manager.setBreakpointTracking(at: 0x0700, originalByte: 0x8D)

        let breakpoints = await manager.getAllBreakpoints()
        XCTAssertEqual(breakpoints.count, 2)
    }

    /// Test BRK opcode constant.
    func test_brkOpcodeConstant() {
        XCTAssertEqual(BreakpointManager.brkOpcode, 0x00)
    }

    /// Test ROM start address constant.
    func test_romStartAddress() {
        XCTAssertEqual(BreakpointManager.romStartAddress, 0xC000)
    }

    /// Test I/O address classification.
    func test_ioAddressClassification() async {
        let manager = BreakpointManager()

        // I/O addresses should be classified as ROM (can't breakpoint)
        let class1 = await manager.classifyAddress(0xD000)
        let class2 = await manager.classifyAddress(0xD400)
        let class3 = await manager.classifyAddress(0xD7FF)
        XCTAssertEqual(class1, .rom)
        XCTAssertEqual(class2, .rom)
        XCTAssertEqual(class3, .rom)
    }

    /// Test Breakpoint equality.
    func test_breakpointEquality() {
        let bp1 = Breakpoint(address: 0x0600, type: .ram, originalByte: 0xA9)
        let bp2 = Breakpoint(address: 0x0600, type: .rom)  // Same address, different type
        let bp3 = Breakpoint(address: 0x0700, type: .ram)

        // Equality is based on address only
        XCTAssertEqual(bp1, bp2)
        XCTAssertNotEqual(bp1, bp3)
    }

    /// Test Breakpoint default values.
    func test_breakpointDefaults() {
        let bp = Breakpoint(address: 0x0600, type: .ram)

        XCTAssertEqual(bp.hitCount, 0)
        XCTAssertTrue(bp.enabled)
        XCTAssertNil(bp.condition)
        XCTAssertNil(bp.originalByte)
    }
}

// =============================================================================
// MARK: - Breakpoint Error Tests
// =============================================================================

/// Tests for BreakpointError.
final class BreakpointErrorTests: XCTestCase {
    /// Test error descriptions.
    func test_errorDescriptions() {
        XCTAssertNotNil(BreakpointError.alreadySet(0x0600).errorDescription)
        XCTAssertTrue(BreakpointError.alreadySet(0x0600).errorDescription!.contains("0600"))

        XCTAssertNotNil(BreakpointError.notFound(0x0700).errorDescription)
        XCTAssertTrue(BreakpointError.notFound(0x0700).errorDescription!.contains("0700"))

        XCTAssertNotNil(BreakpointError.cannotModifyROM(0xE000).errorDescription)
        XCTAssertTrue(BreakpointError.cannotModifyROM(0xE000).errorDescription!.contains("E000"))

        XCTAssertNotNil(BreakpointError.invalidAddress(0xFFFF).errorDescription)
        XCTAssertTrue(BreakpointError.invalidAddress(0xFFFF).errorDescription!.contains("FFFF"))
    }
}

// =============================================================================
// MARK: - Mock Memory Access
// =============================================================================

/// Mock implementation of MemoryAccess for testing.
final class MockMemoryAccess: MemoryAccess, @unchecked Sendable {
    private var memory: [UInt16: UInt8] = [:]

    func readMemory(at address: UInt16) async -> UInt8 {
        memory[address] ?? 0
    }

    func writeMemory(at address: UInt16, value: UInt8) async {
        memory[address] = value
    }

    /// Sets a value for testing (synchronous).
    func set(_ address: UInt16, _ value: UInt8) {
        memory[address] = value
    }

    /// Gets a value for testing (synchronous).
    func get(_ address: UInt16) -> UInt8 {
        memory[address] ?? 0
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

    /// Test symbols property access.
    func test_symbols() throws {
        let ia = InteractiveAssembler(startAddress: 0x0600)

        // Define a label
        _ = try ia.assembleLine("START LDA #$00")

        // Access symbols
        XCTAssertEqual(ia.symbols.lookup("START"), 0x0600)
    }
}

// =============================================================================
// MARK: - MonitorStepResult Tests
// =============================================================================

/// Tests for MonitorStepResult.
final class MonitorStepResultTests: XCTestCase {
    /// Test success factory method.
    func test_success() {
        let regs = CPURegisters(a: 0x00, x: 0x01, y: 0x02, s: 0xFF, p: 0x20, pc: 0x0600)
        let result = MonitorStepResult.success(registers: regs, stoppedAt: 0x0602)

        XCTAssertTrue(result.success)
        XCTAssertFalse(result.breakpointHit)
        XCTAssertNil(result.breakpointAddress)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.stoppedAt, 0x0602)
        XCTAssertEqual(result.instructionsExecuted, 1)
        XCTAssertEqual(result.registers.pc, 0x0600)
    }

    /// Test success with custom instruction count.
    func test_success_customCount() {
        let regs = CPURegisters(a: 0x00, x: 0x00, y: 0x00, s: 0xFF, p: 0x20, pc: 0x0600)
        let result = MonitorStepResult.success(registers: regs, stoppedAt: 0x060A, instructionsExecuted: 5)

        XCTAssertEqual(result.instructionsExecuted, 5)
    }

    /// Test breakpoint factory method.
    func test_breakpoint() {
        let regs = CPURegisters(a: 0x00, x: 0x00, y: 0x00, s: 0xFF, p: 0x20, pc: 0x0700)
        let result = MonitorStepResult.breakpoint(registers: regs, address: 0x0700, instructionsExecuted: 10)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.breakpointHit)
        XCTAssertEqual(result.breakpointAddress, 0x0700)
        XCTAssertEqual(result.stoppedAt, 0x0700)
        XCTAssertEqual(result.instructionsExecuted, 10)
    }

    /// Test error factory method.
    func test_error() {
        let regs = CPURegisters(a: 0x00, x: 0x00, y: 0x00, s: 0xFF, p: 0x20, pc: 0x0600)
        let result = MonitorStepResult.error("Step failed", registers: regs)

        XCTAssertFalse(result.success)
        XCTAssertFalse(result.breakpointHit)
        XCTAssertNil(result.breakpointAddress)
        XCTAssertEqual(result.errorMessage, "Step failed")
        XCTAssertEqual(result.stoppedAt, 0x0600)
        XCTAssertEqual(result.instructionsExecuted, 0)
    }
}

// =============================================================================
// MARK: - ParsedOperand Tests
// =============================================================================

/// Tests for ParsedOperand enum.
final class ParsedOperandTests: XCTestCase {
    /// Test none operand.
    func test_none() {
        let op = ParsedOperand.none

        XCTAssertEqual(op.mode, .implied)
        XCTAssertEqual(op.value, 0)
    }

    /// Test accumulator operand.
    func test_accumulator() {
        let op = ParsedOperand.accumulator

        XCTAssertEqual(op.mode, .accumulator)
        XCTAssertEqual(op.value, 0)
    }

    /// Test immediate operand.
    func test_immediate() {
        let op = ParsedOperand.immediate(0x42)

        XCTAssertEqual(op.mode, .immediate)
        XCTAssertEqual(op.value, 0x42)
    }

    /// Test zeroPage operand.
    func test_zeroPage() {
        let op = ParsedOperand.zeroPage(0x80)

        XCTAssertEqual(op.mode, .zeroPage)
        XCTAssertEqual(op.value, 0x80)
    }

    /// Test absolute operand.
    func test_absolute() {
        let op = ParsedOperand.absolute(0x1234)

        XCTAssertEqual(op.mode, .absolute)
        XCTAssertEqual(op.value, 0x1234)
    }

    /// Test indexed operands.
    func test_indexed() {
        XCTAssertEqual(ParsedOperand.zeroPageX(0x50).mode, .zeroPageX)
        XCTAssertEqual(ParsedOperand.zeroPageY(0x60).mode, .zeroPageY)
        XCTAssertEqual(ParsedOperand.absoluteX(0x1000).mode, .absoluteX)
        XCTAssertEqual(ParsedOperand.absoluteY(0x2000).mode, .absoluteY)
    }

    /// Test indirect operands.
    func test_indirect() {
        XCTAssertEqual(ParsedOperand.indirect(0x1234).mode, .indirect)
        XCTAssertEqual(ParsedOperand.indexedIndirect(0x80).mode, .indexedIndirectX)
        XCTAssertEqual(ParsedOperand.indirectIndexed(0x90).mode, .indirectIndexedY)
    }

    /// Test relative operand.
    func test_relative() {
        let op = ParsedOperand.relative(0x060A)

        XCTAssertEqual(op.mode, .relative)
        XCTAssertEqual(op.value, 0x060A)
    }

    /// Test equatable conformance.
    func test_equatable() {
        let op1 = ParsedOperand.immediate(0x42)
        let op2 = ParsedOperand.immediate(0x42)
        let op3 = ParsedOperand.immediate(0x43)

        XCTAssertEqual(op1, op2)
        XCTAssertNotEqual(op1, op3)
    }
}

// =============================================================================
// MARK: - AssemblyResult Tests
// =============================================================================

/// Tests for AssemblyResult structure.
final class AssemblyResultTests: XCTestCase {
    /// Test basic properties.
    func test_basicProperties() {
        let result = AssemblyResult(
            bytes: [0xA9, 0x00],
            address: 0x0600,
            sourceLine: "LDA #$00",
            label: nil
        )

        XCTAssertEqual(result.bytes, [0xA9, 0x00])
        XCTAssertEqual(result.address, 0x0600)
        XCTAssertEqual(result.sourceLine, "LDA #$00")
        XCTAssertNil(result.label)
        XCTAssertEqual(result.length, 2)
    }

    /// Test with label.
    func test_withLabel() {
        let result = AssemblyResult(
            bytes: [0xA9, 0x00],
            address: 0x0600,
            sourceLine: "START LDA #$00",
            label: "START"
        )

        XCTAssertEqual(result.label, "START")
    }

    /// Test empty bytes (pseudo-op like ORG).
    func test_emptyBytes() {
        let result = AssemblyResult(
            bytes: [],
            address: 0x0800,
            sourceLine: "ORG $0800",
            label: nil
        )

        XCTAssertTrue(result.bytes.isEmpty)
        XCTAssertEqual(result.length, 0)
    }
}
