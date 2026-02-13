// =============================================================================
// DisassemblerTests.swift - Unit Tests for 6502 Disassembler
// =============================================================================
//
// This file contains comprehensive unit tests for the Phase 10 6502 Disassembler
// implementation. Tests cover:
//
// - AddressingMode: byte counts, operand formatting
// - OpcodeInfo/OpcodeTable: opcode lookups, cycle counts, flags
// - DisassembledInstruction: formatting, computed properties
// - AddressLabels: label lookup and management
// - Disassembler: full instruction disassembly
// - ArrayMemoryBus: memory access helper
// - CLI Protocol: disassemble command parsing
//
// Running these tests:
//   swift test --filter Disassembler
//   swift test --filter AddressingMode
//   swift test --filter OpcodeTable
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - AddressingMode Tests
// =============================================================================

/// Tests for the AddressingMode enum.
final class AddressingModeTests: XCTestCase {

    // MARK: - Byte Count Tests

    /// Test that implied addressing mode has 1 byte.
    func test_byteCount_implied() {
        XCTAssertEqual(AddressingMode.implied.byteCount, 1)
    }

    /// Test that accumulator addressing mode has 1 byte.
    func test_byteCount_accumulator() {
        XCTAssertEqual(AddressingMode.accumulator.byteCount, 1)
    }

    /// Test that immediate addressing mode has 2 bytes.
    func test_byteCount_immediate() {
        XCTAssertEqual(AddressingMode.immediate.byteCount, 2)
    }

    /// Test that zero page addressing modes have 2 bytes.
    func test_byteCount_zeroPage() {
        XCTAssertEqual(AddressingMode.zeroPage.byteCount, 2)
        XCTAssertEqual(AddressingMode.zeroPageX.byteCount, 2)
        XCTAssertEqual(AddressingMode.zeroPageY.byteCount, 2)
    }

    /// Test that relative addressing mode has 2 bytes.
    func test_byteCount_relative() {
        XCTAssertEqual(AddressingMode.relative.byteCount, 2)
    }

    /// Test that indirect indexed modes have 2 bytes.
    func test_byteCount_indirectIndexed() {
        XCTAssertEqual(AddressingMode.indexedIndirectX.byteCount, 2)
        XCTAssertEqual(AddressingMode.indirectIndexedY.byteCount, 2)
    }

    /// Test that absolute addressing modes have 3 bytes.
    func test_byteCount_absolute() {
        XCTAssertEqual(AddressingMode.absolute.byteCount, 3)
        XCTAssertEqual(AddressingMode.absoluteX.byteCount, 3)
        XCTAssertEqual(AddressingMode.absoluteY.byteCount, 3)
    }

    /// Test that indirect addressing mode has 3 bytes.
    func test_byteCount_indirect() {
        XCTAssertEqual(AddressingMode.indirect.byteCount, 3)
    }

    /// Test that unknown addressing mode has 1 byte.
    func test_byteCount_unknown() {
        XCTAssertEqual(AddressingMode.unknown.byteCount, 1)
    }

    // MARK: - Operand Byte Count Tests

    /// Test operand byte counts are one less than total byte count.
    func test_operandByteCount() {
        XCTAssertEqual(AddressingMode.implied.operandByteCount, 0)
        XCTAssertEqual(AddressingMode.immediate.operandByteCount, 1)
        XCTAssertEqual(AddressingMode.absolute.operandByteCount, 2)
    }

    // MARK: - Operand Formatting Tests

    /// Test immediate mode formatting.
    func test_formatOperand_immediate() {
        let result = AddressingMode.immediate.formatOperand(0x42)
        XCTAssertEqual(result, "#$42")
    }

    /// Test zero page mode formatting.
    func test_formatOperand_zeroPage() {
        let result = AddressingMode.zeroPage.formatOperand(0x80)
        XCTAssertEqual(result, "$80")
    }

    /// Test zero page,X mode formatting.
    func test_formatOperand_zeroPageX() {
        let result = AddressingMode.zeroPageX.formatOperand(0x80)
        XCTAssertEqual(result, "$80,X")
    }

    /// Test zero page,Y mode formatting.
    func test_formatOperand_zeroPageY() {
        let result = AddressingMode.zeroPageY.formatOperand(0x80)
        XCTAssertEqual(result, "$80,Y")
    }

    /// Test absolute mode formatting.
    func test_formatOperand_absolute() {
        let result = AddressingMode.absolute.formatOperand(0x1234)
        XCTAssertEqual(result, "$1234")
    }

    /// Test absolute,X mode formatting.
    func test_formatOperand_absoluteX() {
        let result = AddressingMode.absoluteX.formatOperand(0x1234)
        XCTAssertEqual(result, "$1234,X")
    }

    /// Test absolute,Y mode formatting.
    func test_formatOperand_absoluteY() {
        let result = AddressingMode.absoluteY.formatOperand(0x1234)
        XCTAssertEqual(result, "$1234,Y")
    }

    /// Test indirect mode formatting.
    func test_formatOperand_indirect() {
        let result = AddressingMode.indirect.formatOperand(0x1234)
        XCTAssertEqual(result, "($1234)")
    }

    /// Test indexed indirect (X) mode formatting.
    func test_formatOperand_indexedIndirectX() {
        let result = AddressingMode.indexedIndirectX.formatOperand(0x80)
        XCTAssertEqual(result, "($80,X)")
    }

    /// Test indirect indexed (Y) mode formatting.
    func test_formatOperand_indirectIndexedY() {
        let result = AddressingMode.indirectIndexedY.formatOperand(0x80)
        XCTAssertEqual(result, "($80),Y")
    }

    /// Test accumulator mode formatting.
    func test_formatOperand_accumulator() {
        let result = AddressingMode.accumulator.formatOperand(0)
        XCTAssertEqual(result, "A")
    }

    /// Test implied mode formatting (empty).
    func test_formatOperand_implied() {
        let result = AddressingMode.implied.formatOperand(0)
        XCTAssertEqual(result, "")
    }

    /// Test relative mode formatting shows target address.
    func test_formatOperand_relative() {
        let result = AddressingMode.relative.formatOperand(0xE47A)
        XCTAssertEqual(result, "$E47A")
    }

    /// Test formatting with label substitution.
    func test_formatOperand_withLabel() {
        let result = AddressingMode.absolute.formatOperand(0xD40A, label: "WSYNC")
        XCTAssertEqual(result, "WSYNC")
    }

    // MARK: - Description Tests

    /// Test addressing mode descriptions.
    func test_description() {
        XCTAssertEqual(AddressingMode.implied.description, "Implied")
        XCTAssertEqual(AddressingMode.immediate.description, "Immediate")
        XCTAssertEqual(AddressingMode.absolute.description, "Absolute")
        XCTAssertEqual(AddressingMode.zeroPageX.description, "Zero Page,X")
    }

    /// Test addressing mode notation.
    func test_notation() {
        XCTAssertEqual(AddressingMode.implied.notation, "impl")
        XCTAssertEqual(AddressingMode.immediate.notation, "#")
        XCTAssertEqual(AddressingMode.absolute.notation, "abs")
        XCTAssertEqual(AddressingMode.indirectIndexedY.notation, "(zp),Y")
    }

    // MARK: - CaseIterable Tests

    /// Test that all addressing modes are enumerable.
    func test_allCases() {
        XCTAssertEqual(AddressingMode.allCases.count, 14)
    }
}

// =============================================================================
// MARK: - CPUFlags Tests
// =============================================================================

/// Tests for the CPUFlags OptionSet.
final class CPUFlagsTests: XCTestCase {

    /// Test individual flag values.
    func test_individualFlags() {
        XCTAssertEqual(CPUFlags.carry.rawValue, 0x01)
        XCTAssertEqual(CPUFlags.zero.rawValue, 0x02)
        XCTAssertEqual(CPUFlags.interrupt.rawValue, 0x04)
        XCTAssertEqual(CPUFlags.decimal.rawValue, 0x08)
        XCTAssertEqual(CPUFlags.breakFlag.rawValue, 0x10)
        XCTAssertEqual(CPUFlags.overflow.rawValue, 0x40)
        XCTAssertEqual(CPUFlags.negative.rawValue, 0x80)
    }

    /// Test common flag combinations.
    func test_flagCombinations() {
        XCTAssertEqual(CPUFlags.nz.rawValue, 0x82)
        XCTAssertEqual(CPUFlags.nzc.rawValue, 0x83)
        XCTAssertTrue(CPUFlags.nvzc.contains(.negative))
        XCTAssertTrue(CPUFlags.nvzc.contains(.overflow))
        XCTAssertTrue(CPUFlags.nvzc.contains(.zero))
        XCTAssertTrue(CPUFlags.nvzc.contains(.carry))
    }

    /// Test flag description formatting.
    func test_description() {
        XCTAssertEqual(CPUFlags.nz.description, "NZ")
        XCTAssertEqual(CPUFlags.nzc.description, "NZC")
        XCTAssertEqual(CPUFlags([]).description, "-")
    }
}

// =============================================================================
// MARK: - OpcodeTable Tests
// =============================================================================

/// Tests for the OpcodeTable opcode lookup.
final class OpcodeTableTests: XCTestCase {

    // MARK: - Common Opcode Tests

    /// Test LDA immediate opcode (0xA9).
    func test_lookup_LDA_immediate() {
        let info = OpcodeTable.lookup(0xA9)

        XCTAssertEqual(info.mnemonic, "LDA")
        XCTAssertEqual(info.mode, .immediate)
        XCTAssertEqual(info.byteCount, 2)
        XCTAssertEqual(info.cycles, 2)
        XCTAssertFalse(info.isIllegal)
        XCTAssertTrue(info.affectedFlags.contains(.negative))
        XCTAssertTrue(info.affectedFlags.contains(.zero))
    }

    /// Test STA absolute opcode (0x8D).
    func test_lookup_STA_absolute() {
        let info = OpcodeTable.lookup(0x8D)

        XCTAssertEqual(info.mnemonic, "STA")
        XCTAssertEqual(info.mode, .absolute)
        XCTAssertEqual(info.byteCount, 3)
        XCTAssertEqual(info.cycles, 4)
        XCTAssertFalse(info.isIllegal)
        XCTAssertEqual(info.affectedFlags, [])  // STA doesn't affect flags
    }

    /// Test JMP absolute opcode (0x4C).
    func test_lookup_JMP_absolute() {
        let info = OpcodeTable.lookup(0x4C)

        XCTAssertEqual(info.mnemonic, "JMP")
        XCTAssertEqual(info.mode, .absolute)
        XCTAssertEqual(info.byteCount, 3)
        XCTAssertEqual(info.cycles, 3)
    }

    /// Test JMP indirect opcode (0x6C).
    func test_lookup_JMP_indirect() {
        let info = OpcodeTable.lookup(0x6C)

        XCTAssertEqual(info.mnemonic, "JMP")
        XCTAssertEqual(info.mode, .indirect)
        XCTAssertEqual(info.byteCount, 3)
        XCTAssertEqual(info.cycles, 5)
    }

