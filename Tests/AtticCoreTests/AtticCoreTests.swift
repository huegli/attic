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

    /// Test error description for initializationFailed.
    func test_errorDescription_initializationFailed() {
        let error = AtticError.initializationFailed("Test init error")
        let desc = error.errorDescription ?? ""

        XCTAssertTrue(desc.contains("initialization"))
        XCTAssertTrue(desc.contains("Test init error"))
    }
}

// =============================================================================
// MARK: - AtariScreen Constants Tests
// =============================================================================

/// Tests for AtariScreen constants.
final class AtariScreenTests: XCTestCase {
    /// Test screen dimensions are correct for visible Atari display.
    func test_dimensions_correct() {
        XCTAssertEqual(AtariScreen.width, 336)
        XCTAssertEqual(AtariScreen.height, 240)
        XCTAssertEqual(AtariScreen.bufferWidth, 384)
        XCTAssertEqual(AtariScreen.visibleX1, 24)
        XCTAssertEqual(AtariScreen.visibleX2, 360)
    }

    /// Test pixel count matches visible dimensions.
    func test_pixelCount_matchesDimensions() {
        XCTAssertEqual(AtariScreen.pixelCount, AtariScreen.width * AtariScreen.height)
        XCTAssertEqual(AtariScreen.pixelCount, 80640)  // 336 * 240
    }

    /// Test BGRA buffer size is correct.
    func test_bgraBufferSize_correctForPixels() {
        // 4 bytes per pixel (BGRA)
        XCTAssertEqual(AtariScreen.bgraBufferSize, AtariScreen.pixelCount * 4)
        XCTAssertEqual(AtariScreen.bgraBufferSize, 322560)  // 336 * 240 * 4
    }
}

// =============================================================================
// MARK: - InputState Tests
// =============================================================================

/// Tests for the InputState struct.
final class InputStateTests: XCTestCase {
    /// Test default initialization.
    func test_init_defaultValues() {
        let input = InputState()

        XCTAssertEqual(input.keyChar, 0)
        XCTAssertEqual(input.keyCode, 0)
        XCTAssertFalse(input.shift)
        XCTAssertFalse(input.control)
        XCTAssertFalse(input.start)
        XCTAssertFalse(input.select)
        XCTAssertFalse(input.option)
    }

    /// Test joystick default values (centered).
    func test_init_joystickCentered() {
        let input = InputState()

        // 0x0F means all directions released (RLDU bits all set)
        XCTAssertEqual(input.joystick0, 0x0F)
        XCTAssertEqual(input.joystick1, 0x0F)
    }

    /// Test trigger default values (not pressed).
    func test_init_triggersReleased() {
        let input = InputState()

        XCTAssertFalse(input.trigger0)
        XCTAssertFalse(input.trigger1)
    }

    /// Test modifying input state.
    func test_mutation_keyboardInput() {
        var input = InputState()

        input.keyChar = 65  // 'A'
        input.shift = true
        input.control = true

        XCTAssertEqual(input.keyChar, 65)
        XCTAssertTrue(input.shift)
        XCTAssertTrue(input.control)
    }

    /// Test modifying console keys.
    func test_mutation_consoleKeys() {
        var input = InputState()

        input.start = true
        input.select = true
        input.option = true

        XCTAssertTrue(input.start)
        XCTAssertTrue(input.select)
        XCTAssertTrue(input.option)
    }

    /// Test modifying joystick state.
    func test_mutation_joystick() {
        var input = InputState()

        // Joystick up (bit 0 clear)
        input.joystick0 = 0x0E
        input.trigger0 = true

        XCTAssertEqual(input.joystick0, 0x0E)
        XCTAssertTrue(input.trigger0)
    }
}

// =============================================================================
// MARK: - FrameResult Tests
// =============================================================================

