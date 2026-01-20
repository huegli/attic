// =============================================================================
// Disassembler.swift - 6502 Disassembler Implementation
// =============================================================================
//
// This file implements the 6502 disassembler for the Atari 800 XL emulator.
// The disassembler converts raw machine code bytes into human-readable
// assembly language instructions.
//
// Features:
// - Disassembles all documented 6502 instructions
// - Recognizes illegal/undocumented opcodes used by Atari software
// - Calculates branch targets and provides relative offset information
// - Supports address labels for hardware registers and OS routines
// - Provides detailed instruction information (cycles, flags, etc.)
//
// The Disassembler works with any MemoryBus implementation, allowing it
// to read from the emulator's memory, a mock memory for testing, or
// even raw byte arrays.
//
// Usage:
// ```swift
// let disasm = Disassembler(labels: AddressLabels.atariStandard)
//
// // Disassemble a single instruction
// let inst = disasm.disassemble(at: 0xE477, memory: memory)
// print(inst.formatted)  // "$E477  A9 00     LDA #$00"
//
// // Disassemble multiple instructions
// let instructions = disasm.disassembleRange(from: 0xE477, lines: 16, memory: memory)
// for inst in instructions {
//     print(inst.formattedWithLabel)
// }
// ```
//
// =============================================================================

import Foundation

/// A 6502 disassembler that converts machine code to assembly language.
///
/// The disassembler reads bytes from a MemoryBus and produces
/// DisassembledInstruction structures containing all information about
/// each instruction.
///
/// The disassembler is designed to be:
/// - **Stateless**: Each disassemble call is independent
/// - **Configurable**: Labels can be customized
/// - **Complete**: Handles all 256 possible opcodes
/// - **Informative**: Provides cycle counts, flag effects, and more
///
/// Thread Safety:
/// The Disassembler struct itself is `Sendable` and can be used from any
/// thread. However, the MemoryBus passed to disassemble methods must be
/// accessed appropriately (typically through the EmulatorEngine actor).
public struct Disassembler: Sendable {
    // =========================================================================
    // MARK: - Configuration
    // =========================================================================

    /// The label table used to provide symbolic names for addresses.
    ///
    /// Labels are shown in place of numeric addresses for branch targets,
    /// jump destinations, and memory operands when available.
    public var labels: AddressLabels

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new disassembler.
    ///
    /// - Parameter labels: The label table to use. Defaults to the standard
    ///   Atari 800 XL labels (hardware registers, OS vectors, etc.).
    public init(labels: AddressLabels = .atariStandard) {
        self.labels = labels
    }

    // =========================================================================
    // MARK: - Single Instruction Disassembly
    // =========================================================================

    /// Disassembles a single instruction at the specified address.
    ///
    /// This method reads the opcode and operand bytes from memory, decodes
    /// the instruction, and returns a complete DisassembledInstruction.
    ///
    /// - Parameters:
    ///   - address: The memory address to disassemble from.
    ///   - memory: The memory bus to read from.
    /// - Returns: A DisassembledInstruction containing all instruction details.
    ///
    /// Example:
    /// ```swift
    /// let inst = disasm.disassemble(at: 0xE477, memory: memory)
    /// print(inst.mnemonic)  // "LDA"
    /// print(inst.operand)   // "#$00"
    /// ```
    public func disassemble(at address: UInt16, memory: MemoryBus) -> DisassembledInstruction {
        // Read the opcode byte
        let opcode = memory.read(address)

        // Look up opcode information
        let info = OpcodeTable.lookup(opcode)

        // Read operand bytes based on addressing mode
        let bytes = readInstructionBytes(at: address, count: info.byteCount, memory: memory)

        // Calculate operand value (if any)
        let operandValue = extractOperandValue(from: bytes, mode: info.mode)

        // Calculate target address for branches/jumps
        let (targetAddress, relativeOffset) = calculateTarget(
            address: address,
            operandValue: operandValue,
            mode: info.mode,
            mnemonic: info.mnemonic
        )

        // Look up label for target address
        let targetLabel = targetAddress.flatMap { labels.lookup($0) }

        // Format the operand string
        let operand = formatOperand(
            mode: info.mode,
            operandValue: operandValue,
            targetAddress: targetAddress,
            targetLabel: targetLabel
        )

        return DisassembledInstruction(
            address: address,
            bytes: bytes,
            mnemonic: info.mnemonic,
            operand: operand,
            addressingMode: info.mode,
            targetAddress: targetAddress,
            relativeOffset: relativeOffset,
            targetLabel: targetLabel,
            cycles: info.cycles,
            pageCrossCycles: info.pageCrossCycles,
            affectedFlags: info.affectedFlags,
            isIllegal: info.isIllegal,
            halts: info.halts
        )
    }