    /// Test BRK opcode (0x00).
    func test_lookup_BRK() {
        let info = OpcodeTable.lookup(0x00)

        XCTAssertEqual(info.mnemonic, "BRK")
        XCTAssertEqual(info.mode, .implied)
        XCTAssertEqual(info.byteCount, 1)
        XCTAssertEqual(info.cycles, 7)
    }

    /// Test NOP opcode (0xEA).
    func test_lookup_NOP() {
        let info = OpcodeTable.lookup(0xEA)

        XCTAssertEqual(info.mnemonic, "NOP")
        XCTAssertEqual(info.mode, .implied)
        XCTAssertEqual(info.byteCount, 1)
        XCTAssertEqual(info.cycles, 2)
        XCTAssertFalse(info.isIllegal)
    }

    /// Test RTS opcode (0x60).
    func test_lookup_RTS() {
        let info = OpcodeTable.lookup(0x60)

        XCTAssertEqual(info.mnemonic, "RTS")
        XCTAssertEqual(info.mode, .implied)
        XCTAssertEqual(info.cycles, 6)
    }

    /// Test JSR opcode (0x20).
    func test_lookup_JSR() {
        let info = OpcodeTable.lookup(0x20)

        XCTAssertEqual(info.mnemonic, "JSR")
        XCTAssertEqual(info.mode, .absolute)
        XCTAssertEqual(info.byteCount, 3)
        XCTAssertEqual(info.cycles, 6)
    }

    // MARK: - Branch Instruction Tests

    /// Test BNE opcode (0xD0).
    func test_lookup_BNE() {
        let info = OpcodeTable.lookup(0xD0)

        XCTAssertEqual(info.mnemonic, "BNE")
        XCTAssertEqual(info.mode, .relative)
        XCTAssertEqual(info.byteCount, 2)
        XCTAssertEqual(info.cycles, 2)
        XCTAssertEqual(info.pageCrossCycles, 2)  // +1 if taken, +1 if page cross
    }

    /// Test BEQ opcode (0xF0).
    func test_lookup_BEQ() {
        let info = OpcodeTable.lookup(0xF0)

        XCTAssertEqual(info.mnemonic, "BEQ")
        XCTAssertEqual(info.mode, .relative)
    }

    /// Test all branch opcodes are relative mode.
    func test_allBranches_relativeMode() {
        let branchOpcodes: [UInt8] = [0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0]
        let branchMnemonics = ["BPL", "BMI", "BVC", "BVS", "BCC", "BCS", "BNE", "BEQ"]

        for (opcode, mnemonic) in zip(branchOpcodes, branchMnemonics) {
            let info = OpcodeTable.lookup(opcode)
            XCTAssertEqual(info.mnemonic, mnemonic, "Mnemonic mismatch for opcode $\(String(format: "%02X", opcode))")
            XCTAssertEqual(info.mode, .relative, "Mode mismatch for \(mnemonic)")
        }
    }

    // MARK: - Accumulator Mode Tests

    /// Test ASL accumulator (0x0A).
    func test_lookup_ASL_accumulator() {
        let info = OpcodeTable.lookup(0x0A)

        XCTAssertEqual(info.mnemonic, "ASL")
        XCTAssertEqual(info.mode, .accumulator)
        XCTAssertEqual(info.byteCount, 1)
    }

    /// Test LSR accumulator (0x4A).
    func test_lookup_LSR_accumulator() {
        let info = OpcodeTable.lookup(0x4A)

        XCTAssertEqual(info.mnemonic, "LSR")
        XCTAssertEqual(info.mode, .accumulator)
    }

    /// Test ROL accumulator (0x2A).
    func test_lookup_ROL_accumulator() {
        let info = OpcodeTable.lookup(0x2A)

        XCTAssertEqual(info.mnemonic, "ROL")
        XCTAssertEqual(info.mode, .accumulator)
    }

    /// Test ROR accumulator (0x6A).
    func test_lookup_ROR_accumulator() {
        let info = OpcodeTable.lookup(0x6A)

        XCTAssertEqual(info.mnemonic, "ROR")
        XCTAssertEqual(info.mode, .accumulator)
    }

    // MARK: - Illegal Opcode Tests

    /// Test LAX illegal opcode (0xA7).
    func test_lookup_LAX_illegal() {
        let info = OpcodeTable.lookup(0xA7)

        XCTAssertEqual(info.mnemonic, "LAX")
        XCTAssertEqual(info.mode, .zeroPage)
        XCTAssertTrue(info.isIllegal)
        XCTAssertFalse(info.halts)
    }

    /// Test SAX illegal opcode (0x87).
    func test_lookup_SAX_illegal() {
        let info = OpcodeTable.lookup(0x87)

        XCTAssertEqual(info.mnemonic, "SAX")
        XCTAssertEqual(info.mode, .zeroPage)
        XCTAssertTrue(info.isIllegal)
    }

    /// Test DCP illegal opcode (0xC7).
    func test_lookup_DCP_illegal() {
        let info = OpcodeTable.lookup(0xC7)

        XCTAssertEqual(info.mnemonic, "DCP")
        XCTAssertTrue(info.isIllegal)
    }

    /// Test ISC illegal opcode (0xE7).
    func test_lookup_ISC_illegal() {
        let info = OpcodeTable.lookup(0xE7)

        XCTAssertEqual(info.mnemonic, "ISC")
        XCTAssertTrue(info.isIllegal)
    }

    /// Test SLO illegal opcode (0x07).
    func test_lookup_SLO_illegal() {
        let info = OpcodeTable.lookup(0x07)

        XCTAssertEqual(info.mnemonic, "SLO")
        XCTAssertTrue(info.isIllegal)
    }

    /// Test JAM/KIL opcode (0x02) halts CPU.
    func test_lookup_JAM_halts() {
        let info = OpcodeTable.lookup(0x02)

        XCTAssertEqual(info.mnemonic, "JAM")
        XCTAssertTrue(info.isIllegal)
        XCTAssertTrue(info.halts)
    }

    /// Test illegal NOP with zero page addressing (0x04).
    func test_lookup_illegalNOP_zeroPage() {
        let info = OpcodeTable.lookup(0x04)

        XCTAssertEqual(info.mnemonic, "NOP")
        XCTAssertEqual(info.mode, .zeroPage)
        XCTAssertEqual(info.byteCount, 2)
        XCTAssertTrue(info.isIllegal)
    }

    // MARK: - Page Cross Cycle Tests

    /// Test LDA absolute,X has page cross cycles.
    func test_pageCrossCycles_LDA_absoluteX() {
        let info = OpcodeTable.lookup(0xBD)  // LDA abs,X

        XCTAssertEqual(info.mnemonic, "LDA")
        XCTAssertEqual(info.mode, .absoluteX)
        XCTAssertEqual(info.cycles, 4)
        XCTAssertEqual(info.pageCrossCycles, 1)
    }

    /// Test LDA (indirect),Y has page cross cycles.
    func test_pageCrossCycles_LDA_indirectY() {
        let info = OpcodeTable.lookup(0xB1)  // LDA (zp),Y

        XCTAssertEqual(info.mnemonic, "LDA")
        XCTAssertEqual(info.mode, .indirectIndexedY)
        XCTAssertEqual(info.cycles, 5)
        XCTAssertEqual(info.pageCrossCycles, 1)
    }

    /// Test STA absolute,X has NO page cross cycles (always 5).
    func test_pageCrossCycles_STA_absoluteX() {
        let info = OpcodeTable.lookup(0x9D)  // STA abs,X

        XCTAssertEqual(info.mnemonic, "STA")
        XCTAssertEqual(info.mode, .absoluteX)
        XCTAssertEqual(info.cycles, 5)
        XCTAssertEqual(info.pageCrossCycles, 0)  // Write ops don't have page cross penalty
    }
}

// =============================================================================
// MARK: - DisassembledInstruction Tests
// =============================================================================

/// Tests for the DisassembledInstruction struct.
final class DisassembledInstructionTests: XCTestCase {

    // MARK: - Basic Properties Tests

