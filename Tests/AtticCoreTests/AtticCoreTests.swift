// =============================================================================
// AtticCoreTests.swift - Unit Tests for AtticCore
// =============================================================================
//
// This file contains unit tests for the AtticCore library.
// Tests are written using Swift's XCTest framework.
//
// Running tests:
//   swift test                    Run all tests
//   swift test --filter CPU       Run tests containing "CPU"
//
// Test Organization:
// - Each test class focuses on a specific component
// - Test methods are named: test_<feature>_<scenario>_<expectedResult>
// - Use setUp() and tearDown() for common initialization
//
// These are basic tests for Phase 1. More comprehensive tests will be
// added as features are implemented.
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - AtticCore Tests
// =============================================================================

/// Tests for the main AtticCore module.
final class AtticCoreTests: XCTestCase {
    /// Test that version information is available.
    func test_version_isNonEmpty() {
        XCTAssertFalse(AtticCore.version.isEmpty)
        XCTAssertTrue(AtticCore.version.contains("."))  // Should be semantic version
    }

    /// Test that the welcome banner is generated correctly.
    func test_welcomeBanner_containsAppName() {
        let banner = AtticCore.welcomeBanner
        XCTAssertTrue(banner.contains(AtticCore.appName))
        XCTAssertTrue(banner.contains("Atari 800 XL"))
    }

    /// Test full title includes version.
    func test_fullTitle_includesVersion() {
        let title = AtticCore.fullTitle
        XCTAssertTrue(title.contains(AtticCore.version))
        XCTAssertTrue(title.contains(AtticCore.appName))
    }
}

// =============================================================================
// MARK: - CPURegisters Tests
// =============================================================================

/// Tests for the CPURegisters struct.
final class CPURegistersTests: XCTestCase {
    /// Test default initialization.
    func test_init_defaultValues() {
        let regs = CPURegisters()

        XCTAssertEqual(regs.a, 0)
        XCTAssertEqual(regs.x, 0)
        XCTAssertEqual(regs.y, 0)
        XCTAssertEqual(regs.s, 0xFF)  // Stack starts at top
        XCTAssertEqual(regs.pc, 0)
    }

    /// Test custom initialization.
    func test_init_customValues() {
        let regs = CPURegisters(a: 0x42, x: 0x10, y: 0x20, s: 0xF0, p: 0x30, pc: 0x0600)

        XCTAssertEqual(regs.a, 0x42)
        XCTAssertEqual(regs.x, 0x10)
        XCTAssertEqual(regs.y, 0x20)
        XCTAssertEqual(regs.s, 0xF0)
        XCTAssertEqual(regs.p, 0x30)
        XCTAssertEqual(regs.pc, 0x0600)
    }

    /// Test flag accessors.
    func test_flags_carryFlag() {
        var regs = CPURegisters()

        // Initially clear
        XCTAssertFalse(regs.carry)

        // Set carry
        regs.carry = true
        XCTAssertTrue(regs.carry)
        XCTAssertEqual(regs.p & CPURegisters.Flag.carry, CPURegisters.Flag.carry)

        // Clear carry
        regs.carry = false
        XCTAssertFalse(regs.carry)
    }

    /// Test flag accessors - zero flag.
    func test_flags_zeroFlag() {
        var regs = CPURegisters()

        regs.zero = true
        XCTAssertTrue(regs.zero)

        regs.zero = false
        XCTAssertFalse(regs.zero)
    }

    /// Test flag accessors - negative flag.
    func test_flags_negativeFlag() {
        var regs = CPURegisters()

        regs.negative = true
        XCTAssertTrue(regs.negative)
        XCTAssertTrue(regs.isFlagSet(CPURegisters.Flag.negative))
    }