    /// Disassembles a single instruction from raw bytes.
    ///
    /// This method is useful when you have bytes in an array rather than
    /// in emulator memory (e.g., for testing or file analysis).
    ///
    /// - Parameters:
    ///   - address: The address to use for display and branch calculation.
    ///   - bytes: The instruction bytes (must include opcode and operand).
    /// - Returns: A DisassembledInstruction, or nil if bytes is empty.
    public func disassembleBytes(at address: UInt16, bytes: [UInt8]) -> DisassembledInstruction? {
        guard !bytes.isEmpty else { return nil }

        let memory = ArrayMemoryBus(data: bytes, baseAddress: address)
        return disassemble(at: address, memory: memory)
    }

    // =========================================================================
    // MARK: - Range Disassembly
    // =========================================================================

    /// Disassembles a range of instructions starting at the specified address.
    ///
    /// This method disassembles `count` instructions, following the byte
    /// stream sequentially. Each instruction's address is determined by the
    /// previous instruction's length.
    ///
    /// - Parameters:
    ///   - from: The starting address.
    ///   - lines: The number of instructions to disassemble.
    ///   - memory: The memory bus to read from.
    /// - Returns: An array of DisassembledInstruction values.
    ///
    /// Example:
    /// ```swift
    /// let instructions = disasm.disassembleRange(from: 0xE477, lines: 16, memory: memory)
    /// for inst in instructions {
    ///     print(inst.formatted)
    /// }
    /// ```
    public func disassembleRange(
        from startAddress: UInt16,
        lines count: Int,
        memory: MemoryBus
    ) -> [DisassembledInstruction] {
        var instructions: [DisassembledInstruction] = []
        instructions.reserveCapacity(count)

        var address = startAddress

        for _ in 0..<count {
            let instruction = disassemble(at: address, memory: memory)
            instructions.append(instruction)

            // Move to next instruction
            address = instruction.nextAddress

            // Stop if we wrap around memory
            if address < startAddress && instructions.count > 1 {
                break
            }
        }

        return instructions
    }

    /// Disassembles instructions in an address range.
    ///
    /// This method disassembles all instructions between two addresses.
    /// Unlike `disassembleRange(from:lines:)`, this stops at a specific
    /// end address rather than a fixed count.
    ///
    /// - Parameters:
    ///   - start: The starting address (inclusive).
    ///   - end: The ending address (exclusive).
    ///   - memory: The memory bus to read from.
    /// - Returns: An array of DisassembledInstruction values.
    public func disassembleAddressRange(
        from start: UInt16,
        to end: UInt16,
        memory: MemoryBus
    ) -> [DisassembledInstruction] {
        var instructions: [DisassembledInstruction] = []
        var address = start

        while address < end {
            let instruction = disassemble(at: address, memory: memory)
            instructions.append(instruction)
            address = instruction.nextAddress

            // Safety: prevent infinite loop if instruction has 0 bytes (shouldn't happen)
            if instruction.byteCount == 0 {
                break
            }
        }

        return instructions
    }

    // =========================================================================
    // MARK: - Formatted Output
    // =========================================================================

    /// Formats a range of instructions as a multi-line string.
    ///
    /// Each instruction is formatted using its `formattedWithLabel` property
    /// and joined with newlines.
    ///
    /// - Parameters:
    ///   - from: The starting address.
    ///   - lines: The number of instructions to disassemble.
    ///   - memory: The memory bus to read from.
    /// - Returns: A multi-line string containing the disassembly.
    public func formatRange(
        from startAddress: UInt16,
        lines count: Int,
        memory: MemoryBus
    ) -> String {
        let instructions = disassembleRange(from: startAddress, lines: count, memory: memory)
        return instructions.map { $0.formattedWithLabel }.joined(separator: "\n")
    }

    // =========================================================================
    // MARK: - Private Helpers
    // =========================================================================

    /// Reads instruction bytes from memory.
    private func readInstructionBytes(
        at address: UInt16,
        count: Int,
        memory: MemoryBus
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)

        for offset in 0..<count {
            let addr = address &+ UInt16(offset)
            bytes.append(memory.read(addr))
        }

