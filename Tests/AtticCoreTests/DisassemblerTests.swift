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
    func test_pokeyLabels() {
        let labels = AddressLabels.pokeyRegisters

        XCTAssertEqual(labels.lookup(0xD200), "AUDF1")
        XCTAssertEqual(labels.lookup(0xD20A), "RANDOM")
        XCTAssertEqual(labels.lookup(0xD20F), "SKCTL")
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
