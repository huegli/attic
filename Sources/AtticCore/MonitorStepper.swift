// =============================================================================
// MonitorStepper.swift - Instruction-Level Stepping for the Monitor
// =============================================================================
//
// This file implements instruction-level stepping for the monitor/debugger.
// Unlike frame-level stepping (which executes an entire video frame), this
// provides precise control by executing one CPU instruction at a time.
//
// Implementation Strategy:
// -----------------------
// Since libatari800 doesn't expose instruction-level stepping directly,
// we implement it by:
//
// 1. Determining the length of the current instruction using the opcode table
// 2. Placing a temporary BRK instruction at the next instruction address
// 3. Running the emulator until the BRK is hit
// 4. Removing the temporary BRK
//
// This approach works for most instructions. Special handling is needed for:
// - Branch instructions (may go to different address)
// - Jump instructions (JSR, JMP)
// - Return instructions (RTS, RTI)
//
// Step Over:
// ---------
// For JSR instructions, "step over" places the temporary BRK at the return
// address (PC + 3) so the subroutine executes completely before stopping.
//
// Run Until:
// ---------
// Runs until the PC reaches a specific address. Useful for running to
// the end of a loop or to a specific routine.
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Step Result
// =============================================================================

/// The result of a stepping operation.
public struct MonitorStepResult: Sendable {
    /// The CPU registers after stepping.
    public let registers: CPURegisters

    /// The address where execution stopped.
    public let stoppedAt: UInt16

    /// Whether a breakpoint was hit (permanent, not temporary).
    public let breakpointHit: Bool

    /// The breakpoint address if one was hit.
    public let breakpointAddress: UInt16?

    /// Number of instructions executed.
    public let instructionsExecuted: Int

    /// Whether the step was successful.
    public let success: Bool

    /// Error message if step failed.
    public let errorMessage: String?

    /// Creates a successful step result.
    public static func success(
        registers: CPURegisters,
        stoppedAt: UInt16,
        instructionsExecuted: Int = 1
    ) -> MonitorStepResult {
        MonitorStepResult(
            registers: registers,
            stoppedAt: stoppedAt,
            breakpointHit: false,
            breakpointAddress: nil,
            instructionsExecuted: instructionsExecuted,
            success: true,
            errorMessage: nil
        )
    }

    /// Creates a result for breakpoint hit.
    public static func breakpoint(
        registers: CPURegisters,
        address: UInt16,
        instructionsExecuted: Int
    ) -> MonitorStepResult {
        MonitorStepResult(
            registers: registers,
            stoppedAt: address,
            breakpointHit: true,
            breakpointAddress: address,
            instructionsExecuted: instructionsExecuted,
            success: true,
            errorMessage: nil
        )
    }

    /// Creates an error result.
    public static func error(_ message: String, registers: CPURegisters) -> MonitorStepResult {
        MonitorStepResult(
            registers: registers,
            stoppedAt: registers.pc,
            breakpointHit: false,
            breakpointAddress: nil,
            instructionsExecuted: 0,
            success: false,
            errorMessage: message
        )
    }
}

// =============================================================================
// MARK: - Memory Access Adapter
// =============================================================================

/// Adapter to make EmulatorEngine conform to MemoryAccess.
///
/// This allows the breakpoint manager to work with the emulator engine
/// without tight coupling.
public struct EmulatorMemoryAdapter: MemoryAccess, Sendable {
    private let emulator: EmulatorEngine

    public init(emulator: EmulatorEngine) {
        self.emulator = emulator
    }

    public func readMemory(at address: UInt16) async -> UInt8 {
        await emulator.readMemory(at: address)
    }

    public func writeMemory(at address: UInt16, value: UInt8) async {
        await emulator.writeMemory(at: address, value: value)
    }
}

// =============================================================================
// MARK: - Monitor Stepper
// =============================================================================