    /// Test basic instruction properties.
    func test_basicProperties() {
        let inst = DisassembledInstruction(
            address: 0xE477,
            bytes: [0xA9, 0x00],
            mnemonic: "LDA",
            operand: "#$00",
            addressingMode: .immediate,
            cycles: 2,
            affectedFlags: .nz
        )

        XCTAssertEqual(inst.address, 0xE477)
        XCTAssertEqual(inst.bytes, [0xA9, 0x00])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "#$00")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertEqual(inst.cycles, 2)
    }

    /// Test opcode computed property.
    func test_opcode() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0xA9, 0x42],
            mnemonic: "LDA",
            operand: "#$42",
            addressingMode: .immediate,
            cycles: 2
        )

        XCTAssertEqual(inst.opcode, 0xA9)
    }

    /// Test byteCount computed property.
    func test_byteCount() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0x8D, 0x00, 0xD4],
            mnemonic: "STA",
            operand: "$D400",
            addressingMode: .absolute,
            cycles: 4
        )

        XCTAssertEqual(inst.byteCount, 3)
    }

    /// Test nextAddress computed property.
    func test_nextAddress() {
        let inst = DisassembledInstruction(
            address: 0xE477,
            bytes: [0xA9, 0x00],
            mnemonic: "LDA",
            operand: "#$00",
            addressingMode: .immediate,
            cycles: 2
        )

        XCTAssertEqual(inst.nextAddress, 0xE479)
    }

    /// Test nextAddress wraps at 16-bit boundary.
    func test_nextAddress_wraps() {
        let inst = DisassembledInstruction(
            address: 0xFFFE,
            bytes: [0x8D, 0x00, 0xD4],
            mnemonic: "STA",
            operand: "$D400",
            addressingMode: .absolute,
            cycles: 4
        )

        XCTAssertEqual(inst.nextAddress, 0x0001)  // Wraps around
    }

    // MARK: - Branch/Jump Classification Tests

    /// Test isBranch for branch instruction.
    func test_isBranch_true() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0xD0, 0x05],
            mnemonic: "BNE",
            operand: "$0607",
            addressingMode: .relative,
            targetAddress: 0x0607,
            relativeOffset: 5,
            cycles: 2
        )

        XCTAssertTrue(inst.isBranch)
    }

    /// Test isBranch for non-branch instruction.
    func test_isBranch_false() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0xA9, 0x00],
            mnemonic: "LDA",
            operand: "#$00",
            addressingMode: .immediate,
            cycles: 2
        )

        XCTAssertFalse(inst.isBranch)
    }

    /// Test isJump for JMP.
    func test_isJump_JMP() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0x4C, 0x00, 0x07],
            mnemonic: "JMP",
            operand: "$0700",
            addressingMode: .absolute,
            targetAddress: 0x0700,
            cycles: 3
        )

        XCTAssertTrue(inst.isJump)
    }

    /// Test isJump for JSR.
    func test_isJump_JSR() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0x20, 0x00, 0x07],
            mnemonic: "JSR",
            operand: "$0700",
            addressingMode: .absolute,
            targetAddress: 0x0700,
            cycles: 6
        )

        XCTAssertTrue(inst.isJump)
    }

    /// Test changesFlow for various instructions.
    func test_changesFlow() {
        // Branch changes flow
        let branch = DisassembledInstruction(
            address: 0x0600, bytes: [0xD0, 0x05], mnemonic: "BNE", operand: "$0607",
            addressingMode: .relative, cycles: 2
        )
        XCTAssertTrue(branch.changesFlow)

        // JMP changes flow
        let jmp = DisassembledInstruction(
            address: 0x0600, bytes: [0x4C, 0x00, 0x07], mnemonic: "JMP", operand: "$0700",
            addressingMode: .absolute, cycles: 3
        )
        XCTAssertTrue(jmp.changesFlow)

        // RTS changes flow
        let rts = DisassembledInstruction(
            address: 0x0600, bytes: [0x60], mnemonic: "RTS", operand: "",
            addressingMode: .implied, cycles: 6
        )
        XCTAssertTrue(rts.changesFlow)

        // LDA doesn't change flow
        let lda = DisassembledInstruction(
            address: 0x0600, bytes: [0xA9, 0x00], mnemonic: "LDA", operand: "#$00",
            addressingMode: .immediate, cycles: 2
        )
        XCTAssertFalse(lda.changesFlow)
    }

    // MARK: - Formatting Tests

    /// Test bytesString formatting.
    func test_bytesString() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0x8D, 0x00, 0xD4],
            mnemonic: "STA",
            operand: "$D400",
            addressingMode: .absolute,
            cycles: 4
        )

        XCTAssertEqual(inst.bytesString, "8D 00 D4")
    }

    /// Test paddedBytesString has fixed width.
    func test_paddedBytesString() {
        let inst1 = DisassembledInstruction(
            address: 0x0600, bytes: [0xEA], mnemonic: "NOP", operand: "",
            addressingMode: .implied, cycles: 2
        )
        XCTAssertEqual(inst1.paddedBytesString.count, 8)

        let inst2 = DisassembledInstruction(
            address: 0x0600, bytes: [0xA9, 0x00], mnemonic: "LDA", operand: "#$00",
            addressingMode: .immediate, cycles: 2
        )
        XCTAssertEqual(inst2.paddedBytesString.count, 8)

        let inst3 = DisassembledInstruction(
            address: 0x0600, bytes: [0x8D, 0x00, 0xD4], mnemonic: "STA", operand: "$D400",
            addressingMode: .absolute, cycles: 4
        )
        XCTAssertEqual(inst3.paddedBytesString.count, 8)
    }

    /// Test instructionText formatting.
    func test_instructionText() {
        let inst1 = DisassembledInstruction(
            address: 0x0600, bytes: [0xA9, 0x00], mnemonic: "LDA", operand: "#$00",
            addressingMode: .immediate, cycles: 2
        )
        XCTAssertEqual(inst1.instructionText, "LDA #$00")

        let inst2 = DisassembledInstruction(
            address: 0x0600, bytes: [0xEA], mnemonic: "NOP", operand: "",
            addressingMode: .implied, cycles: 2
        )
        XCTAssertEqual(inst2.instructionText, "NOP")
    }

    /// Test formatted output.
    func test_formatted() {
        let inst = DisassembledInstruction(
            address: 0xE477,
            bytes: [0xA9, 0x00],
            mnemonic: "LDA",
            operand: "#$00",
            addressingMode: .immediate,
            cycles: 2
        )

        let formatted = inst.formatted
        XCTAssertTrue(formatted.hasPrefix("$E477"))
        XCTAssertTrue(formatted.contains("A9 00"))
        XCTAssertTrue(formatted.contains("LDA #$00"))
    }

    /// Test formattedWithOffset for branch.
    func test_formattedWithOffset_branch() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0xD0, 0x05],
            mnemonic: "BNE",
            operand: "$0607",
            addressingMode: .relative,
            targetAddress: 0x0607,
            relativeOffset: 5,
            cycles: 2
        )

        let formatted = inst.formattedWithOffset
        XCTAssertTrue(formatted.contains("(+5)"))
    }

    /// Test formattedWithOffset for backward branch.
    func test_formattedWithOffset_backwardBranch() {
        let inst = DisassembledInstruction(
            address: 0x0610,
            bytes: [0xD0, 0xF0],  // -16
            mnemonic: "BNE",
            operand: "$0602",
            addressingMode: .relative,
            targetAddress: 0x0602,
            relativeOffset: -14,
            cycles: 2
        )

        let formatted = inst.formattedWithOffset
        XCTAssertTrue(formatted.contains("(-14)"))
    }

    /// Test formattedWithLabel shows label.
    func test_formattedWithLabel() {
        let inst = DisassembledInstruction(
            address: 0x0600,
            bytes: [0xD0, 0x05],
            mnemonic: "BNE",
            operand: "$0607",
            addressingMode: .relative,
            targetAddress: 0x0607,
            relativeOffset: 5,
            targetLabel: "LOOP",
            cycles: 2
        )

        let formatted = inst.formattedWithLabel
        XCTAssertTrue(formatted.contains("LOOP"))
        XCTAssertTrue(formatted.contains("(+5)"))
    }

    // MARK: - Memory Access Classification Tests

    /// Test readsMemory for load instructions.
    func test_readsMemory_load() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0xAD, 0x00, 0xD4], mnemonic: "LDA", operand: "$D400",
            addressingMode: .absolute, cycles: 4
        )
        XCTAssertTrue(inst.readsMemory)
    }

    /// Test readsMemory false for immediate mode.
    func test_readsMemory_immediate() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0xA9, 0x00], mnemonic: "LDA", operand: "#$00",
            addressingMode: .immediate, cycles: 2
        )
        XCTAssertFalse(inst.readsMemory)
    }

    /// Test readsMemory false for store instructions.
    func test_readsMemory_store() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0x8D, 0x00, 0xD4], mnemonic: "STA", operand: "$D400",
            addressingMode: .absolute, cycles: 4
        )
        XCTAssertFalse(inst.readsMemory)
    }

    /// Test writesMemory for store instructions.
    func test_writesMemory_store() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0x8D, 0x00, 0xD4], mnemonic: "STA", operand: "$D400",
            addressingMode: .absolute, cycles: 4
        )
        XCTAssertTrue(inst.writesMemory)
    }

    /// Test writesMemory false for load instructions.
    func test_writesMemory_load() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0xAD, 0x00, 0xD4], mnemonic: "LDA", operand: "$D400",
            addressingMode: .absolute, cycles: 4
        )
        XCTAssertFalse(inst.writesMemory)
    }

    /// Test writesMemory for read-modify-write (memory, not accumulator).
    func test_writesMemory_RMW() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0xEE, 0x00, 0x06], mnemonic: "INC", operand: "$0600",
            addressingMode: .absolute, cycles: 6
        )
        XCTAssertTrue(inst.writesMemory)
    }

    /// Test writesMemory false for accumulator mode RMW.
    func test_writesMemory_RMW_accumulator() {
        let inst = DisassembledInstruction(
            address: 0x0600, bytes: [0x0A], mnemonic: "ASL", operand: "A",
            addressingMode: .accumulator, cycles: 2
        )
        XCTAssertFalse(inst.writesMemory)
    }
}

// =============================================================================
// MARK: - AddressLabels Tests
// =============================================================================

/// Tests for the AddressLabels struct.
final class AddressLabelsTests: XCTestCase {

    // MARK: - Basic Operations

    /// Test empty label table.
    func test_init_empty() {
        let labels = AddressLabels()
        XCTAssertNil(labels.lookup(0x0000))
        XCTAssertTrue(labels.addresses.isEmpty)
    }

    /// Test adding and looking up labels.
    func test_addAndLookup() {
        var labels = AddressLabels()
        labels.add(0x0600, "MYCODE")

        XCTAssertEqual(labels.lookup(0x0600), "MYCODE")
    }

    /// Test removing labels.
    func test_remove() {
        var labels = AddressLabels()
        labels.add(0x0600, "MYCODE")

        let removed = labels.remove(0x0600)
        XCTAssertEqual(removed, "MYCODE")
        XCTAssertNil(labels.lookup(0x0600))
    }

    /// Test removing non-existent label.
    func test_remove_nonExistent() {
        var labels = AddressLabels()
        let removed = labels.remove(0x0600)
        XCTAssertNil(removed)
    }

    /// Test addresses property.
    func test_addresses() {
        var labels = AddressLabels()
        labels.add(0x0700, "B")
        labels.add(0x0600, "A")
        labels.add(0x0800, "C")

        let addresses = labels.addresses
        XCTAssertEqual(addresses, [0x0600, 0x0700, 0x0800])  // Sorted
    }

    /// Test allLabels property.
    func test_allLabels() {
        var labels = AddressLabels()
        labels.add(0x0700, "B")
        labels.add(0x0600, "A")

        let all = labels.allLabels
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].address, 0x0600)
        XCTAssertEqual(all[0].label, "A")
        XCTAssertEqual(all[1].address, 0x0700)
        XCTAssertEqual(all[1].label, "B")
    }

    /// Test merging label tables.
    func test_merge() {
        var labels1 = AddressLabels()
        labels1.add(0x0600, "A")
        labels1.add(0x0700, "B")

        var labels2 = AddressLabels()
        labels2.add(0x0700, "B2")  // Override
        labels2.add(0x0800, "C")

        labels1.merge(labels2)

        XCTAssertEqual(labels1.lookup(0x0600), "A")
        XCTAssertEqual(labels1.lookup(0x0700), "B2")  // Overwritten
        XCTAssertEqual(labels1.lookup(0x0800), "C")
    }

    // MARK: - Standard Labels Tests

    /// Test hardware registers are included.
    func test_hardwareRegisters() {
        let labels = AddressLabels.hardwareRegisters

        // GTIA
        XCTAssertNotNil(labels.lookup(0xD01A))  // COLBK

        // POKEY
        XCTAssertNotNil(labels.lookup(0xD20A))  // RANDOM

        // PIA
        XCTAssertNotNil(labels.lookup(0xD300))  // PORTA

        // ANTIC
        XCTAssertNotNil(labels.lookup(0xD40A))  // WSYNC
    }

    /// Test ANTIC register labels.
    func test_anticLabels() {
        let labels = AddressLabels.anticRegisters

        XCTAssertEqual(labels.lookup(0xD400), "DMACTL")
        XCTAssertEqual(labels.lookup(0xD40A), "WSYNC")
        XCTAssertEqual(labels.lookup(0xD40B), "VCOUNT")
    }

    /// Test POKEY register labels.
    /// Note: POKEY registers use combined "Write/Read" names for dual-purpose addresses.
    func test_pokeyLabels() {
        let labels = AddressLabels.pokeyRegisters

        // $D200 is AUDF1 (write) / POT0 (read)
        XCTAssertEqual(labels.lookup(0xD200), "AUDF1/POT0")
        // $D20A is SKRES (write) / RANDOM (read)
        XCTAssertEqual(labels.lookup(0xD20A), "SKRES/RANDOM")
        // $D20F is SKCTL (write) / SKSTAT (read)
        XCTAssertEqual(labels.lookup(0xD20F), "SKCTL/SKSTAT")
    }

    /// Test OS vector labels.
    func test_osVectorLabels() {
        let labels = AddressLabels.osVectors

        XCTAssertEqual(labels.lookup(0xFFFC), "RESET")
        XCTAssertEqual(labels.lookup(0xFFFE), "IRQ")
        XCTAssertEqual(labels.lookup(0xE456), "CIOV")
    }

    /// Test standard labels combines all categories.
    func test_atariStandard() {
        let labels = AddressLabels.atariStandard

        // Should have hardware registers
        XCTAssertNotNil(labels.lookup(0xD40A))  // WSYNC

        // Should have OS vectors
        XCTAssertNotNil(labels.lookup(0xFFFC))  // RESET

        // Should have zero page variables
        XCTAssertNotNil(labels.lookup(0x0054))  // ROWCRS
    }
}

