// =============================================================================
// BASICLineHandler.swift - BASIC Memory Injection Coordinator
// =============================================================================
//
// This file implements the coordinator that handles BASIC line entry by:
// 1. Reading current BASIC state from emulator memory
// 2. Tokenizing the input line
// 3. Injecting the tokenized result back into emulator memory
// 4. Updating all relevant BASIC pointers
//
// The handler implements the "emulator-primary" design where the emulator
// memory is the single source of truth. Each line is tokenized and injected
// immediately, exactly like real Atari BASIC.
//
// Usage:
//
//     let handler = BASICLineHandler(emulator: engine)
//     let result = try await handler.enterLine("10 PRINT \"HELLO\"")
//     print(result.message)  // "Line 10 stored (18 bytes)"
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Line Entry Result
// =============================================================================

/// The result of entering a BASIC line.
public struct BASICLineResult: Sendable {
    /// Whether the operation succeeded.
    public let success: Bool

    /// A human-readable message about the operation.
    public let message: String

    /// The line number that was affected (if applicable).
    public let lineNumber: UInt16?

    /// The number of bytes used by the tokenized line.
    public let bytesUsed: Int?

    /// Creates a successful result.
    public static func success(
        lineNumber: UInt16,
        bytesUsed: Int,
        message: String? = nil
    ) -> BASICLineResult {
        BASICLineResult(
            success: true,
            message: message ?? "Line \(lineNumber) stored (\(bytesUsed) bytes)",
            lineNumber: lineNumber,
            bytesUsed: bytesUsed
        )
    }

    /// Creates a deleted result.
    public static func deleted(lineNumber: UInt16) -> BASICLineResult {
        BASICLineResult(
            success: true,
            message: "Line \(lineNumber) deleted",
            lineNumber: lineNumber,
            bytesUsed: nil
        )
    }

    /// Creates an error result.
    public static func error(_ message: String) -> BASICLineResult {
        BASICLineResult(
            success: false,
            message: message,
            lineNumber: nil,
            bytesUsed: nil
        )
    }

    /// Creates a result for immediate mode command.
    public static func immediate(_ message: String) -> BASICLineResult {
        BASICLineResult(
            success: true,
            message: message,
            lineNumber: nil,
            bytesUsed: nil
        )
    }
}

// =============================================================================
// MARK: - Line Handler
// =============================================================================