/// Tests for the FrameResult enum.
final class FrameResultTests: XCTestCase {
    /// Test all cases exist and are distinct.
    func test_allCases() {
        let cases: [FrameResult] = [.ok, .notInitialized, .breakpoint, .cpuCrash, .error]

        // Verify all cases are distinct
        for (i, case1) in cases.enumerated() {
            for (j, case2) in cases.enumerated() {
                if i == j {
                    XCTAssertEqual(String(describing: case1), String(describing: case2))
                } else {
                    XCTAssertNotEqual(String(describing: case1), String(describing: case2))
                }
            }
        }
    }

    /// Test FrameResult is Sendable (compile-time check, just verify usage).
    func test_sendable() {
        let result: FrameResult = .ok
        // If this compiles, FrameResult is Sendable
        Task {
            let _ = result
        }
    }
}

// =============================================================================
// MARK: - AudioConfiguration Tests
// =============================================================================

/// Tests for the AudioConfiguration struct.
final class AudioConfigurationTests: XCTestCase {
    /// Test typical configuration values.
    func test_init_typicalValues() {
        let config = AudioConfiguration(sampleRate: 44100, channels: 1, sampleSize: 16)

        XCTAssertEqual(config.sampleRate, 44100)
        XCTAssertEqual(config.channels, 1)
        XCTAssertEqual(config.sampleSize, 16)
    }

    /// Test stereo configuration.
    func test_init_stereo() {
        let config = AudioConfiguration(sampleRate: 48000, channels: 2, sampleSize: 16)

        XCTAssertEqual(config.channels, 2)
    }

    /// Test 8-bit audio.
    func test_init_8bit() {
        let config = AudioConfiguration(sampleRate: 22050, channels: 1, sampleSize: 8)

        XCTAssertEqual(config.sampleSize, 8)
    }
}

// =============================================================================
// MARK: - StateTags Tests
// =============================================================================

/// Tests for the StateTags struct.
final class StateTagsTests: XCTestCase {
    /// Test default initialization.
    func test_init_defaultValues() {
        let tags = StateTags()

        XCTAssertEqual(tags.size, 0)
        XCTAssertEqual(tags.cpu, 0)
        XCTAssertEqual(tags.pc, 0)
        XCTAssertEqual(tags.baseRam, 0)
        XCTAssertEqual(tags.antic, 0)
        XCTAssertEqual(tags.gtia, 0)
        XCTAssertEqual(tags.pia, 0)
        XCTAssertEqual(tags.pokey, 0)
    }

    /// Test custom values.
    func test_init_customValues() {
        var tags = StateTags()
        tags.size = 1000
        tags.cpu = 100
        tags.pc = 106
        tags.baseRam = 200

        XCTAssertEqual(tags.size, 1000)
        XCTAssertEqual(tags.cpu, 100)
        XCTAssertEqual(tags.pc, 106)
        XCTAssertEqual(tags.baseRam, 200)
    }
}

// =============================================================================
// MARK: - StateFlags Tests
// =============================================================================

/// Tests for the StateFlags struct.
final class StateFlagsTests: XCTestCase {
    /// Test default initialization.
    func test_init_defaultValues() {
        let flags = StateFlags()

        XCTAssertFalse(flags.selfTestEnabled)
        XCTAssertEqual(flags.frameCount, 0)
    }

    /// Test custom values.
    func test_init_customValues() {
        var flags = StateFlags()
        flags.selfTestEnabled = true
        flags.frameCount = 12345

        XCTAssertTrue(flags.selfTestEnabled)
        XCTAssertEqual(flags.frameCount, 12345)
    }
}

// =============================================================================
// MARK: - EmulatorState Tests
// =============================================================================

/// Tests for the EmulatorState struct.
final class EmulatorStateTests: XCTestCase {
    /// Test default initialization.
    func test_init_defaultValues() {
        let state = EmulatorState()

        XCTAssertTrue(state.data.isEmpty)
        XCTAssertEqual(state.tags.size, 0)
        XCTAssertFalse(state.flags.selfTestEnabled)
    }

