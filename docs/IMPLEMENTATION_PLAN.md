# Implementation Plan

## Overview

This document outlines the implementation phases for the Atari 800 XL emulator project. Phases 1-16 are complete and constitute the MVP. For future implementation phases (17-19) and deferred features, see [FUTURE_IMPLEMENTATION.md](FUTURE_IMPLEMENTATION.md).

## Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Project Foundation | Complete |
| 2 | Emulator Core | Complete |
| 3 | Metal Renderer | Complete |
| 4 | Audio Engine | Complete |
| 5 | Input Handling | Complete (keyboard; joystick deferred) |
| 6 | AESP Protocol Library | Complete |
| 7 | Emulator Server | Complete |
| 8 | GUI as Protocol Client | Complete |
| 9 | CLI Socket Protocol | Complete |
| 10 | 6502 Disassembler | Complete |
| 11 | Monitor Mode | Complete |
| 12 | ATR File System | Complete |
| 13 | DOS Mode | Complete |
| 14 | BASIC Tokenizer | Complete |
| 15 | BASIC Detokenizer & Mode | Complete |
| 16 | State Persistence | Complete |

---

## Phase 1: Project Foundation

**Status:** Complete

**Goal:** Basic project structure and build system.

### Tasks

1. **Create Swift Package**
   ```
   Package.swift with targets:
   - AtticCore (library)
   - AtticProtocol (library)
   - AtticServer (executable)
   - attic (CLI executable)
   - AtticGUI (GUI executable)
   ```

2. **Set up libatari800 integration**
   - Add pre-compiled libatari800 to Libraries/
   - Create module map for C interop
   - Create basic Swift wrapper types

3. **Create stub files for all modules**
   - Empty Swift files with proper structure
   - Basic protocols and types

### Deliverables

- Project builds with `swift build`
- Basic test target runs
- libatari800 headers accessible from Swift

---

## Phase 2: Emulator Core

**Status:** Complete

**Goal:** Emulator runs headless, basic memory access works.

### Tasks

1. **LibAtari800Wrapper**
   ```swift
   class LibAtari800Wrapper {
       func initialize(romPath: URL) throws
       func reset(cold: Bool)
       func executeFrame()
       func readMemory(at: UInt16) -> UInt8
       func writeMemory(at: UInt16, value: UInt8)
       func getRegisters() -> CPURegisters
       func setRegisters(_ registers: CPURegisters)
   }
   ```

2. **EmulatorEngine actor**
   - Wraps LibAtari800Wrapper
   - Manages emulation state (running/paused)
   - Thread-safe memory access

3. **Frame buffer management**
   - Extract pixel data from libatari800
   - Convert to BGRA format

4. **ROM loading**
   - Multi-path ROM discovery
   - ROM validation

### Testing

- Unit tests for memory read/write
- Integration test: cold start and verify known memory values

### Deliverables

- Emulator initializes and runs
- Memory can be read/written
- Registers accessible

---

## Phase 3: Metal Renderer

**Status:** Complete

**Goal:** Emulator output visible on screen.

### Tasks

1. **MetalRenderer class**
   ```swift
   class MetalRenderer {
       func updateTexture(with pixels: Data)
       func render(to view: MTKView)
   }
   ```

2. **Atari palette**
   - 256-color NTSC palette
   - Conversion from indexed to BGRA

3. **MTKView integration**
   - NSViewRepresentable for SwiftUI
   - 60Hz refresh rate

4. **Basic SwiftUI window**
   - Metal view
   - Status bar

### Testing

- Emulator boot sequence visible
- "READY" prompt displays
- Smooth animation (no tearing)

### Deliverables

- GUI app launches and shows emulator output
- Display updates at 60Hz

---

## Phase 4: Audio Engine

**Status:** Complete

**Goal:** Emulator audio output working.

### Tasks

1. **AudioEngine class**
   ```swift
   class AudioEngine {
       func start()
       func stop()
       func enqueueSamples(_ samples: [Float])
       func enqueueSamples(bytes: Data)
   }
   ```

