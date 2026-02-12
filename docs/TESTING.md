# Test Suite Guide

The Attic project has ~1120 tests across two SPM test targets. The full suite
takes ~61 seconds, but **1012 unit tests finish in ~1.5s** while **108
integration tests consume the remaining ~59.5s** (97.5% of runtime). A
`Makefile` provides focused targets so you can iterate quickly.

## Quick Reference

```bash
make test-smoke   # Fast feedback – skips slow suites        (~3s)
make test-unit    # Pure unit tests only                     (~2s)
make test-basic   # BASIC tokenizer/detokenizer              (<1s)
make test-asm     # Assembler, disassembler, 6502            (<1s)
make test-atr     # ATR filesystem                           (<1s)
make test-core    # Core emulator types + frame rate         (<1s)
make test-protocol# AESP protocol (messages, server, E2E)   (~15s)
make test-cli     # CLI parsing, sockets, subprocesses       (~37s)
make test-server  # AtticServer subprocess tests             (~7s)
make test         # Full suite                               (~61s)
```

## When to Use Each Target

| Situation | Target |
|-----------|--------|
| Editing tokenizer / detokenizer code | `make test-basic` |
| Editing assembler / disassembler code | `make test-asm` |
| Editing ATR filesystem code | `make test-atr` |
| Editing core types (registers, state, frame rate) | `make test-core` |
| Editing AESP protocol or server/client code | `make test-protocol` |
| Editing CLI commands or socket layer | `make test-cli` |
| General development – quick sanity check | `make test-smoke` |
| Pre-commit / CI | `make test` |

## Test Categories

### Unit Tests (~1012 tests, ~1.5s)

Fast, in-process tests with no subprocess or network dependencies.

**AtticCoreTests target:**

| Group | Test Classes | Focus |
|-------|-------------|-------|
| Core types | AtticCoreTests, CPURegistersTests, REPLModeTests, CommandParserTests, AtticErrorTests, AtariScreenTests, InputStateTests, FrameResultTests, AudioConfigurationTests, StateTagsTests, StateFlagsTests, EmulatorStateTests, LibAtari800WrapperTests, EmulatorEngineTests | Emulator type definitions and state |
| BASIC | BASICTokenizerTests, BASICDetokenizerTests | Tokenization round-trips |
| Assembler / Monitor | AssemblerTests, AssemblerPseudoOpTests, AssemblerErrorTests, ExpressionParserTests, SymbolTableTests, BreakpointManagerTests, BreakpointErrorTests, InteractiveAssemblerTests, MonitorStepResultTests, ParsedOperandTests, AssemblyResultTests, MonitorOpcodeTableHelperTests, MonitorOpcodeInfoUsageTests | 6502 assembly and monitor |
| Disassembler | AddressingModeTests, CPUFlagsTests, OpcodeTableTests, DisassembledInstructionTests, AddressLabelsTests, ArrayMemoryBusTests, DisassemblerTests, CLIDisassembleCommandTests | 6502 disassembly |
| ATR filesystem | ATRImageTests, ATRFileSystemTests, DirectoryEntryTests, DiskTypeTests, SectorLinkTests, VTOCTests | Disk image parsing |
| Frame rate | FrameRateMonitorInitTests, FrameRateFPSTests, FrameRateDropTests, FrameRateStatisticsTests, FrameRateRingBufferTests, FrameRateResetTests, FrameRateSustainedTests, FrameRateFPSCounterTests | Performance monitoring |
| State persistence | StatePersistenceTests | Save/load emulator state |
| CLI protocol | CLIProtocolTests | Protocol message types |
| DOS / Monitor commands | ModeSwitchingTests, DOSCommandParserTests, MonitorRegisterCommandTests, HelpAndStatusContentTests, DOSWorkflowTests | DOS and monitor modes |
| Integration (fast) | BASICPipelineIntegrationTests, StatePersistenceIntegrationTests, AssemblerDisassemblerIntegrationTests, ExpressionEvaluatorIntegrationTests | Cross-component in-process tests |

**AtticProtocolTests target (unit portion):**

| Group | Test Classes | Focus |
|-------|-------------|-------|
| Message encoding | AESPConstantsTests, AESPMessageTypeTests, AESPMessageEncodingTests, AESPMessageDecodingTests, AESPMessageRoundtripTests, AESPErrorTests, AESPMessageEquatableTests, AESPMessageBufferTests, AESPMessageDescriptionTests | Binary message format |
| Extended messages | AESPControlMessageExtendedTests, AESPInputMessageExtendedTests, AESPVideoMessageExtendedTests, AESPAudioMessageExtendedTests, AESPProtocolConformanceTests | Additional message types |
| Config | AESPServerConfigurationTests, AESPClientConfigurationTests, AESPSendableTests, AESPServerDelegatePropertyTests | Server/client configuration |

### Integration Tests (~108 tests, ~59.5s)

These tests launch subprocesses, open TCP connections, or perform end-to-end
protocol exchanges. They are skipped by `make test-smoke`.

| Test Class | Time | What it tests |
|-----------|------|---------------|
| CLISocketIntegrationTests | ~25.9s | CLI socket client/server round-trips |
| AtticServerSubprocessTests | ~6.6s | Launching AtticServer as a subprocess |
| CLIAdvancedCommandTests | ~6.1s | Advanced CLI commands via subprocess |
| AESPMessageTypeE2ETests | ~4.0s | End-to-end AESP message exchange |
| CLICommandFormattingTests | ~2.6s | CLI output formatting via subprocess |
| CLIMemoryCommandTests | ~2.3s | Memory read/write commands via subprocess |
| AESPErrorHandlingE2ETests | ~2.3s | Protocol error handling end-to-end |
| AESPClientCommandTests | ~2.4s | Client command dispatch |
| AESPClientSubscriptionTests | ~1.9s | Client subscription lifecycle |
| AESPClientInputTests | ~1.7s | Client input forwarding |
| AESPControlChannelE2ETests | ~1.2s | Control channel end-to-end |
| AESPAudioChannelE2ETests | ~1.1s | Audio channel end-to-end |
| AESPVideoChannelE2ETests | ~0.9s | Video channel end-to-end |

Additional medium-speed integration suites (skipped by `make test-unit` but
included in `make test-smoke`):

- AESPServerClientTests, AESPClientConnectionOptionsTests, AESPClientStreamTests
- AESPServerLifecycleTests, AESPClientStateTests
- AESPVideoBroadcastTests, AESPAudioBroadcastTests, AESPMessageBroadcastTests
- AESPServerDelegateTests, AESPChannelTests
- AtticCLISubprocessTests

## SPM Test Targets

| SPM Target | Path | Contents |
|-----------|------|----------|
| AtticCoreTests | `Tests/AtticCoreTests/` | Core types, BASIC, assembler, disassembler, ATR, CLI, frame rate, state, DOS/monitor |
| AtticProtocolTests | `Tests/AtticProtocolTests/` | AESP messages, server, client, E2E |

## Adding New Tests

- **Fast unit tests**: Add to an existing test file or create a new class in the
  appropriate test target. No changes to the Makefile needed unless you want a
  dedicated feature target.
- **Slow integration tests**: If your new suite launches subprocesses or opens
  network connections, add its class name to the `--skip` lists in the `test-smoke`
  and `test-unit` targets in the Makefile.
