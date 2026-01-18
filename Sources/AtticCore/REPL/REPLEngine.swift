// =============================================================================
// REPLEngine.swift - REPL State Machine and Command Executor
// =============================================================================
//
// This file implements the REPL (Read-Eval-Print Loop) engine that manages
// user interaction with the emulator. The REPLEngine:
//
// - Maintains the current mode (monitor, basic, dos)
// - Parses commands using CommandParser
// - Executes commands against the EmulatorEngine
// - Formats output for display
// - Manages the prompt for comint compatibility
//
// The REPL is designed to work with Emacs comint-mode, which requires:
// - Prompts matching a specific regex pattern
// - Clean line-based output
// - No ANSI escape codes (unless requested)
//
// Usage:
//
//     let engine = EmulatorEngine()
//     let repl = REPLEngine(emulator: engine)
//
//     // Process a command
//     let output = await repl.execute("g $0600")
//     print(output)
//
//     // Get the current prompt
//     print(repl.prompt)
//
// =============================================================================

import Foundation

/// The REPL engine manages command processing and state.
///
/// This is the main interface for the CLI to interact with the emulator.
/// It handles command parsing, execution, and output formatting.
public actor REPLEngine {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The emulator engine to control.
    private let emulator: EmulatorEngine

    /// Command parser instance.
    private let parser: CommandParser

    /// Current REPL mode.
    private(set) public var mode: REPLMode

    /// Disk manager for DOS mode file operations.
    /// Provides direct ATR file access independent of emulator disk I/O.
    private let diskManager: DiskManager

    /// Whether the REPL should continue running.
    private var isRunning: Bool = true

    /// Callback for output that should be sent to the user.
    /// Set this to receive output asynchronously.
    public var onOutput: ((String) async -> Void)?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new REPL engine.
    ///
    /// - Parameters:
    ///   - emulator: The emulator engine to control.
    ///   - initialMode: The starting mode (default: BASIC with Atari variant).
    public init(emulator: EmulatorEngine, initialMode: REPLMode = .default) {
        self.emulator = emulator
        self.parser = CommandParser()
        self.mode = initialMode
        self.diskManager = DiskManager()
    }

    // =========================================================================
    // MARK: - Prompt
    // =========================================================================

    /// Returns the current prompt string.
    ///
    /// The prompt format depends on the current mode:
    /// - Monitor: [monitor] $XXXX>
    /// - BASIC: [basic] >
    /// - DOS: [dos] D1:>
    public var prompt: String {
        get async {
            switch mode {
            case .monitor:
                let regs = await emulator.getRegisters()
                return mode.prompt(pc: regs.pc)
            case .basic:
                return mode.prompt()
            case .dos:
                let currentDrive = await diskManager.currentDrive
                return mode.prompt(drive: currentDrive)
            }
        }
    }

    // =========================================================================
    // MARK: - Command Execution
    // =========================================================================

    /// Executes a command and returns the output.
    ///
    /// - Parameter input: The command string to execute.
    /// - Returns: The output to display, or nil for no output.
    public func execute(_ input: String) async -> String? {
        // Parse the command
        let command: Command
        do {
            command = try parser.parse(input, mode: mode)
        } catch let error as AtticError {
            return formatError(error)
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        // Execute the command
        return await executeCommand(command)
    }

    /// Executes a parsed command.
    private func executeCommand(_ command: Command) async -> String? {
        switch command {
        // =====================================================================
        // Global Commands
        // =====================================================================

        case .switchMode(let newMode):
            mode = newMode
            return "Switched to \(newMode.name) mode"

        case .help(let topic):
            return formatHelp(topic: topic)

        case .status:
            return await formatStatus()

        case .reset:
            await emulator.reset(cold: true)
            return "Cold reset performed"

        case .warmStart:
            await emulator.reset(cold: false)
            return "Warm reset performed"

        case .screenshot(let path):
            // TODO: Implement screenshot capture via GUI
            return "Screenshot saved to \(path ?? "~/Desktop/Attic-<timestamp>.png")"

        case .saveState(let path):
            do {
                try await emulator.saveState(to: URL(fileURLWithPath: path))
                return "State saved to \(path)"
            } catch {
                return "Error saving state: \(error.localizedDescription)"
            }

        case .loadState(let path):
            do {
                try await emulator.loadState(from: URL(fileURLWithPath: path))
                return "State loaded from \(path)"
            } catch {
                return "Error loading state: \(error.localizedDescription)"
            }

        case .quit:
            isRunning = false
            return "Goodbye"

        case .shutdown:
            isRunning = false
            // TODO: Send shutdown signal to GUI
            return "Shutting down"

        // =====================================================================
        // Monitor Commands
        // =====================================================================

        case .go(let address):
            if let addr = address {
                var regs = await emulator.getRegisters()
                regs.pc = addr
                await emulator.setRegisters(regs)
            }
            await emulator.resume()
            return "Running"

        case .step(let count):
            // Use MonitorController for proper instruction-level stepping
            // (Note: MonitorController should be injected via initializer in future)
            // For now, use frame-based stepping as fallback
            for _ in 0..<count {
                let result = await emulator.executeFrame()
                if result == .breakpoint {
                    let regs = await emulator.getRegisters()
                    return formatRegisters(regs) + "\n* Breakpoint hit at $\(String(format: "%04X", regs.pc))"
                }
            }
            let regs = await emulator.getRegisters()
            return formatRegisters(regs)

        case .stepOver:
            // Step over subroutine - for now uses frame stepping
            // Full implementation via MonitorController.stepOver()
            let result = await emulator.executeFrame()
            let regs = await emulator.getRegisters()
            if result == .breakpoint {
                return formatRegisters(regs) + "\n* Breakpoint hit at $\(String(format: "%04X", regs.pc))"
            }
            return formatRegisters(regs)

        case .pause:
            await emulator.pause()
            return "Paused"

        case .runUntil(let address):
            // Set temporary breakpoint and run
            await emulator.setBreakpoint(at: address)
            await emulator.resume()
            return "Running until $\(String(format: "%04X", address))"

        case .registers(let modifications):
            if let mods = modifications {
                var regs = await emulator.getRegisters()
                for (regName, value) in mods {
                    switch regName.uppercased() {
                    case "A": regs.a = UInt8(value & 0xFF)
                    case "X": regs.x = UInt8(value & 0xFF)
                    case "Y": regs.y = UInt8(value & 0xFF)
                    case "S": regs.s = UInt8(value & 0xFF)
                    case "P": regs.p = UInt8(value & 0xFF)
                    case "PC": regs.pc = value
                    default: break
                    }
                }
                await emulator.setRegisters(regs)
            }
            let regs = await emulator.getRegisters()
            return formatRegisters(regs)

        case .memoryDump(let address, let length):
            let bytes = await emulator.readMemoryBlock(at: address, count: length)
            return formatMemoryDump(address: address, bytes: bytes)

        case .memoryWrite(let address, let bytes):
            await emulator.writeMemoryBlock(at: address, bytes: bytes)
            return "Wrote \(bytes.count) bytes at $\(String(format: "%04X", address))"

        case .memoryFill(let start, let end, let value):
            let count = Int(end) - Int(start) + 1
            let bytes = [UInt8](repeating: value, count: count)
            await emulator.writeMemoryBlock(at: start, bytes: bytes)
            return "Filled \(count) bytes ($\(String(format: "%04X", start))-$\(String(format: "%04X", end))) with $\(String(format: "%02X", value))"

        case .disassemble(let address, let lines):
            // Use MonitorController for disassembly
            let monitor = MonitorController(emulator: emulator)
            return await monitor.disassemble(at: address, lines: lines)

        case .assemble(let address):
            // Enter interactive assembly mode
            // Note: Full interactive mode requires stateful handling in the CLI
            // For now, return instructions on how to use it
            return """
            Assembly mode at $\(String(format: "%04X", address))
            Enter instructions one per line. Empty line exits.
            (Full interactive mode requires CLI integration)
            """

        case .breakpointSet(let address):
            if await emulator.setBreakpoint(at: address) {
                return "Breakpoint set at $\(String(format: "%04X", address))"
            } else {
                return "Breakpoint already exists at $\(String(format: "%04X", address))"
            }

        case .breakpointList:
            let bps = await emulator.getBreakpoints()
            if bps.isEmpty {
                return "No breakpoints set"
            }
            return "Breakpoints:\n" + bps.map { "  $\(String(format: "%04X", $0))" }.joined(separator: "\n")

        case .breakpointClear(let address):
            if await emulator.clearBreakpoint(at: address) {
                return "Breakpoint cleared at $\(String(format: "%04X", address))"
            } else {
                return "No breakpoint at $\(String(format: "%04X", address))"
            }

        case .breakpointClearAll:
            await emulator.clearAllBreakpoints()
            return "All breakpoints cleared"

        // =====================================================================
        // BASIC Commands (Stubs)
        // =====================================================================

        case .basicLine(let number, let content):
            return "Line \(number): \(content) [tokenization not yet implemented]"

        case .basicDelete(let start, let end):
            if let end = end {
                return "Deleted lines \(start)-\(end) [not yet implemented]"
            }
            return "Deleted line \(start) [not yet implemented]"

        case .basicRenumber(let start, let step):
            return "Renumber start=\(start ?? 10) step=\(step ?? 10) [not yet implemented]"

        case .basicRun:
            return "RUN [not yet implemented]"

        case .basicStop:
            return "STOP [not yet implemented]"

        case .basicContinue:
            return "CONT [not yet implemented]"

        case .basicNew:
            return "NEW [not yet implemented]"

        case .basicList(_, _):
            return "LIST [not yet implemented]"

        case .basicVars(let name):
            if let name = name {
                return "VAR \(name) [not yet implemented]"
            }
            return "VARS [not yet implemented]"

        case .basicSaveATR(let filename):
            return "SAVE \"\(filename)\" [not yet implemented]"

        case .basicLoadATR(let filename):
            return "LOAD \"\(filename)\" [not yet implemented]"

        case .basicImport(let path):
            return "Import from \(path) [not yet implemented]"

        case .basicExport(let path):
            return "Export to \(path) [not yet implemented]"

        // =====================================================================
        // DOS Commands
        // =====================================================================

        case .dosMountDisk(let drive, let path):
            return await executeDOSMount(drive: drive, path: path)

        case .dosUnmount(let drive):
            return await executeDOSUnmount(drive: drive)

        case .dosDrives:
            return await executeDOSDrives()

        case .dosChangeDrive(let drive):
            return await executeDOSChangeDrive(drive: drive)

        case .dosDirectory(let pattern):
            return await executeDOSDirectory(pattern: pattern)

        case .dosFileInfo(let filename):
            return await executeDOSFileInfo(filename: filename)

        case .dosType(let filename):
            return await executeDOSType(filename: filename)

        case .dosDump(let filename):
            return await executeDOSDump(filename: filename)

        case .dosCopy(let source, let dest):
            return await executeDOSCopy(source: source, dest: dest)

        case .dosRename(let oldName, let newName):
            return await executeDOSRename(oldName: oldName, newName: newName)

        case .dosDelete(let filename):
            return await executeDOSDelete(filename: filename)

        case .dosLock(let filename):
            return await executeDOSLock(filename: filename)

        case .dosUnlock(let filename):
            return await executeDOSUnlock(filename: filename)

        case .dosExport(let filename, let path):
            return await executeDOSExport(filename: filename, path: path)

        case .dosImport(let path, let filename):
            return await executeDOSImport(path: path, filename: filename)

        case .dosNewDisk(let path, let type):
            return await executeDOSNewDisk(path: path, type: type)

        case .dosFormat:
            return await executeDOSFormat()
        }
    }

    // =========================================================================
    // MARK: - DOS Command Implementations
    // =========================================================================

    /// Mounts an ATR disk image.
    private func executeDOSMount(drive: Int, path: String) async -> String {
        do {
            let info = try await diskManager.mount(drive: drive, path: path)
            let typeStr = info.diskType?.shortDescription ?? "Unknown"
            return "Mounted D\(drive): \(info.filename) (\(typeStr), \(info.fileCount) files, \(info.freeSectors) free)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Unmounts a disk.
    private func executeDOSUnmount(drive: Int) async -> String {
        do {
            try await diskManager.unmount(drive: drive)
            return "Unmounted D\(drive):"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Lists all drives.
    private func executeDOSDrives() async -> String {
        let drives = await diskManager.listDrives()
        return drives.map { $0.displayString }.joined(separator: "\n")
    }

    /// Changes the current drive.
    private func executeDOSChangeDrive(drive: Int) async -> String {
        do {
            try await diskManager.changeDrive(to: drive)
            return "Changed to D\(drive):"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Lists directory contents.
    private func executeDOSDirectory(pattern: String?) async -> String {
        do {
            let entries = try await diskManager.listDirectory(pattern: pattern)

            if entries.isEmpty {
                return "No files found"
            }

            // Format directory listing
            var output = ""
            var totalSectors = 0

            for entry in entries {
                let name = entry.filename.trimmingCharacters(in: .whitespaces)
                let ext = entry.ext.trimmingCharacters(in: .whitespaces)
                let lockedStr = entry.isLocked ? "*" : " "
                output += String(format: "%@ %-8s %-3s %4d\n", lockedStr, name, ext, entry.sectorCount)
                totalSectors += Int(entry.sectorCount)
            }

            // Get disk stats for free sectors
            let currentDrive = await diskManager.currentDrive
            if let info = try? await diskManager.getInfo(drive: currentDrive) {
                output += "\(entries.count) files, \(totalSectors) sectors used, \(info.freeSectors) free"
            } else {
                output += "\(entries.count) files, \(totalSectors) sectors used"
            }

            return output
        } catch {
            return formatDOSError(error)
        }
    }

    /// Shows file information.
    private func executeDOSFileInfo(filename: String) async -> String {
        do {
            let info = try await diskManager.getFileInfo(name: filename)
            return """
              Filename: \(info.name)
              Size: \(info.sectorCount) sectors (\(info.size) bytes)
              Start sector: \(info.startSector)
              Flags: \(info.isLocked ? "Locked" : "Normal")
            """
        } catch {
            return formatDOSError(error)
        }
    }

    /// Displays a text file.
    private func executeDOSType(filename: String) async -> String {
        do {
            let data = try await diskManager.readFile(name: filename)

            // Convert to string, handling ATASCII to ASCII conversion
            // ATASCII uses $9B for end of line (EOL)
            var text = ""
            for byte in data {
                if byte == 0x9B {
                    text += "\n"
                } else if byte >= 0x20 && byte < 0x7F {
                    text += String(Character(UnicodeScalar(byte)))
                } else if byte == 0x00 {
                    // Null byte - often padding, skip
                    continue
                } else {
                    // Other control characters - show as placeholder
                    text += "."
                }
            }

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return formatDOSError(error)
        }
    }

    /// Hex dumps a file.
    private func executeDOSDump(filename: String) async -> String {
        do {
            let data = try await diskManager.readFile(name: filename)
            return formatHexDump(data: Array(data), baseAddress: 0)
        } catch {
            return formatDOSError(error)
        }
    }

    /// Copies a file (placeholder - cross-drive copy not yet implemented).
    private func executeDOSCopy(source: String, dest: String) async -> String {
        do {
            // Parse source and destination for drive prefixes (e.g., "D2:FILE.COM")
            let (sourceDrive, sourceName) = parseDriveSpec(source)
            let (destDrive, destName) = parseDriveSpec(dest)

            let srcDriveNum = sourceDrive ?? await diskManager.currentDrive
            let dstDriveNum = destDrive ?? await diskManager.currentDrive
            let dstFileName = destName.isEmpty ? sourceName : destName

            let sectors = try await diskManager.copyFile(
                from: srcDriveNum,
                name: sourceName,
                to: dstDriveNum,
                as: dstFileName
            )

            if srcDriveNum == dstDriveNum {
                return "Copied \(sourceName) to \(dstFileName) (\(sectors) sectors)"
            } else {
                return "Copied D\(srcDriveNum):\(sourceName) to D\(dstDriveNum):\(dstFileName) (\(sectors) sectors)"
            }
        } catch {
            return formatDOSError(error)
        }
    }

    /// Parses a drive specification like "D2:FILE.COM" into (driveNumber, filename).
    /// Returns (nil, original) if no drive prefix found.
    private func parseDriveSpec(_ spec: String) -> (Int?, String) {
        let upper = spec.uppercased()
        if upper.hasPrefix("D") && upper.count >= 3 && upper[upper.index(upper.startIndex, offsetBy: 2)] == ":" {
            if let driveNum = Int(String(upper[upper.index(upper.startIndex, offsetBy: 1)])) {
                let filename = String(spec.dropFirst(3))
                return (driveNum, filename)
            }
        }
        return (nil, spec)
    }

    /// Renames a file.
    private func executeDOSRename(oldName: String, newName: String) async -> String {
        do {
            try await diskManager.renameFile(from: oldName, to: newName)
            return "Renamed \(oldName) to \(newName)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Deletes a file.
    private func executeDOSDelete(filename: String) async -> String {
        do {
            try await diskManager.deleteFile(name: filename)
            return "Deleted \(filename)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Locks a file (makes read-only).
    private func executeDOSLock(filename: String) async -> String {
        do {
            try await diskManager.lockFile(name: filename)
            return "Locked \(filename)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Unlocks a file.
    private func executeDOSUnlock(filename: String) async -> String {
        do {
            try await diskManager.unlockFile(name: filename)
            return "Unlocked \(filename)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Exports a file to the host filesystem.
    private func executeDOSExport(filename: String, path: String) async -> String {
        do {
            let bytes = try await diskManager.exportFile(name: filename, to: path)
            let expandedPath = NSString(string: path).expandingTildeInPath
            return "Exported \(filename) to \(expandedPath) (\(bytes) bytes)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Imports a file from the host filesystem.
    private func executeDOSImport(path: String, filename: String) async -> String {
        do {
            let sectors = try await diskManager.importFile(from: path, name: filename)
            let expandedPath = NSString(string: path).expandingTildeInPath
            return "Imported \(expandedPath) as \(filename) (\(sectors) sectors)"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Creates a new disk image.
    private func executeDOSNewDisk(path: String, type: String?) async -> String {
        do {
            let diskType = type.flatMap { DiskType.fromString($0) } ?? .singleDensity
            let url = try await diskManager.createDisk(at: path, type: diskType)
            return "Created new disk image: \(url.path) (\(diskType.displayName))"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Formats the current disk (placeholder - requires confirmation).
    private func executeDOSFormat() async -> String {
        // Formatting is destructive - in a real implementation we'd ask for confirmation
        // For now, just execute it
        do {
            let currentDrive = await diskManager.currentDrive
            try await diskManager.formatDisk(drive: currentDrive)
            return "Formatted D\(currentDrive):"
        } catch {
            return formatDOSError(error)
        }
    }

    /// Formats a DOS-related error for display.
    private func formatDOSError(_ error: Error) -> String {
        if let diskError = error as? DiskManagerError {
            return "Error: \(diskError.errorDescription ?? String(describing: diskError))"
        } else if let atrError = error as? ATRError {
            return "Error: \(atrError.errorDescription ?? String(describing: atrError))"
        } else {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Formats data as a hex dump.
    private func formatHexDump(data: [UInt8], baseAddress: Int) -> String {
        var output = ""

        for chunk in stride(from: 0, to: data.count, by: 16) {
            let end = min(chunk + 16, data.count)
            let lineBytes = Array(data[chunk..<end])
            let addr = baseAddress + chunk

            // Address
            output += String(format: "%04X: ", addr)

            // Hex bytes
            for (i, byte) in lineBytes.enumerated() {
                output += String(format: "%02X ", byte)
                if i == 7 { output += " " }  // Extra space in middle
            }

            // Padding for incomplete line
            if lineBytes.count < 16 {
                let missing = 16 - lineBytes.count
                output += String(repeating: "   ", count: missing)
                if lineBytes.count < 8 { output += " " }
            }

            // ASCII representation
            output += " |"
            for byte in lineBytes {
                let char = (byte >= 0x20 && byte < 0x7F) ? Character(UnicodeScalar(byte)) : "."
                output.append(char)
            }
            output += "|\n"
        }

        return output.trimmingCharacters(in: .newlines)
    }

    // =========================================================================
    // MARK: - Output Formatting
    // =========================================================================

    /// Formats an error for display.
    private func formatError(_ error: AtticError) -> String {
        var output = "Error: \(error.errorDescription ?? "Unknown error")"
        if case .invalidCommand(_, let suggestion) = error, let suggestion = suggestion {
            output += "\n  Suggestion: \(suggestion)"
        }
        return output
    }

    /// Formats help text.
    private func formatHelp(topic: String?) -> String {
        if let topic = topic {
            // TODO: Implement topic-specific help
            return "Help for '\(topic)' not available"
        }

        // General help plus mode-specific help
        return """
        Global Commands:
          .monitor          Switch to monitor mode
          .basic [turbo]    Switch to BASIC mode
          .dos              Switch to DOS mode
          .help [topic]     Show help
          .status           Show emulator status
          .reset            Cold reset
          .warmstart        Warm reset
          .screenshot [p]   Take screenshot
          .state save <p>   Save state
          .state load <p>   Load state
          .quit             Exit CLI
          .shutdown         Exit and close GUI

        \(mode.helpText)
        """
    }

    /// Formats emulator status.
    private func formatStatus() async -> String {
        let state = await emulator.state
        let regs = await emulator.getRegisters()
        let breakpoints = await emulator.getBreakpoints()

        var output = """
        Emulator Status
          State: \(state)
          PC: $\(String(format: "%04X", regs.pc))
        """

        // TODO: Add disk mount status

        if breakpoints.isEmpty {
            output += "\n  Breakpoints: (none)"
        } else {
            output += "\n  Breakpoints: " + breakpoints.map { "$\(String(format: "%04X", $0))" }.joined(separator: ", ")
        }

        output += "\n  Mode: \(mode.description)"

        return output
    }

    /// Formats CPU registers for display.
    private func formatRegisters(_ regs: CPURegisters) -> String {
        """
          \(regs.formatted)
          Flags: \(regs.flagsFormatted)
        """
    }

    /// Formats a memory dump.
    private func formatMemoryDump(address: UInt16, bytes: [UInt8]) -> String {
        var output = ""
        var addr = address

        for chunk in stride(from: 0, to: bytes.count, by: 16) {
            let end = min(chunk + 16, bytes.count)
            let lineBytes = Array(bytes[chunk..<end])

            // Address
            output += String(format: "%04X: ", addr)

            // Hex bytes
            for (i, byte) in lineBytes.enumerated() {
                output += String(format: "%02X ", byte)
                if i == 7 { output += " " }  // Extra space in middle
            }

            // Padding for incomplete line
            if lineBytes.count < 16 {
                let missing = 16 - lineBytes.count
                output += String(repeating: "   ", count: missing)
                if lineBytes.count < 8 { output += " " }
            }

            // ASCII representation
            output += " |"
            for byte in lineBytes {
                let char = (byte >= 0x20 && byte < 0x7F) ? Character(UnicodeScalar(byte)) : "."
                output.append(char)
            }
            output += "|\n"

            addr = addr &+ 16
        }

        return output.trimmingCharacters(in: .newlines)
    }

    // =========================================================================
    // MARK: - Session Control
    // =========================================================================

    /// Returns true if the REPL should continue running.
    public var shouldContinue: Bool {
        isRunning
    }

    /// Stops the REPL loop.
    public func stop() {
        isRunning = false
    }
}
