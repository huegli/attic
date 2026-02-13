// =============================================================================
// CLIProtocolTests.swift - Unit Tests for CLI Protocol Types and Parsers
// =============================================================================
//
// This file contains comprehensive unit tests for the CLI protocol layer:
// - CLIProtocolConstants: Protocol constants and socket path generation
// - CLICommand: Command types and their properties
// - CLIResponse: Response formatting and multi-line support
// - CLIEvent: Event formatting for async notifications
// - CLICommandParser: Parsing text commands into CLICommand values
// - CLIResponseParser: Parsing response/event lines
// - CLIProtocolError: Error types and their descriptions
//
// =============================================================================

import XCTest
@testable import AtticCore

final class CLIProtocolTests: XCTestCase {

    // =========================================================================
    // MARK: - CLIProtocolConstants Tests
    // =========================================================================

    func testProtocolPrefixes() {
        // Verify protocol prefixes are correct
        XCTAssertEqual(CLIProtocolConstants.commandPrefix, "CMD:")
        XCTAssertEqual(CLIProtocolConstants.okPrefix, "OK:")
        XCTAssertEqual(CLIProtocolConstants.errorPrefix, "ERR:")
        XCTAssertEqual(CLIProtocolConstants.eventPrefix, "EVENT:")
    }

    func testMultiLineSeparator() {
        // Multi-line separator should be Record Separator character
        XCTAssertEqual(CLIProtocolConstants.multiLineSeparator, "\u{1E}")
    }

    func testSocketPathGeneration() {
        // Test socket path generation for a specific PID
        let path = CLIProtocolConstants.socketPath(for: 12345)
        XCTAssertEqual(path, "/tmp/attic-12345.sock")
    }

    func testSocketPathPrefix() {
        XCTAssertEqual(CLIProtocolConstants.socketPathPrefix, "/tmp/attic-")
        XCTAssertEqual(CLIProtocolConstants.socketPathSuffix, ".sock")
    }

    func testProtocolVersion() {
        XCTAssertEqual(CLIProtocolConstants.protocolVersion, "1.0")
    }

    func testTimeoutConstants() {
        XCTAssertEqual(CLIProtocolConstants.commandTimeout, 30.0)
        XCTAssertEqual(CLIProtocolConstants.pingTimeout, 1.0)
        XCTAssertEqual(CLIProtocolConstants.connectionTimeout, 5.0)
    }

    func testMaxLineLength() {
        XCTAssertEqual(CLIProtocolConstants.maxLineLength, 4096)
    }

    // =========================================================================
    // MARK: - CLIResponse Tests
    // =========================================================================

    func testOkResponseFormatting() {
        let response = CLIResponse.ok("pong")
        XCTAssertEqual(response.formatted, "OK:pong")
    }

    func testOkResponseWithEmptyData() {
        let response = CLIResponse.ok("")
        XCTAssertEqual(response.formatted, "OK:")
    }

    func testErrorResponseFormatting() {
        let response = CLIResponse.error("Command not found")
        XCTAssertEqual(response.formatted, "ERR:Command not found")
    }

    func testMultiLineResponse() {
        let response = CLIResponse.okMultiLine(["line1", "line2", "line3"])
        XCTAssertEqual(response.formatted, "OK:line1\u{1E}line2\u{1E}line3")
    }

    func testMultiLineResponseWithSingleLine() {
        let response = CLIResponse.okMultiLine(["only one line"])
        XCTAssertEqual(response.formatted, "OK:only one line")
    }

    func testMultiLineResponseWithEmptyArray() {
        let response = CLIResponse.okMultiLine([])
        XCTAssertEqual(response.formatted, "OK:")
    }

    // =========================================================================
    // MARK: - CLIEvent Tests
    // =========================================================================

    func testBreakpointEventFormatting() {
        let event = CLIEvent.breakpoint(address: 0x0600, a: 0x50, x: 0x10, y: 0x00, s: 0xFF, p: 0x30)
        XCTAssertEqual(event.formatted, "EVENT:breakpoint $0600 A=$50 X=$10 Y=$00 S=$FF P=$30")
    }

    func testBreakpointEventZeroAddress() {
        let event = CLIEvent.breakpoint(address: 0x0000, a: 0x00, x: 0x00, y: 0x00, s: 0x00, p: 0x00)
        XCTAssertEqual(event.formatted, "EVENT:breakpoint $0000 A=$00 X=$00 Y=$00 S=$00 P=$00")
    }

    func testStoppedEventFormatting() {
        let event = CLIEvent.stopped(address: 0xE000)
        XCTAssertEqual(event.formatted, "EVENT:stopped $E000")
    }

    func testErrorEventFormatting() {
        let event = CLIEvent.error(message: "Something went wrong")
        XCTAssertEqual(event.formatted, "EVENT:error Something went wrong")
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Connection Commands
    // =========================================================================

    func testParsePing() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("ping")
        guard case .ping = command else {
            XCTFail("Expected .ping, got \(command)")
            return
        }
    }

