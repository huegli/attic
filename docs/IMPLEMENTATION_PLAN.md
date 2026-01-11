# Implementation Plan

## Overview

This document outlines the recommended implementation order for the Atari 800 XL emulator project. The phases are designed to produce working, testable components at each stage.

## Phase 1: Project Foundation

**Goal:** Basic project structure and build system.

### Tasks

1. **Create Swift Package**
   ```
   Package.swift with three targets:
   - AtticCore (library)
   - attic (cli executable)
   - Attic.app (GUI executable)
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

### Estimated Time: 1-2 days

---

## Phase 2: Emulator Core

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
   - Convert to RGB format

4. **ROM loading**
   - Bundle resource access
   - ROM validation

### Testing

- Unit tests for memory read/write
- Integration test: cold start and verify known memory values
- Frame execution produces expected changes

### Deliverables

- Emulator initializes and runs
- Memory can be read/written
- Registers accessible

### Estimated Time: 3-4 days

---

## Phase 3: Metal Renderer

**Goal:** Emulator output visible on screen.

### Tasks

1. **MetalRenderer class**
   ```swift
   class MetalRenderer {
       func updateTexture(pixels: [UInt8])
       func render(to view: MTKView)
   }
   ```

2. **Atari palette**
   - 256-color NTSC palette
   - Conversion from indexed to RGB

3. **MTKView integration**
   - NSViewRepresentable for SwiftUI
   - Display link for 60Hz refresh

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

### Estimated Time: 2-3 days

---

## Phase 4: Audio Engine

**Goal:** Emulator audio output working.

### Tasks

1. **AudioEngine class**
   ```swift
   class AudioEngine {
       func start()
       func stop()
       func enqueueSamples(_ samples: [Float])
   }
   ```

2. **Ring buffer**
   - Lock-free implementation
   - Underrun handling

3. **AVAudioEngine setup**
   - Source node for sample generation
   - Proper cleanup on pause/stop

4. **Sample extraction from libatari800**
   - POKEY output
   - Resampling if needed

### Testing

- Audio plays without crackling
- Audio syncs with video
- Clean stop/start

### Deliverables

- Boot sound plays
- Keyclick sounds work

### Estimated Time: 2-3 days

---

## Phase 5: Input Handling

**Goal:** Keyboard and controller input working.

### Tasks

1. **KeyboardHandler**
   - Key mapping table
   - Function key to special key mapping
   - Key injection to libatari800

2. **ControlPanelView**
   - START/SELECT/OPTION buttons
   - Status display

3. **GameControllerHandler**
   - GameController framework setup
   - D-pad and button mapping

4. **Special keys**
   - F1=START, F2=SELECT, F3=OPTION
   - Reset handling

### Testing

- Type in BASIC
- Run a simple game
- Controller works

### Deliverables

- Full keyboard input
- On-screen buttons
- Game controller support

### Estimated Time: 2-3 days

---

## Phase 6: Socket Protocol

**Goal:** CLI can communicate with GUI.

### Tasks

1. **SocketServer (GUI side)**
   ```swift
   class SocketServer {
       func start() throws -> URL  // Returns socket path
       func accept() -> SocketClient
       func close()
   }
   ```

2. **SocketClient (CLI side)**
   ```swift
   class SocketClient {
       func connect(to path: URL) throws
       func send(_ command: String) throws
       func receive() throws -> String
       func close()
   }
   ```

3. **Protocol implementation**
   - Command parsing
   - Response formatting
   - Async event handling

4. **GUI launch from CLI**
   - Subprocess management
   - Socket discovery

### Testing

- CLI connects to running GUI
- Commands execute correctly
- Events delivered

### Deliverables

- CLI and GUI communicate
- Basic commands work (ping, pause, resume)

### Estimated Time: 2-3 days

---

## Phase 7: 6502 Disassembler

**Goal:** Memory can be disassembled.

### Tasks

1. **Opcode table**
   - All 6502 instructions
   - Addressing modes
   - Byte counts

2. **Disassembler**
   ```swift
   struct Disassembler {
       func disassemble(at address: UInt16, 
                       memory: MemoryBus) -> DisassembledInstruction
       func disassembleRange(from: UInt16, 
                            lines: Int) -> [DisassembledInstruction]
   }
   ```

3. **Output formatting**
   - Address, bytes, mnemonic, operand
   - Labels for common addresses

### Testing

- Disassemble known ROM routines
- All addressing modes handled
- Output matches reference

### Deliverables

- Disassembly works correctly

### Estimated Time: 1-2 days

---

## Phase 8: Monitor Mode

**Goal:** Full debugging capability.

### Tasks

1. **Monitor REPL mode**
   - Command parsing
   - Register display/modify
   - Memory display/modify

2. **Assembler**
   - Parse assembly syntax
   - Generate opcodes
   - Interactive assembly mode

3. **Breakpoint manager**
   - BRK injection
   - Original byte tracking
   - Hit detection

4. **Stepping**
   - Single step
   - Step over
   - Run until

### Testing

- Set breakpoint, hit it
- Step through code
- Modify registers and memory

### Deliverables

- Complete monitor functionality

### Estimated Time: 3-4 days

---

## Phase 9: ATR File System

**Goal:** Read and write ATR disk images.

### Tasks

1. **ATRImage class**
   - Header parsing
   - Sector read/write
   - Multiple density support

2. **AtariFileSystem**
   - DOS 2.x format parsing
   - VTOC handling
   - Directory operations

3. **File operations**
   - Read file chain
   - Write file
   - Delete file

### Testing

- Read known disk images
- Write and read back files
- Directory listing correct

### Deliverables

- ATR format fully supported

### Estimated Time: 2-3 days

---

## Phase 10: DOS Mode

**Goal:** Disk management from REPL.

### Tasks

1. **DOS REPL mode**
   - Mount/unmount commands
   - Directory listing
   - File operations

2. **Host transfer**
   - Export to macOS
   - Import from macOS

3. **Disk creation**
   - New empty ATR
   - Format command

### Testing

- Mount disk, list files
- Copy files between disks
- Transfer to/from host

### Deliverables

- Complete DOS mode

### Estimated Time: 2-3 days

---

## Phase 11: BASIC Tokenizer

**Goal:** Enter BASIC programs via REPL.

### Tasks

1. **Lexer**
   - Token recognition
   - Keyword matching (permissive)
   - Abbreviation support

2. **Token encoder**
   - Statement tokens
   - Operators
   - Functions
   - BCD float conversion

3. **Memory layout builder**
   - Variable tables
   - Statement table
   - Pointer updates

4. **Memory injection**
   - Pause emulator
   - Write tokenized program
   - Update BASIC pointers

### Testing

- Tokenize simple programs
- Inject and RUN
- Complex programs work

### Deliverables

- BASIC tokenization works

### Estimated Time: 3-4 days

---

## Phase 12: BASIC Detokenizer & Mode

**Goal:** Complete BASIC mode.

### Tasks

1. **Detokenizer**
   - Read from emulator memory
   - Convert tokens to text
   - Reconstruct line numbers

2. **BASIC REPL mode**
   - Line entry
   - LIST/RUN/NEW
   - Variable inspection

3. **File operations**
   - Import .BAS from host
   - Export .BAS to host
   - Save/load to ATR

4. **Turbo BASIC support**
   - Extended token table
   - Mode switching

### Testing

- Enter program, list it back
- Save and load programs
- Turbo BASIC extensions

### Deliverables

- Complete BASIC mode

### Estimated Time: 2-3 days

---

## Phase 13: State Persistence

**Goal:** Save and restore emulator state.

### Tasks

1. **State serialization**
   - libatari800 state capture
   - Metadata (disks, breakpoints)
   - File format

2. **State loading**
   - Validate format
   - Restore emulator
   - Restore mounts

3. **Integration**
   - Menu commands
   - REPL commands

### Testing

- Save mid-game, restore
- State file portable
- Error handling

### Deliverables

- Save states work reliably

### Estimated Time: 1-2 days

---

## Phase 14: Polish & Integration

**Goal:** Production-ready application.

### Tasks

1. **Menu bar**
   - All menu items
   - Keyboard shortcuts

2. **Error handling**
   - Comprehensive error messages
   - Suggestions

3. **Preferences**
   - Settings persistence
   - Recent files

4. **Emacs elisp**
   - atari800-mode
   - Key bindings
   - Syntax highlighting (optional)

5. **Documentation**
   - README
   - User guide

6. **App bundle**
   - Icon
   - Info.plist
   - Code signing (if distributing)

### Testing

- End-to-end workflows
- Edge cases
- Performance

### Deliverables

- Complete, polished application

### Estimated Time: 3-5 days

---

## Summary

| Phase | Description | Days |
|-------|-------------|------|
| 1 | Project Foundation | 1-2 |
| 2 | Emulator Core | 3-4 |
| 3 | Metal Renderer | 2-3 |
| 4 | Audio Engine | 2-3 |
| 5 | Input Handling | 2-3 |
| 6 | Socket Protocol | 2-3 |
| 7 | 6502 Disassembler | 1-2 |
| 8 | Monitor Mode | 3-4 |
| 9 | ATR File System | 2-3 |
| 10 | DOS Mode | 2-3 |
| 11 | BASIC Tokenizer | 3-4 |
| 12 | BASIC Detokenizer & Mode | 2-3 |
| 13 | State Persistence | 1-2 |
| 14 | Polish & Integration | 3-5 |
| **Total** | | **30-44 days** |

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
                   ▼
            Phase 6 (Socket)
                   │
    ┌──────────────┴──────────────┐
    ▼                             ▼
Phase 7 (Disasm)              Phase 9 (ATR)
    │                             │
    ▼                             ▼
Phase 8 (Monitor)            Phase 10 (DOS)
    │                             │
    └──────────────┬──────────────┘
                   │
                   ▼
           Phase 11 (Tokenizer)
                   │
                   ▼
           Phase 12 (BASIC Mode)
                   │
                   ▼
           Phase 13 (State)
                   │
                   ▼
           Phase 14 (Polish)
```

## Milestones

| Milestone | Phases | Description |
|-----------|--------|-------------|
| M1 | 1-5 | Playable emulator with GUI |
| M2 | 6-8 | Debugging via Emacs |
| M3 | 9-12 | Full REPL functionality |
| M4 | 13-14 | Production release |