    /// Test state with data.
    func test_stateWithData() {
        var state = EmulatorState()
        state.data = [1, 2, 3, 4, 5]
        state.tags.size = 5
        state.tags.cpu = 0
        state.tags.pc = 6
        state.flags.frameCount = 100

        XCTAssertEqual(state.data.count, 5)
        XCTAssertEqual(state.tags.size, 5)
        XCTAssertEqual(state.flags.frameCount, 100)
    }
}

// =============================================================================
// MARK: - LibAtari800Wrapper Tests (No ROM Required)
// =============================================================================

/// Tests for LibAtari800Wrapper that don't require ROM files.
final class LibAtari800WrapperTests: XCTestCase {
    /// Test wrapper initialization creates uninitialized state.
    func test_init_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        XCTAssertFalse(wrapper.isInitialized)
    }

    /// Test memory access returns nil/empty when not initialized.
    func test_memoryAccess_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        XCTAssertNil(wrapper.getMemoryPointer())
        XCTAssertEqual(wrapper.readMemory(at: 0x0000), 0)
        XCTAssertTrue(wrapper.readMemoryBlock(at: 0x0000, count: 16).isEmpty)
    }

    /// Test screen access returns nil when not initialized.
    func test_screenAccess_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        XCTAssertNil(wrapper.getScreenPointer())
    }

    /// Test frame buffer returns zeros when not initialized.
    func test_frameBuffer_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        let buffer = wrapper.getFrameBufferBGRA()
        XCTAssertEqual(buffer.count, AtariScreen.bgraBufferSize)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 })
    }

    /// Test executeFrame returns notInitialized.
    func test_executeFrame_notInitialized() {
        let wrapper = LibAtari800Wrapper()
        var input = InputState()

        let result = wrapper.executeFrame(input: &input)
        XCTAssertEqual(String(describing: result), String(describing: FrameResult.notInitialized))
    }

    /// Test getRegisters returns default when not initialized.
    func test_getRegisters_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        let regs = wrapper.getRegisters()
        XCTAssertEqual(regs, CPURegisters())
    }

    /// Test reboot returns false when not initialized.
    func test_reboot_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        XCTAssertFalse(wrapper.reboot())
    }

    /// Test mount/unmount disk when not initialized.
    func test_diskOperations_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        XCTAssertFalse(wrapper.mountDisk(drive: 1, path: "/nonexistent.atr"))
        // unmountDisk doesn't return value, just verify no crash
        wrapper.unmountDisk(drive: 1)
    }

    /// Test audio buffer returns nil when not initialized.
    func test_audioBuffer_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        let (ptr, count) = wrapper.getAudioBuffer()
        XCTAssertNil(ptr)
        XCTAssertEqual(count, 0)
    }

    /// Test saveState returns empty state when not initialized.
    func test_saveState_notInitialized() {
        let wrapper = LibAtari800Wrapper()

        let state = wrapper.saveState()
        XCTAssertTrue(state.data.isEmpty)
    }

    /// Test initialize throws for missing ROM.
    func test_initialize_missingROM() {
        let wrapper = LibAtari800Wrapper()
        let tempDir = FileManager.default.temporaryDirectory

        XCTAssertThrowsError(try wrapper.initialize(romPath: tempDir)) { error in
            XCTAssertTrue(error is AtticError)
            if case AtticError.romNotFound = error {
                // Expected
            } else {
                XCTFail("Expected romNotFound error")
            }
        }
    }

    /// Test drive number validation.
    func test_mountDisk_invalidDriveNumber() {
        let wrapper = LibAtari800Wrapper()

        // Drive numbers must be 1-8
        XCTAssertFalse(wrapper.mountDisk(drive: 0, path: "/test.atr"))
        XCTAssertFalse(wrapper.mountDisk(drive: 9, path: "/test.atr"))
    }
}

// =============================================================================
// MARK: - EmulatorEngine Tests (No ROM Required)
// =============================================================================