/// Provides instruction-level stepping for the monitor.
///
/// This actor coordinates between the emulator engine, breakpoint manager,
/// and opcode table to implement precise single-stepping.
///
/// Usage:
///
///     let stepper = MonitorStepper(emulator: engine, breakpoints: bpManager)
///
///     // Single-step one instruction
///     let result = await stepper.step()
///
///     // Step over a subroutine call
///     let result = await stepper.stepOver()
///
///     // Run until specific address
///     let result = await stepper.runUntil(address: 0x060A)
///
public actor MonitorStepper {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The emulator engine.
    private let emulator: EmulatorEngine

    /// The breakpoint manager.
    private let breakpoints: BreakpointManager

    /// Memory access adapter for breakpoint operations.
    private var memoryAdapter: EmulatorMemoryAdapter {
        EmulatorMemoryAdapter(emulator: emulator)
    }

    /// Maximum instructions to execute for "run until" before timing out.
    public var maxRunUntilInstructions: Int = 1_000_000

    /// Whether stepping is currently in progress.
    private var stepping: Bool = false

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new monitor stepper.
    ///
    /// - Parameters:
    ///   - emulator: The emulator engine to control.
    ///   - breakpoints: The breakpoint manager.
    public init(emulator: EmulatorEngine, breakpoints: BreakpointManager) {
        self.emulator = emulator
        self.breakpoints = breakpoints
    }

    // =========================================================================
    // MARK: - Single Step
    // =========================================================================

    /// Executes a single instruction.
    ///
    /// This is the core stepping operation. It:
    /// 1. Reads the current instruction to determine its length
    /// 2. Places a temporary BRK at the next instruction
    /// 3. Runs until the BRK is hit
    /// 4. Cleans up the temporary BRK
    ///
    /// - Returns: The result of the step operation.
    public func step() async -> MonitorStepResult {
        guard !stepping else {
            let regs = await emulator.getRegisters()
            return .error("Step already in progress", registers: regs)
        }

        stepping = true
        defer { stepping = false }

        let regs = await emulator.getRegisters()
        let pc = regs.pc

        // Get the instruction length at current PC
        let opcode = await emulator.readMemory(at: pc)

        // Check if we're at a breakpoint - need to get original byte
        let actualOpcode: UInt8
        if let original = await breakpoints.getOriginalByte(at: pc) {
            actualOpcode = original
        } else {
            actualOpcode = opcode
        }

        let length = OpcodeTable.instructionLength(actualOpcode)
        let nextPC = pc &+ UInt16(length)

        // Check if this is a flow-control instruction that might not go to nextPC
        let info = OpcodeTable.lookup(actualOpcode)
        // For branches, jumps, and returns, we can't easily place a temp BRK
        // Instead, we'll run one frame and check if PC changed meaningfully
        if OpcodeTable.isBranch(info.mnemonic) ||
           OpcodeTable.isJump(info.mnemonic) ||
           OpcodeTable.isReturn(info.mnemonic) {
            return await stepFlowControl(info: info, pc: pc, regs: regs)
        }

        // Normal instruction: place temp BRK at next instruction
        return await stepNormal(nextPC: nextPC, originalPC: pc)
    }

    /// Steps through a flow-control instruction (branch, jump, return).
    private func stepFlowControl(info: OpcodeInfo, pc: UInt16, regs: CPURegisters) async -> MonitorStepResult {
        // For flow control, we need to be careful about where the temp BRK goes

        if OpcodeTable.isReturn(info.mnemonic) {
            // RTS/RTI: return address is on stack, we'll just execute one frame
            // and stop wherever it lands
            return await executeAndStop()
        }

        if info.mnemonic == "JMP" {
            // JMP: we know the target, place temp BRK there
            let targetPC = await getJumpTarget(pc: pc, mode: info.mode)
            return await stepNormal(nextPC: targetPC, originalPC: pc)
        }

        if info.mnemonic == "JSR" {
            // JSR: for single step, we go to the subroutine
            let targetPC = await getJumpTarget(pc: pc, mode: info.mode)
            return await stepNormal(nextPC: targetPC, originalPC: pc)
        }

        if OpcodeTable.isBranch(info.mnemonic) {
            // Branch: could go to target or fall through
            // Place temp BRK at both locations and see which hits
            return await stepBranch(pc: pc)
        }

        // Fallback: just execute one frame
        return await executeAndStop()
    }

    /// Steps through a branch instruction.
    private func stepBranch(pc: UInt16) async -> MonitorStepResult {
        // Read the branch offset
        let offset = Int8(bitPattern: await emulator.readMemory(at: pc + 1))
        let branchTarget = OpcodeTable.branchTarget(from: pc + 2, offset: offset)
        let fallThrough = pc + 2

        let memory = memoryAdapter

        // Set temporary breakpoints at both destinations
        await breakpoints.setTemporaryBreakpoint(at: branchTarget, memory: memory)
        if branchTarget != fallThrough {
            await breakpoints.setTemporaryBreakpoint(at: fallThrough, memory: memory)
        }

        // If we're sitting on a permanent breakpoint, temporarily suspend it
        let wasAtBreakpoint = await breakpoints.hasBreakpoint(at: pc)
        if wasAtBreakpoint {
            await breakpoints.suspendBreakpoint(at: pc, memory: memory)
        }

        // Execute one frame
        let result = await emulator.executeFrame()

        // Clear temporary breakpoints
        await breakpoints.clearTemporaryBreakpoint(memory: memory)

        // Re-enable the permanent breakpoint if we had one
        if wasAtBreakpoint {
            await breakpoints.resumeBreakpoint(at: pc, memory: memory)
        }

        // Get final state
        let finalRegs = await emulator.getRegisters()

        // Check if we hit a permanent breakpoint
        let hasPermanentBreakpoint = await breakpoints.hasBreakpoint(at: finalRegs.pc)
        let isTemporary = await breakpoints.isTemporaryBreakpoint(at: finalRegs.pc)
        if hasPermanentBreakpoint && !isTemporary {
            await breakpoints.recordHit(at: finalRegs.pc)
            return .breakpoint(registers: finalRegs, address: finalRegs.pc, instructionsExecuted: 1)
        }

        return .success(registers: finalRegs, stoppedAt: finalRegs.pc)
    }

    /// Steps through a normal (non-flow-control) instruction.
    private func stepNormal(nextPC: UInt16, originalPC: UInt16) async -> MonitorStepResult {
        let memory = memoryAdapter

        // Set temporary breakpoint at next instruction
        await breakpoints.setTemporaryBreakpoint(at: nextPC, memory: memory)

        // If we're sitting on a permanent breakpoint, temporarily suspend it
        let wasAtBreakpoint = await breakpoints.hasBreakpoint(at: originalPC)
        if wasAtBreakpoint {
            await breakpoints.suspendBreakpoint(at: originalPC, memory: memory)
        }

        // Execute one frame (should hit our temp BRK almost immediately)
        _ = await emulator.executeFrame()

        // Clear temporary breakpoint
        await breakpoints.clearTemporaryBreakpoint(memory: memory)

        // Re-enable the permanent breakpoint if we had one
        if wasAtBreakpoint {
            await breakpoints.resumeBreakpoint(at: originalPC, memory: memory)
        }

        // Get final state
        let finalRegs = await emulator.getRegisters()

        // Check if we hit a permanent breakpoint (not the one we just passed)
        if await breakpoints.hasBreakpoint(at: finalRegs.pc) &&
           finalRegs.pc != originalPC {
            await breakpoints.recordHit(at: finalRegs.pc)
            return .breakpoint(registers: finalRegs, address: finalRegs.pc, instructionsExecuted: 1)
        }

        return .success(registers: finalRegs, stoppedAt: finalRegs.pc)
    }

    /// Execute one frame and stop (for RTS/RTI where we don't know the destination).
    private func executeAndStop() async -> MonitorStepResult {
        let memory = memoryAdapter
        let originalPC = await emulator.getRegisters().pc

        // Suspend breakpoint at current location if present
        let wasAtBreakpoint = await breakpoints.hasBreakpoint(at: originalPC)
        if wasAtBreakpoint {
            await breakpoints.suspendBreakpoint(at: originalPC, memory: memory)
        }

        // Execute one frame
        _ = await emulator.executeFrame()

        // Re-enable breakpoint
        if wasAtBreakpoint {
            await breakpoints.resumeBreakpoint(at: originalPC, memory: memory)
        }

        let finalRegs = await emulator.getRegisters()

        // Check for breakpoint hit
        if await breakpoints.hasBreakpoint(at: finalRegs.pc) && finalRegs.pc != originalPC {
            await breakpoints.recordHit(at: finalRegs.pc)
            return .breakpoint(registers: finalRegs, address: finalRegs.pc, instructionsExecuted: 1)
        }

        return .success(registers: finalRegs, stoppedAt: finalRegs.pc)
    }

    /// Gets the jump target for JMP/JSR instructions.
    private func getJumpTarget(pc: UInt16, mode: AddressingMode) async -> UInt16 {
        let low = UInt16(await emulator.readMemory(at: pc + 1))
        let high = UInt16(await emulator.readMemory(at: pc + 2))
        let address = (high << 8) | low

        if mode == .indirect {
            // JMP ($xxxx) - read the actual target from the pointer
            // Note: 6502 bug - doesn't correctly handle page boundary for indirect
            let targetLow = UInt16(await emulator.readMemory(at: address))
            let highAddr = (address & 0xFF00) | ((address + 1) & 0x00FF)  // 6502 page wrap bug
            let targetHigh = UInt16(await emulator.readMemory(at: highAddr))
            return (targetHigh << 8) | targetLow
        }

        return address
    }

    // =========================================================================
    // MARK: - Step Over
    // =========================================================================

    /// Steps over a subroutine call.
    ///
    /// If the current instruction is JSR, this runs until the subroutine
    /// returns. Otherwise, it behaves like a normal step.
    ///
    /// - Returns: The result of the step operation.
    public func stepOver() async -> MonitorStepResult {
        guard !stepping else {
            let regs = await emulator.getRegisters()
            return .error("Step already in progress", registers: regs)
        }

        stepping = true
        defer { stepping = false }

        let regs = await emulator.getRegisters()
        let pc = regs.pc

        // Get the instruction
        let opcode = await emulator.readMemory(at: pc)
        let actualOpcode: UInt8
        if let original = await breakpoints.getOriginalByte(at: pc) {
            actualOpcode = original
        } else {
            actualOpcode = opcode
        }

        // Check if it's JSR
        let info = OpcodeTable.lookup(actualOpcode)
        guard info.mnemonic == "JSR" else {
            // Not JSR, do normal step
            stepping = false
            return await step()
        }

        // For JSR, place temp BRK at return address (PC + 3)
        let returnAddress = pc &+ 3
        return await stepNormal(nextPC: returnAddress, originalPC: pc)
    }

    // =========================================================================
    // MARK: - Step Multiple
    // =========================================================================

    /// Executes multiple single steps.
    ///
    /// - Parameter count: Number of instructions to step.
    /// - Returns: The result after all steps.
    public func step(count: Int) async -> MonitorStepResult {
        guard count > 0 else {
            let regs = await emulator.getRegisters()
            return .success(registers: regs, stoppedAt: regs.pc, instructionsExecuted: 0)
        }

        var totalExecuted = 0

        for _ in 0..<count {
            let result = await step()

            totalExecuted += result.instructionsExecuted

            // Stop on error or breakpoint hit
            if !result.success || result.breakpointHit {
                return MonitorStepResult(
                    registers: result.registers,
                    stoppedAt: result.stoppedAt,
                    breakpointHit: result.breakpointHit,
                    breakpointAddress: result.breakpointAddress,
                    instructionsExecuted: totalExecuted,
                    success: result.success,
                    errorMessage: result.errorMessage
                )
            }
        }

        let finalRegs = await emulator.getRegisters()
        return .success(registers: finalRegs, stoppedAt: finalRegs.pc,
                        instructionsExecuted: totalExecuted)
    }

    // =========================================================================
    // MARK: - Run Until
    // =========================================================================

    /// Runs until the PC reaches a specific address.
    ///
    /// - Parameters:
    ///   - address: The target address.
    ///   - maxInstructions: Maximum instructions before timeout (default: maxRunUntilInstructions).
    /// - Returns: The result when stopped.
    public func runUntil(address: UInt16, maxInstructions: Int? = nil) async -> MonitorStepResult {
        guard !stepping else {
            let regs = await emulator.getRegisters()
            return .error("Step already in progress", registers: regs)
        }

        stepping = true
        defer { stepping = false }

        let maxCount = maxInstructions ?? maxRunUntilInstructions
        let memory = memoryAdapter

        // Set a temporary breakpoint at the target
        await breakpoints.setTemporaryBreakpoint(at: address, memory: memory)

        var executed = 0

        // Run frames until we hit the target or a permanent breakpoint
        while executed < maxCount {
            let pc = await emulator.getRegisters().pc

            // Check if we're at a permanent breakpoint
            if await breakpoints.hasBreakpoint(at: pc) {
                await breakpoints.suspendBreakpoint(at: pc, memory: memory)
            }

            _ = await emulator.executeFrame()
            executed += 1000  // Approximate instructions per frame

            let newPC = await emulator.getRegisters().pc

            // Check if we hit our target
            if newPC == address {
                await breakpoints.clearTemporaryBreakpoint(memory: memory)
                let finalRegs = await emulator.getRegisters()
                return .success(registers: finalRegs, stoppedAt: finalRegs.pc,
                                instructionsExecuted: executed)
            }

            // Check if we hit a permanent breakpoint
            if await breakpoints.hasBreakpoint(at: newPC) {
                await breakpoints.clearTemporaryBreakpoint(memory: memory)
                await breakpoints.recordHit(at: newPC)
                let finalRegs = await emulator.getRegisters()
                return .breakpoint(registers: finalRegs, address: newPC,
                                   instructionsExecuted: executed)
            }
        }

        // Timeout
        await breakpoints.clearTemporaryBreakpoint(memory: memory)
        let finalRegs = await emulator.getRegisters()
        return .error("Run until $\(String(format: "%04X", address)) timed out after \(maxCount) instructions",
                      registers: finalRegs)
    }
}