2. **Ring buffer**
   - Lock-free implementation
   - Underrun handling with silence fill

3. **AVAudioEngine setup**
   - Source node for sample generation
   - Proper cleanup on pause/stop

4. **Sample extraction from libatari800**
   - POKEY 16-bit output
   - Conversion to Float for AVAudioEngine

### Testing

- Audio plays without crackling
- Audio syncs with video
- Clean stop/start

### Deliverables

- Boot sound plays
- Keyclick sounds work

---

## Phase 5: Input Handling

**Status:** Complete (keyboard portion)

**Goal:** Keyboard and controller input working.

### Implementation Notes

- Keyboard input complete
- Game controller support deferred to Phase 17

### Tasks Completed

1. **KeyboardHandler**
   - Key mapping table (Mac keyCodes to Atari AKEY_* constants)
   - Function key to special key mapping (F1=START, F2=SELECT, F3=OPTION)
   - Key injection via `input_template_t` structure
   - NSEvent local monitors for reliable event capture

2. **ControlPanelView**
   - START/SELECT/OPTION buttons with press/release handling
   - Buttons reflect keyboard state (highlight when F1/F2/F3 pressed)
   - Status display (running/paused, FPS counter)

3. **Special keys**
   - F1=START, F2=SELECT, F3=OPTION
   - Backtick (`) = ATARI key
   - Arrow keys for cursor movement
   - Shift/Control modifiers forwarded to emulator

4. **Application Activation**
   - `NSApp.setActivationPolicy(.regular)` for proper GUI behavior

### Key Files

- `Sources/AtticCore/Input/KeyboardInputHandler.swift`
- `Sources/AtticGUI/Input/KeyEventView.swift`

### Deliverables

- Full keyboard input
- On-screen console buttons
- Joystick support (deferred)

---

## Phase 6: AESP Protocol Library

**Status:** Complete

**Goal:** Create the Attic Emulator Server Protocol (AESP) for emulator/GUI separation.

### Protocol Architecture

```
┌─────────────────────────────────────┐
│        Emulator Server              │
│    (standalone process)             │
└───────────────┬─────────────────────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐   ┌───▼───┐   ┌───▼───┐
│Control│   │ Video │   │ Audio │
│ 47800 │   │ 47801 │   │ 47802 │
└───────┘   └───────┘   └───────┘
```

### Binary Message Format

```
┌────────┬────────┬────────┬────────┬─────────────┐
│ Magic  │Version │ Type   │ Length │  Payload    │
│0xAE50  │ 0x01   │(1 byte)│(4 byte)│ (variable)  │
└────────┴────────┴────────┴────────┴─────────────┘
   Header (8 bytes)              Payload
```

### Message Types

| Range | Category | Examples |
|-------|----------|----------|
| 0x00-0x3F | Control | PING, PAUSE, RESUME, RESET, STATUS, MEMORY_READ/WRITE |
| 0x40-0x5F | Input | KEY_DOWN, KEY_UP, JOYSTICK, CONSOLE_KEYS |
| 0x60-0x7F | Video | FRAME_RAW, FRAME_DELTA, FRAME_CONFIG |
| 0x80-0x9F | Audio | AUDIO_PCM, AUDIO_CONFIG, AUDIO_SYNC |

### Key Files

- `Sources/AtticProtocol/AESPMessageType.swift`
- `Sources/AtticProtocol/AESPMessage.swift`
- `Sources/AtticProtocol/AESPServer.swift`
- `Sources/AtticProtocol/AESPClient.swift`

### Testing

- Unit tests for message encoding/decoding
- Roundtrip test: encode then decode then verify equality
- Server accepts connections on all ports
- Client can connect and receive streams

### Deliverables

- `AtticProtocol` module with full message support
- Server and client actors ready for integration

---

## Phase 7: Emulator Server

**Status:** Complete

**Goal:** Standalone emulator server process using AESP.

### Tasks

1. **Create `AtticServer` executable**

2. **Server Main Loop**
   - Initialize emulator with ROMs
   - Start AESP server on ports 47800-47802
   - Run emulation at 60fps with precise frame timing
   - Broadcast video/audio to connected clients

3. **Command Handling**
   - Process control messages (pause, resume, reset)
   - Handle input messages (key events, console keys)
   - Respond to memory read/write requests

4. **Frame Broadcasting**
   - Raw BGRA frames (384x240x4 = 368KB)
   - 60fps push to all connected video clients

5. **Audio Broadcasting**
   - Raw 16-bit PCM samples
   - Include timestamps for A/V sync

### Key Files

- `Sources/AtticServer/main.swift`

### Deliverables

- `AtticServer` executable runs emulator headlessly
- Broadcasts video/audio to connected clients

---

## Phase 8: GUI as Protocol Client

**Status:** Complete

**Goal:** AtticGUI becomes a protocol client instead of directly owning EmulatorEngine.

### Implementation Notes

- AtticGUI supports two operation modes: client (default) and embedded
- **Client mode:** Connects to already-running AtticServer on localhost:47800-47802
- **Embedded mode:** Runs EmulatorEngine directly (for debugging), enabled with `--embedded` flag
- Both modes use absolute frame scheduling to maintain precise 60fps timing

### Tasks

1. **Modify AtticViewModel**
   - Client mode: AESPClient connects to external server
   - Embedded mode: Direct EmulatorEngine ownership

2. **Frame Receiver**
   - AsyncStream for frame data
   - Update Metal texture on main thread

3. **Audio Receiver**
   - AsyncStream for audio samples
   - Enqueue to AudioEngine

4. **Input Forwarding**
   - Send KEY_DOWN/KEY_UP via protocol in client mode

### Testing

- Run AtticServer standalone
- Run AtticGUI, verify it connects to server
- GUI shows "No Server" error when server not running
- Display shows emulator output at 60fps
- Audio plays correctly without crackling

### Deliverables

- AtticGUI works as protocol client (default mode)
- AtticGUI works in embedded mode (`--embedded` flag)
- Server-first workflow with clear error messaging

---

## Phase 9: CLI Socket Protocol

**Status:** Complete

**Goal:** CLI can communicate with AtticServer via text-based protocol for REPL.

### Implementation Notes

- CLI connects directly to AtticServer via Unix socket at `/tmp/attic-<pid>.sock`
- Text-based protocol: `CMD:<command>\n` then `OK:<response>\n` or `ERR:<message>\n`
- Multi-line responses use `\x1E` (Record Separator) as delimiter

### Protocol Commands

| Command | Description |
|---------|-------------|
| `ping` | Connection test, returns `OK:pong` |
| `pause` | Pause emulation |
| `resume` | Resume emulation |
| `step [n]` | Step n frames (default: 1) |
| `reset cold/warm` | Reset emulator |
| `status` | Get emulator status |
| `read $XXXX count` | Read memory bytes |
| `write $XXXX XX,XX,...` | Write memory bytes |
| `registers [A=$XX ...]` | Get/set CPU registers |
| `breakpoint set/clear/list` | Manage breakpoints |
| `mount n path` | Mount disk image |
| `state save/load path` | Save/load state |

### Key Files

- `Sources/AtticCore/CLI/CLIProtocol.swift`
- `Sources/AtticCore/CLI/CLISocketServer.swift`
- `Sources/AtticCore/CLI/CLISocketClient.swift`

### Deliverables

- CLI and AtticServer communicate via text protocol
- All control commands work
- Socket discovery and server auto-launch

---

## Phase 10: 6502 Disassembler

**Status:** Complete

**Goal:** Memory can be disassembled.

### Implementation Notes

- Complete opcode table with all 256 6502 opcodes including illegal/undocumented opcodes stable on 6502C (SALLY)
- 13 addressing modes fully supported with operand formatting
- AddressLabels provides symbolic names for hardware registers, OS vectors, zero-page variables

### Tasks

1. **Opcode table**
   - All 6502 instructions
   - Illegal opcodes for 6502C (LAX, SAX, DCP, ISC, SLO, RLA, SRE, RRA, etc.)
   - Addressing modes and byte counts
   - Cycle timing and flag effects

2. **Disassembler**
   ```swift
   struct Disassembler {
       func disassemble(at address: UInt16, memory: MemoryBus) -> DisassembledInstruction
       func disassembleRange(from: UInt16, lines: Int, memory: MemoryBus) -> [DisassembledInstruction]
   }
   ```

3. **Output formatting**
   - Address, bytes, mnemonic, operand
   - Labels for hardware registers, OS vectors
   - Branch target with offset: `BNE $E47A (+5)`

### Key Files

- `Sources/AtticCore/Disassembler/AddressingMode.swift`
- `Sources/AtticCore/Disassembler/OpcodeInfo.swift`
- `Sources/AtticCore/Disassembler/DisassembledInstruction.swift`
- `Sources/AtticCore/Disassembler/AddressLabels.swift`
- `Sources/AtticCore/Disassembler/Disassembler.swift`

### Deliverables

- Disassembly works correctly
- CLI command integration (`d` or `disassemble`)

---

## Phase 11: Monitor Mode

**Status:** Complete

**Goal:** Full debugging capability.

### Implementation Notes

- MAC65-style assembler with full expression and label support
- BreakpointManager with BRK injection (RAM) and PC-polling (ROM)
- Instruction-level stepping via temporary BRK placement

### Tasks

1. **Monitor REPL mode**
   - Commands: g, s, so, pause, until, r, m, >, f, d, a, bp, bc
   - Register display/modify
   - Memory display/modify

2. **Assembler**
   - MAC65-style syntax with all 6502 instructions
   - Expression parser (+, -, *, /, <, >, labels, *, character literals)
   - Pseudo-ops: ORG, DB/BYTE, DW/WORD, DS/BLOCK, HEX, ASC, DCI, END

3. **Breakpoint manager**
   - BRK injection for RAM addresses ($00-$BFFF)
   - PC polling for ROM addresses ($C000+)
   - Original byte tracking and restoration
   - Hit count tracking

4. **Stepping**
   - Single step (s, s N) using temporary BRK after instruction
   - Step over (so) for JSR instructions
   - Run until (until $XXXX)

### Key Files

- `Sources/AtticCore/Monitor/OpcodeTable.swift`
- `Sources/AtticCore/Monitor/Assembler.swift`
- `Sources/AtticCore/Monitor/BreakpointManager.swift`
- `Sources/AtticCore/Monitor/MonitorStepper.swift`
- `Sources/AtticCore/Monitor/MonitorController.swift`

### Deliverables

- Complete monitor functionality
- Full assembler with MAC65 syntax
- Breakpoint manager with RAM/ROM support
- Instruction-level stepping

---

## Phase 12: ATR File System

**Status:** Complete

**Goal:** Read and write ATR disk images.

### Implementation Notes

- Full ATR container format support (header parsing, sector access, multiple densities)
- DOS 2.x and 2.5 filesystem support with VTOC bitmap management
- Full read/write operations including writeFile, deleteFile, renameFile, lockFile, unlockFile

### Disk Types Supported

| Type | Sectors | Sector Size | Capacity |
|------|---------|-------------|----------|
| Single Density (SS/SD) | 720 | 128 | 90KB |
| Enhanced Density (SS/ED) | 1040 | 128 | 130KB |
| Double Density (SS/DD) | 720 | 256 | 180KB |
| Quad Density (DS/DD) | 1440 | 256 | 360KB (read-only) |

### Key Files

- `Sources/AtticCore/Filesystem/ATRError.swift`
- `Sources/AtticCore/Filesystem/DiskType.swift`
- `Sources/AtticCore/Filesystem/SectorLink.swift`
- `Sources/AtticCore/Filesystem/DirectoryEntry.swift`
- `Sources/AtticCore/Filesystem/VTOC.swift`
- `Sources/AtticCore/Filesystem/ATRImage.swift`
- `Sources/AtticCore/Filesystem/ATRFileSystem.swift`

### Testing

- DiskType detection and parsing tests
- SectorLink encoding/decoding round-trip tests
- DirectoryEntry parsing and wildcard matching tests
- VTOC bitmap operations and validation tests
- ATRImage creation, loading, sector access tests
- ATRFileSystem directory listing and file reading tests

### Deliverables

- ATR container format fully supported
- DOS 2.x/2.5 filesystem read/write operations
- Disk image creation and formatting
- Comprehensive test coverage

---

## Phase 13: DOS Mode

**Status:** Complete

**Goal:** Disk management from REPL.

### Implementation Notes

- Uses the consolidated `Filesystem` module
- `DiskManager` actor for thread-safe mounted disk management
- Full file write support with sector allocation

### DOS Commands

| Command | Description |
|---------|-------------|
| `mount` | Mount ATR at drive (1-8) |
| `unmount` | Unmount drive |
| `drives` | Show all drives |
| `cd` | Change current drive |
| `dir` | List directory with wildcards |
| `info` | Show file details |
| `type` | Display text file |
| `dump` | Hex dump file |
| `copy` | Copy files between disks |
| `rename` | Rename file |
| `delete` | Delete file |
| `lock` | Set read-only |
| `unlock` | Clear read-only |
| `export` | Extract to macOS |
| `import` | Import from host filesystem |
| `newdisk` | Create new ATR |
| `format` | Format disk |

### Key Files

- `Sources/AtticCore/Filesystem/DiskManager.swift`
- `Sources/AtticCore/REPL/REPLEngine.swift` (DOS command implementations)

### Deliverables

- Core DOS mode functionality
- ATR parsing and manipulation
- DOS 2.x filesystem read/write support
- Comprehensive test suite

---

## Phase 14: BASIC Tokenizer

**Status:** Complete

**Goal:** Enter BASIC programs via REPL.

### Implementation Notes

- Full Atari BASIC tokenization with all statement and function tokens
- BCD float conversion for numeric constants
- Abbreviation support (PR. = PRINT, etc.)
- Memory layout building for VNTP, VVTP, STMTAB, STMCUR

### Tasks

1. **Lexer**
   - Token recognition
   - Keyword matching (case-insensitive)
   - Abbreviation expansion

2. **Token encoder**
   - Statement tokens (0x00-0x36)
   - Operator tokens (0x12-0x3F)
   - Function tokens (0x00-0x54)
   - BCD float conversion

3. **Memory layout builder**
   - Variable name table (VNTP)
   - Variable value table (VVTP)
   - Statement table (STMTAB)
   - Pointer updates (LOMEM, VNTP, VVTP, STMTAB, STMCUR)

4. **Memory injection**
   - Pause emulator
   - Write tokenized program
   - Update BASIC pointers

### Key Files

- `Sources/AtticCore/BASIC/BASICTokenizer.swift`
- `Sources/AtticCore/BASIC/BASICToken.swift`
- `Sources/AtticCore/BASIC/BASICVariable.swift`
- `Sources/AtticCore/BASIC/BCDFloat.swift`
- `Sources/AtticCore/BASIC/BASICLineHandler.swift`
- `Sources/AtticCore/BASIC/BASICMemoryLayout.swift`

### Testing

- Tokenize simple programs
- Roundtrip: tokenize then detokenize then verify
- Complex programs with all features

### Deliverables

- BASIC tokenization works
- Memory injection into emulator

---

## Phase 15: BASIC Detokenizer & Mode

**Status:** Complete

**Goal:** Complete BASIC mode.

### Implementation Notes

- Token-to-text conversion for all statement, operator, and function tokens
- BCD float to string conversion
- Line number reconstruction from STMTAB
- LIST command support in BASIC mode

### Tasks

1. **Detokenizer**
   - Read from emulator memory
   - Convert tokens to text
   - Reconstruct line numbers

2. **BASIC REPL mode**
   - Line entry (with tokenization)
   - LIST (with detokenization)
   - RUN/NEW/CSAVE/CLOAD

3. **File operations**
   - Import .BAS from host
   - Export .BAS to host

### Key Files

- `Sources/AtticCore/BASIC/BASICDetokenizer.swift`
- `Sources/AtticCore/REPL/REPLEngine.swift` (BASIC mode commands)

### Testing

- Enter program, list it back
- Roundtrip verification
- Edge cases (empty lines, max line numbers)

### Deliverables

- Complete BASIC mode
- LIST/RUN/NEW commands

---

## Phase 16: State Persistence

**Status:** Complete

**Goal:** Save and restore emulator state.

### Implementation Notes

- v2 state file format with JSON metadata section
- StateMetadata captures: timestamp, REPL mode, mounted disk paths (reference only)
- REPL mode is restored when loading state
- Breakpoints are cleared on load (RAM contents change invalidates BRK injections)

### File Format v2

```
┌────────────────────────────────────┐
│ Header (16 bytes)                  │
│   Magic: "ATTC" (4 bytes)          │
│   Version: 0x02 (1 byte)           │
│   Flags: (1 byte)                  │
│   Reserved: (10 bytes)             │
├────────────────────────────────────┤
│ Metadata Length (4 bytes, LE)      │
├────────────────────────────────────┤
│ Metadata (JSON, UTF-8)             │
├────────────────────────────────────┤
│ State Tags (32 bytes)              │
├────────────────────────────────────┤
│ State Flags (8 bytes)              │
├────────────────────────────────────┤
│ libatari800 State Data (~210KB)    │
└────────────────────────────────────┘
```

### Key Files

- `Sources/AtticCore/State/StateMetadata.swift`

### Testing

- Unit tests for metadata encoding/decoding
- Unit tests for file read/write round-trip
- Error handling tests (bad magic, wrong version, truncated)

### Deliverables

- Save states work with full metadata
- REPL mode restored on load
- Clear error messages for invalid files

---

## Dependencies

```
Phase 1 (Foundation)
    │
    ▼
Phase 2 (Emulator Core)
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
Phase 3        Phase 4        Phase 5
(Renderer)     (Audio)        (Input)
    │              │              │
    └──────────────┴──────────────┘
                   │
    ┌──────────────┴──────────────┐
    ▼                             ▼
Phase 6-8 (AESP Protocol)    Phase 9 (CLI Socket)
(Protocol, Server, Client)         │
    │                              │
    └──────────────┬───────────────┘
                   │
    ┌──────────────┴──────────────┐
    ▼                             ▼
Phase 10 (Disasm)            Phase 12 (ATR)
    │                             │
    ▼                             ▼
Phase 11 (Monitor)           Phase 13 (DOS)
    │                             │
    └──────────────┬──────────────┘
                   │
                   ▼
           Phase 14 (Tokenizer)
                   │
                   ▼
           Phase 15 (BASIC Mode)
                   │
                   ▼
           Phase 16 (State)
```

## Milestones

| Milestone | Phases | Description | Status |
|-----------|--------|-------------|--------|
| M1 | 1-5 | Playable emulator with GUI | Complete |
| M2 | 6-8 | Emulator/GUI separation | Complete |
| M3 | 9-11 | Debugging via Emacs | Complete |
| M4 | 12-15 | Full REPL functionality | Complete |
| M5 | 16 | State persistence | Complete |

## Future Work

For future phases (17-19) and deferred features from the MVP, see [FUTURE_IMPLEMENTATION.md](FUTURE_IMPLEMENTATION.md).