// =============================================================================
// MARK: - ArrayMemoryBus Tests
// =============================================================================

/// Tests for the ArrayMemoryBus helper struct.
final class ArrayMemoryBusTests: XCTestCase {

    /// Test reading within bounds.
    func test_read_withinBounds() {
        let data: [UInt8] = [0xA9, 0x42, 0x8D, 0x00, 0xD4]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        XCTAssertEqual(memory.read(0x0600), 0xA9)
        XCTAssertEqual(memory.read(0x0601), 0x42)
        XCTAssertEqual(memory.read(0x0602), 0x8D)
        XCTAssertEqual(memory.read(0x0603), 0x00)
        XCTAssertEqual(memory.read(0x0604), 0xD4)
    }

    /// Test reading outside bounds returns 0.
    func test_read_outsideBounds() {
        let data: [UInt8] = [0xA9, 0x42]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        XCTAssertEqual(memory.read(0x05FF), 0x00)  // Before
        XCTAssertEqual(memory.read(0x0602), 0x00)  // After
        XCTAssertEqual(memory.read(0x0000), 0x00)  // Way before
        XCTAssertEqual(memory.read(0xFFFF), 0x00)  // Way after
    }

    /// Test default base address of 0.
    func test_defaultBaseAddress() {
        let data: [UInt8] = [0xA9, 0x42]
        let memory = ArrayMemoryBus(data: data)

        XCTAssertEqual(memory.read(0x0000), 0xA9)
        XCTAssertEqual(memory.read(0x0001), 0x42)
    }

    /// Test write has no effect (read-only).
    func test_write_readOnly() {
        let data: [UInt8] = [0xA9, 0x42]
        var memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        memory.write(0x0600, value: 0xFF)
        XCTAssertEqual(memory.read(0x0600), 0xA9)  // Unchanged
    }
}

// =============================================================================
// MARK: - Disassembler Tests
// =============================================================================

/// Tests for the Disassembler struct.
final class DisassemblerTests: XCTestCase {

    var disasm: Disassembler!

    override func setUp() {
        super.setUp()
        disasm = Disassembler(labels: AddressLabels.atariStandard)
    }

    // MARK: - Single Instruction Tests

