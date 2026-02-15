# Makefile for Attic – build, test, and package targets
#
# The full test suite (~1120 tests) takes ~61s. Most of that time is spent in
# integration tests that launch subprocesses or open network connections.
# This Makefile provides focused targets so you can get fast feedback during
# development and only run the full suite when needed.
#
# Usage:
#   make app          # Build Attic.app bundle (release)
#   make clean-app    # Remove build/ directory
#   make test-smoke   # Fast feedback (~3s) – skips slow integration suites
#   make test-basic   # Just BASIC tokenizer/detokenizer tests
#   make test         # Full suite (~61s)
#
# See docs/TESTING.md for detailed test categorization.

.PHONY: app clean-app kill-stale \
        test test-smoke test-unit \
        test-protocol test-cli test-basic test-asm test-atr test-core test-state test-server test-perf test-error test-multiclient

# ---------------------------------------------------------------------------
# Pre-test cleanup
# ---------------------------------------------------------------------------

## Kill orphan Attic processes and remove stale sockets before running tests.
## Prevents hangs caused by leftover AtticServer/xctest processes from
## interrupted previous runs holding ports or socket files.
kill-stale:
	@for name in AtticServer AtticGUI attic; do \
		pids=$$(pgrep -x "$$name" 2>/dev/null); \
		if [ -n "$$pids" ]; then \
			echo "[kill-stale] Terminating $$name (PIDs: $$pids)"; \
			kill -TERM $$pids 2>/dev/null; \
		fi; \
	done
	@sleep 0.5
	@for name in AtticServer AtticGUI attic; do \
		pids=$$(pgrep -x "$$name" 2>/dev/null); \
		if [ -n "$$pids" ]; then \
			echo "[kill-stale] $$name still running, sending SIGKILL (PIDs: $$pids)"; \
			kill -KILL $$pids 2>/dev/null; \
		fi; \
	done
	@rm -f /tmp/attic-*.sock

# ---------------------------------------------------------------------------
# App bundle
# ---------------------------------------------------------------------------

## Build Attic.app in build/ (release configuration)
app:
	./scripts/make-app.sh

## Remove the build/ directory (app bundle and generated icon)
clean-app:
	rm -rf build

# ---------------------------------------------------------------------------
# Full suite
# ---------------------------------------------------------------------------

## Run the complete test suite (~61s, 1170+ tests)
test: kill-stale
	swift test

# ---------------------------------------------------------------------------
# Smoke / unit targets
# ---------------------------------------------------------------------------

## Fast smoke tests – skip the 15 slowest integration suites (~3s)
test-smoke: kill-stale
	swift test \
		--skip CLISocketIntegrationTests \
		--skip AtticServerSubprocessTests \
		--skip CLIAdvancedCommandTests \
		--skip AESPMessageTypeE2ETests \
		--skip CLICommandFormattingTests \
		--skip CLIMemoryCommandTests \
		--skip AESPErrorHandlingE2ETests \
		--skip AESPClientCommandTests \
		--skip AESPClientSubscriptionTests \
		--skip AESPClientInputTests \
		--skip AESPControlChannelE2ETests \
		--skip AESPAudioChannelE2ETests \
		--skip AESPVideoChannelE2ETests \
		--skip AESPMultipleGUIClientTests \
		--skip AESPCLIAndGUITogetherTests

## Pure unit tests only – skip ALL integration & E2E suites (~2s)
test-unit: kill-stale
	swift test \
		--skip CLISocketIntegrationTests \
		--skip AtticServerSubprocessTests \
		--skip CLIAdvancedCommandTests \
		--skip AESPMessageTypeE2ETests \
		--skip CLICommandFormattingTests \
		--skip CLIMemoryCommandTests \
		--skip AESPErrorHandlingE2ETests \
		--skip AESPClientCommandTests \
		--skip AESPClientSubscriptionTests \
		--skip AESPClientInputTests \
		--skip AESPControlChannelE2ETests \
		--skip AESPAudioChannelE2ETests \
		--skip AESPVideoChannelE2ETests \
		--skip AESPServerClientTests \
		--skip AESPClientConnectionOptionsTests \
		--skip AESPClientStreamTests \
		--skip AESPServerLifecycleTests \
		--skip AESPClientStateTests \
		--skip AESPVideoBroadcastTests \
		--skip AESPAudioBroadcastTests \
		--skip AESPMessageBroadcastTests \
		--skip AESPServerDelegateTests \
		--skip AESPChannelTests \
		--skip AtticCLISubprocessTests \
		--skip AESPMultipleGUIClientTests \
		--skip AESPCLIAndGUITogetherTests

# ---------------------------------------------------------------------------
# Feature-area targets
# ---------------------------------------------------------------------------

## AESP protocol tests – message encoding, server, client, E2E (~15s)
test-protocol: kill-stale
	swift test --filter 'AtticProtocolTests'

## CLI parsing, socket, and subprocess tests (~37s)
test-cli: kill-stale
	swift test --filter 'CLI|AtticServerSubprocess|AtticCLISubprocess'

## BASIC tokenizer and detokenizer (<1s)
test-basic:
	swift test --filter 'BASIC'

## Assembler, disassembler, 6502, monitor/debugger (<1s)
test-asm:
	swift test --filter 'Assembler|Disassembl|Opcode|CPUFlags|AddressingMode|ExpressionParser|SymbolTable|ParsedOperand|AssemblyResult|MonitorOpcodeTable|MonitorOpcodeInfo|InteractiveAssembler|BreakpointManager|BreakpointError|MonitorStepResult|MonitorStepLogic'

## ATR filesystem tests (<1s)
test-atr:
	swift test --filter 'ATR|DirectoryEntry|DiskType|SectorLink|VTOC'

## Core emulator types and frame rate (<1s)
test-core:
	swift test --filter 'AtticCoreTests|CPURegisters|REPLMode|CommandParser|AtticError|AtariScreen|InputState|FrameResult|AudioConfiguration|StateTags|StateFlags|EmulatorState|LibAtari800Wrapper|EmulatorEngine|FrameRate|StatePersistence|StateSaveIntegration|StateLoadIntegration|StateIntegrityIntegration|StateCommandParsing|FrameRatePerformance|AudioLatencyPerformance|MemoryUsagePerformance|MissingROMs|InvalidFiles|NetworkErrors'

## State persistence save/load/integrity (<1s)
test-state:
	swift test --filter 'StatePersistence|StateSaveIntegration|StateLoadIntegration|StateIntegrityIntegration|StateCommandParsing'

## AtticServer subprocess tests (~7s)
test-server: kill-stale
	swift test --filter 'AtticServerSubprocess'

## Performance tests – frame rate, audio latency, memory usage (<1s)
test-perf:
	swift test --filter 'FrameRatePerformance|AudioLatencyPerformance|MemoryUsagePerformance'

## Error handling tests – missing ROMs, invalid files, network errors (<1s)
test-error:
	swift test --filter 'MissingROMs|InvalidFiles|NetworkErrors'

## Multi-client tests – multiple GUI clients and CLI+GUI together (~12s)
test-multiclient: kill-stale
	swift test --filter 'AESPMultipleGUIClient|AESPCLIAndGUITogether'