/// Coordinates BASIC line entry with the emulator.
///
/// This actor manages the interaction between the BASIC tokenizer and
/// the emulator's memory. It ensures thread-safe access to the emulator
/// and handles all the memory manipulation required to insert, replace,
/// or delete BASIC lines.
public actor BASICLineHandler {
    /// The emulator engine providing memory access.
    private let emulator: EmulatorEngine

    /// The tokenizer instance.
    private let tokenizer = BASICTokenizer()

    /// Creates a line handler for the given emulator.
    ///
    /// - Parameter emulator: The emulator engine to work with.
    public init(emulator: EmulatorEngine) {
        self.emulator = emulator
    }

    // =========================================================================
    // MARK: - Line Entry
    // =========================================================================

    /// Enters a BASIC line into the emulator.
    ///
    /// This is the main entry point for BASIC line handling. It:
    /// 1. Parses the input to determine if it's a line entry or immediate command
    /// 2. For line entry: tokenizes, finds position, injects into memory
    /// 3. For immediate commands: executes directly (RUN, LIST, etc.)
    ///
    /// - Parameter input: The BASIC input line.
    /// - Returns: The result of the operation.
    public func enterLine(_ input: String) async -> BASICLineResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty input
        guard !trimmed.isEmpty else {
            return .error("Empty line")
        }

        // Check if this starts with a line number
        if let firstChar = trimmed.first, firstChar.isNumber {
            return await enterNumberedLine(trimmed)
        } else {
            // Immediate mode command
            return await handleImmediateCommand(trimmed)
        }
    }

    /// Enters a numbered line (stored program line).
    private func enterNumberedLine(_ input: String) async -> BASICLineResult {
        // Read current BASIC state
        let state = await readMemoryState()

        // Read existing variables from VNT
        let existingVariables = await readVariables(state: state)

        // Check for line number only (delete line)
        if let lineNumOnly = parseLineNumberOnly(input) {
            return await deleteLine(lineNumOnly, state: state)
        }

        // Tokenize the line
        let tokenizedLine: TokenizedLine
        do {
            tokenizedLine = try tokenizer.tokenize(input, existingVariables: existingVariables)
        } catch let error as BASICTokenizerError {
            return .error(error.message)
        } catch {
            return .error("Tokenization error: \(error.localizedDescription)")
        }

        // Inject into memory
        return await injectLine(tokenizedLine, state: state, existingVariables: existingVariables)
    }

    /// Handles immediate mode commands (RUN, LIST, NEW, etc.).
    private func handleImmediateCommand(_ input: String) async -> BASICLineResult {
        let upper = input.uppercased().trimmingCharacters(in: .whitespaces)

        // Handle known immediate commands
        if upper == "RUN" || upper.hasPrefix("RUN ") {
            return await runProgram()
        }

        if upper == "NEW" {
            return await newProgram()
        }

        if upper == "LIST" || upper.hasPrefix("LIST ") {
            return .immediate("LIST command - use .basic list in REPL")
        }

        if upper == "CONT" {
            return await continueProgram()
        }

        // Unknown immediate command - try to tokenize as a direct statement
        // (like PRINT "HELLO" without line number)
        return .error("Immediate mode not supported. Add a line number or use RUN/NEW/LIST")
    }

    // =========================================================================
    // MARK: - Memory Reading
    // =========================================================================

    /// Reads the current BASIC memory state from the emulator.
    private func readMemoryState() async -> BASICMemoryState {
        // Read all pointers concurrently
        async let lomem = emulator.readWord(at: BASICPointers.lomem)
        async let vntp = emulator.readWord(at: BASICPointers.vntp)
        async let vntd = emulator.readWord(at: BASICPointers.vntd)
        async let vvtp = emulator.readWord(at: BASICPointers.vvtp)
        async let stmtab = emulator.readWord(at: BASICPointers.stmtab)
        async let stmcur = emulator.readWord(at: BASICPointers.stmcur)
        async let starp = emulator.readWord(at: BASICPointers.starp)
        async let runstk = emulator.readWord(at: BASICPointers.runstk)
        async let memtop = emulator.readWord(at: BASICPointers.memtop)

        return await BASICMemoryState(
            lomem: lomem,
            vntp: vntp,
            vntd: vntd,
            vvtp: vvtp,
            stmtab: stmtab,
            stmcur: stmcur,
            starp: starp,
            runstk: runstk,
            memtop: memtop
        )
    }

    /// Reads existing variables from the Variable Name Table.
    private func readVariables(state: BASICMemoryState) async -> [BASICVariable] {
        // Read VNT bytes
        let vntSize = Int(state.vntd - state.vntp)
        guard vntSize > 0 else { return [] }

        let vntBytes = await emulator.readMemoryBlock(at: state.vntp, count: vntSize)

        // Parse variable names
        let names = BASICVariableTable.parseVNT(from: vntBytes)

        // Create variable entries with indices
        return names.enumerated().map { index, name in
            BASICVariable(name: name, index: UInt8(index))
        }
    }

    // =========================================================================
    // MARK: - Line Injection
    // =========================================================================

    /// Injects a tokenized line into emulator memory.
    private func injectLine(
        _ line: TokenizedLine,
        state: BASICMemoryState,
        existingVariables: [BASICVariable]
    ) async -> BASICLineResult {
        // Find where this line should go
        let position = await findLinePosition(
            lineNumber: line.lineNumber,
            state: state
        )

        // Calculate memory changes needed
        let shift = BASICMemoryOps.calculateShift(
            newLineLength: line.bytes.count,
            existingLineLength: position.existingLength
        )

        // Check if we have enough memory
        let newStarp = Int(state.starp) + shift
        if newStarp > Int(state.runstk) - 256 {
            return .error("Out of memory")
        }

        // Pause emulator for memory operations
        await emulator.pause()

        // If we have new variables, add them first
        if !line.newVariables.isEmpty {
            await addNewVariables(line.newVariables, state: state, existingCount: existingVariables.count)
        }

        // Re-read state after variable additions
        let updatedState = await readMemoryState()

        // Shift memory if needed
        if shift != 0 {
            await shiftMemory(
                from: position.address + UInt16(position.existingLength),
                by: shift,
                until: updatedState.starp
            )
        }

        // Write the tokenized line
        await emulator.writeMemoryBlock(at: position.address, bytes: line.bytes)

        // Update STARP pointer
        let newStarpValue = UInt16(Int(updatedState.starp) + shift)
        await emulator.writeWord(at: BASICPointers.starp, value: newStarpValue)

        // Resume emulator
        await emulator.resume()

        return .success(lineNumber: line.lineNumber, bytesUsed: line.bytes.count)
    }

    /// Finds the position where a line should be inserted/replaced.
    private func findLinePosition(
        lineNumber: UInt16,
        state: BASICMemoryState
    ) async -> (address: UInt16, existingLength: Int) {
        var address = state.stmtab

        while address < state.starp {
            let currentLineNum = await emulator.readWord(at: address)

            // End of program marker
            if currentLineNum == 0 {
                return (address, 0)
            }

            // Found the line
            if currentLineNum == lineNumber {
                let lineLength = Int(await emulator.readMemoryBlock(at: address + 2, count: 1).first ?? 0)
                return (address, lineLength)
            }

            // Past where this line should go
            if currentLineNum > lineNumber {
                return (address, 0)
            }

            // Move to next line
            let lineLength = await emulator.readMemoryBlock(at: address + 2, count: 1).first ?? 0
            address = address &+ UInt16(lineLength)
        }

        return (address, 0)
    }

    /// Shifts memory to make room for or remove a line.
    private func shiftMemory(from address: UInt16, by shift: Int, until endAddress: UInt16) async {
        guard shift != 0 else { return }

        let size = Int(endAddress) - Int(address)
        guard size > 0 else { return }

        // Read the memory block to shift
        let bytes = await emulator.readMemoryBlock(at: address, count: size)

        // Write to new location
        let newAddress = UInt16(Int(address) + shift)
        await emulator.writeMemoryBlock(at: newAddress, bytes: bytes)

        // If shrinking, clear the old tail
        if shift < 0 {
            let clearStart = newAddress + UInt16(size)
            let clearBytes = [UInt8](repeating: 0, count: -shift)
            await emulator.writeMemoryBlock(at: clearStart, bytes: clearBytes)
        }
    }

    /// Adds new variables to the VNT and VVT.
    private func addNewVariables(
        _ variables: [BASICVariableName],
        state: BASICMemoryState,
        existingCount: Int
    ) async {
        // Calculate new VNT entries
        var vntAdditions: [UInt8] = []
        for variable in variables {
            vntAdditions.append(contentsOf: variable.encodeForVNT())
        }

        // Calculate space needed
        let vntGrowth = vntAdditions.count
        let vvtGrowth = variables.count * BASICMemoryDefaults.vvtEntrySize

        // Shift Statement Table forward to make room
        let stmtSize = Int(state.starp - state.stmtab)
        if stmtSize > 0 {
            let stmtBytes = await emulator.readMemoryBlock(at: state.stmtab, count: stmtSize)
            let newStmtab = UInt16(Int(state.stmtab) + vntGrowth + vvtGrowth)
            await emulator.writeMemoryBlock(at: newStmtab, bytes: stmtBytes)
        }

        // Write new VNT entries (at end of existing VNT, before terminator)
        let vntInsertPoint = state.vntd
        await emulator.writeMemoryBlock(at: vntInsertPoint, bytes: vntAdditions)

        // Write VNT terminator after new entries
        await emulator.writeMemoryBlock(at: vntInsertPoint + UInt16(vntGrowth), bytes: [0x00])

        // Initialize new VVT entries with zeros
        let vvtInsertPoint = UInt16(Int(state.vvtp) + existingCount * BASICMemoryDefaults.vvtEntrySize)
        let vvtZeros = [UInt8](repeating: 0, count: vvtGrowth)
        await emulator.writeMemoryBlock(at: vvtInsertPoint + UInt16(vntGrowth), bytes: vvtZeros)

        // Update all BASIC pointers
        let newVntd = vntInsertPoint + UInt16(vntGrowth)
        let newVvtp = state.vvtp + UInt16(vntGrowth)
        let newStmtab = state.stmtab + UInt16(vntGrowth + vvtGrowth)
        let newStmcur = newStmtab  // Reset to start
        let newStarp = state.starp + UInt16(vntGrowth + vvtGrowth)

        await emulator.writeWord(at: BASICPointers.vntd, value: newVntd)
        await emulator.writeWord(at: BASICPointers.vvtp, value: newVvtp)
        await emulator.writeWord(at: BASICPointers.stmtab, value: newStmtab)
        await emulator.writeWord(at: BASICPointers.stmcur, value: newStmcur)
        await emulator.writeWord(at: BASICPointers.starp, value: newStarp)
    }

    // =========================================================================
    // MARK: - Line Deletion
    // =========================================================================

    /// Parses a line number only (for deletion).
    private func parseLineNumberOnly(_ input: String) -> UInt16? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let lineNum = Int(trimmed), lineNum >= 0, lineNum <= 32767 else {
            return nil
        }
        // Check that input is ONLY a line number
        if String(lineNum) == trimmed {
            return UInt16(lineNum)
        }
        return nil
    }

    /// Deletes a line from the program.
    private func deleteLine(_ lineNumber: UInt16, state: BASICMemoryState) async -> BASICLineResult {
        // Find the line
        let position = await findLinePosition(lineNumber: lineNumber, state: state)

        // If line doesn't exist, just acknowledge
        guard position.existingLength > 0 else {
            return .deleted(lineNumber: lineNumber)
        }

        // Pause emulator
        await emulator.pause()

        // Shift memory to remove the line
        await shiftMemory(
            from: position.address + UInt16(position.existingLength),
            by: -position.existingLength,
            until: state.starp
        )

        // Update STARP
        let newStarp = UInt16(Int(state.starp) - position.existingLength)
        await emulator.writeWord(at: BASICPointers.starp, value: newStarp)

        // Resume emulator
        await emulator.resume()

        return .deleted(lineNumber: lineNumber)
    }

    // =========================================================================
    // MARK: - Range Deletion
    // =========================================================================

    /// Parses a line number or range string (e.g., "10" or "10-50").
    ///
    /// Supports two formats:
    /// - Single line: "10" → deletes line 10
    /// - Range: "10-50" → deletes lines 10 through 50 inclusive
    ///
    /// - Parameter input: The line/range string from the user.
    /// - Returns: A tuple of (start, end) line numbers, or nil if invalid.
    private func parseLineRange(_ input: String) -> (start: UInt16, end: UInt16)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if let dashIndex = trimmed.firstIndex(of: "-") {
            // Range format: "10-50"
            let startStr = String(trimmed[trimmed.startIndex..<dashIndex])
            let endStr = String(trimmed[trimmed.index(after: dashIndex)..<trimmed.endIndex])
            guard let start = UInt16(startStr), let end = UInt16(endStr),
                  start <= end, start <= 32767, end <= 32767 else {
                return nil
            }
            return (start, end)
        } else {
            // Single line: "10"
            guard let lineNum = UInt16(trimmed), lineNum <= 32767 else {
                return nil
            }
            return (lineNum, lineNum)
        }
    }

    /// Deletes one or more BASIC lines by line number or range.
    ///
    /// Supports single line ("10") or range ("10-50"). Lines are stored
    /// sorted in the statement table, so matching lines form a contiguous
    /// block. A single memory shift removes the entire block efficiently.
    ///
    /// - Parameter lineOrRange: A line number or "start-end" range string.
    /// - Returns: The result of the deletion operation.
    public func deleteLines(lineOrRange: String) async -> BASICLineResult {
        guard let range = parseLineRange(lineOrRange) else {
            return .error("Invalid line range: \(lineOrRange)")
        }

        let state = await readMemoryState()

        // Scan statement table to find the contiguous block of matching lines.
        // Lines are sorted by number, so all matches are adjacent in memory.
        var blockStart: UInt16? = nil
        var blockEnd: UInt16? = nil
        var address = state.stmtab
        var deletedCount = 0

        while address < state.starp {
            let lineNum = await emulator.readWord(at: address)
            if lineNum == 0 { break }

            let lineLength = Int(await emulator.readMemoryBlock(
                at: address + 2, count: 1
            ).first ?? 0)

            if lineNum >= range.start && lineNum <= range.end {
                if blockStart == nil {
                    blockStart = address
                }
                blockEnd = address &+ UInt16(lineLength)
                deletedCount += 1
            } else if lineNum > range.end {
                break
            }

            address = address &+ UInt16(lineLength)
        }

        // If no lines matched, return gracefully
        guard let start = blockStart, let end = blockEnd, deletedCount > 0 else {
            if range.start == range.end {
                return .deleted(lineNumber: range.start)
            }
            return .immediate("No lines in range \(range.start)-\(range.end)")
        }

        let blockSize = Int(end - start)

        await emulator.pause()

        // Single memory shift removes the entire contiguous block
        await shiftMemory(from: end, by: -blockSize, until: state.starp)

        let newStarp = UInt16(Int(state.starp) - blockSize)
        await emulator.writeWord(at: BASICPointers.starp, value: newStarp)

        await emulator.resume()

        if range.start == range.end {
            return .deleted(lineNumber: range.start)
        }
        return .immediate("Deleted \(deletedCount) lines (\(range.start)-\(range.end))")
    }

    // =========================================================================
    // MARK: - Program Commands
    // =========================================================================

    /// Clears the current BASIC program (NEW command).
    public func newProgram() async -> BASICLineResult {
        await emulator.pause()

        // Read LOMEM and MEMTOP
        let lomem = await emulator.readWord(at: BASICPointers.lomem)
        let memtop = await emulator.readWord(at: BASICPointers.memtop)

        // Set up empty program state
        // VNT is empty (just terminator)
        await emulator.writeMemoryBlock(at: lomem, bytes: [0x00])

        // VVT starts right after VNT terminator
        let vvtp = lomem + 1

        // STMTAB starts at VVT (no variables)
        let stmtab = vvtp

        // Write end-of-program marker
        await emulator.writeMemoryBlock(at: stmtab, bytes: BASICLineFormat.endOfProgramMarker)

        // STARP is after end marker
        let starp = stmtab + 3

        // Update all pointers
        await emulator.writeWord(at: BASICPointers.vntp, value: lomem)
        await emulator.writeWord(at: BASICPointers.vntd, value: lomem)
        await emulator.writeWord(at: BASICPointers.vvtp, value: vvtp)
        await emulator.writeWord(at: BASICPointers.stmtab, value: stmtab)
        await emulator.writeWord(at: BASICPointers.stmcur, value: stmtab)
        await emulator.writeWord(at: BASICPointers.starp, value: starp)
        await emulator.writeWord(at: BASICPointers.runstk, value: memtop)

        await emulator.resume()

        return .immediate("NEW - Program cleared")
    }

    /// Runs the current BASIC program.
    public func runProgram() async -> BASICLineResult {
        // To run, we need to trigger BASIC's RUN behavior
        // This typically means setting STMCUR to STMTAB and resuming

        let state = await readMemoryState()

        // Check if there's a program
        let firstLineNum = await emulator.readWord(at: state.stmtab)
        if firstLineNum == 0 {
            return .error("No program to run")
        }

        // Reset STMCUR to start of program
        await emulator.writeWord(at: BASICPointers.stmcur, value: state.stmtab)

        // Resume emulator
        await emulator.resume()

        return .immediate("Running")
    }

    /// Continues a stopped program.
    public func continueProgram() async -> BASICLineResult {
        await emulator.resume()
        return .immediate("Continuing")
    }

    // =========================================================================
    // MARK: - Program Listing
    // =========================================================================

    /// Gets information about the current program.
    public func getProgramInfo() async -> (lines: Int, bytes: Int, variables: Int) {
        let state = await readMemoryState()

        var lineCount = 0
        var address = state.stmtab

        // Count lines
        while address < state.starp {
            let lineNum = await emulator.readWord(at: address)
            if lineNum == 0 { break }

            lineCount += 1
            let lineLength = await emulator.readMemoryBlock(at: address + 2, count: 1).first ?? 0
            address = address &+ UInt16(lineLength)
        }

        return (
            lines: lineCount,
            bytes: state.programSize,
            variables: state.variableCount
        )
    }

    /// Lists the current BASIC program as human-readable text.
    ///
    /// This method reads the tokenized program from emulator memory,
    /// detokenizes it, and returns a formatted listing.
    ///
    /// - Parameter range: Optional line number range (start, end).
    ///                    nil means list all lines.
    ///                    Partial values filter accordingly.
    /// - Returns: The formatted program listing, or empty string if no program.
    public func listProgram(range: (start: Int?, end: Int?)?) async -> String {
        let state = await readMemoryState()

        // Read the program bytes
        let programSize = Int(state.starp - state.stmtab)
        guard programSize > 0 else { return "" }

        let programBytes = await emulator.readMemoryBlock(
            at: state.stmtab,
            count: programSize
        )

        // Read variable names for detokenization
        let variableNames = await readVariableNames(state: state)

        // Detokenize the program
        let detokenizer = BASICDetokenizer()
        let listing = detokenizer.formatListing(
            programBytes,
            variables: variableNames,
            range: range
        )

        return listing
    }

    /// Lists all defined variables with their names and types.
    ///
    /// - Returns: Array of variable names defined in the current program.
    public func listVariables() async -> [BASICVariableName] {
        let state = await readMemoryState()
        return await readVariableNames(state: state)
    }

    /// Reads variable names from the Variable Name Table (VNT).
    ///
    /// The VNT stores variable names in a packed format where:
    /// - Each name consists of alphanumeric characters
    /// - The last character of each name has bit 7 set ($80)
    /// - Type suffixes follow: $ for string, ( for array, $( for string array
    ///
    /// - Parameter state: The current BASIC memory state.
    /// - Returns: Array of parsed variable names in order.
    private func readVariableNames(state: BASICMemoryState) async -> [BASICVariableName] {
        let vntSize = Int(state.vntd - state.vntp)
        guard vntSize > 0 else { return [] }

        let vntBytes = await emulator.readMemoryBlock(at: state.vntp, count: vntSize)
        return BASICVariableTable.parseVNT(from: vntBytes)
    }

    // =========================================================================
    // MARK: - Variable Values
    // =========================================================================

    /// Decodes a variable value from its 8-byte VVT entry.
    ///
    /// The VVT stores different data depending on variable type:
    /// - Numeric: 6-byte BCD float at bytes 0-5
    /// - String: buffer address (0-1), DIM capacity (2-3), current length (4-5)
    /// - Numeric array: offset (0-1), first dim+1 (2-3), second dim+1 (4-5)
    /// - String array: offset (0-1), dim+1 (2-3), unused (4-7)
    ///
    /// - Parameters:
    ///   - vvtEntry: The 8 raw bytes from the VVT for this variable.
    ///   - type: The variable type from the VNT.
    /// - Returns: A human-readable string representation of the value.
    private func decodeVariableValue(vvtEntry: [UInt8], type: BASICVariableType) async -> String {
        guard vvtEntry.count == 8 else { return "?" }

        switch type {
        case .numeric:
            // First 6 bytes are the BCD floating-point representation
            let bcdBytes = Array(vvtEntry[0..<6])
            let bcd = BCDFloat(bytes: bcdBytes)
            return bcd.decimalString

        case .string:
            // Atari BASIC string VVT layout:
            // bytes 0-1: buffer address, bytes 2-3: DIM capacity, bytes 4-5: current length
            let address = UInt16(vvtEntry[0]) | (UInt16(vvtEntry[1]) << 8)
            let currentLength = UInt16(vvtEntry[4]) | (UInt16(vvtEntry[5]) << 8)
            if currentLength == 0 || address == 0 {
                return "\"\""
            }
            // Read up to 256 chars of the actual string content from memory
            let readLen = Int(min(currentLength, 256))
            let stringBytes = await emulator.readMemoryBlock(at: address, count: readLen)
            // Convert ATASCII to printable characters (basic ASCII range)
            let chars = stringBytes.map { byte -> Character in
                if byte >= 32 && byte < 127 {
                    return Character(UnicodeScalar(byte))
                } else {
                    return "."
                }
            }
            return "\"\(String(chars))\""

        case .numericArray:
            // Atari BASIC stores dimensions as size+1
            // bytes 0-1: offset from STARP, bytes 2-3: dim1+1, bytes 4-5: dim2+1
            let dim1 = UInt16(vvtEntry[2]) | (UInt16(vvtEntry[3]) << 8)
            let dim2 = UInt16(vvtEntry[4]) | (UInt16(vvtEntry[5]) << 8)
            if dim2 <= 1 {
                return "DIM(\(dim1 > 0 ? dim1 - 1 : 0))"
            } else {
                return "DIM(\(dim1 > 0 ? dim1 - 1 : 0),\(dim2 > 0 ? dim2 - 1 : 0))"
            }

        case .stringArray:
            // String arrays use DIM for capacity
            let dim1 = UInt16(vvtEntry[2]) | (UInt16(vvtEntry[3]) << 8)
            return "DIM$(\(dim1 > 0 ? dim1 - 1 : 0))"
        }
    }

    /// Lists all variables with their current values.
    ///
    /// Reads variable names from the VNT and their corresponding 8-byte
    /// entries from the VVT, decoding each value based on its type.
    ///
    /// - Returns: Array of (name, value) pairs for all defined variables.
    public func listVariablesWithValues() async -> [(name: BASICVariableName, value: String)] {
        let state = await readMemoryState()
        let names = await readVariableNames(state: state)

        guard !names.isEmpty else { return [] }

        // Read the entire VVT block (8 bytes per variable)
        let vvtSize = state.variableCount * BASICMemoryDefaults.vvtEntrySize
        guard vvtSize > 0 else { return [] }

        let vvtBytes = await emulator.readMemoryBlock(at: state.vvtp, count: vvtSize)

        var results: [(name: BASICVariableName, value: String)] = []

        for (index, name) in names.enumerated() {
            let entryStart = index * BASICMemoryDefaults.vvtEntrySize
            let entryEnd = entryStart + BASICMemoryDefaults.vvtEntrySize
            guard entryEnd <= vvtBytes.count else { break }

            let entry = Array(vvtBytes[entryStart..<entryEnd])
            let value = await decodeVariableValue(vvtEntry: entry, type: name.type)
            results.append((name: name, value: value))
        }

        return results
    }

    /// Reads the value of a single variable by name.
    ///
    /// Parses the variable name string, finds it in the VNT by matching
    /// both name and type, then reads and decodes its VVT entry.
    ///
    /// - Parameter name: The variable name (e.g., "X", "A$", "SCORE").
    /// - Returns: The variable's value as a string, or nil if not found.
    public func readVariableValue(name: String) async -> String? {
        guard let varName = BASICVariableName.parse(name) else {
            return nil
        }

        let state = await readMemoryState()
        let names = await readVariableNames(state: state)

        guard let index = names.firstIndex(of: varName) else {
            return nil
        }

        // Read the specific 8-byte VVT entry for this variable
        let entryAddress = state.vvtp + UInt16(index * BASICMemoryDefaults.vvtEntrySize)
        let entry = await emulator.readMemoryBlock(
            at: entryAddress, count: BASICMemoryDefaults.vvtEntrySize
        )
        guard entry.count == BASICMemoryDefaults.vvtEntrySize else { return nil }

        return await decodeVariableValue(vvtEntry: entry, type: varName.type)
    }

    // =========================================================================
    // MARK: - Export / Import
    // =========================================================================

    /// Exports the current BASIC program to a file as detokenized text.
    ///
    /// Uses `listProgram()` to get the human-readable listing and writes
    /// it to the specified path as UTF-8 text. Each line in the output
    /// file is a complete BASIC statement with its line number.
    ///
    /// - Parameter path: The file path to write to (tilde is expanded).
    /// - Returns: A summary message with the number of lines exported.
    /// - Throws: File I/O errors if the path is not writable.
    public func exportProgram(to path: String) async throws -> String {
        let listing = await listProgram(range: nil)
        guard !listing.isEmpty else {
            return "No program to export"
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        try listing.write(toFile: expandedPath, atomically: true, encoding: .utf8)

        let lineCount = listing.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        return "Exported \(lineCount) lines to \(expandedPath)"
    }

    /// Imports a BASIC program from a text file.
    ///
    /// Reads each line from the file and enters it via `enterLine()`.
    /// The file should contain one BASIC statement per line with line numbers.
    /// Does NOT clear the existing program first — call NEW explicitly
    /// before importing if a clean slate is desired.
    ///
    /// - Parameter path: The file path to read from (tilde is expanded).
    /// - Returns: A result with success/error counts.
    /// - Throws: File I/O errors if the file cannot be read.
    public func importProgram(from path: String) async throws -> BASICLineResult {
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .error("File not found: \(expandedPath)")
        }

        let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return .error("File is empty: \(expandedPath)")
        }

        var successCount = 0
        var errorCount = 0
        var errors: [String] = []

        for line in lines {
            let result = await enterLine(line)
            if result.success {
                successCount += 1
            } else {
                errorCount += 1
                // Collect up to 5 error messages for reporting
                if errors.count < 5 {
                    errors.append(result.message)
                }
            }
        }

        var message = "Imported \(successCount) lines from \(expandedPath)"
        if errorCount > 0 {
            message += ", \(errorCount) errors"
            if !errors.isEmpty {
                message += ": " + errors.joined(separator: "; ")
            }
        }

        return BASICLineResult(
            success: errorCount == 0,
            message: message,
            lineNumber: nil,
            bytesUsed: nil
        )
    }
}