    /// Test formatted output.
    func test_formatted_correctFormat() {
        let regs = CPURegisters(a: 0x42, x: 0x10, y: 0x20, s: 0xF0, p: 0x30, pc: 0x0600)
        let formatted = regs.formatted

        XCTAssertTrue(formatted.contains("A=$42"))
        XCTAssertTrue(formatted.contains("X=$10"))
        XCTAssertTrue(formatted.contains("Y=$20"))
        XCTAssertTrue(formatted.contains("S=$F0"))
        XCTAssertTrue(formatted.contains("P=$30"))
        XCTAssertTrue(formatted.contains("PC=$0600"))
    }

    /// Test flags formatted output.
    func test_flagsFormatted_correctLength() {
        let regs = CPURegisters()
        let flags = regs.flagsFormatted

        // Should always be 8 characters
        XCTAssertEqual(flags.count, 8)
    }

    /// Test flags formatted with specific flags set.
    func test_flagsFormatted_withFlagsSet() {
        var regs = CPURegisters()
        regs.negative = true
        regs.zero = true
        regs.carry = true

        let flags = regs.flagsFormatted

        XCTAssertEqual(flags.first, "N")  // Negative set
        XCTAssertTrue(flags.contains("Z"))  // Zero set
        XCTAssertEqual(flags.last, "C")  // Carry set
    }

    /// Test Equatable conformance.
    func test_equatable_sameValues() {
        let regs1 = CPURegisters(a: 0x42, x: 0x10, y: 0x20, s: 0xF0, p: 0x30, pc: 0x0600)
        let regs2 = CPURegisters(a: 0x42, x: 0x10, y: 0x20, s: 0xF0, p: 0x30, pc: 0x0600)

        XCTAssertEqual(regs1, regs2)
    }

    /// Test Equatable - different values.
    func test_equatable_differentValues() {
        let regs1 = CPURegisters(a: 0x42)
        let regs2 = CPURegisters(a: 0x43)

        XCTAssertNotEqual(regs1, regs2)
    }
}

// =============================================================================
// MARK: - REPLMode Tests
// =============================================================================

/// Tests for the REPLMode enum.
final class REPLModeTests: XCTestCase {
    /// Test monitor prompt format.
    func test_prompt_monitor() {
        let mode = REPLMode.monitor
        let prompt = mode.prompt(pc: 0xE477)

        XCTAssertTrue(prompt.hasPrefix("[monitor]"))
        XCTAssertTrue(prompt.contains("$E477"))
        XCTAssertTrue(prompt.hasSuffix("> "))
    }

    /// Test BASIC prompt format.
    func test_prompt_basic() {
        let mode = REPLMode.basic(variant: .atari)
        let prompt = mode.prompt()

        XCTAssertEqual(prompt, "[basic] > ")
    }

    /// Test Turbo BASIC prompt format.
    func test_prompt_turboBasic() {
        let mode = REPLMode.basic(variant: .turbo)
        let prompt = mode.prompt()

        XCTAssertTrue(prompt.contains("turbo"))
    }

    /// Test DOS prompt format.
    func test_prompt_dos() {
        let mode = REPLMode.dos
        let prompt = mode.prompt(drive: 2)

        XCTAssertTrue(prompt.hasPrefix("[dos]"))
        XCTAssertTrue(prompt.contains("D2:"))
        XCTAssertTrue(prompt.hasSuffix("> "))
    }

    /// Test mode parsing - monitor.
    func test_from_monitor() {
        let mode = REPLMode.from(command: ".monitor")
        XCTAssertEqual(mode, .monitor)
    }

    /// Test mode parsing - basic.
    func test_from_basic() {
        let mode = REPLMode.from(command: ".basic")
        XCTAssertEqual(mode, .basic(variant: .atari))
    }

    /// Test mode parsing - turbo basic.
    func test_from_turboBasic() {
        let mode = REPLMode.from(command: ".basic turbo")
        XCTAssertEqual(mode, .basic(variant: .turbo))
    }

    /// Test mode parsing - dos.
    func test_from_dos() {
        let mode = REPLMode.from(command: ".dos")
        XCTAssertEqual(mode, .dos)
    }