    /// Test disassembling LDA immediate.
    func test_disassemble_LDA_immediate() {
        let data: [UInt8] = [0xA9, 0x42]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.address, 0x0600)
        XCTAssertEqual(inst.bytes, [0xA9, 0x42])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "#$42")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertEqual(inst.cycles, 2)
    }

    /// Test disassembling STA absolute.
    func test_disassemble_STA_absolute() {
        let data: [UInt8] = [0x8D, 0x00, 0xD4]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertEqual(inst.bytes, [0x8D, 0x00, 0xD4])
    }

    /// Test disassembling STA with ANTIC label.
    func test_disassemble_STA_withLabel() {
        let data: [UInt8] = [0x8D, 0x0A, 0xD4]  // STA $D40A (WSYNC)
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "STA")
        // Note: Labels are only shown in branch/jump targets, not in operands
    }

    /// Test disassembling NOP.
    func test_disassemble_NOP() {
        let data: [UInt8] = [0xEA]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "NOP")
        XCTAssertEqual(inst.operand, "")
        XCTAssertEqual(inst.addressingMode, .implied)
        XCTAssertEqual(inst.byteCount, 1)
    }

    /// Test disassembling ASL accumulator.
    func test_disassemble_ASL_accumulator() {
        let data: [UInt8] = [0x0A]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "ASL")
        XCTAssertEqual(inst.operand, "A")
        XCTAssertEqual(inst.addressingMode, .accumulator)
    }

    /// Test disassembling JMP absolute.
    func test_disassemble_JMP() {
        let data: [UInt8] = [0x4C, 0x00, 0x07]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "JMP")
        XCTAssertEqual(inst.targetAddress, 0x0700)
        XCTAssertTrue(inst.isJump)
    }

    /// Test disassembling JSR.
    func test_disassemble_JSR() {
        let data: [UInt8] = [0x20, 0x56, 0xE4]  // JSR $E456 (CIOV)
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "JSR")
        XCTAssertEqual(inst.targetAddress, 0xE456)
        XCTAssertEqual(inst.targetLabel, "CIOV")
    }

    // MARK: - Branch Tests

    /// Test disassembling forward branch.
    func test_disassemble_BNE_forward() {
        let data: [UInt8] = [0xD0, 0x05]  // BNE +5
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "BNE")
        XCTAssertEqual(inst.addressingMode, .relative)
        XCTAssertEqual(inst.relativeOffset, 5)
        XCTAssertEqual(inst.targetAddress, 0x0607)  // 0x0600 + 2 + 5
    }

    /// Test disassembling backward branch.
    func test_disassemble_BNE_backward() {
        let data: [UInt8] = [0xD0, 0xFE]  // BNE -2 (infinite loop)
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "BNE")
        XCTAssertEqual(inst.relativeOffset, -2)
        XCTAssertEqual(inst.targetAddress, 0x0600)  // 0x0600 + 2 + (-2)
    }

    /// Test disassembling BEQ.
    func test_disassemble_BEQ() {
        let data: [UInt8] = [0xF0, 0x10]  // BEQ +16
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0700)

        let inst = disasm.disassemble(at: 0x0700, memory: memory)

        XCTAssertEqual(inst.mnemonic, "BEQ")
        XCTAssertEqual(inst.targetAddress, 0x0712)  // 0x0700 + 2 + 16
    }

    // MARK: - Illegal Opcode Tests

    /// Test disassembling LAX illegal opcode.
    func test_disassemble_LAX() {
        let data: [UInt8] = [0xA7, 0x80]  // LAX $80
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test disassembling JAM/KIL opcode.
    func test_disassemble_JAM() {
        let data: [UInt8] = [0x02]  // JAM
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.mnemonic, "JAM")
        XCTAssertTrue(inst.isIllegal)
        XCTAssertTrue(inst.halts)
    }

    // MARK: - Range Disassembly Tests

    /// Test disassembling a range of instructions.
    func test_disassembleRange() {
        let data: [UInt8] = [
            0xA9, 0x00,       // LDA #$00
            0x8D, 0x00, 0xD4, // STA $D400
            0xEA,             // NOP
            0x60              // RTS
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let instructions = disasm.disassembleRange(from: 0x0600, lines: 4, memory: memory)

        XCTAssertEqual(instructions.count, 4)
        XCTAssertEqual(instructions[0].mnemonic, "LDA")
        XCTAssertEqual(instructions[0].address, 0x0600)
        XCTAssertEqual(instructions[1].mnemonic, "STA")
        XCTAssertEqual(instructions[1].address, 0x0602)
        XCTAssertEqual(instructions[2].mnemonic, "NOP")
        XCTAssertEqual(instructions[2].address, 0x0605)
        XCTAssertEqual(instructions[3].mnemonic, "RTS")
        XCTAssertEqual(instructions[3].address, 0x0606)
    }

    /// Test address range disassembly.
    func test_disassembleAddressRange() {
        let data: [UInt8] = [
            0xA9, 0x00,       // LDA #$00
            0x8D, 0x00, 0xD4, // STA $D400
            0xEA,             // NOP
            0x60              // RTS
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let instructions = disasm.disassembleAddressRange(from: 0x0600, to: 0x0606, memory: memory)

        XCTAssertEqual(instructions.count, 3)  // LDA, STA, NOP (RTS is at 0x0606 which is exclusive)
    }

    /// Test formatRange produces multi-line output.
    func test_formatRange() {
        let data: [UInt8] = [
            0xA9, 0x00,       // LDA #$00
            0xEA              // NOP
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let output = disasm.formatRange(from: 0x0600, lines: 2, memory: memory)

        XCTAssertTrue(output.contains("$0600"))
        XCTAssertTrue(output.contains("LDA"))
        XCTAssertTrue(output.contains("NOP"))
    }

    // MARK: - Bytes Disassembly Tests

    /// Test disassembling from raw bytes.
    func test_disassembleBytes() {
        let bytes: [UInt8] = [0xA9, 0x42]

        let inst = disasm.disassembleBytes(at: 0x0600, bytes: bytes)

        XCTAssertNotNil(inst)
        XCTAssertEqual(inst?.mnemonic, "LDA")
        XCTAssertEqual(inst?.operand, "#$42")
    }

    /// Test disassembling empty bytes returns nil.
    func test_disassembleBytes_empty() {
        let inst = disasm.disassembleBytes(at: 0x0600, bytes: [])
        XCTAssertNil(inst)
    }

    // MARK: - Custom Labels Tests

    /// Test disassembler with custom labels.
    func test_customLabels() {
        var labels = AddressLabels()
        labels.add(0x0700, "MYLOOP")

        let disasm = Disassembler(labels: labels)
        let data: [UInt8] = [0x20, 0x00, 0x07]  // JSR $0700
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertEqual(inst.targetLabel, "MYLOOP")
    }

    /// Test disassembler without labels.
    func test_noLabels() {
        let disasm = Disassembler(labels: AddressLabels())
        let data: [UInt8] = [0x20, 0x56, 0xE4]  // JSR $E456
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let inst = disasm.disassemble(at: 0x0600, memory: memory)

        XCTAssertNil(inst.targetLabel)  // No labels configured
    }
}

// =============================================================================
// MARK: - CLI Protocol Disassemble Command Tests
// =============================================================================

/// Tests for the disassemble command parsing in CLI protocol.
final class CLIDisassembleCommandTests: XCTestCase {

    var parser: CLICommandParser!

    override func setUp() {
        super.setUp()
        parser = CLICommandParser()
    }

    /// Test parsing 'd' command with no arguments.
    func test_parse_d_noArgs() throws {
        let cmd = try parser.parse("d")

        if case .disassemble(let address, let lines) = cmd {
            XCTAssertNil(address)
            XCTAssertNil(lines)
        } else {
            XCTFail("Expected disassemble command")
        }
    }

    /// Test parsing 'disassemble' command with no arguments.
    func test_parse_disassemble_noArgs() throws {
        let cmd = try parser.parse("disassemble")

        if case .disassemble(let address, let lines) = cmd {
            XCTAssertNil(address)
            XCTAssertNil(lines)
        } else {
            XCTFail("Expected disassemble command")
        }
    }

    /// Test parsing 'd' with hex address.
    func test_parse_d_hexAddress() throws {
        let cmd = try parser.parse("d $0600")

        if case .disassemble(let address, let lines) = cmd {
            XCTAssertEqual(address, 0x0600)
            XCTAssertNil(lines)
        } else {
            XCTFail("Expected disassemble command")
        }
    }

    /// Test parsing 'd' with address and line count.
    func test_parse_d_addressAndLines() throws {
        let cmd = try parser.parse("d $E477 8")

        if case .disassemble(let address, let lines) = cmd {
            XCTAssertEqual(address, 0xE477)
            XCTAssertEqual(lines, 8)
        } else {
            XCTFail("Expected disassemble command")
        }
    }

    /// Test parsing 'd' with decimal address.
    func test_parse_d_decimalAddress() throws {
        let cmd = try parser.parse("d 1536")  // 0x0600

        if case .disassemble(let address, _) = cmd {
            XCTAssertEqual(address, 1536)
        } else {
            XCTFail("Expected disassemble command")
        }
    }

    /// Test parsing 'd' with 0x prefix address.
    func test_parse_d_0xAddress() throws {
        let cmd = try parser.parse("d 0x0600")

        if case .disassemble(let address, _) = cmd {
            XCTAssertEqual(address, 0x0600)
        } else {
            XCTFail("Expected disassemble command")
        }
    }

    /// Test parsing 'd' with invalid address throws error.
    func test_parse_d_invalidAddress() {
        XCTAssertThrowsError(try parser.parse("d xyz")) { error in
            XCTAssertTrue(error is CLIProtocolError)
        }
    }

    /// Test parsing 'd' with invalid line count throws error.
    func test_parse_d_invalidLines() {
        XCTAssertThrowsError(try parser.parse("d $0600 abc")) { error in
            XCTAssertTrue(error is CLIProtocolError)
        }
    }

    /// Test parsing 'd' with zero lines throws error.
    func test_parse_d_zeroLines() {
        XCTAssertThrowsError(try parser.parse("d $0600 0")) { error in
            XCTAssertTrue(error is CLIProtocolError)
        }
    }

    /// Test parsing 'd' with negative lines throws error.
    func test_parse_d_negativeLines() {
        XCTAssertThrowsError(try parser.parse("d $0600 -5")) { error in
            XCTAssertTrue(error is CLIProtocolError)
        }
    }
}

// =============================================================================
// MARK: - 7.1 Basic Disassembly Tests
// =============================================================================

/// Tests for basic disassembly output format, verifying that address, bytes,
/// mnemonic, operand, and known labels all appear correctly in output.
///
/// These tests simulate disassembling realistic ROM-like code at $E000 and
/// verify the complete output pipeline from raw bytes through formatted strings.
final class BasicDisassemblyTests: XCTestCase {

    var disasm: Disassembler!

    override func setUp() {
        super.setUp()
        disasm = Disassembler(labels: AddressLabels.atariStandard)
    }

    // MARK: - Output Format Tests

    /// Test that formatted output contains address prefix "$XXXX".
    func test_formattedOutput_containsAddress() {
        let data: [UInt8] = [0xA9, 0x00]  // LDA #$00
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)

        XCTAssertTrue(inst.formatted.hasPrefix("$E000"))
    }

    /// Test that formatted output contains the raw hex bytes.
    func test_formattedOutput_containsBytes() {
        let data: [UInt8] = [0x8D, 0x0A, 0xD4]  // STA $D40A
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)
        let output = inst.formatted

        XCTAssertTrue(output.contains("8D 0A D4"))
    }

    /// Test that formatted output contains the mnemonic.
    func test_formattedOutput_containsMnemonic() {
        let data: [UInt8] = [0xA2, 0xFF]  // LDX #$FF
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)

        XCTAssertTrue(inst.formatted.contains("LDX"))
    }

    /// Test that formatted output contains the operand.
    func test_formattedOutput_containsOperand() {
        let data: [UInt8] = [0xA2, 0xFF]  // LDX #$FF
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)

        XCTAssertTrue(inst.formatted.contains("#$FF"))
    }

    /// Test that formattedWithLabel output shows known labels for JSR targets.
    func test_formattedWithLabel_showsKnownLabel_JSR() {
        // JSR $E456 (CIOV - Central I/O vector)
        let data: [UInt8] = [0x20, 0x56, 0xE4]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)
        let output = inst.formattedWithLabel

        XCTAssertTrue(output.contains("CIOV"), "Expected CIOV label in output: \(output)")
    }

    /// Test that formattedWithLabel shows known labels for JMP targets.
    func test_formattedWithLabel_showsKnownLabel_JMP() {
        // JMP to RESET vector address $FFFC
        let data: [UInt8] = [0x4C, 0xFC, 0xFF]  // JMP $FFFC
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)
        let output = inst.formattedWithLabel

        XCTAssertTrue(output.contains("RESET"), "Expected RESET label in output: \(output)")
    }

    /// Test that branch instructions show labels when target matches a known address.
    func test_formattedWithLabel_branchToKnownAddress() {
        // BNE that branches to CIOV ($E456) from $E454
        // offset = $E456 - ($E454 + 2) = 0
        let data: [UInt8] = [0xD0, 0x00]  // BNE to self+2 = $E456
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE454)

        let inst = disasm.disassemble(at: 0xE454, memory: memory)
        let output = inst.formattedWithLabel

        XCTAssertTrue(output.contains("CIOV"), "Expected CIOV label in branch output: \(output)")
    }

    // MARK: - ROM-Like Code Sequence Tests

    /// Test disassembling a realistic ROM initialization sequence.
    func test_romInitSequence() {
        // Typical 6502 initialization: SEI, CLD, LDX #$FF, TXS
        let data: [UInt8] = [
            0x78,             // SEI
            0xD8,             // CLD
            0xA2, 0xFF,       // LDX #$FF
            0x9A,             // TXS
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let instructions = disasm.disassembleRange(from: 0xE000, lines: 4, memory: memory)

        XCTAssertEqual(instructions.count, 4)
        XCTAssertEqual(instructions[0].mnemonic, "SEI")
        XCTAssertEqual(instructions[0].address, 0xE000)
        XCTAssertEqual(instructions[1].mnemonic, "CLD")
        XCTAssertEqual(instructions[1].address, 0xE001)
        XCTAssertEqual(instructions[2].mnemonic, "LDX")
        XCTAssertEqual(instructions[2].operand, "#$FF")
        XCTAssertEqual(instructions[2].address, 0xE002)
        XCTAssertEqual(instructions[3].mnemonic, "TXS")
        XCTAssertEqual(instructions[3].address, 0xE004)
    }

    /// Test disassembling a subroutine with JSR and RTS.
    func test_subroutineCallAndReturn() {
        let data: [UInt8] = [
            0x20, 0x56, 0xE4, // JSR $E456 (CIOV)
            0xA9, 0x00,       // LDA #$00
            0x60,             // RTS
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE100)

        let instructions = disasm.disassembleRange(from: 0xE100, lines: 3, memory: memory)

        XCTAssertEqual(instructions[0].mnemonic, "JSR")
        XCTAssertEqual(instructions[0].targetAddress, 0xE456)
        XCTAssertEqual(instructions[0].targetLabel, "CIOV")
        XCTAssertEqual(instructions[1].mnemonic, "LDA")
        XCTAssertEqual(instructions[2].mnemonic, "RTS")
    }

    /// Test disassembling a loop with backward branch.
    func test_loopWithBackwardBranch() {
        // A simple loop: LDA $80, BNE back to LDA
        let data: [UInt8] = [
            0xA5, 0x80,       // LDA $80
            0xD0, 0xFC,       // BNE $0600 (-4, back to LDA)
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let instructions = disasm.disassembleRange(from: 0x0600, lines: 2, memory: memory)

        XCTAssertEqual(instructions[0].mnemonic, "LDA")
        XCTAssertEqual(instructions[1].mnemonic, "BNE")
        XCTAssertEqual(instructions[1].targetAddress, 0x0600)
        XCTAssertEqual(instructions[1].relativeOffset, -4)
    }

    /// Test formatRange produces properly separated multi-line output.
    func test_formatRange_multiLine() {
        let data: [UInt8] = [
            0xA9, 0x42,       // LDA #$42
            0x8D, 0x0A, 0xD4, // STA $D40A
            0xEA,             // NOP
            0x60,             // RTS
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let output = disasm.formatRange(from: 0xE000, lines: 4, memory: memory)
        let lines = output.split(separator: "\n")

        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix("$E000"))
        XCTAssertTrue(lines[0].contains("LDA #$42"))
        XCTAssertTrue(lines[1].hasPrefix("$E002"))
        XCTAssertTrue(lines[1].contains("STA"))
        XCTAssertTrue(lines[2].hasPrefix("$E005"))
        XCTAssertTrue(lines[2].contains("NOP"))
        XCTAssertTrue(lines[3].hasPrefix("$E006"))
        XCTAssertTrue(lines[3].contains("RTS"))
    }

    /// Test that addresses increment correctly for mixed instruction sizes.
    func test_addressIncrement_mixedSizes() {
        let data: [UInt8] = [
            0xEA,             // NOP       (1 byte)
            0xA9, 0x00,       // LDA #$00  (2 bytes)
            0x8D, 0x00, 0xD4, // STA $D400 (3 bytes)
            0x60,             // RTS       (1 byte)
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let instructions = disasm.disassembleRange(from: 0xE000, lines: 4, memory: memory)

        XCTAssertEqual(instructions[0].address, 0xE000)  // 1-byte NOP
        XCTAssertEqual(instructions[1].address, 0xE001)  // 2-byte LDA
        XCTAssertEqual(instructions[2].address, 0xE003)  // 3-byte STA
        XCTAssertEqual(instructions[3].address, 0xE006)  // 1-byte RTS
    }

    /// Test the detailed multi-line format output.
    func test_detailedOutput() {
        let data: [UInt8] = [0x20, 0x56, 0xE4]  // JSR $E456
        let memory = ArrayMemoryBus(data: data, baseAddress: 0xE000)

        let inst = disasm.disassemble(at: 0xE000, memory: memory)
        let detailed = inst.detailed

        XCTAssertTrue(detailed.contains("Address: $E000"))
        XCTAssertTrue(detailed.contains("Bytes: 20 56 E4"))
        XCTAssertTrue(detailed.contains("Instruction: JSR $E456"))
        XCTAssertTrue(detailed.contains("Mode: Absolute"))
        XCTAssertTrue(detailed.contains("Cycles: 6"))
        XCTAssertTrue(detailed.contains("Target: $E456 (CIOV)"))
    }

    /// Test padded bytes string alignment across different instruction sizes.
    func test_paddedBytesAlignment() {
        let oneByte = DisassembledInstruction(
            address: 0, bytes: [0xEA], mnemonic: "NOP", operand: "",
            addressingMode: .implied, cycles: 2
        )
        let twoBytes = DisassembledInstruction(
            address: 0, bytes: [0xA9, 0x42], mnemonic: "LDA", operand: "#$42",
            addressingMode: .immediate, cycles: 2
        )
        let threeBytes = DisassembledInstruction(
            address: 0, bytes: [0x8D, 0x00, 0xD4], mnemonic: "STA", operand: "$D400",
            addressingMode: .absolute, cycles: 4
        )

        // All should be exactly 8 characters for column alignment
        XCTAssertEqual(oneByte.paddedBytesString.count, 8)
        XCTAssertEqual(twoBytes.paddedBytesString.count, 8)
        XCTAssertEqual(threeBytes.paddedBytesString.count, 8)
    }
}

// =============================================================================
// MARK: - 7.2 Addressing Mode Disassembly Tests
// =============================================================================

/// Comprehensive tests for disassembly of all 6502 addressing modes.
///
/// These tests verify end-to-end disassembly through the Disassembler for each
/// addressing mode, checking that the correct mnemonic, operand format, and
/// addressing mode enum value are produced from raw bytes.
final class AddressingModeDisassemblyTests: XCTestCase {

    var disasm: Disassembler!

    override func setUp() {
        super.setUp()
        disasm = Disassembler(labels: AddressLabels())  // No labels for clean operand testing
    }

    // MARK: - Implied Addressing

    /// Test implied addressing: no operand (e.g., NOP, RTS, SEI, CLD, TXS).
    func test_implied_NOP() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xEA])
        XCTAssertEqual(inst.mnemonic, "NOP")
        XCTAssertEqual(inst.operand, "")
        XCTAssertEqual(inst.addressingMode, .implied)
        XCTAssertEqual(inst.byteCount, 1)
    }

    func test_implied_RTS() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x60])
        XCTAssertEqual(inst.mnemonic, "RTS")
        XCTAssertEqual(inst.operand, "")
        XCTAssertEqual(inst.addressingMode, .implied)
    }

    func test_implied_RTI() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x40])
        XCTAssertEqual(inst.mnemonic, "RTI")
        XCTAssertEqual(inst.addressingMode, .implied)
    }

    func test_implied_SEI() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x78])
        XCTAssertEqual(inst.mnemonic, "SEI")
        XCTAssertEqual(inst.addressingMode, .implied)
    }

    func test_implied_CLD() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xD8])
        XCTAssertEqual(inst.mnemonic, "CLD")
        XCTAssertEqual(inst.addressingMode, .implied)
    }

    func test_implied_PHA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x48])
        XCTAssertEqual(inst.mnemonic, "PHA")
        XCTAssertEqual(inst.addressingMode, .implied)
    }

    func test_implied_PLA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x68])
        XCTAssertEqual(inst.mnemonic, "PLA")
        XCTAssertEqual(inst.addressingMode, .implied)
    }

    // MARK: - Accumulator Addressing

    /// Test accumulator addressing: operand is "A" (e.g., ASL A, LSR A, ROL A, ROR A).
    func test_accumulator_ASL() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x0A])
        XCTAssertEqual(inst.mnemonic, "ASL")
        XCTAssertEqual(inst.operand, "A")
        XCTAssertEqual(inst.addressingMode, .accumulator)
        XCTAssertEqual(inst.byteCount, 1)
    }

    func test_accumulator_LSR() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x4A])
        XCTAssertEqual(inst.mnemonic, "LSR")
        XCTAssertEqual(inst.operand, "A")
        XCTAssertEqual(inst.addressingMode, .accumulator)
    }

    func test_accumulator_ROL() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x2A])
        XCTAssertEqual(inst.mnemonic, "ROL")
        XCTAssertEqual(inst.operand, "A")
        XCTAssertEqual(inst.addressingMode, .accumulator)
    }

    func test_accumulator_ROR() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x6A])
        XCTAssertEqual(inst.mnemonic, "ROR")
        XCTAssertEqual(inst.operand, "A")
        XCTAssertEqual(inst.addressingMode, .accumulator)
    }

    // MARK: - Immediate Addressing

    /// Test immediate addressing: #$xx format (e.g., LDA #$42, LDX #$00, CPX #$FF).
    func test_immediate_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA9, 0x42])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "#$42")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertEqual(inst.byteCount, 2)
    }

    func test_immediate_LDX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA2, 0x00])
        XCTAssertEqual(inst.mnemonic, "LDX")
        XCTAssertEqual(inst.operand, "#$00")
        XCTAssertEqual(inst.addressingMode, .immediate)
    }

    func test_immediate_LDY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA0, 0xFF])
        XCTAssertEqual(inst.mnemonic, "LDY")
        XCTAssertEqual(inst.operand, "#$FF")
        XCTAssertEqual(inst.addressingMode, .immediate)
    }

    func test_immediate_CPX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xE0, 0x80])
        XCTAssertEqual(inst.mnemonic, "CPX")
        XCTAssertEqual(inst.operand, "#$80")
        XCTAssertEqual(inst.addressingMode, .immediate)
    }

    func test_immediate_AND() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x29, 0x0F])
        XCTAssertEqual(inst.mnemonic, "AND")
        XCTAssertEqual(inst.operand, "#$0F")
        XCTAssertEqual(inst.addressingMode, .immediate)
    }

    // MARK: - Zero Page Addressing

    /// Test zero page addressing: $xx format (8-bit address).
    func test_zeroPage_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA5, 0x80])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertEqual(inst.byteCount, 2)
    }

    func test_zeroPage_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x85, 0x42])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "$42")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
    }

    func test_zeroPage_BIT() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x24, 0x10])
        XCTAssertEqual(inst.mnemonic, "BIT")
        XCTAssertEqual(inst.operand, "$10")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
    }

    // MARK: - Zero Page,X Addressing

    /// Test zero page indexed by X: $xx,X format.
    func test_zeroPageX_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xB5, 0x80])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "$80,X")
        XCTAssertEqual(inst.addressingMode, .zeroPageX)
        XCTAssertEqual(inst.byteCount, 2)
    }

    func test_zeroPageX_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x95, 0x80])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "$80,X")
        XCTAssertEqual(inst.addressingMode, .zeroPageX)
    }

    func test_zeroPageX_INC() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xF6, 0x10])
        XCTAssertEqual(inst.mnemonic, "INC")
        XCTAssertEqual(inst.operand, "$10,X")
        XCTAssertEqual(inst.addressingMode, .zeroPageX)
    }

    // MARK: - Zero Page,Y Addressing

    /// Test zero page indexed by Y: $xx,Y format (used by LDX/STX).
    func test_zeroPageY_LDX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xB6, 0x80])
        XCTAssertEqual(inst.mnemonic, "LDX")
        XCTAssertEqual(inst.operand, "$80,Y")
        XCTAssertEqual(inst.addressingMode, .zeroPageY)
        XCTAssertEqual(inst.byteCount, 2)
    }

    func test_zeroPageY_STX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x96, 0x80])
        XCTAssertEqual(inst.mnemonic, "STX")
        XCTAssertEqual(inst.operand, "$80,Y")
        XCTAssertEqual(inst.addressingMode, .zeroPageY)
    }

    // MARK: - Absolute Addressing

    /// Test absolute addressing: $xxxx format (16-bit address).
    func test_absolute_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xAD, 0x34, 0x12])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "$1234")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertEqual(inst.byteCount, 3)
    }

    func test_absolute_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x8D, 0x00, 0xD4])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "$D400")
        XCTAssertEqual(inst.addressingMode, .absolute)
    }

    func test_absolute_JMP() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x4C, 0x00, 0x07])
        XCTAssertEqual(inst.mnemonic, "JMP")
        XCTAssertEqual(inst.operand, "$0700")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertEqual(inst.targetAddress, 0x0700)
    }

    func test_absolute_JSR() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x20, 0x00, 0x07])
        XCTAssertEqual(inst.mnemonic, "JSR")
        XCTAssertEqual(inst.operand, "$0700")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertEqual(inst.targetAddress, 0x0700)
    }

    /// Test little-endian byte ordering for absolute addresses.
    func test_absolute_littleEndian() {
        // $ABCD stored as CD AB in memory
        let inst = disassembleBytes(at: 0x0600, bytes: [0xAD, 0xCD, 0xAB])
        XCTAssertEqual(inst.operand, "$ABCD")
    }

    // MARK: - Absolute,X Addressing

    /// Test absolute indexed by X: $xxxx,X format.
    func test_absoluteX_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xBD, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "$1000,X")
        XCTAssertEqual(inst.addressingMode, .absoluteX)
        XCTAssertEqual(inst.byteCount, 3)
    }

    func test_absoluteX_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x9D, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "$1000,X")
        XCTAssertEqual(inst.addressingMode, .absoluteX)
    }

    func test_absoluteX_INC() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xFE, 0x00, 0x04])
        XCTAssertEqual(inst.mnemonic, "INC")
        XCTAssertEqual(inst.operand, "$0400,X")
        XCTAssertEqual(inst.addressingMode, .absoluteX)
    }

    // MARK: - Absolute,Y Addressing

    /// Test absolute indexed by Y: $xxxx,Y format.
    func test_absoluteY_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xB9, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "$1000,Y")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
        XCTAssertEqual(inst.byteCount, 3)
    }

    func test_absoluteY_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x99, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "$1000,Y")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
    }

    func test_absoluteY_LDX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xBE, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "LDX")
        XCTAssertEqual(inst.operand, "$1000,Y")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
    }

    // MARK: - Indirect Addressing

    /// Test indirect addressing: ($xxxx) format (JMP only).
    func test_indirect_JMP() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x6C, 0x00, 0x02])
        XCTAssertEqual(inst.mnemonic, "JMP")
        XCTAssertEqual(inst.operand, "($0200)")
        XCTAssertEqual(inst.addressingMode, .indirect)
        XCTAssertEqual(inst.byteCount, 3)
    }

    /// Test indirect addressing with high address.
    func test_indirect_JMP_highAddress() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x6C, 0xFC, 0xFF])
        XCTAssertEqual(inst.mnemonic, "JMP")
        XCTAssertEqual(inst.operand, "($FFFC)")
        XCTAssertEqual(inst.addressingMode, .indirect)
    }

    // MARK: - Indexed Indirect (X) Addressing

    /// Test indexed indirect: ($xx,X) format - pointer in zero page + X.
    func test_indexedIndirectX_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA1, 0x80])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "($80,X)")
        XCTAssertEqual(inst.addressingMode, .indexedIndirectX)
        XCTAssertEqual(inst.byteCount, 2)
    }

    func test_indexedIndirectX_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x81, 0x40])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "($40,X)")
        XCTAssertEqual(inst.addressingMode, .indexedIndirectX)
    }

    func test_indexedIndirectX_EOR() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x41, 0x20])
        XCTAssertEqual(inst.mnemonic, "EOR")
        XCTAssertEqual(inst.operand, "($20,X)")
        XCTAssertEqual(inst.addressingMode, .indexedIndirectX)
    }

    // MARK: - Indirect Indexed (Y) Addressing

    /// Test indirect indexed: ($xx),Y format - pointer in zero page, then + Y.
    func test_indirectIndexedY_LDA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xB1, 0x80])
        XCTAssertEqual(inst.mnemonic, "LDA")
        XCTAssertEqual(inst.operand, "($80),Y")
        XCTAssertEqual(inst.addressingMode, .indirectIndexedY)
        XCTAssertEqual(inst.byteCount, 2)
    }

    func test_indirectIndexedY_STA() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x91, 0x40])
        XCTAssertEqual(inst.mnemonic, "STA")
        XCTAssertEqual(inst.operand, "($40),Y")
        XCTAssertEqual(inst.addressingMode, .indirectIndexedY)
    }

    func test_indirectIndexedY_CMP() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xD1, 0x10])
        XCTAssertEqual(inst.mnemonic, "CMP")
        XCTAssertEqual(inst.operand, "($10),Y")
        XCTAssertEqual(inst.addressingMode, .indirectIndexedY)
    }

    // MARK: - Relative Addressing (Branches)

    /// Test relative addressing with positive (forward) offset.
    func test_relative_forward() {
        // BNE +5: from $0600, target = $0600 + 2 + 5 = $0607
        let inst = disassembleBytes(at: 0x0600, bytes: [0xD0, 0x05])
        XCTAssertEqual(inst.mnemonic, "BNE")
        XCTAssertEqual(inst.operand, "$0607")
        XCTAssertEqual(inst.addressingMode, .relative)
        XCTAssertEqual(inst.targetAddress, 0x0607)
        XCTAssertEqual(inst.relativeOffset, 5)
        XCTAssertEqual(inst.byteCount, 2)
    }

    /// Test relative addressing with negative (backward) offset.
    func test_relative_backward() {
        // BNE -4: from $0610, target = $0610 + 2 + (-4) = $060E
        let inst = disassembleBytes(at: 0x0610, bytes: [0xD0, 0xFC])
        XCTAssertEqual(inst.mnemonic, "BNE")
        XCTAssertEqual(inst.targetAddress, 0x060E)
        XCTAssertEqual(inst.relativeOffset, -4)
    }

    /// Test relative addressing with offset of zero (branch to next instruction).
    func test_relative_zeroOffset() {
        // BEQ 0: from $0600, target = $0600 + 2 + 0 = $0602
        let inst = disassembleBytes(at: 0x0600, bytes: [0xF0, 0x00])
        XCTAssertEqual(inst.mnemonic, "BEQ")
        XCTAssertEqual(inst.targetAddress, 0x0602)
        XCTAssertEqual(inst.relativeOffset, 0)
    }

    /// Test relative addressing with maximum forward offset (+127).
    func test_relative_maxForward() {
        // BCC +127: from $0600, target = $0600 + 2 + 127 = $0681
        let inst = disassembleBytes(at: 0x0600, bytes: [0x90, 0x7F])
        XCTAssertEqual(inst.mnemonic, "BCC")
        XCTAssertEqual(inst.targetAddress, 0x0681)
        XCTAssertEqual(inst.relativeOffset, 127)
    }

    /// Test relative addressing with maximum backward offset (-128).
    func test_relative_maxBackward() {
        // BCS -128: from $0680, target = $0680 + 2 + (-128) = $0602
        let inst = disassembleBytes(at: 0x0680, bytes: [0xB0, 0x80])
        XCTAssertEqual(inst.mnemonic, "BCS")
        XCTAssertEqual(inst.targetAddress, 0x0602)
        XCTAssertEqual(inst.relativeOffset, -128)
    }

    /// Test all eight branch instructions use relative addressing.
    func test_allBranches_relative() {
        let branches: [(UInt8, String)] = [
            (0x10, "BPL"), (0x30, "BMI"),
            (0x50, "BVC"), (0x70, "BVS"),
            (0x90, "BCC"), (0xB0, "BCS"),
            (0xD0, "BNE"), (0xF0, "BEQ"),
        ]

        for (opcode, mnemonic) in branches {
            let inst = disassembleBytes(at: 0x0600, bytes: [opcode, 0x10])
            XCTAssertEqual(inst.mnemonic, mnemonic, "Mnemonic mismatch for opcode $\(String(format: "%02X", opcode))")
            XCTAssertEqual(inst.addressingMode, .relative, "\(mnemonic) should be relative mode")
            XCTAssertTrue(inst.isBranch, "\(mnemonic) should be classified as branch")
        }
    }

    /// Test formattedWithOffset shows correct annotation for branches.
    func test_relative_formattedWithOffset_forward() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xD0, 0x05])
        let output = inst.formattedWithOffset

        XCTAssertTrue(output.contains("(+5)"), "Forward branch should show (+5)")
    }

    func test_relative_formattedWithOffset_backward() {
        let inst = disassembleBytes(at: 0x0610, bytes: [0xD0, 0xF0])
        let output = inst.formattedWithOffset

        XCTAssertTrue(output.contains("(-16)"), "Backward branch should show (-16)")
    }

    // MARK: - Helper

    /// Convenience helper to disassemble bytes through the full pipeline.
    private func disassembleBytes(at address: UInt16, bytes: [UInt8]) -> DisassembledInstruction {
        let memory = ArrayMemoryBus(data: bytes, baseAddress: address)
        return disasm.disassemble(at: address, memory: memory)
    }
}