/// Tests for EmulatorEngine that don't require ROM files.
final class EmulatorEngineTests: XCTestCase {
    /// Test engine initial state.
    func test_init_defaultState() async {
        let engine = EmulatorEngine()

        let state = await engine.state
        XCTAssertEqual(state, .uninitialized)
    }

    /// Test engine is not initialized by default.
    func test_init_notInitialized() async {
        let engine = EmulatorEngine()

        let isInit = await engine.isInitialized
        XCTAssertFalse(isInit)
    }

    /// Test initialize throws for missing ROM.
    func test_initialize_missingROM() async {
        let engine = EmulatorEngine()
        let tempDir = FileManager.default.temporaryDirectory

        do {
            try await engine.initialize(romPath: tempDir)
            XCTFail("Expected error for missing ROM")
        } catch {
            XCTAssertTrue(error is AtticError)
        }
    }

    /// Test getRegisters returns default when not initialized.
    func test_getRegisters_notInitialized() async {
        let engine = EmulatorEngine()

        let regs = await engine.getRegisters()
        XCTAssertEqual(regs, CPURegisters())
    }

    /// Test executeFrame returns notInitialized.
    func test_executeFrame_notInitialized() async {
        let engine = EmulatorEngine()

        let result = await engine.executeFrame()
        XCTAssertEqual(String(describing: result), String(describing: FrameResult.notInitialized))
    }

    /// Test readMemory returns zero when not initialized.
    func test_readMemory_notInitialized() async {
        let engine = EmulatorEngine()

        let value = await engine.readMemory(at: 0x0600)
        XCTAssertEqual(value, 0)
    }

    /// Test readMemoryBlock returns empty when not initialized.
    func test_readMemoryBlock_notInitialized() async {
        let engine = EmulatorEngine()

        let data = await engine.readMemoryBlock(at: 0x0600, count: 16)
        XCTAssertTrue(data.isEmpty)
    }

    /// Test breakpoint operations when not initialized.
    func test_breakpoints_notInitialized() async {
        let engine = EmulatorEngine()

        // Should work even when not initialized
        let added = await engine.setBreakpoint(at: 0x0600)
        XCTAssertTrue(added)

        let bps = await engine.getBreakpoints()
        XCTAssertEqual(bps, [0x0600])

        let cleared = await engine.clearBreakpoint(at: 0x0600)
        XCTAssertTrue(cleared)

        let bpsAfter = await engine.getBreakpoints()
        XCTAssertTrue(bpsAfter.isEmpty)
    }

    /// Test clearAllBreakpoints.
    func test_clearAllBreakpoints() async {
        let engine = EmulatorEngine()

        _ = await engine.setBreakpoint(at: 0x0600)
        _ = await engine.setBreakpoint(at: 0x0700)
        _ = await engine.setBreakpoint(at: 0x0800)

        await engine.clearAllBreakpoints()

        let bps = await engine.getBreakpoints()
        XCTAssertTrue(bps.isEmpty)
    }

    /// Test pause and resume have no effect when not initialized.
    ///
    /// The emulator's pause() and resume() methods only change state
    /// when the emulator has been initialized with ROMs. This test verifies
    /// that calling these methods on an uninitialized engine has no effect.
    func test_pauseResume_notInitialized() async {
        let engine = EmulatorEngine()

        // Initial state is uninitialized
        var state = await engine.state
        XCTAssertEqual(state, .uninitialized)

        // Pause should have no effect when uninitialized
        // (pause() only changes state if currently .running)
        await engine.pause()
        state = await engine.state
        XCTAssertEqual(state, .uninitialized)

        // Resume should have no effect when not initialized
        // (resume() has guard for wrapper.isInitialized)
        await engine.resume()
        state = await engine.state
        XCTAssertEqual(state, .uninitialized)
    }

    /// Test frame buffer when not initialized.
    func test_frameBuffer_notInitialized() async {
        let engine = EmulatorEngine()

        let buffer = await engine.getFrameBuffer()
        XCTAssertEqual(buffer.count, AtariScreen.bgraBufferSize)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 })
    }
}