        return bytes
    }

    /// Extracts the operand value from instruction bytes.
    ///
    /// For 1-byte instructions, returns nil.
    /// For 2-byte instructions, returns the second byte.
    /// For 3-byte instructions, returns the 16-bit value (little-endian).
    private func extractOperandValue(
        from bytes: [UInt8],
        mode: AddressingMode
    ) -> UInt16? {
        switch mode.byteCount {
        case 1:
            return nil
        case 2:
            return bytes.count > 1 ? UInt16(bytes[1]) : nil
        case 3:
            if bytes.count > 2 {
                return UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            }
            return nil
        default:
            return nil
        }
    }

    /// Calculates the target address for branches and jumps.
    ///
    /// - Returns: A tuple of (target address, relative offset for branches)
    private func calculateTarget(
        address: UInt16,
        operandValue: UInt16?,
        mode: AddressingMode,
        mnemonic: String
    ) -> (UInt16?, Int8?) {
        guard let value = operandValue else {
            return (nil, nil)
        }

        switch mode {
        case .relative:
            // Branch instructions: target = PC + 2 + signed offset
            // (PC points to instruction, +2 for instruction length)
            let offset = Int8(bitPattern: UInt8(value))
            let nextPC = Int(address) + 2  // Address after the branch instruction
            let target = UInt16((nextPC + Int(offset)) & 0xFFFF)
            return (target, offset)

        case .absolute:
            // JMP and JSR use the operand directly as target
            if mnemonic == "JMP" || mnemonic == "JSR" {
                return (value, nil)
            }
            return (nil, nil)

        case .indirect:
            // JMP ($xxxx) - target is the address read from operand
            // We don't read memory here, so we can't calculate the actual target
            // Just return nil - the caller can read memory if needed
            return (nil, nil)

        default:
            return (nil, nil)
        }
    }

    /// Formats the operand for display.
    private func formatOperand(
        mode: AddressingMode,
        operandValue: UInt16?,
        targetAddress: UInt16?,
        targetLabel: String?
    ) -> String {
        guard let value = operandValue else {
            // No operand (implied or accumulator)
            return mode == .accumulator ? "A" : ""
        }

        // For branches and jumps, prefer showing the target address/label
        if mode == .relative {
            if let label = targetLabel {
                return label
            } else if let target = targetAddress {
                return String(format: "$%04X", target)
            }
        }

        // For other modes, format according to the mode
        return mode.formatOperand(value, label: nil)
    }
}

// =============================================================================
// MARK: - Array Memory Bus (for testing)
// =============================================================================

/// A simple MemoryBus implementation backed by an array.
///
/// This is useful for disassembling raw bytes without needing the full
/// emulator infrastructure. Addresses outside the array return 0x00.
///
/// Example:
/// ```swift
/// let bytes: [UInt8] = [0xA9, 0x42, 0x8D, 0x00, 0xD4]
/// let memory = ArrayMemoryBus(data: bytes, baseAddress: 0x0600)
/// let inst = disasm.disassemble(at: 0x0600, memory: memory)
/// // inst.instructionText == "LDA #$42"
/// ```
public struct ArrayMemoryBus: MemoryBus, Sendable {
    /// The raw bytes.
    private let data: [UInt8]

    /// The base address where data starts.
    private let baseAddress: UInt16

    /// Creates an array-backed memory bus.
    ///
    /// - Parameters:
    ///   - data: The byte array.
    ///   - baseAddress: The address where the array starts in the address space.
    public init(data: [UInt8], baseAddress: UInt16 = 0) {
        self.data = data
        self.baseAddress = baseAddress
    }

    /// Reads a byte at the specified address.
    ///
    /// Returns 0x00 for addresses outside the array bounds.
    public func read(_ address: UInt16) -> UInt8 {
        let offset = Int(address) - Int(baseAddress)
        guard offset >= 0 && offset < data.count else {
            return 0x00
        }
        return data[offset]
    }

    /// Writing is not supported - does nothing.
    public func write(_ address: UInt16, value: UInt8) {
        // Read-only
    }
}

// =============================================================================
// MARK: - Convenience Extensions
// =============================================================================

extension Disassembler {
    /// Disassembles the instruction at the current program counter.
    ///
    /// This is a convenience method for debugging that gets the PC from
    /// the CPU registers and disassembles there.
    ///
    /// - Parameters:
    ///   - registers: The current CPU registers (to get PC).
    ///   - memory: The memory bus to read from.
    /// - Returns: The disassembled instruction at PC.
    public func disassembleAtPC(
        registers: CPURegisters,
        memory: MemoryBus
    ) -> DisassembledInstruction {
        disassemble(at: registers.pc, memory: memory)
    }

    /// Disassembles a range starting at the current program counter.
    ///
    /// - Parameters:
    ///   - registers: The current CPU registers (to get PC).
    ///   - lines: Number of instructions to disassemble.
    ///   - memory: The memory bus to read from.
    /// - Returns: Array of disassembled instructions starting at PC.
    public func disassembleFromPC(
        registers: CPURegisters,
        lines: Int,
        memory: MemoryBus
    ) -> [DisassembledInstruction] {
        disassembleRange(from: registers.pc, lines: lines, memory: memory)
    }
}