// =============================================================================
// MARK: - 7.3 Illegal Opcode Disassembly Tests
// =============================================================================

/// Comprehensive tests for illegal/undocumented 6502 opcode disassembly.
///
/// Tests verify that all categories of illegal opcodes are correctly identified
/// with isIllegal flag, proper mnemonics, correct addressing modes, and
/// accurate cycle counts.
final class IllegalOpcodeDisassemblyTests: XCTestCase {

    var disasm: Disassembler!

    override func setUp() {
        super.setUp()
        disasm = Disassembler(labels: AddressLabels())
    }

    // MARK: - LAX (LDA + LDX combined)

    /// Test LAX zero page.
    func test_LAX_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA7, 0x80])
        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertFalse(inst.halts)
        XCTAssertEqual(inst.cycles, 3)
    }

    /// Test LAX absolute.
    func test_LAX_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xAF, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertEqual(inst.cycles, 4)
    }

    /// Test LAX zero page,Y.
    func test_LAX_zeroPageY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xB7, 0x80])
        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertEqual(inst.operand, "$80,Y")
        XCTAssertEqual(inst.addressingMode, .zeroPageY)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test LAX absolute,Y with page cross cycles.
    func test_LAX_absoluteY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xBF, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertEqual(inst.pageCrossCycles, 1)
    }

    /// Test LAX (indirect,X).
    func test_LAX_indexedIndirectX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA3, 0x80])
        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertEqual(inst.operand, "($80,X)")
        XCTAssertEqual(inst.addressingMode, .indexedIndirectX)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test LAX (indirect),Y.
    func test_LAX_indirectIndexedY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xB3, 0x80])
        XCTAssertEqual(inst.mnemonic, "LAX")
        XCTAssertEqual(inst.operand, "($80),Y")
        XCTAssertEqual(inst.addressingMode, .indirectIndexedY)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - SAX (Store A AND X)

    /// Test SAX zero page.
    func test_SAX_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x87, 0x80])
        XCTAssertEqual(inst.mnemonic, "SAX")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertEqual(inst.cycles, 3)
    }

    /// Test SAX absolute.
    func test_SAX_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x8F, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "SAX")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test SAX (indirect,X).
    func test_SAX_indexedIndirectX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x83, 0x80])
        XCTAssertEqual(inst.mnemonic, "SAX")
        XCTAssertEqual(inst.operand, "($80,X)")
        XCTAssertEqual(inst.addressingMode, .indexedIndirectX)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test SAX zero page,Y.
    func test_SAX_zeroPageY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x97, 0x80])
        XCTAssertEqual(inst.mnemonic, "SAX")
        XCTAssertEqual(inst.operand, "$80,Y")
        XCTAssertEqual(inst.addressingMode, .zeroPageY)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - DCP (DEC + CMP)

    /// Test DCP zero page.
    func test_DCP_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xC7, 0x80])
        XCTAssertEqual(inst.mnemonic, "DCP")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertEqual(inst.cycles, 5)
    }

    /// Test DCP absolute.
    func test_DCP_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xCF, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "DCP")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test DCP absolute,X.
    func test_DCP_absoluteX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xDF, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "DCP")
        XCTAssertEqual(inst.addressingMode, .absoluteX)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test DCP (indirect),Y.
    func test_DCP_indirectIndexedY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xD3, 0x80])
        XCTAssertEqual(inst.mnemonic, "DCP")
        XCTAssertEqual(inst.addressingMode, .indirectIndexedY)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - ISC (INC + SBC)

    /// Test ISC zero page.
    func test_ISC_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xE7, 0x80])
        XCTAssertEqual(inst.mnemonic, "ISC")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test ISC absolute.
    func test_ISC_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xEF, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "ISC")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test ISC absolute,X.
    func test_ISC_absoluteX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xFF, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "ISC")
        XCTAssertEqual(inst.addressingMode, .absoluteX)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - SLO (ASL + ORA)

    /// Test SLO zero page.
    func test_SLO_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x07, 0x80])
        XCTAssertEqual(inst.mnemonic, "SLO")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test SLO absolute.
    func test_SLO_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x0F, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "SLO")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - RLA (ROL + AND)

    /// Test RLA zero page.
    func test_RLA_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x27, 0x80])
        XCTAssertEqual(inst.mnemonic, "RLA")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test RLA absolute.
    func test_RLA_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x2F, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "RLA")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - SRE (LSR + EOR)

    /// Test SRE zero page.
    func test_SRE_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x47, 0x80])
        XCTAssertEqual(inst.mnemonic, "SRE")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test SRE absolute.
    func test_SRE_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x4F, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "SRE")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - RRA (ROR + ADC)

    /// Test RRA zero page.
    func test_RRA_zeroPage() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x67, 0x80])
        XCTAssertEqual(inst.mnemonic, "RRA")
        XCTAssertEqual(inst.operand, "$80")
        XCTAssertEqual(inst.addressingMode, .zeroPage)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test RRA absolute.
    func test_RRA_absolute() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x6F, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "RRA")
        XCTAssertEqual(inst.operand, "$1000")
        XCTAssertEqual(inst.addressingMode, .absolute)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - Immediate Illegal Opcodes

    /// Test ANC immediate.
    func test_ANC_immediate() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x0B, 0x42])
        XCTAssertEqual(inst.mnemonic, "ANC")
        XCTAssertEqual(inst.operand, "#$42")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertEqual(inst.cycles, 2)
    }

    /// Test second ANC encoding.
    func test_ANC_alternate() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x2B, 0x42])
        XCTAssertEqual(inst.mnemonic, "ANC")
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test ALR (AND + LSR) immediate.
    func test_ALR_immediate() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x4B, 0x0F])
        XCTAssertEqual(inst.mnemonic, "ALR")
        XCTAssertEqual(inst.operand, "#$0F")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test ARR (AND + ROR) immediate.
    func test_ARR_immediate() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x6B, 0x42])
        XCTAssertEqual(inst.mnemonic, "ARR")
        XCTAssertEqual(inst.operand, "#$42")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test XAA (unstable) immediate.
    func test_XAA_immediate() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x8B, 0x42])
        XCTAssertEqual(inst.mnemonic, "XAA")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test illegal SBC duplicate ($EB).
    func test_SBC_illegalDuplicate() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xEB, 0x42])
        XCTAssertEqual(inst.mnemonic, "SBC")
        XCTAssertEqual(inst.operand, "#$42")
        XCTAssertEqual(inst.addressingMode, .immediate)
        XCTAssertTrue(inst.isIllegal)
    }

    // MARK: - Unstable Store Instructions

    /// Test AHX (indirect),Y.
    func test_AHX_indirectIndexedY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x93, 0x80])
        XCTAssertEqual(inst.mnemonic, "AHX")
        XCTAssertEqual(inst.addressingMode, .indirectIndexedY)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test AHX absolute,Y.
    func test_AHX_absoluteY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x9F, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "AHX")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test SHY absolute,X.
    func test_SHY_absoluteX() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x9C, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "SHY")
        XCTAssertEqual(inst.operand, "$1000,X")
        XCTAssertEqual(inst.addressingMode, .absoluteX)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test SHX absolute,Y.
    func test_SHX_absoluteY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x9E, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "SHX")
        XCTAssertEqual(inst.operand, "$1000,Y")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test TAS absolute,Y.
    func test_TAS_absoluteY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x9B, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "TAS")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
        XCTAssertTrue(inst.isIllegal)
    }

    /// Test LAS absolute,Y.
    func test_LAS_absoluteY() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xBB, 0x00, 0x10])
        XCTAssertEqual(inst.mnemonic, "LAS")
        XCTAssertEqual(inst.addressingMode, .absoluteY)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertEqual(inst.pageCrossCycles, 1)
    }

    // MARK: - JAM/KIL (CPU Halt)

    /// Test JAM opcode ($02) halts CPU.
    func test_JAM_0x02() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x02])
        XCTAssertEqual(inst.mnemonic, "JAM")
        XCTAssertEqual(inst.addressingMode, .implied)
        XCTAssertTrue(inst.isIllegal)
        XCTAssertTrue(inst.halts)
        XCTAssertEqual(inst.byteCount, 1)
    }

    /// Test all JAM opcodes are recognized.
    func test_allJAM_opcodes() {
        let jamOpcodes: [UInt8] = [
            0x02, 0x12, 0x22, 0x32, 0x42, 0x52,
            0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2,
        ]

        for opcode in jamOpcodes {
            let inst = disassembleBytes(at: 0x0600, bytes: [opcode])
            XCTAssertEqual(inst.mnemonic, "JAM",
                "Opcode $\(String(format: "%02X", opcode)) should be JAM")
            XCTAssertTrue(inst.isIllegal,
                "JAM $\(String(format: "%02X", opcode)) should be illegal")
            XCTAssertTrue(inst.halts,
                "JAM $\(String(format: "%02X", opcode)) should halt")
        }
    }

    // MARK: - Illegal NOPs

    /// Test 1-byte illegal NOP (implied mode).
    func test_illegalNOP_implied() {
        let impliedNops: [UInt8] = [0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA]

        for opcode in impliedNops {
            let inst = disassembleBytes(at: 0x0600, bytes: [opcode])
            XCTAssertEqual(inst.mnemonic, "NOP",
                "Opcode $\(String(format: "%02X", opcode)) should be NOP")
            XCTAssertEqual(inst.addressingMode, .implied,
                "Illegal NOP $\(String(format: "%02X", opcode)) should be implied")
            XCTAssertTrue(inst.isIllegal,
                "NOP $\(String(format: "%02X", opcode)) should be illegal")
            XCTAssertEqual(inst.byteCount, 1)
        }
    }

    /// Test 2-byte illegal NOP (zero page or immediate mode).
    func test_illegalNOP_2byte() {
        // Zero page NOPs
        let inst1 = disassembleBytes(at: 0x0600, bytes: [0x04, 0x80])
        XCTAssertEqual(inst1.mnemonic, "NOP")
        XCTAssertEqual(inst1.addressingMode, .zeroPage)
        XCTAssertTrue(inst1.isIllegal)
        XCTAssertEqual(inst1.byteCount, 2)

        // Immediate NOPs
        let inst2 = disassembleBytes(at: 0x0600, bytes: [0x80, 0x42])
        XCTAssertEqual(inst2.mnemonic, "NOP")
        XCTAssertEqual(inst2.addressingMode, .immediate)
        XCTAssertTrue(inst2.isIllegal)
        XCTAssertEqual(inst2.byteCount, 2)
    }

    /// Test 3-byte illegal NOP (absolute and absolute,X modes).
    func test_illegalNOP_3byte() {
        // Absolute NOP
        let inst1 = disassembleBytes(at: 0x0600, bytes: [0x0C, 0x00, 0x10])
        XCTAssertEqual(inst1.mnemonic, "NOP")
        XCTAssertEqual(inst1.addressingMode, .absolute)
        XCTAssertTrue(inst1.isIllegal)
        XCTAssertEqual(inst1.byteCount, 3)

        // Absolute,X NOP
        let inst2 = disassembleBytes(at: 0x0600, bytes: [0x1C, 0x00, 0x10])
        XCTAssertEqual(inst2.mnemonic, "NOP")
        XCTAssertEqual(inst2.addressingMode, .absoluteX)
        XCTAssertTrue(inst2.isIllegal)
        XCTAssertEqual(inst2.byteCount, 3)
        XCTAssertEqual(inst2.pageCrossCycles, 1)
    }

    // MARK: - Legal vs Illegal Distinction

    /// Test that legal NOP ($EA) is NOT marked illegal.
    func test_legalNOP_notIllegal() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xEA])
        XCTAssertEqual(inst.mnemonic, "NOP")
        XCTAssertFalse(inst.isIllegal, "Legal NOP $EA should not be illegal")
    }

    /// Test that legal SBC ($E9) is NOT marked illegal.
    func test_legalSBC_notIllegal() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xE9, 0x42])
        XCTAssertEqual(inst.mnemonic, "SBC")
        XCTAssertFalse(inst.isIllegal, "Legal SBC $E9 should not be illegal")
    }

    /// Test that illegal SBC ($EB) IS marked illegal.
    func test_illegalSBC_isIllegal() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xEB, 0x42])
        XCTAssertEqual(inst.mnemonic, "SBC")
        XCTAssertTrue(inst.isIllegal, "Illegal SBC $EB should be illegal")
    }

    // MARK: - Mixed Legal and Illegal Sequence

    /// Test disassembling a sequence mixing legal and illegal opcodes.
    func test_mixedLegalIllegalSequence() {
        let data: [UInt8] = [
            0xA9, 0x42,       // LDA #$42     (legal)
            0x07, 0x80,       // SLO $80      (illegal)
            0x8D, 0x00, 0xD4, // STA $D400    (legal)
            0xA7, 0x90,       // LAX $90      (illegal)
        ]
        let memory = ArrayMemoryBus(data: data, baseAddress: 0x0600)

        let instructions = disasm.disassembleRange(from: 0x0600, lines: 4, memory: memory)

        XCTAssertEqual(instructions.count, 4)

        // LDA - legal
        XCTAssertEqual(instructions[0].mnemonic, "LDA")
        XCTAssertFalse(instructions[0].isIllegal)

        // SLO - illegal
        XCTAssertEqual(instructions[1].mnemonic, "SLO")
        XCTAssertTrue(instructions[1].isIllegal)

        // STA - legal
        XCTAssertEqual(instructions[2].mnemonic, "STA")
        XCTAssertFalse(instructions[2].isIllegal)

        // LAX - illegal
        XCTAssertEqual(instructions[3].mnemonic, "LAX")
        XCTAssertTrue(instructions[3].isIllegal)
    }

    /// Test that illegal opcodes show "Illegal/undocumented" in detailed output.
    func test_illegalOpcode_detailedOutput() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0xA7, 0x80])
        let detailed = inst.detailed

        XCTAssertTrue(detailed.contains("Illegal/undocumented opcode"),
            "Detailed output should note illegal opcode")
    }

    /// Test that JAM shows halt warning in detailed output.
    func test_JAM_detailedOutput() {
        let inst = disassembleBytes(at: 0x0600, bytes: [0x02])
        let detailed = inst.detailed

        XCTAssertTrue(detailed.contains("halts the CPU"),
            "Detailed output should warn about CPU halt")
    }

    // MARK: - Read-Modify-Write Illegal Opcodes

    /// Test that RMW illegal opcodes are classified as writing memory.
    func test_illegalRMW_writesMemory() {
        // SLO zero page (ASL + ORA)
        let slo = disassembleBytes(at: 0x0600, bytes: [0x07, 0x80])
        XCTAssertTrue(slo.writesMemory, "SLO should write memory")

        // RLA zero page (ROL + AND)
        let rla = disassembleBytes(at: 0x0600, bytes: [0x27, 0x80])
        XCTAssertTrue(rla.writesMemory, "RLA should write memory")

        // SRE zero page (LSR + EOR)
        let sre = disassembleBytes(at: 0x0600, bytes: [0x47, 0x80])
        XCTAssertTrue(sre.writesMemory, "SRE should write memory")

        // RRA zero page (ROR + ADC)
        let rra = disassembleBytes(at: 0x0600, bytes: [0x67, 0x80])
        XCTAssertTrue(rra.writesMemory, "RRA should write memory")

        // DCP zero page (DEC + CMP)
        let dcp = disassembleBytes(at: 0x0600, bytes: [0xC7, 0x80])
        XCTAssertTrue(dcp.writesMemory, "DCP should write memory")

        // ISC zero page (INC + SBC)
        let isc = disassembleBytes(at: 0x0600, bytes: [0xE7, 0x80])
        XCTAssertTrue(isc.writesMemory, "ISC should write memory")
    }

    /// Test that illegal store opcodes are classified as writing memory.
    func test_illegalStore_writesMemory() {
        // SAX zero page
        let sax = disassembleBytes(at: 0x0600, bytes: [0x87, 0x80])
        XCTAssertTrue(sax.writesMemory, "SAX should write memory")
    }

    // MARK: - Helper

    /// Convenience helper to disassemble bytes through the full pipeline.
    private func disassembleBytes(at address: UInt16, bytes: [UInt8]) -> DisassembledInstruction {
        let memory = ArrayMemoryBus(data: bytes, baseAddress: address)
        return disasm.disassemble(at: address, memory: memory)
    }
}