    /// Test mode parsing - invalid.
    func test_from_invalid() {
        let mode = REPLMode.from(command: ".invalid")
        XCTAssertNil(mode)
    }

    /// Test default mode.
    func test_default() {
        let mode = REPLMode.default
        XCTAssertEqual(mode, .basic(variant: .atari))
    }
}

// =============================================================================
// MARK: - CommandParser Tests
// =============================================================================

/// Tests for the CommandParser.
final class CommandParserTests: XCTestCase {
    var parser: CommandParser!

    override func setUp() {
        super.setUp()
        parser = CommandParser()
    }

    /// Test parsing empty input throws error.
    func test_parse_emptyInput_throws() {
        XCTAssertThrowsError(try parser.parse("", mode: .monitor))
        XCTAssertThrowsError(try parser.parse("   ", mode: .monitor))
    }

    /// Test parsing global command - help.
    func test_parse_help() throws {
        let cmd = try parser.parse(".help", mode: .monitor)

        if case .help(let topic) = cmd {
            XCTAssertNil(topic)
        } else {
            XCTFail("Expected help command")
        }
    }

    /// Test parsing global command - help with topic.
    func test_parse_helpWithTopic() throws {
        let cmd = try parser.parse(".help registers", mode: .monitor)

        if case .help(let topic) = cmd {
            XCTAssertEqual(topic, "registers")
        } else {
            XCTFail("Expected help command with topic")
        }
    }

    /// Test parsing mode switch.
    func test_parse_modeSwitch() throws {
        let cmd = try parser.parse(".monitor", mode: .basic(variant: .atari))

        if case .switchMode(let mode) = cmd {
            XCTAssertEqual(mode, .monitor)
        } else {
            XCTFail("Expected switchMode command")
        }
    }

    /// Test parsing monitor step command.
    func test_parse_step() throws {
        let cmd = try parser.parse("s 5", mode: .monitor)

        if case .step(let count) = cmd {
            XCTAssertEqual(count, 5)
        } else {
            XCTFail("Expected step command")
        }
    }

    /// Test parsing BASIC line entry.
    func test_parse_basicLine() throws {
        let cmd = try parser.parse("10 PRINT \"HELLO\"", mode: .basic(variant: .atari))

        if case .basicLine(let number, let content) = cmd {
            XCTAssertEqual(number, 10)
            XCTAssertEqual(content, "PRINT \"HELLO\"")
        } else {
            XCTFail("Expected basicLine command")
        }
    }

    /// Test parsing DOS directory command.
    func test_parse_dosDir() throws {
        let cmd = try parser.parse("dir *.COM", mode: .dos)

        if case .dosDirectory(let pattern) = cmd {
            XCTAssertEqual(pattern, "*.COM")
        } else {
            XCTFail("Expected dosDirectory command")
        }
    }
}

// =============================================================================
// MARK: - Error Tests
// =============================================================================

/// Tests for AtticError.
final class AtticErrorTests: XCTestCase {
    /// Test error description for romNotFound.
    func test_errorDescription_romNotFound() {
        let error = AtticError.romNotFound("/path/to/rom")
        XCTAssertTrue(error.errorDescription?.contains("/path/to/rom") ?? false)
    }

    /// Test error description for invalidCommand.
    func test_errorDescription_invalidCommand() {
        let error = AtticError.invalidCommand("xyz", suggestion: "Did you mean abc?")
        let desc = error.errorDescription ?? ""

        XCTAssertTrue(desc.contains("xyz"))
        XCTAssertTrue(desc.contains("Did you mean abc?"))
    }

    /// Test error description for invalidCommand without suggestion.
    func test_errorDescription_invalidCommandNoSuggestion() {
        let error = AtticError.invalidCommand("xyz", suggestion: nil)
        let desc = error.errorDescription ?? ""

        XCTAssertTrue(desc.contains("xyz"))
        XCTAssertFalse(desc.contains("suggestion"))
    }
}