// =============================================================================
// MARK: - EmulatorEngine Extensions
// =============================================================================

/// Extension to make EmulatorEngine conform to BASICMemoryReader.
///
/// These methods wrap the synchronous memory access methods on EmulatorEngine
/// to satisfy the async protocol requirements. Since EmulatorEngine is an actor,
/// the actual memory operations are actor-isolated and don't need await when
/// called from within the actor.
extension EmulatorEngine: BASICMemoryReader {
    /// Reads a 16-bit word from memory.
    public func readWord(at address: UInt16) async -> UInt16 {
        let bytes = readMemoryBlock(at: address, count: 2)
        guard bytes.count >= 2 else { return 0 }
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    /// Reads a block of bytes from memory.
    public func readBlock(at address: UInt16, count: Int) async -> [UInt8] {
        readMemoryBlock(at: address, count: count)
    }
}

/// Extension to make EmulatorEngine conform to BASICMemoryWriter.
///
/// These methods wrap the synchronous memory access methods on EmulatorEngine
/// to satisfy the async protocol requirements.
extension EmulatorEngine: BASICMemoryWriter {
    /// Writes a 16-bit word to memory.
    public func writeWord(at address: UInt16, value: UInt16) async {
        let bytes = [UInt8(value & 0xFF), UInt8(value >> 8)]
        writeMemoryBlock(at: address, bytes: bytes)
    }

    /// Writes a block of bytes to memory.
    public func writeBlock(at address: UInt16, bytes: [UInt8]) async {
        writeMemoryBlock(at: address, bytes: bytes)
    }
}
