// =============================================================================
// DOSIntegrationTests.swift - Integration Tests for DOS Commands & Mode Switching
// =============================================================================
//
// This file provides integration test coverage for:
// 1. Mode switching through CommandParser (all mode transitions)
// 2. DOS command parsing (every command's happy and error paths)
// 3. Monitor register command parsing
// 4. Help text and status content verification
// 5. End-to-end DOS command workflow sequences
//
// These tests exercise CommandParser.parse(_:mode:) directly, verifying that
// user input is correctly translated into structured Command values. No
// emulator or server is needed — these are pure parsing tests.
//
// Running:
//   swift test --filter DOSIntegrationTests
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - Mode Switching Tests
// =============================================================================

/// Tests that CommandParser correctly handles mode switching via global
/// dot-commands (e.g., `.monitor`, `.basic`, `.dos`).
///
/// Mode switching is a global command available in all modes. The parser
/// should return `.switchMode(targetMode)` regardless of the current mode.
final class ModeSwitchingTests: XCTestCase {
    let parser = CommandParser()

    // MARK: - Basic Transitions

    /// Switching to monitor from BASIC mode.
    func test_switchToMonitor_fromBasicMode() throws {
        let cmd = try parser.parse(".monitor", mode: .basic(variant: .atari))
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .monitor)
    }

    /// Switching to monitor from DOS mode.
    func test_switchToMonitor_fromDOSMode() throws {
        let cmd = try parser.parse(".monitor", mode: .dos)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .monitor)
    }

    /// Switching to BASIC (Atari) from monitor mode.
    func test_switchToBasic_fromMonitorMode() throws {
        let cmd = try parser.parse(".basic", mode: .monitor)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .basic(variant: .atari))
    }

    /// Switching to Turbo BASIC from monitor mode.
    func test_switchToTurboBasic_fromMonitorMode() throws {
        let cmd = try parser.parse(".basic turbo", mode: .monitor)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .basic(variant: .turbo))
    }

    /// Switching to BASIC from DOS mode.
    func test_switchToBasic_fromDOSMode() throws {
        let cmd = try parser.parse(".basic", mode: .dos)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .basic(variant: .atari))
    }

    /// Switching to DOS from BASIC mode.
    func test_switchToDOS_fromBasicMode() throws {
        let cmd = try parser.parse(".dos", mode: .basic(variant: .atari))
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .dos)
    }

    /// Switching to DOS from monitor mode.
    func test_switchToDOS_fromMonitorMode() throws {
        let cmd = try parser.parse(".dos", mode: .monitor)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .dos)
    }

    /// Same-mode switch (monitor → monitor) should still succeed.
    func test_switchToSameMode_monitor() throws {
        let cmd = try parser.parse(".monitor", mode: .monitor)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .monitor)
    }

    /// Same-mode switch (dos → dos) should still succeed.
    func test_switchToSameMode_dos() throws {
        let cmd = try parser.parse(".dos", mode: .dos)
        guard case .switchMode(let mode) = cmd else {
            XCTFail("Expected switchMode, got \(cmd)")
            return
        }
        XCTAssertEqual(mode, .dos)
    }

    // MARK: - Global Commands in All Modes

    /// `.help` should work in monitor mode.
    func test_help_worksInMonitorMode() throws {
        let cmd = try parser.parse(".help", mode: .monitor)
        guard case .help(let topic) = cmd else {
            XCTFail("Expected help, got \(cmd)")
            return
        }
        XCTAssertNil(topic)
    }

    /// `.help` should work in BASIC mode.
    func test_help_worksInBasicMode() throws {
        let cmd = try parser.parse(".help", mode: .basic(variant: .atari))
        guard case .help(let topic) = cmd else {
            XCTFail("Expected help, got \(cmd)")
            return
        }
        XCTAssertNil(topic)
    }

    /// `.help` should work in DOS mode.
    func test_help_worksInDOSMode() throws {
        let cmd = try parser.parse(".help", mode: .dos)
        guard case .help(let topic) = cmd else {
            XCTFail("Expected help, got \(cmd)")
            return
        }
        XCTAssertNil(topic)
    }

    /// `.status` should work in all modes.
    func test_status_worksInAllModes() throws {
        for mode in [REPLMode.monitor, .basic(variant: .atari), .dos] {
            let cmd = try parser.parse(".status", mode: mode)
            guard case .status = cmd else {
                XCTFail("Expected status in \(mode.name), got \(cmd)")
                return
            }
        }
    }

    // MARK: - Mode-specific Commands in Wrong Mode

    /// A DOS command (`dir`) should fail in monitor mode.
    func test_dosCommand_rejectedInMonitorMode() {
        XCTAssertThrowsError(try parser.parse("dir", mode: .monitor)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// A monitor command (`r`) should fail in DOS mode.
    func test_monitorCommand_rejectedInDOSMode() {
        XCTAssertThrowsError(try parser.parse("r", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// Empty input should fail in all modes.
    func test_emptyInput_throwsInAllModes() {
        for mode in [REPLMode.monitor, .basic(variant: .atari), .dos] {
            XCTAssertThrowsError(try parser.parse("", mode: mode)) { error in
                guard case AtticError.invalidCommand = error else {
                    XCTFail("Expected invalidCommand in \(mode.name), got \(error)")
                    return
                }
            }
        }
    }
}

// =============================================================================
// MARK: - DOS Command Parser Tests
// =============================================================================

/// Tests every DOS command branch in CommandParser.parseDOSCommand().
///
/// Each command is tested for:
/// - Happy path: valid input produces the correct Command case
/// - Error path: missing/invalid arguments throw AtticError.invalidCommand
final class DOSCommandParserTests: XCTestCase {
    let parser = CommandParser()

    // MARK: - mount

    /// `mount 1 /path/to/disk.atr` → dosMountDisk(drive: 1, path: ...)
    func test_mount_validDriveAndPath() throws {
        let cmd = try parser.parse("mount 1 /path/to/disk.atr", mode: .dos)
        guard case .dosMountDisk(let drive, let path) = cmd else {
            XCTFail("Expected dosMountDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(drive, 1)
        XCTAssertEqual(path, "/path/to/disk.atr")
    }

    /// `mount 8 /path/to/disk.atr` → dosMountDisk with drive 8 (max valid).
    func test_mount_maxDrive() throws {
        let cmd = try parser.parse("mount 8 /some/path.atr", mode: .dos)
        guard case .dosMountDisk(let drive, _) = cmd else {
            XCTFail("Expected dosMountDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(drive, 8)
    }

    /// Path with spaces should be handled by joining remaining args.
    func test_mount_pathWithSpaces() throws {
        let cmd = try parser.parse("mount 2 /path/to/my disk.atr", mode: .dos)
        guard case .dosMountDisk(let drive, let path) = cmd else {
            XCTFail("Expected dosMountDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(drive, 2)
        XCTAssertEqual(path, "/path/to/my disk.atr")
    }

    /// `mount` without args should throw.
    func test_mount_missingArgs_throws() {
        XCTAssertThrowsError(try parser.parse("mount", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `mount 1` (missing path) should throw.
    func test_mount_missingPath_throws() {
        XCTAssertThrowsError(try parser.parse("mount 1", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `mount 0 /path` (drive 0 is invalid) should throw.
    func test_mount_invalidDriveZero_throws() {
        XCTAssertThrowsError(try parser.parse("mount 0 /path", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `mount 9 /path` (drive 9 is invalid) should throw.
    func test_mount_invalidDriveNine_throws() {
        XCTAssertThrowsError(try parser.parse("mount 9 /path", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - unmount

    /// `unmount 1` → dosUnmount(drive: 1)
    func test_unmount_validDrive() throws {
        let cmd = try parser.parse("unmount 1", mode: .dos)
        guard case .dosUnmount(let drive) = cmd else {
            XCTFail("Expected dosUnmount, got \(cmd)")
            return
        }
        XCTAssertEqual(drive, 1)
    }

    /// `unmount` without drive should throw.
    func test_unmount_missingDrive_throws() {
        XCTAssertThrowsError(try parser.parse("unmount", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `unmount 0` (invalid drive) should throw.
    func test_unmount_invalidDrive_throws() {
        XCTAssertThrowsError(try parser.parse("unmount 0", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - drives

    /// `drives` → dosDrives
    func test_drives_noArgs() throws {
        let cmd = try parser.parse("drives", mode: .dos)
        guard case .dosDrives = cmd else {
            XCTFail("Expected dosDrives, got \(cmd)")
            return
        }
    }

    // MARK: - cd

    /// `cd 2` → dosChangeDrive(drive: 2)
    func test_cd_validDrive() throws {
        let cmd = try parser.parse("cd 2", mode: .dos)
        guard case .dosChangeDrive(let drive) = cmd else {
            XCTFail("Expected dosChangeDrive, got \(cmd)")
            return
        }
        XCTAssertEqual(drive, 2)
    }

    /// `cd` without drive should throw.
    func test_cd_missingDrive_throws() {
        XCTAssertThrowsError(try parser.parse("cd", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `cd 9` (invalid drive) should throw.
    func test_cd_invalidDrive_throws() {
        XCTAssertThrowsError(try parser.parse("cd 9", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - dir

    /// `dir` without pattern → dosDirectory(pattern: nil)
    func test_dir_noPattern() throws {
        let cmd = try parser.parse("dir", mode: .dos)
        guard case .dosDirectory(let pattern) = cmd else {
            XCTFail("Expected dosDirectory, got \(cmd)")
            return
        }
        XCTAssertNil(pattern)
    }

    /// `dir *.COM` → dosDirectory(pattern: "*.COM")
    func test_dir_withPattern() throws {
        let cmd = try parser.parse("dir *.COM", mode: .dos)
        guard case .dosDirectory(let pattern) = cmd else {
            XCTFail("Expected dosDirectory, got \(cmd)")
            return
        }
        XCTAssertEqual(pattern, "*.COM")
    }

    // MARK: - info

    /// `info GAME.COM` → dosFileInfo(filename: "GAME.COM")
    func test_info_validFilename() throws {
        let cmd = try parser.parse("info GAME.COM", mode: .dos)
        guard case .dosFileInfo(let filename) = cmd else {
            XCTFail("Expected dosFileInfo, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "GAME.COM")
    }

    /// `info` without filename should throw.
    func test_info_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("info", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - type

    /// `type README.TXT` → dosType(filename: "README.TXT")
    func test_type_validFilename() throws {
        let cmd = try parser.parse("type README.TXT", mode: .dos)
        guard case .dosType(let filename) = cmd else {
            XCTFail("Expected dosType, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "README.TXT")
    }

    /// `type` without filename should throw.
    func test_type_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("type", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - dump

    /// `dump GAME.COM` → dosDump(filename: "GAME.COM")
    func test_dump_validFilename() throws {
        let cmd = try parser.parse("dump GAME.COM", mode: .dos)
        guard case .dosDump(let filename) = cmd else {
            XCTFail("Expected dosDump, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "GAME.COM")
    }

    /// `dump` without filename should throw.
    func test_dump_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("dump", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - copy

    /// `copy SRC.COM D2:DST.COM` → dosCopy(source: "SRC.COM", destination: "D2:DST.COM")
    func test_copy_validSourceAndDest() throws {
        let cmd = try parser.parse("copy SRC.COM D2:DST.COM", mode: .dos)
        guard case .dosCopy(let source, let destination) = cmd else {
            XCTFail("Expected dosCopy, got \(cmd)")
            return
        }
        XCTAssertEqual(source, "SRC.COM")
        XCTAssertEqual(destination, "D2:DST.COM")
    }

    /// `copy SRC.COM` (missing destination) should throw.
    func test_copy_missingDest_throws() {
        XCTAssertThrowsError(try parser.parse("copy SRC.COM", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `copy` with no args should throw.
    func test_copy_noArgs_throws() {
        XCTAssertThrowsError(try parser.parse("copy", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - rename

    /// `rename OLD.COM NEW.COM` → dosRename(oldName: "OLD.COM", newName: "NEW.COM")
    func test_rename_validNames() throws {
        let cmd = try parser.parse("rename OLD.COM NEW.COM", mode: .dos)
        guard case .dosRename(let oldName, let newName) = cmd else {
            XCTFail("Expected dosRename, got \(cmd)")
            return
        }
        XCTAssertEqual(oldName, "OLD.COM")
        XCTAssertEqual(newName, "NEW.COM")
    }

    /// `rename OLD.COM` (missing new name) should throw.
    func test_rename_missingNewName_throws() {
        XCTAssertThrowsError(try parser.parse("rename OLD.COM", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - delete / del

    /// `delete FILE.COM` → dosDelete(filename: "FILE.COM")
    func test_delete_validFilename() throws {
        let cmd = try parser.parse("delete FILE.COM", mode: .dos)
        guard case .dosDelete(let filename) = cmd else {
            XCTFail("Expected dosDelete, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "FILE.COM")
    }

    /// `del FILE.COM` (alternate spelling) → dosDelete(filename: "FILE.COM")
    func test_del_alternateSpelling() throws {
        let cmd = try parser.parse("del FILE.COM", mode: .dos)
        guard case .dosDelete(let filename) = cmd else {
            XCTFail("Expected dosDelete, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "FILE.COM")
    }

    /// `delete` without filename should throw.
    func test_delete_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("delete", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - lock

    /// `lock FILE.COM` → dosLock(filename: "FILE.COM")
    func test_lock_validFilename() throws {
        let cmd = try parser.parse("lock FILE.COM", mode: .dos)
        guard case .dosLock(let filename) = cmd else {
            XCTFail("Expected dosLock, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "FILE.COM")
    }

    /// `lock` without filename should throw.
    func test_lock_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("lock", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - unlock

    /// `unlock FILE.COM` → dosUnlock(filename: "FILE.COM")
    func test_unlock_validFilename() throws {
        let cmd = try parser.parse("unlock FILE.COM", mode: .dos)
        guard case .dosUnlock(let filename) = cmd else {
            XCTFail("Expected dosUnlock, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "FILE.COM")
    }

    /// `unlock` without filename should throw.
    func test_unlock_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("unlock", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - export

    /// `export GAME.COM ~/Desktop/game.com` → dosExport(filename:path:)
    func test_export_validFileAndPath() throws {
        let cmd = try parser.parse("export GAME.COM ~/Desktop/game.com", mode: .dos)
        guard case .dosExport(let filename, let path) = cmd else {
            XCTFail("Expected dosExport, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "GAME.COM")
        XCTAssertEqual(path, NSString(string: "~/Desktop/game.com").expandingTildeInPath)
    }

    /// Export with path containing spaces should join remaining parts.
    func test_export_pathWithSpaces() throws {
        let cmd = try parser.parse("export GAME.COM ~/My Files/game.com", mode: .dos)
        guard case .dosExport(let filename, let path) = cmd else {
            XCTFail("Expected dosExport, got \(cmd)")
            return
        }
        XCTAssertEqual(filename, "GAME.COM")
        XCTAssertEqual(path, NSString(string: "~/My Files/game.com").expandingTildeInPath)
    }

    /// `export GAME.COM` (missing path) should throw.
    func test_export_missingPath_throws() {
        XCTAssertThrowsError(try parser.parse("export GAME.COM", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `export` with no args should throw.
    func test_export_noArgs_throws() {
        XCTAssertThrowsError(try parser.parse("export", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - import

    /// `import ~/game.com GAME.COM` → dosImport(path:filename:)
    func test_import_validPathAndFile() throws {
        let cmd = try parser.parse("import ~/game.com GAME.COM", mode: .dos)
        guard case .dosImport(let path, let filename) = cmd else {
            XCTFail("Expected dosImport, got \(cmd)")
            return
        }
        XCTAssertEqual(path, NSString(string: "~/game.com").expandingTildeInPath)
        XCTAssertEqual(filename, "GAME.COM")
    }

    /// Import with path containing spaces: last arg is filename, rest is path.
    func test_import_pathWithSpaces() throws {
        let cmd = try parser.parse("import ~/My Files/game.com GAME.COM", mode: .dos)
        guard case .dosImport(let path, let filename) = cmd else {
            XCTFail("Expected dosImport, got \(cmd)")
            return
        }
        XCTAssertEqual(path, NSString(string: "~/My Files/game.com").expandingTildeInPath)
        XCTAssertEqual(filename, "GAME.COM")
    }

    /// `import ~/game.com` (missing filename) should throw.
    func test_import_missingFilename_throws() {
        XCTAssertThrowsError(try parser.parse("import ~/game.com", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// `import` with no args should throw.
    func test_import_noArgs_throws() {
        XCTAssertThrowsError(try parser.parse("import", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - newdisk

    /// `newdisk /path/new.atr` (no type) → dosNewDisk(path:type:nil)
    func test_newdisk_withoutType() throws {
        let cmd = try parser.parse("newdisk /path/new.atr", mode: .dos)
        guard case .dosNewDisk(let path, let type) = cmd else {
            XCTFail("Expected dosNewDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/path/new.atr")
        XCTAssertNil(type)
    }

    /// `newdisk /path/new.atr ss/sd` → dosNewDisk with single-density type.
    func test_newdisk_withSingleDensity() throws {
        let cmd = try parser.parse("newdisk /path/new.atr ss/sd", mode: .dos)
        guard case .dosNewDisk(let path, let type) = cmd else {
            XCTFail("Expected dosNewDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/path/new.atr")
        XCTAssertEqual(type, "ss/sd")
    }

    /// `newdisk /path/new.atr ss/ed` → enhanced density type.
    func test_newdisk_withEnhancedDensity() throws {
        let cmd = try parser.parse("newdisk /path/new.atr ss/ed", mode: .dos)
        guard case .dosNewDisk(_, let type) = cmd else {
            XCTFail("Expected dosNewDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(type, "ss/ed")
    }

    /// `newdisk /path/new.atr ss/dd` → double density type.
    func test_newdisk_withDoubleDensity() throws {
        let cmd = try parser.parse("newdisk /path/new.atr ss/dd", mode: .dos)
        guard case .dosNewDisk(_, let type) = cmd else {
            XCTFail("Expected dosNewDisk, got \(cmd)")
            return
        }
        XCTAssertEqual(type, "ss/dd")
    }

    /// `newdisk` with no path should throw.
    func test_newdisk_missingPath_throws() {
        XCTAssertThrowsError(try parser.parse("newdisk", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - format

    /// `format` → dosFormat
    func test_format_noArgs() throws {
        let cmd = try parser.parse("format", mode: .dos)
        guard case .dosFormat = cmd else {
            XCTFail("Expected dosFormat, got \(cmd)")
            return
        }
    }

    // MARK: - Unknown command

    /// An unknown DOS command should throw invalidCommand.
    func test_unknownCommand_throws() {
        XCTAssertThrowsError(try parser.parse("foobar", mode: .dos)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - Case insensitivity

    /// DOS commands should be case-insensitive.
    func test_commands_areCaseInsensitive() throws {
        let cmd1 = try parser.parse("DIR", mode: .dos)
        guard case .dosDirectory = cmd1 else {
            XCTFail("Expected dosDirectory for DIR, got \(cmd1)")
            return
        }

        let cmd2 = try parser.parse("Mount 1 /path.atr", mode: .dos)
        guard case .dosMountDisk = cmd2 else {
            XCTFail("Expected dosMountDisk for Mount, got \(cmd2)")
            return
        }

        let cmd3 = try parser.parse("DRIVES", mode: .dos)
        guard case .dosDrives = cmd3 else {
            XCTFail("Expected dosDrives for DRIVES, got \(cmd3)")
            return
        }
    }
}

// =============================================================================
// MARK: - Monitor Register Command Tests
// =============================================================================

/// Tests for the `r` register command parsed through
/// `CommandParser.parse(_:mode: .monitor)`.
///
/// The `r` command displays registers (no args) or sets register values
/// using the format `r REG=$VALUE`.
final class MonitorRegisterCommandTests: XCTestCase {
    let parser = CommandParser()

    /// `r` alone → registers(modifications: nil) — display all registers.
    func test_r_alone_displaysRegisters() throws {
        let cmd = try parser.parse("r", mode: .monitor)
        guard case .registers(let modifications) = cmd else {
            XCTFail("Expected registers, got \(cmd)")
            return
        }
        XCTAssertNil(modifications)
    }

    /// `r A=$50` → single register modification.
    func test_r_singleRegister() throws {
        let cmd = try parser.parse("r A=$50", mode: .monitor)
        guard case .registers(let modifications) = cmd else {
            XCTFail("Expected registers, got \(cmd)")
            return
        }
        XCTAssertNotNil(modifications)
        XCTAssertEqual(modifications?.count, 1)
        XCTAssertEqual(modifications?[0].0, "A")
        XCTAssertEqual(modifications?[0].1, 0x50)
    }

    /// `r A=$50 X=$10 Y=$20` → multiple register modifications.
    func test_r_multipleRegisters() throws {
        let cmd = try parser.parse("r A=$50 X=$10 Y=$20", mode: .monitor)
        guard case .registers(let modifications) = cmd else {
            XCTFail("Expected registers, got \(cmd)")
            return
        }
        XCTAssertNotNil(modifications)
        XCTAssertEqual(modifications?.count, 3)
        XCTAssertEqual(modifications?[0].0, "A")
        XCTAssertEqual(modifications?[0].1, 0x50)
        XCTAssertEqual(modifications?[1].0, "X")
        XCTAssertEqual(modifications?[1].1, 0x10)
        XCTAssertEqual(modifications?[2].0, "Y")
        XCTAssertEqual(modifications?[2].1, 0x20)
    }

    /// `r PC=$0600` → 16-bit PC register modification.
    func test_r_programCounter() throws {
        let cmd = try parser.parse("r PC=$0600", mode: .monitor)
        guard case .registers(let modifications) = cmd else {
            XCTFail("Expected registers, got \(cmd)")
            return
        }
        XCTAssertNotNil(modifications)
        XCTAssertEqual(modifications?.count, 1)
        XCTAssertEqual(modifications?[0].0, "PC")
        XCTAssertEqual(modifications?[0].1, 0x0600)
    }

    /// All 6 registers set at once.
    func test_r_allSixRegisters() throws {
        let cmd = try parser.parse("r A=$01 X=$02 Y=$03 S=$FF P=$30 PC=$E000", mode: .monitor)
        guard case .registers(let modifications) = cmd else {
            XCTFail("Expected registers, got \(cmd)")
            return
        }
        XCTAssertNotNil(modifications)
        XCTAssertEqual(modifications?.count, 6)
        XCTAssertEqual(modifications?[0].0, "A")
        XCTAssertEqual(modifications?[0].1, 0x01)
        XCTAssertEqual(modifications?[1].0, "X")
        XCTAssertEqual(modifications?[1].1, 0x02)
        XCTAssertEqual(modifications?[2].0, "Y")
        XCTAssertEqual(modifications?[2].1, 0x03)
        XCTAssertEqual(modifications?[3].0, "S")
        XCTAssertEqual(modifications?[3].1, 0xFF)
        XCTAssertEqual(modifications?[4].0, "P")
        XCTAssertEqual(modifications?[4].1, 0x30)
        XCTAssertEqual(modifications?[5].0, "PC")
        XCTAssertEqual(modifications?[5].1, 0xE000)
    }

    /// Register names should be uppercased (e.g., `r a=$50` → "A").
    func test_r_lowercaseRegisterName_uppercased() throws {
        let cmd = try parser.parse("r a=$50", mode: .monitor)
        guard case .registers(let modifications) = cmd else {
            XCTFail("Expected registers, got \(cmd)")
            return
        }
        XCTAssertEqual(modifications?[0].0, "A")
    }

    /// Invalid register name should throw.
    func test_r_invalidRegisterName_throws() {
        XCTAssertThrowsError(try parser.parse("r Q=$50", mode: .monitor)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// Invalid format (missing =) should throw.
    func test_r_invalidFormat_throws() {
        XCTAssertThrowsError(try parser.parse("r A50", mode: .monitor)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }

    /// Invalid value (not hex) should throw.
    func test_r_invalidValue_throws() {
        XCTAssertThrowsError(try parser.parse("r A=$ZZ", mode: .monitor)) { error in
            guard case AtticError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }
}

// =============================================================================
// MARK: - Help and Status Content Tests
// =============================================================================

/// Tests that REPLMode.helpText contains the expected commands for each
/// mode, and that `.help` / `.status` parse correctly via CommandParser.
final class HelpAndStatusContentTests: XCTestCase {
    let parser = CommandParser()

    // MARK: - Monitor Help Text

    /// Monitor help should contain all documented execution commands.
    func test_monitorHelp_containsExecutionCommands() {
        let help = REPLMode.monitor.helpText
        XCTAssertTrue(help.contains("g"), "Missing 'g' (go) command")
        XCTAssertTrue(help.contains("s"), "Missing 's' (step) command")
        XCTAssertTrue(help.contains("pause"), "Missing 'pause' command")
        XCTAssertTrue(help.contains("until"), "Missing 'until' command")
    }

    /// Monitor help should contain register commands.
    func test_monitorHelp_containsRegisterCommands() {
        let help = REPLMode.monitor.helpText
        XCTAssertTrue(help.contains("r"), "Missing 'r' (registers) command")
        XCTAssertTrue(help.contains("A, X, Y, S, P, PC"), "Missing register list")
    }

    /// Monitor help should contain memory commands.
    func test_monitorHelp_containsMemoryCommands() {
        let help = REPLMode.monitor.helpText
        XCTAssertTrue(help.contains("m"), "Missing 'm' (memory dump) command")
        XCTAssertTrue(help.contains(">"), "Missing '>' (write) command")
        XCTAssertTrue(help.contains("f"), "Missing 'f' (fill) command")
    }

    /// Monitor help should contain disassembly commands.
    func test_monitorHelp_containsDisassemblyCommands() {
        let help = REPLMode.monitor.helpText
        XCTAssertTrue(help.contains("d"), "Missing 'd' (disassemble) command")
        XCTAssertTrue(help.contains("a"), "Missing 'a' (assemble) command")
    }

    /// Monitor help should contain breakpoint commands.
    func test_monitorHelp_containsBreakpointCommands() {
        let help = REPLMode.monitor.helpText
        XCTAssertTrue(help.contains("bp"), "Missing 'bp' (breakpoint set/list) command")
        XCTAssertTrue(help.contains("bc"), "Missing 'bc' (breakpoint clear) command")
    }

    // MARK: - BASIC Help Text

    /// BASIC help should contain program editing commands.
    func test_basicHelp_containsEditingCommands() {
        let help = REPLMode.basic(variant: .atari).helpText
        XCTAssertTrue(help.contains("del"), "Missing 'del' command")
        XCTAssertTrue(help.contains("renum"), "Missing 'renum' command")
    }

    /// BASIC help should contain execution commands.
    func test_basicHelp_containsExecutionCommands() {
        let help = REPLMode.basic(variant: .atari).helpText
        XCTAssertTrue(help.contains("run"), "Missing 'run' command")
        XCTAssertTrue(help.contains("stop"), "Missing 'stop' command")
        XCTAssertTrue(help.contains("cont"), "Missing 'cont' command")
        XCTAssertTrue(help.contains("new"), "Missing 'new' command")
    }

    /// BASIC help should contain listing commands.
    func test_basicHelp_containsListingCommands() {
        let help = REPLMode.basic(variant: .atari).helpText
        XCTAssertTrue(help.contains("list"), "Missing 'list' command")
        XCTAssertTrue(help.contains("vars"), "Missing 'vars' command")
    }

    /// BASIC help should contain file I/O commands.
    func test_basicHelp_containsFileIOCommands() {
        let help = REPLMode.basic(variant: .atari).helpText
        XCTAssertTrue(help.contains("save"), "Missing 'save' command")
        XCTAssertTrue(help.contains("load"), "Missing 'load' command")
        XCTAssertTrue(help.contains("import"), "Missing 'import' command")
        XCTAssertTrue(help.contains("export"), "Missing 'export' command")
    }

    // MARK: - DOS Help Text

    /// DOS help should contain drive management commands.
    func test_dosHelp_containsDriveCommands() {
        let help = REPLMode.dos.helpText
        XCTAssertTrue(help.contains("mount"), "Missing 'mount' command")
        XCTAssertTrue(help.contains("unmount"), "Missing 'unmount' command")
        XCTAssertTrue(help.contains("drives"), "Missing 'drives' command")
        XCTAssertTrue(help.contains("cd"), "Missing 'cd' command")
    }

    /// DOS help should contain file operation commands.
    func test_dosHelp_containsFileOperationCommands() {
        let help = REPLMode.dos.helpText
        XCTAssertTrue(help.contains("dir"), "Missing 'dir' command")
        XCTAssertTrue(help.contains("type"), "Missing 'type' command")
        XCTAssertTrue(help.contains("dump"), "Missing 'dump' command")
        XCTAssertTrue(help.contains("copy"), "Missing 'copy' command")
        XCTAssertTrue(help.contains("rename"), "Missing 'rename' command")
        XCTAssertTrue(help.contains("delete"), "Missing 'delete' command")
        XCTAssertTrue(help.contains("lock"), "Missing 'lock' command")
        XCTAssertTrue(help.contains("unlock"), "Missing 'unlock' command")
    }

    /// DOS help should contain host transfer commands.
    func test_dosHelp_containsTransferCommands() {
        let help = REPLMode.dos.helpText
        XCTAssertTrue(help.contains("export"), "Missing 'export' command")
        XCTAssertTrue(help.contains("import"), "Missing 'import' command")
    }

    /// DOS help should contain disk management commands.
    func test_dosHelp_containsDiskManagementCommands() {
        let help = REPLMode.dos.helpText
        XCTAssertTrue(help.contains("newdisk"), "Missing 'newdisk' command")
        XCTAssertTrue(help.contains("format"), "Missing 'format' command")
    }

    // MARK: - Help/Status Command Parsing

    /// `.help` with a topic should pass the topic through.
    func test_helpWithTopic_parsesTopic() throws {
        let cmd = try parser.parse(".help mount", mode: .dos)
        guard case .help(let topic) = cmd else {
            XCTFail("Expected help, got \(cmd)")
            return
        }
        XCTAssertEqual(topic, "mount")
    }

    /// `.status` should parse in all modes.
    func test_status_parsesInAllModes() throws {
        let modes: [REPLMode] = [.monitor, .basic(variant: .atari), .basic(variant: .turbo), .dos]
        for mode in modes {
            let cmd = try parser.parse(".status", mode: mode)
            guard case .status = cmd else {
                XCTFail("Expected status in \(mode.name), got \(cmd)")
                return
            }
        }
    }

    // MARK: - Mode Properties

    /// Mode names should be short identifiers.
    func test_modeNames() {
        XCTAssertEqual(REPLMode.monitor.name, "monitor")
        XCTAssertEqual(REPLMode.basic(variant: .atari).name, "basic")
        XCTAssertEqual(REPLMode.basic(variant: .turbo).name, "basic")
        XCTAssertEqual(REPLMode.dos.name, "dos")
    }

    /// Mode descriptions should contain meaningful text.
    func test_modeDescriptions() {
        XCTAssertTrue(REPLMode.monitor.description.contains("Monitor"))
        XCTAssertTrue(REPLMode.basic(variant: .atari).description.contains("Atari BASIC"))
        XCTAssertTrue(REPLMode.basic(variant: .turbo).description.contains("Turbo BASIC"))
        XCTAssertTrue(REPLMode.dos.description.contains("DOS"))
    }

    /// Prompts should match expected formats.
    func test_promptFormats() {
        XCTAssertEqual(REPLMode.monitor.prompt(pc: 0x0600), "[monitor] $0600> ")
        XCTAssertEqual(REPLMode.basic(variant: .atari).prompt(), "[basic] > ")
        XCTAssertEqual(REPLMode.basic(variant: .turbo).prompt(), "[basic:turbo] > ")
        XCTAssertEqual(REPLMode.dos.prompt(drive: 2), "[dos] D2:> ")
    }

    /// Default mode should be Atari BASIC.
    func test_defaultMode() {
        XCTAssertEqual(REPLMode.default, .basic(variant: .atari))
    }
}

// =============================================================================
// MARK: - DOS Workflow Tests
// =============================================================================

/// Tests realistic command sequences through CommandParser, simulating
/// how a user would chain commands together in a session.
///
/// These tests verify that the parser correctly handles multi-step
/// workflows across different command categories.
final class DOSWorkflowTests: XCTestCase {
    let parser = CommandParser()

    /// Simulated workflow: mount → dir → type → unmount.
    func test_workflow_mountDirTypeUnmount() throws {
        // Step 1: Mount a disk
        let mount = try parser.parse("mount 1 ~/disks/game.atr", mode: .dos)
        guard case .dosMountDisk(let drive, _) = mount else {
            XCTFail("Expected dosMountDisk, got \(mount)")
            return
        }
        XCTAssertEqual(drive, 1)

        // Step 2: List directory
        let dir = try parser.parse("dir", mode: .dos)
        guard case .dosDirectory(let pattern) = dir else {
            XCTFail("Expected dosDirectory, got \(dir)")
            return
        }
        XCTAssertNil(pattern)

        // Step 3: View a file
        let typeCmd = try parser.parse("type README.TXT", mode: .dos)
        guard case .dosType(let filename) = typeCmd else {
            XCTFail("Expected dosType, got \(typeCmd)")
            return
        }
        XCTAssertEqual(filename, "README.TXT")

        // Step 4: Unmount
        let unmount = try parser.parse("unmount 1", mode: .dos)
        guard case .dosUnmount(let unmountDrive) = unmount else {
            XCTFail("Expected dosUnmount, got \(unmount)")
            return
        }
        XCTAssertEqual(unmountDrive, 1)
    }

    /// Simulated workflow: mount two drives, cd between them.
    func test_workflow_multiDrive() throws {
        // Mount drive 1
        let mount1 = try parser.parse("mount 1 ~/disk1.atr", mode: .dos)
        guard case .dosMountDisk(let d1, _) = mount1 else {
            XCTFail("Expected dosMountDisk, got \(mount1)")
            return
        }
        XCTAssertEqual(d1, 1)

        // Mount drive 2
        let mount2 = try parser.parse("mount 2 ~/disk2.atr", mode: .dos)
        guard case .dosMountDisk(let d2, _) = mount2 else {
            XCTFail("Expected dosMountDisk, got \(mount2)")
            return
        }
        XCTAssertEqual(d2, 2)

        // Switch to drive 2
        let cd = try parser.parse("cd 2", mode: .dos)
        guard case .dosChangeDrive(let cdDrive) = cd else {
            XCTFail("Expected dosChangeDrive, got \(cd)")
            return
        }
        XCTAssertEqual(cdDrive, 2)

        // List drives
        let drives = try parser.parse("drives", mode: .dos)
        guard case .dosDrives = drives else {
            XCTFail("Expected dosDrives, got \(drives)")
            return
        }
    }

    /// Simulated workflow: lock → unlock → rename → delete.
    func test_workflow_fileManagement() throws {
        let lock = try parser.parse("lock GAME.COM", mode: .dos)
        guard case .dosLock(let f1) = lock else {
            XCTFail("Expected dosLock, got \(lock)")
            return
        }
        XCTAssertEqual(f1, "GAME.COM")

        let unlock = try parser.parse("unlock GAME.COM", mode: .dos)
        guard case .dosUnlock(let f2) = unlock else {
            XCTFail("Expected dosUnlock, got \(unlock)")
            return
        }
        XCTAssertEqual(f2, "GAME.COM")

        let rename = try parser.parse("rename GAME.COM ARCADE.COM", mode: .dos)
        guard case .dosRename(let oldName, let newName) = rename else {
            XCTFail("Expected dosRename, got \(rename)")
            return
        }
        XCTAssertEqual(oldName, "GAME.COM")
        XCTAssertEqual(newName, "ARCADE.COM")

        let delete = try parser.parse("delete ARCADE.COM", mode: .dos)
        guard case .dosDelete(let f3) = delete else {
            XCTFail("Expected dosDelete, got \(delete)")
            return
        }
        XCTAssertEqual(f3, "ARCADE.COM")
    }

    /// Simulated workflow: import → export (host transfer).
    func test_workflow_hostTransfer() throws {
        let importCmd = try parser.parse("import ~/Desktop/program.com PROG.COM", mode: .dos)
        guard case .dosImport(let path, let filename) = importCmd else {
            XCTFail("Expected dosImport, got \(importCmd)")
            return
        }
        XCTAssertEqual(path, NSString(string: "~/Desktop/program.com").expandingTildeInPath)
        XCTAssertEqual(filename, "PROG.COM")

        let exportCmd = try parser.parse("export PROG.COM ~/Desktop/backup.com", mode: .dos)
        guard case .dosExport(let expFile, let expPath) = exportCmd else {
            XCTFail("Expected dosExport, got \(exportCmd)")
            return
        }
        XCTAssertEqual(expFile, "PROG.COM")
        XCTAssertEqual(expPath, NSString(string: "~/Desktop/backup.com").expandingTildeInPath)
    }

    /// Simulated workflow: newdisk → format.
    func test_workflow_diskCreation() throws {
        let newdisk = try parser.parse("newdisk ~/disks/blank.atr ss/sd", mode: .dos)
        guard case .dosNewDisk(let path, let type) = newdisk else {
            XCTFail("Expected dosNewDisk, got \(newdisk)")
            return
        }
        XCTAssertEqual(path, NSString(string: "~/disks/blank.atr").expandingTildeInPath)
        XCTAssertEqual(type, "ss/sd")

        let format = try parser.parse("format", mode: .dos)
        guard case .dosFormat = format else {
            XCTFail("Expected dosFormat, got \(format)")
            return
        }
    }

    /// Cross-mode workflow: basic → monitor → dos → basic, verify
    /// mode-specific commands fail in wrong modes.
    func test_workflow_crossModeTransitions() throws {
        // Start in BASIC, switch to monitor
        let toMonitor = try parser.parse(".monitor", mode: .basic(variant: .atari))
        guard case .switchMode(.monitor) = toMonitor else {
            XCTFail("Expected switchMode(.monitor), got \(toMonitor)")
            return
        }

        // In monitor, `r` works
        let reg = try parser.parse("r", mode: .monitor)
        guard case .registers = reg else {
            XCTFail("Expected registers, got \(reg)")
            return
        }

        // In monitor, `dir` fails (it's a DOS command)
        XCTAssertThrowsError(try parser.parse("dir", mode: .monitor))

        // Switch to DOS
        let toDos = try parser.parse(".dos", mode: .monitor)
        guard case .switchMode(.dos) = toDos else {
            XCTFail("Expected switchMode(.dos), got \(toDos)")
            return
        }

        // In DOS, `dir` works
        let dir = try parser.parse("dir", mode: .dos)
        guard case .dosDirectory = dir else {
            XCTFail("Expected dosDirectory, got \(dir)")
            return
        }

        // In DOS, `r` fails (it's a monitor command)
        XCTAssertThrowsError(try parser.parse("r", mode: .dos))

        // Switch back to BASIC
        let toBasic = try parser.parse(".basic", mode: .dos)
        guard case .switchMode(.basic(variant: .atari)) = toBasic else {
            XCTFail("Expected switchMode(.basic), got \(toBasic)")
            return
        }

        // In BASIC, `run` works
        let run = try parser.parse("run", mode: .basic(variant: .atari))
        guard case .basicRun = run else {
            XCTFail("Expected basicRun, got \(run)")
            return
        }
    }

    /// Filtered directory listing with wildcard pattern.
    func test_workflow_filteredDirectoryListing() throws {
        // Mount, then list with pattern
        let mount = try parser.parse("mount 1 ~/games.atr", mode: .dos)
        guard case .dosMountDisk = mount else {
            XCTFail("Expected dosMountDisk, got \(mount)")
            return
        }

        let dir = try parser.parse("dir *.BAS", mode: .dos)
        guard case .dosDirectory(let pattern) = dir else {
            XCTFail("Expected dosDirectory, got \(dir)")
            return
        }
        XCTAssertEqual(pattern, "*.BAS")

        // Get info on a specific file
        let info = try parser.parse("info HELLO.BAS", mode: .dos)
        guard case .dosFileInfo(let filename) = info else {
            XCTFail("Expected dosFileInfo, got \(info)")
            return
        }
        XCTAssertEqual(filename, "HELLO.BAS")

        // Hex dump
        let dump = try parser.parse("dump HELLO.BAS", mode: .dos)
        guard case .dosDump(let dumpFile) = dump else {
            XCTFail("Expected dosDump, got \(dump)")
            return
        }
        XCTAssertEqual(dumpFile, "HELLO.BAS")
    }

    /// Copy between drives.
    func test_workflow_copyBetweenDrives() throws {
        // Mount two drives and copy a file
        _ = try parser.parse("mount 1 ~/source.atr", mode: .dos)
        _ = try parser.parse("mount 2 ~/dest.atr", mode: .dos)

        let copy = try parser.parse("copy GAME.COM D2:GAME.COM", mode: .dos)
        guard case .dosCopy(let source, let dest) = copy else {
            XCTFail("Expected dosCopy, got \(copy)")
            return
        }
        XCTAssertEqual(source, "GAME.COM")
        XCTAssertEqual(dest, "D2:GAME.COM")
    }
}