    func testParsePingWithPrefix() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("CMD:ping")
        guard case .ping = command else {
            XCTFail("Expected .ping, got \(command)")
            return
        }
    }

    func testParseVersion() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("version")
        guard case .version = command else {
            XCTFail("Expected .version, got \(command)")
            return
        }
    }

    func testParseQuit() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("quit")
        guard case .quit = command else {
            XCTFail("Expected .quit, got \(command)")
            return
        }
    }

    func testParseShutdown() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("shutdown")
        guard case .shutdown = command else {
            XCTFail("Expected .shutdown, got \(command)")
            return
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Emulator Control
    // =========================================================================

    func testParsePause() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("pause")
        guard case .pause = command else {
            XCTFail("Expected .pause, got \(command)")
            return
        }
    }

    func testParseResume() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("resume")
        guard case .resume = command else {
            XCTFail("Expected .resume, got \(command)")
            return
        }
    }

    func testParseStepDefault() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("step")
        guard case .step(let count) = command else {
            XCTFail("Expected .step, got \(command)")
            return
        }
        XCTAssertEqual(count, 1)
    }

    func testParseStepWithCount() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("step 10")
        guard case .step(let count) = command else {
            XCTFail("Expected .step, got \(command)")
            return
        }
        XCTAssertEqual(count, 10)
    }

    func testParseStepInvalidCount() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("step -5")) { error in
            guard case CLIProtocolError.invalidStepCount = error else {
                XCTFail("Expected invalidStepCount error, got \(error)")
                return
            }
        }
    }

    func testParseStepZeroCount() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("step 0")) { error in
            guard case CLIProtocolError.invalidStepCount = error else {
                XCTFail("Expected invalidStepCount error, got \(error)")
                return
            }
        }
    }

    func testParseResetCold() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("reset cold")
        guard case .reset(let cold) = command else {
            XCTFail("Expected .reset, got \(command)")
            return
        }
        XCTAssertTrue(cold)
    }

    func testParseResetWarm() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("reset warm")
        guard case .reset(let cold) = command else {
            XCTFail("Expected .reset, got \(command)")
            return
        }
        XCTAssertFalse(cold)
    }

    func testParseResetDefault() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("reset")
        guard case .reset(let cold) = command else {
            XCTFail("Expected .reset, got \(command)")
            return
        }
        XCTAssertTrue(cold)  // Default is cold reset
    }

    func testParseResetInvalidType() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("reset hot")) { error in
            guard case CLIProtocolError.invalidResetType = error else {
                XCTFail("Expected invalidResetType error, got \(error)")
                return
            }
        }
    }

    func testParseStatus() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("status")
        guard case .status = command else {
            XCTFail("Expected .status, got \(command)")
            return
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Memory Operations
    // =========================================================================

    func testParseReadHexAddress() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("read $0600 16")
        guard case .read(let address, let count) = command else {
            XCTFail("Expected .read, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(count, 16)
    }

    func testParseReadDecimalAddress() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("read 1536 16")
        guard case .read(let address, let count) = command else {
            XCTFail("Expected .read, got \(command)")
            return
        }
        XCTAssertEqual(address, 1536)
        XCTAssertEqual(count, 16)
    }

    func testParseRead0xAddress() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("read 0x0600 16")
        guard case .read(let address, let count) = command else {
            XCTFail("Expected .read, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(count, 16)
    }

    func testParseReadMissingCount() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("read $0600")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseReadInvalidAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("read notanaddress 16")) { error in
            guard case CLIProtocolError.invalidAddress = error else {
                XCTFail("Expected invalidAddress error, got \(error)")
                return
            }
        }
    }

    func testParseWriteHexData() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("write $0600 A9,00,8D,00,D4")
        guard case .write(let address, let data) = command else {
            XCTFail("Expected .write, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(data, [0xA9, 0x00, 0x8D, 0x00, 0xD4])
    }

    func testParseWriteWithSpaces() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("write $0600 A9, 00, 8D")
        guard case .write(let address, let data) = command else {
            XCTFail("Expected .write, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(data, [0xA9, 0x00, 0x8D])
    }

    func testParseWriteWithDollarPrefixBytes() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("write $0600 $A9,$00")
        guard case .write(let address, let data) = command else {
            XCTFail("Expected .write, got \(command)")
            return
        }
        XCTAssertEqual(data, [0xA9, 0x00])
    }

    func testParseWriteInvalidByte() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("write $0600 ZZ,00")) { error in
            guard case CLIProtocolError.invalidByte = error else {
                XCTFail("Expected invalidByte error, got \(error)")
                return
            }
        }
    }

    func testParseWriteMissingData() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("write $0600")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseRegistersQuery() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("registers")
        guard case .registers(let mods) = command else {
            XCTFail("Expected .registers, got \(command)")
            return
        }
        XCTAssertNil(mods)
    }

    func testParseRegistersModify() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("registers A=$50 X=$10")
        guard case .registers(let mods) = command else {
            XCTFail("Expected .registers, got \(command)")
            return
        }
        XCTAssertNotNil(mods)
        XCTAssertEqual(mods?.count, 2)
        XCTAssertEqual(mods?[0].0, "A")
        XCTAssertEqual(mods?[0].1, 0x50)
        XCTAssertEqual(mods?[1].0, "X")
        XCTAssertEqual(mods?[1].1, 0x10)
    }

    func testParseRegistersPC() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("registers PC=$E000")
        guard case .registers(let mods) = command else {
            XCTFail("Expected .registers, got \(command)")
            return
        }
        XCTAssertEqual(mods?[0].0, "PC")
        XCTAssertEqual(mods?[0].1, 0xE000)
    }

    func testParseRegistersInvalidRegister() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("registers Z=$50")) { error in
            guard case CLIProtocolError.invalidRegister = error else {
                XCTFail("Expected invalidRegister error, got \(error)")
                return
            }
        }
    }

    func testParseRegistersInvalidFormat() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("registers A50")) { error in
            guard case CLIProtocolError.invalidRegisterFormat = error else {
                XCTFail("Expected invalidRegisterFormat error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Breakpoints
    // =========================================================================

    func testParseBreakpointSet() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("breakpoint set $0600")
        guard case .breakpointSet(let address) = command else {
            XCTFail("Expected .breakpointSet, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseBreakpointClear() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("breakpoint clear $0600")
        guard case .breakpointClear(let address) = command else {
            XCTFail("Expected .breakpointClear, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseBreakpointClearAll() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("breakpoint clearall")
        guard case .breakpointClearAll = command else {
            XCTFail("Expected .breakpointClearAll, got \(command)")
            return
        }
    }

    func testParseBreakpointList() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("breakpoint list")
        guard case .breakpointList = command else {
            XCTFail("Expected .breakpointList, got \(command)")
            return
        }
    }

    func testParseBreakpointMissingSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("breakpoint")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBreakpointSetMissingAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("breakpoint set")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Disk Operations
    // =========================================================================

    func testParseMount() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("mount 1 /path/to/disk.atr")
        guard case .mount(let drive, let path) = command else {
            XCTFail("Expected .mount, got \(command)")
            return
        }
        XCTAssertEqual(drive, 1)
        XCTAssertEqual(path, "/path/to/disk.atr")
    }

    func testParseMountWithSpacesInPath() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("mount 2 /path/with spaces/disk.atr")
        guard case .mount(let drive, let path) = command else {
            XCTFail("Expected .mount, got \(command)")
            return
        }
        XCTAssertEqual(drive, 2)
        XCTAssertEqual(path, "/path/with spaces/disk.atr")
    }

    func testParseMountInvalidDrive() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("mount 0 /path/to/disk.atr")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    func testParseMountDriveTooHigh() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("mount 9 /path/to/disk.atr")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    func testParseUnmount() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("unmount 1")
        guard case .unmount(let drive) = command else {
            XCTFail("Expected .unmount, got \(command)")
            return
        }
        XCTAssertEqual(drive, 1)
    }

    func testParseDrives() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("drives")
        guard case .drives = command else {
            XCTFail("Expected .drives, got \(command)")
            return
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Boot With File
    // =========================================================================

    func testParseBoot() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("boot /path/to/game.atr")
        guard case .boot(let path) = command else {
            XCTFail("Expected .boot, got \(command)")
            return
        }
        XCTAssertEqual(path, "/path/to/game.atr")
    }

    func testParseBootWithSpacesInPath() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("boot /path/with spaces/my game.xex")
        guard case .boot(let path) = command else {
            XCTFail("Expected .boot, got \(command)")
            return
        }
        XCTAssertEqual(path, "/path/with spaces/my game.xex")
    }

    func testParseBootWithTilde() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("boot ~/Games/starraiders.atr")
        guard case .boot(let path) = command else {
            XCTFail("Expected .boot, got \(command)")
            return
        }
        // Tilde should be expanded to the home directory
        XCTAssertFalse(path.hasPrefix("~"), "Tilde should be expanded")
        XCTAssertTrue(path.hasSuffix("Games/starraiders.atr"))
    }

    func testParseBootMissingPath() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("boot")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBootMissingPathWhitespaceOnly() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("boot   ")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBootWithCMDPrefix() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("CMD:boot /path/to/disk.atr")
        guard case .boot(let path) = command else {
            XCTFail("Expected .boot, got \(command)")
            return
        }
        XCTAssertEqual(path, "/path/to/disk.atr")
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - State Management
    // =========================================================================

    func testParseStateSave() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("state save /path/to/state.sav")
        guard case .stateSave(let path) = command else {
            XCTFail("Expected .stateSave, got \(command)")
            return
        }
        XCTAssertEqual(path, "/path/to/state.sav")
    }

    func testParseStateLoad() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("state load /path/to/state.sav")
        guard case .stateLoad(let path) = command else {
            XCTFail("Expected .stateLoad, got \(command)")
            return
        }
        XCTAssertEqual(path, "/path/to/state.sav")
    }

    func testParseStateMissingSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("state")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseStateMissingPath() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("state save")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Display
    // =========================================================================

    func testParseScreenshotWithPath() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("screenshot /path/to/screenshot.png")
        guard case .screenshot(let path) = command else {
            XCTFail("Expected .screenshot, got \(command)")
            return
        }
        XCTAssertEqual(path, "/path/to/screenshot.png")
    }

    func testParseScreenshotWithoutPath() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("screenshot")
        guard case .screenshot(let path) = command else {
            XCTFail("Expected .screenshot, got \(command)")
            return
        }
        XCTAssertNil(path)
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Injection
    // =========================================================================

    func testParseInjectBasic() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("inject basic SGVsbG8gV29ybGQh")
        guard case .injectBasic(let data) = command else {
            XCTFail("Expected .injectBasic, got \(command)")
            return
        }
        XCTAssertEqual(data, "SGVsbG8gV29ybGQh")
    }

    func testParseInjectKeys() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("inject keys HELLO")
        guard case .injectKeys(let text) = command else {
            XCTFail("Expected .injectKeys, got \(command)")
            return
        }
        XCTAssertEqual(text, "HELLO")
    }

    func testParseInjectKeysWithEscapes() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("inject keys HELLO\\nWORLD")
        guard case .injectKeys(let text) = command else {
            XCTFail("Expected .injectKeys, got \(command)")
            return
        }
        XCTAssertEqual(text, "HELLO\nWORLD")
    }

    func testParseInjectKeysWithTab() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("inject keys A\\tB")
        guard case .injectKeys(let text) = command else {
            XCTFail("Expected .injectKeys, got \(command)")
            return
        }
        XCTAssertEqual(text, "A\tB")
    }

    func testParseInjectMissingSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("inject")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Step Over
    // =========================================================================

    func testParseStepOver() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("stepover")
        guard case .stepOver = command else {
            XCTFail("Expected .stepOver, got \(command)")
            return
        }
    }

    func testParseStepOverAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("so")
        guard case .stepOver = command else {
            XCTFail("Expected .stepOver, got \(command)")
            return
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Run Until
    // =========================================================================

    func testParseRunUntilHex() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("until $0600")
        guard case .runUntil(let address) = command else {
            XCTFail("Expected .runUntil, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseRunUntilAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("rununtil $E000")
        guard case .runUntil(let address) = command else {
            XCTFail("Expected .runUntil, got \(command)")
            return
        }
        XCTAssertEqual(address, 0xE000)
    }

    func testParseRunUntilMissingAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("until")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseRunUntilInvalidAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("until xyz")) { error in
            guard case CLIProtocolError.invalidAddress = error else {
                XCTFail("Expected invalidAddress error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Memory Fill
    // =========================================================================

    func testParseFill() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("fill $0600 $0700 FF")
        guard case .memoryFill(let start, let end, let value) = command else {
            XCTFail("Expected .memoryFill, got \(command)")
            return
        }
        XCTAssertEqual(start, 0x0600)
        XCTAssertEqual(end, 0x0700)
        XCTAssertEqual(value, 0xFF)
    }

    func testParseFillWithDollarValue() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("fill $2000 $3000 $A5")
        guard case .memoryFill(let start, let end, let value) = command else {
            XCTFail("Expected .memoryFill, got \(command)")
            return
        }
        XCTAssertEqual(start, 0x2000)
        XCTAssertEqual(end, 0x3000)
        XCTAssertEqual(value, 0xA5)
    }

    func testParseFillZeroValue() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("fill $0600 $06FF 00")
        guard case .memoryFill(let start, let end, let value) = command else {
            XCTFail("Expected .memoryFill, got \(command)")
            return
        }
        XCTAssertEqual(start, 0x0600)
        XCTAssertEqual(end, 0x06FF)
        XCTAssertEqual(value, 0x00)
    }

    func testParseFillMissingArgs() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("fill $0600 $0700")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseFillInvalidValue() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("fill $0600 $0700 GG")) { error in
            guard case CLIProtocolError.invalidByte = error else {
                XCTFail("Expected invalidByte error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Assembly
    // =========================================================================

    func testParseAssembleInteractive() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("assemble $0600")
        guard case .assemble(let address) = command else {
            XCTFail("Expected .assemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseAssembleInteractiveAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("a $0600")
        guard case .assemble(let address) = command else {
            XCTFail("Expected .assemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseAssembleInteractiveAsmAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("asm $0600")
        guard case .assemble(let address) = command else {
            XCTFail("Expected .assemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseAssembleLine() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("assemble $0600 LDA #$00")
        guard case .assembleLine(let address, let instruction) = command else {
            XCTFail("Expected .assembleLine, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(instruction, "LDA #$00")
    }

    func testParseAssembleLineComplex() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("a $C000 STA $D40E")
        guard case .assembleLine(let address, let instruction) = command else {
            XCTFail("Expected .assembleLine, got \(command)")
            return
        }
        XCTAssertEqual(address, 0xC000)
        XCTAssertEqual(instruction, "STA $D40E")
    }

    func testParseAssembleMissingAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("assemble")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseAssembleInvalidAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("assemble xyz")) { error in
            guard case CLIProtocolError.invalidAddress = error else {
                XCTFail("Expected invalidAddress error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Assembly Input/End
    // =========================================================================

    func testParseAsmInput() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("asm input LDA #$00")
        guard case .assembleInput(let instruction) = command else {
            XCTFail("Expected .assembleInput, got \(command)")
            return
        }
        XCTAssertEqual(instruction, "LDA #$00")
    }

    func testParseAsmInputComplex() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("asm input STA $D400")
        guard case .assembleInput(let instruction) = command else {
            XCTFail("Expected .assembleInput, got \(command)")
            return
        }
        XCTAssertEqual(instruction, "STA $D400")
    }

    func testParseAsmInputAssembleAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("assemble input LDA #$FF")
        guard case .assembleInput(let instruction) = command else {
            XCTFail("Expected .assembleInput, got \(command)")
            return
        }
        XCTAssertEqual(instruction, "LDA #$FF")
    }

    func testParseAsmInputAAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("a input JMP $0600")
        guard case .assembleInput(let instruction) = command else {
            XCTFail("Expected .assembleInput, got \(command)")
            return
        }
        XCTAssertEqual(instruction, "JMP $0600")
    }

    func testParseAsmInputMissingInstruction() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("asm input")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseAsmEnd() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("asm end")
        guard case .assembleEnd = command else {
            XCTFail("Expected .assembleEnd, got \(command)")
            return
        }
    }

    func testParseAsmEndAssembleAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("assemble end")
        guard case .assembleEnd = command else {
            XCTFail("Expected .assembleEnd, got \(command)")
            return
        }
    }

    func testParseAsmEndAAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("a end")
        guard case .assembleEnd = command else {
            XCTFail("Expected .assembleEnd, got \(command)")
            return
        }
    }

    /// Regression: existing single-line assembly still works
    func testParseAssembleLineStillWorks() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("a $0600 LDA #$00")
        guard case .assembleLine(let address, let instruction) = command else {
            XCTFail("Expected .assembleLine, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(instruction, "LDA #$00")
    }

    /// Regression: interactive assembly start still works
    func testParseAssembleInteractiveStillWorks() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("a $0600")
        guard case .assemble(let address) = command else {
            XCTFail("Expected .assemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Disassembly
    // =========================================================================

    func testParseDisassembleNoArgs() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("disassemble")
        guard case .disassemble(let address, let lines) = command else {
            XCTFail("Expected .disassemble, got \(command)")
            return
        }
        XCTAssertNil(address, "Address should be nil (use PC)")
        XCTAssertNil(lines, "Lines should be nil (use default)")
    }

    func testParseDisassembleShortAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("d")
        guard case .disassemble(let address, let lines) = command else {
            XCTFail("Expected .disassemble, got \(command)")
            return
        }
        XCTAssertNil(address)
        XCTAssertNil(lines)
    }

    func testParseDisasmAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("disasm $0600")
        guard case .disassemble(let address, let lines) = command else {
            XCTFail("Expected .disassemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertNil(lines)
    }

    func testParseDisassembleWithAddress() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("d $E000")
        guard case .disassemble(let address, let lines) = command else {
            XCTFail("Expected .disassemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0xE000)
        XCTAssertNil(lines)
    }

    func testParseDisassembleWithAddressAndLines() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("d $0600 8")
        guard case .disassemble(let address, let lines) = command else {
            XCTFail("Expected .disassemble, got \(command)")
            return
        }
        XCTAssertEqual(address, 0x0600)
        XCTAssertEqual(lines, 8)
    }

    func testParseDisassembleInvalidAddress() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("d xyz")) { error in
            guard case CLIProtocolError.invalidAddress = error else {
                XCTFail("Expected invalidAddress error, got \(error)")
                return
            }
        }
    }

    func testParseDisassembleInvalidLineCount() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("d $0600 abc")) { error in
            guard case CLIProtocolError.invalidCount = error else {
                XCTFail("Expected invalidCount error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - BASIC Commands
    // =========================================================================

    func testParseBasicNew() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic new")
        guard case .basicNew = command else {
            XCTFail("Expected .basicNew, got \(command)")
            return
        }
    }

    func testParseBasicRun() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic run")
        guard case .basicRun = command else {
            XCTFail("Expected .basicRun, got \(command)")
            return
        }
    }

    func testParseBasicList() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic list")
        guard case .basicList = command else {
            XCTFail("Expected .basicList, got \(command)")
            return
        }
    }

    func testParseBasicLine() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic 10 PRINT \"HELLO\"")
        guard case .basicLine(let line) = command else {
            XCTFail("Expected .basicLine, got \(command)")
            return
        }
        XCTAssertEqual(line, "10 PRINT \"HELLO\"")
    }

    func testParseBasicLineCasePreserved() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic 20 FOR I=1 TO 10")
        guard case .basicLine(let line) = command else {
            XCTFail("Expected .basicLine, got \(command)")
            return
        }
        XCTAssertEqual(line, "20 FOR I=1 TO 10")
    }

    func testParseBasicCaseInsensitive() throws {
        let parser = CLICommandParser()
        // "NEW", "new", "New" should all parse as basicNew
        let cmd1 = try parser.parse("basic NEW")
        let cmd2 = try parser.parse("basic new")
        guard case .basicNew = cmd1, case .basicNew = cmd2 else {
            XCTFail("Both should be .basicNew")
            return
        }
    }

    func testParseBasicMissingArg() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - BASIC Editing Commands
    // =========================================================================

    func testParseBasicDeleteSingleLine() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic del 10")
        guard case .basicDelete(let lineOrRange) = command else {
            XCTFail("Expected .basicDelete, got \(command)")
            return
        }
        XCTAssertEqual(lineOrRange, "10")
    }

    func testParseBasicDeleteRange() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic DEL 10-50")
        guard case .basicDelete(let lineOrRange) = command else {
            XCTFail("Expected .basicDelete, got \(command)")
            return
        }
        XCTAssertEqual(lineOrRange, "10-50")
    }

    func testParseBasicDeleteMissingArg() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic del")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBasicStop() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic stop")
        guard case .basicStop = command else {
            XCTFail("Expected .basicStop, got \(command)")
            return
        }
    }

    func testParseBasicCont() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic CONT")
        guard case .basicCont = command else {
            XCTFail("Expected .basicCont, got \(command)")
            return
        }
    }

    func testParseBasicVars() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic vars")
        guard case .basicVars = command else {
            XCTFail("Expected .basicVars, got \(command)")
            return
        }
    }

    func testParseBasicVar() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic var X")
        guard case .basicVar(let name) = command else {
            XCTFail("Expected .basicVar, got \(command)")
            return
        }
        XCTAssertEqual(name, "X")
    }

    func testParseBasicVarString() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic var A$")
        guard case .basicVar(let name) = command else {
            XCTFail("Expected .basicVar, got \(command)")
            return
        }
        XCTAssertEqual(name, "A$")
    }

    func testParseBasicVarMissingName() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic var")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBasicInfo() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic info")
        guard case .basicInfo = command else {
            XCTFail("Expected .basicInfo, got \(command)")
            return
        }
    }

    func testParseBasicExport() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic export /tmp/program.bas")
        guard case .basicExport(let path) = command else {
            XCTFail("Expected .basicExport, got \(command)")
            return
        }
        XCTAssertEqual(path, "/tmp/program.bas")
    }

    func testParseBasicExportTildeExpansion() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic export ~/program.bas")
        guard case .basicExport(let path) = command else {
            XCTFail("Expected .basicExport, got \(command)")
            return
        }
        XCTAssertFalse(path.hasPrefix("~"), "Tilde should be expanded")
        XCTAssertTrue(path.hasSuffix("program.bas"))
    }

    func testParseBasicExportMissingPath() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic export")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBasicImport() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic import /tmp/program.bas")
        guard case .basicImport(let path) = command else {
            XCTFail("Expected .basicImport, got \(command)")
            return
        }
        XCTAssertEqual(path, "/tmp/program.bas")
    }

    func testParseBasicImportTildeExpansion() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic import ~/games/mygame.bas")
        guard case .basicImport(let path) = command else {
            XCTFail("Expected .basicImport, got \(command)")
            return
        }
        XCTAssertFalse(path.hasPrefix("~"), "Tilde should be expanded")
        XCTAssertTrue(path.hasSuffix("games/mygame.bas"))
    }

    func testParseBasicImportMissingPath() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic import")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseBasicDirNoArg() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic dir")
        guard case .basicDir(let drive) = command else {
            XCTFail("Expected .basicDir, got \(command)")
            return
        }
        XCTAssertNil(drive)
    }

    func testParseBasicDirWithDrive() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic dir 2")
        guard case .basicDir(let drive) = command else {
            XCTFail("Expected .basicDir, got \(command)")
            return
        }
        XCTAssertEqual(drive, 2)
    }

    func testParseBasicDirInvalidDrive() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic dir 0")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    func testParseBasicDirDriveTooHigh() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic dir 9")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    func testParseBasicDirNonNumericDrive() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("basic dir abc")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    /// Regression: a numbered BASIC line should still parse as .basicLine
    func testParseBasicLineStillWorks() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("basic 10 PRINT X")
        guard case .basicLine(let line) = command else {
            XCTFail("Expected .basicLine, got \(command)")
            return
        }
        XCTAssertEqual(line, "10 PRINT X")
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - Error Cases
    // =========================================================================

    func testParseInvalidCommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("unknowncommand")) { error in
            guard case CLIProtocolError.invalidCommand(let cmd) = error else {
                XCTFail("Expected invalidCommand error, got \(error)")
                return
            }
            XCTAssertEqual(cmd, "unknowncommand")
        }
    }

    func testParseEmptyCommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("")) { error in
            guard case CLIProtocolError.invalidCommand = error else {
                XCTFail("Expected invalidCommand error, got \(error)")
                return
            }
        }
    }

    func testParseLineTooLong() {
        let parser = CLICommandParser()
        let longLine = String(repeating: "a", count: CLIProtocolConstants.maxLineLength + 1)
        XCTAssertThrowsError(try parser.parse(longLine)) { error in
            guard case CLIProtocolError.lineTooLong = error else {
                XCTFail("Expected lineTooLong error, got \(error)")
                return
            }
        }
    }

    func testParseCaseInsensitive() throws {
        let parser = CLICommandParser()
        let command1 = try parser.parse("PING")
        let command2 = try parser.parse("PiNg")
        let command3 = try parser.parse("ping")

        guard case .ping = command1, case .ping = command2, case .ping = command3 else {
            XCTFail("All should be .ping")
            return
        }
    }

    func testParseWithWhitespace() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("  ping  ")
        guard case .ping = command else {
            XCTFail("Expected .ping, got \(command)")
            return
        }
    }

    // =========================================================================
    // MARK: - CLIResponseParser Tests
    // =========================================================================

    func testParseOkResponse() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("OK:pong")
        guard case .response(let response) = result else {
            XCTFail("Expected response, got \(result)")
            return
        }
        guard case .ok(let data) = response else {
            XCTFail("Expected .ok, got \(response)")
            return
        }
        XCTAssertEqual(data, "pong")
    }

    func testParseOkResponseEmpty() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("OK:")
        guard case .response(let response) = result else {
            XCTFail("Expected response")
            return
        }
        guard case .ok(let data) = response else {
            XCTFail("Expected .ok")
            return
        }
        XCTAssertEqual(data, "")
    }

    func testParseErrorResponse() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("ERR:Invalid command")
        guard case .response(let response) = result else {
            XCTFail("Expected response, got \(result)")
            return
        }
        guard case .error(let message) = response else {
            XCTFail("Expected .error, got \(response)")
            return
        }
        XCTAssertEqual(message, "Invalid command")
    }

    func testParseBreakpointEvent() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("EVENT:breakpoint $0600 A=$50 X=$10 Y=$00 S=$FF P=$30")
        guard case .event(let event) = result else {
            XCTFail("Expected event, got \(result)")
            return
        }
        guard case .breakpoint(let address, _, _, _, _, _) = event else {
            XCTFail("Expected .breakpoint, got \(event)")
            return
        }
        XCTAssertEqual(address, 0x0600)
    }

    func testParseStoppedEvent() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("EVENT:stopped $E000")
        guard case .event(let event) = result else {
            XCTFail("Expected event, got \(result)")
            return
        }
        guard case .stopped(let address) = event else {
            XCTFail("Expected .stopped, got \(event)")
            return
        }
        XCTAssertEqual(address, 0xE000)
    }

    func testParseErrorEvent() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("EVENT:error Something went wrong")
        guard case .event(let event) = result else {
            XCTFail("Expected event, got \(result)")
            return
        }
        guard case .error(let message) = event else {
            XCTFail("Expected .error, got \(event)")
            return
        }
        XCTAssertEqual(message, "Something went wrong")
    }

    func testParseUnexpectedResponse() {
        let parser = CLIResponseParser()
        XCTAssertThrowsError(try parser.parse("UNEXPECTED:data")) { error in
            guard case CLIProtocolError.unexpectedResponse = error else {
                XCTFail("Expected unexpectedResponse error, got \(error)")
                return
            }
        }
    }

    func testParseResponseWithWhitespace() throws {
        let parser = CLIResponseParser()
        let result = try parser.parse("  OK:data  ")
        guard case .response(let response) = result else {
            XCTFail("Expected response")
            return
        }
        guard case .ok(let data) = response else {
            XCTFail("Expected .ok")
            return
        }
        XCTAssertEqual(data, "data")
    }

    // =========================================================================
    // MARK: - CLIProtocolError Tests
    // =========================================================================

    func testErrorDescriptions() {
        XCTAssertEqual(CLIProtocolError.lineTooLong.errorDescription, "Line too long")
        XCTAssertEqual(CLIProtocolError.invalidCommand("foo").errorDescription, "Invalid command 'foo'")
        XCTAssertEqual(CLIProtocolError.invalidAddress("xyz").errorDescription, "Invalid address 'xyz'")
        XCTAssertEqual(CLIProtocolError.invalidCount("abc").errorDescription, "Invalid count 'abc'")
        XCTAssertEqual(CLIProtocolError.invalidByte("GG").errorDescription, "Invalid byte value 'GG'")
        XCTAssertEqual(CLIProtocolError.invalidStepCount("0").errorDescription, "Invalid step count '0'")
        XCTAssertEqual(CLIProtocolError.invalidResetType("hot").errorDescription, "Invalid reset type 'hot'")
        XCTAssertEqual(CLIProtocolError.invalidRegister("Z").errorDescription, "Invalid register 'Z'")
        XCTAssertEqual(CLIProtocolError.invalidRegisterFormat("A50").errorDescription, "Invalid register format 'A50'")
        XCTAssertEqual(CLIProtocolError.invalidValue("xxx").errorDescription, "Invalid value 'xxx'")
        XCTAssertEqual(CLIProtocolError.invalidDriveNumber("0").errorDescription, "Invalid drive number '0'")
        XCTAssertEqual(CLIProtocolError.missingArgument("test").errorDescription, "test")
        XCTAssertEqual(CLIProtocolError.connectionFailed("reason").errorDescription, "Connection failed: reason")
        XCTAssertEqual(CLIProtocolError.timeout.errorDescription, "Command timed out")
        XCTAssertEqual(CLIProtocolError.socketNotFound.errorDescription, "No server socket found")
        XCTAssertEqual(CLIProtocolError.unexpectedResponse("data").errorDescription, "Unexpected response: data")
    }

    func testErrorCLIResponse() {
        let error = CLIProtocolError.invalidCommand("test")
        let response = error.cliResponse
        guard case .error(let message) = response else {
            XCTFail("Expected .error response")
            return
        }
        XCTAssertEqual(message, "Invalid command 'test'")
    }

    // =========================================================================
    // MARK: - CLICommandParser Tests - DOS Commands
    // =========================================================================

    func testParseDosChangeDrive() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos cd 2")
        guard case .dosChangeDrive(let drive) = command else {
            XCTFail("Expected .dosChangeDrive, got \(command)")
            return
        }
        XCTAssertEqual(drive, 2)
    }

    func testParseDosChangeDriveInvalid() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos cd 0")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    func testParseDosChangeDriveTooHigh() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos cd 9")) { error in
            guard case CLIProtocolError.invalidDriveNumber = error else {
                XCTFail("Expected invalidDriveNumber error, got \(error)")
                return
            }
        }
    }

    func testParseDosChangeDriveMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos cd")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosDirectoryNoPattern() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos dir")
        guard case .dosDirectory(let pattern) = command else {
            XCTFail("Expected .dosDirectory, got \(command)")
            return
        }
        XCTAssertNil(pattern)
    }

    func testParseDosDirectoryWithPattern() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos dir *.COM")
        guard case .dosDirectory(let pattern) = command else {
            XCTFail("Expected .dosDirectory, got \(command)")
            return
        }
        XCTAssertEqual(pattern, "*.COM")
    }

    func testParseDosFileInfo() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos info AUTORUN.SYS")
        guard case .dosFileInfo(let filename) = command else {
            XCTFail("Expected .dosFileInfo, got \(command)")
            return
        }
        XCTAssertEqual(filename, "AUTORUN.SYS")
    }

    func testParseDosFileInfoMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos info")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosType() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos type README.TXT")
        guard case .dosType(let filename) = command else {
            XCTFail("Expected .dosType, got \(command)")
            return
        }
        XCTAssertEqual(filename, "README.TXT")
    }

    func testParseDosTypeMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos type")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosDump() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos dump GAME.XEX")
        guard case .dosDump(let filename) = command else {
            XCTFail("Expected .dosDump, got \(command)")
            return
        }
        XCTAssertEqual(filename, "GAME.XEX")
    }

    func testParseDosDumpMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos dump")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosCopy() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos copy D1:GAME.BAS D2:GAME.BAS")
        guard case .dosCopy(let source, let destination) = command else {
            XCTFail("Expected .dosCopy, got \(command)")
            return
        }
        XCTAssertEqual(source, "D1:GAME.BAS")
        XCTAssertEqual(destination, "D2:GAME.BAS")
    }

    func testParseDosCopyMissingDest() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos copy D1:FILE")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosCopyMissingBoth() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos copy")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosRename() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos rename OLDNAME.BAS NEWNAME.BAS")
        guard case .dosRename(let oldName, let newName) = command else {
            XCTFail("Expected .dosRename, got \(command)")
            return
        }
        XCTAssertEqual(oldName, "OLDNAME.BAS")
        XCTAssertEqual(newName, "NEWNAME.BAS")
    }

    func testParseDosRenameMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos rename ONLYNAME")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosDelete() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos delete TEMP.DAT")
        guard case .dosDelete(let filename) = command else {
            XCTFail("Expected .dosDelete, got \(command)")
            return
        }
        XCTAssertEqual(filename, "TEMP.DAT")
    }

    func testParseDosDeleteAlias() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos del TEMP.DAT")
        guard case .dosDelete(let filename) = command else {
            XCTFail("Expected .dosDelete, got \(command)")
            return
        }
        XCTAssertEqual(filename, "TEMP.DAT")
    }

    func testParseDosDeleteMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos delete")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosLock() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos lock GAME.BAS")
        guard case .dosLock(let filename) = command else {
            XCTFail("Expected .dosLock, got \(command)")
            return
        }
        XCTAssertEqual(filename, "GAME.BAS")
    }

    func testParseDosLockMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos lock")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosUnlock() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos unlock GAME.BAS")
        guard case .dosUnlock(let filename) = command else {
            XCTFail("Expected .dosUnlock, got \(command)")
            return
        }
        XCTAssertEqual(filename, "GAME.BAS")
    }

    func testParseDosUnlockMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos unlock")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosExport() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos export GAME.BAS /tmp/game.bas")
        guard case .dosExport(let filename, let hostPath) = command else {
            XCTFail("Expected .dosExport, got \(command)")
            return
        }
        XCTAssertEqual(filename, "GAME.BAS")
        XCTAssertEqual(hostPath, "/tmp/game.bas")
    }

    func testParseDosExportTildeExpansion() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos export GAME.BAS ~/games/game.bas")
        guard case .dosExport(let filename, let hostPath) = command else {
            XCTFail("Expected .dosExport, got \(command)")
            return
        }
        XCTAssertEqual(filename, "GAME.BAS")
        XCTAssertFalse(hostPath.hasPrefix("~"), "Tilde should be expanded")
        XCTAssertTrue(hostPath.hasSuffix("games/game.bas"))
    }

    func testParseDosExportMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos export GAME.BAS")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosImport() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos import /tmp/game.bas GAME.BAS")
        guard case .dosImport(let hostPath, let filename) = command else {
            XCTFail("Expected .dosImport, got \(command)")
            return
        }
        XCTAssertEqual(hostPath, "/tmp/game.bas")
        XCTAssertEqual(filename, "GAME.BAS")
    }

    func testParseDosImportTildeExpansion() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos import ~/data/file.dat MYFILE.DAT")
        guard case .dosImport(let hostPath, let filename) = command else {
            XCTFail("Expected .dosImport, got \(command)")
            return
        }
        XCTAssertFalse(hostPath.hasPrefix("~"), "Tilde should be expanded")
        XCTAssertTrue(hostPath.hasSuffix("data/file.dat"))
        XCTAssertEqual(filename, "MYFILE.DAT")
    }

    func testParseDosImportMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos import /tmp/file")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosNewDisk() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos newdisk /tmp/blank.atr")
        guard case .dosNewDisk(let path, let type) = command else {
            XCTFail("Expected .dosNewDisk, got \(command)")
            return
        }
        XCTAssertEqual(path, "/tmp/blank.atr")
        XCTAssertNil(type)
    }

    func testParseDosNewDiskWithType() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos newdisk /tmp/blank.atr dd")
        guard case .dosNewDisk(let path, let type) = command else {
            XCTFail("Expected .dosNewDisk, got \(command)")
            return
        }
        XCTAssertEqual(path, "/tmp/blank.atr")
        XCTAssertEqual(type, "dd")
    }

    func testParseDosNewDiskTildeExpansion() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos newdisk ~/disks/new.atr ed")
        guard case .dosNewDisk(let path, let type) = command else {
            XCTFail("Expected .dosNewDisk, got \(command)")
            return
        }
        XCTAssertFalse(path.hasPrefix("~"), "Tilde should be expanded")
        XCTAssertTrue(path.hasSuffix("disks/new.atr"))
        XCTAssertEqual(type, "ed")
    }

    func testParseDosNewDiskMissing() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos newdisk")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosFormat() throws {
        let parser = CLICommandParser()
        let command = try parser.parse("dos format")
        guard case .dosFormat = command else {
            XCTFail("Expected .dosFormat, got \(command)")
            return
        }
    }

    func testParseDosNoSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos")) { error in
            guard case CLIProtocolError.missingArgument = error else {
                XCTFail("Expected missingArgument error, got \(error)")
                return
            }
        }
    }

    func testParseDosInvalidSubcommand() {
        let parser = CLICommandParser()
        XCTAssertThrowsError(try parser.parse("dos badcommand")) { error in
            guard case CLIProtocolError.invalidCommand = error else {
                XCTFail("Expected invalidCommand error, got \(error)")
                return
            }
        }
    }

    func testParseDosCommandCaseInsensitive() throws {
        let parser = CLICommandParser()
        // "DIR", "dir", "Dir" should all parse correctly
        let cmd1 = try parser.parse("dos DIR")
        let cmd2 = try parser.parse("dos dir")
        let cmd3 = try parser.parse("dos Dir")
        guard case .dosDirectory = cmd1,
              case .dosDirectory = cmd2,
              case .dosDirectory = cmd3 else {
            XCTFail("All should be .dosDirectory")
            return
        }
    }
}
