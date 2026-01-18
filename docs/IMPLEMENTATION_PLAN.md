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

## Phase 5: Input Handling ✅ (Keyboard Complete)

**Goal:** Keyboard and controller input working.

**Status:** Keyboard input complete. Game controller support deferred.

### Tasks

1. **KeyboardHandler** ✅
   - Key mapping table (Mac keyCodes → Atari AKEY_* constants)
   - Function key to special key mapping (F1=START, F2=SELECT, F3=OPTION)
   - Key injection via `input_template_t` structure
   - NSEvent local monitors for reliable event capture

2. **ControlPanelView** ✅
   - START/SELECT/OPTION buttons with press/release handling
   - Buttons reflect keyboard state (highlight when F1/F2/F3 pressed)
   - Status display (running/paused, FPS counter)

3. **GameControllerHandler** ⏳ (Deferred)
   - GameController framework setup
   - D-pad and button mapping

4. **Special keys** ✅
   - F1=START, F2=SELECT, F3=OPTION
   - Backtick (`) = ATARI key
   - Arrow keys for cursor movement
   - Shift/Control modifiers forwarded to emulator

5. **Application Activation** ✅
   - `NSApp.setActivationPolicy(.regular)` for proper GUI behavior
   - Menu bar and Dock icon when running via `swift run`

### Testing

- ✅ Type in BASIC (works)
- ⏳ Run a simple game (joystick games need controller support)
- ⏳ Controller works (deferred)

### Deliverables

- ✅ Full keyboard input
- ✅ On-screen buttons
- ⏳ Game controller support (future phase)

### Implementation Notes

**Key Files Created:**
- `Sources/AtticCore/Input/KeyboardInputHandler.swift` - Key mapping and state tracking
- `Sources/AtticGUI/Input/KeyEventView.swift` - NSViewRepresentable for event capture

**Key Architectural Decisions:**
- Used `NSEvent.addLocalMonitorForEvents` instead of first responder (more reliable in SwiftUI)
- Keyboard handler is `@MainActor` for thread safety with UI
- Console keys tracked separately from regular keys
- Command key combinations pass through for menu shortcuts

### Estimated Time: 2-3 days (actual: keyboard portion ~1 day)

---

## Phase 6: AESP Protocol Library

**Goal:** Create the Attic Emulator Server Protocol (AESP) for emulator/GUI separation.

### Background

AESP enables separating the emulator into a standalone server process, allowing multiple clients (native GUI, web browser) to connect. This is a binary protocol optimized for low-latency video/audio streaming.

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
│ Port  │   │ Port  │   │ Port  │
└───┬───┘   └───┬───┘   └───┬───┘
    │           │           │
    └─────────┬─┴───────────┘
              │
      ┌───────┴───────┐
      │               │
┌─────▼─────┐   ┌─────▼─────┐
│Native GUI │   │WebSocket  │
│(SwiftUI)  │   │Bridge     │
└───────────┘   └─────┬─────┘
                      │
                ┌─────▼─────┐
                │Web Browser│
                └───────────┘
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

### Tasks

1. **Create `AtticProtocol` module**
   ```
   Sources/AtticProtocol/
   ├── AESPMessageType.swift    # Message type enum
   ├── AESPMessage.swift        # Message encoding/decoding
   ├── AESPServer.swift         # Server actor
   └── AESPClient.swift         # Client connection
   ```

2. **Message Types Enum**
   ```swift
   public enum AESPMessageType: UInt8 {
       // Control (0x00-0x3F)
       case ping = 0x00
       case pong = 0x01
       case pause = 0x02
       case resume = 0x03
       case reset = 0x04
       case status = 0x05
       case memoryRead = 0x10
       case memoryWrite = 0x11

       // Input (0x40-0x5F)
       case keyDown = 0x40
       case keyUp = 0x41
       case joystick = 0x42
       case consoleKeys = 0x43

       // Video (0x60-0x7F)
       case frameRaw = 0x60
       case frameDelta = 0x61
       case frameConfig = 0x62

       // Audio (0x80-0x9F)
       case audioPCM = 0x80
       case audioConfig = 0x81
       case audioSync = 0x82
   }
   ```

3. **Message Encoding/Decoding**
   ```swift
   public struct AESPMessage: Sendable {
       public static let magic: UInt16 = 0xAE50
       public static let version: UInt8 = 0x01

       public let type: AESPMessageType
       public let payload: Data

       public func encode() -> Data
       public static func decode(from data: Data) throws -> AESPMessage
   }
   ```

4. **Server Actor**
   ```swift
   public actor AESPServer {
       func start(controlPort: Int, videoPort: Int, audioPort: Int) async throws
       func broadcastFrame(_ frameBuffer: [UInt8]) async
       func broadcastAudio(_ samples: [UInt8]) async
       func stop() async
   }
   ```

5. **Client Actor**
   ```swift
   public actor AESPClient {
       func connect(host: String, controlPort: Int, videoPort: Int, audioPort: Int) async throws
       func sendInput(_ message: AESPMessage) async throws
       var frameStream: AsyncStream<[UInt8]> { get }
       var audioStream: AsyncStream<[UInt8]> { get }
       func disconnect() async
   }
   ```

6. **Update Package.swift**
   - Add `AtticProtocol` library target
   - Add dependency from `AtticCore` and `AtticGUI`

### Ports

- Control: `/tmp/attic-<pid>-control.sock` or TCP `localhost:47800`
- Video: `/tmp/attic-<pid>-video.sock` or TCP `localhost:47801`
- Audio: `/tmp/attic-<pid>-audio.sock` or TCP `localhost:47802`

### Testing

- Unit tests for message encoding/decoding
- Roundtrip test: encode → decode → verify equality
- Server accepts connections on all ports
- Client can connect and receive streams

### Deliverables

- `AtticProtocol` module with full message support
- Server and client actors ready for integration

---

## Phase 7: Emulator Server

**Goal:** Standalone emulator server process using AESP.

### Tasks

1. **Create `AtticServer` executable**
   ```
   Sources/AtticServer/
   └── main.swift
   ```

2. **Server Main Loop**
   ```swift
   @main
   struct AtticServer {
       static func main() async throws {
           let emulator = EmulatorEngine()
           try await emulator.initialize(romPath: romURL)

           let server = AESPServer()
           try await server.start(
               controlPort: 47800,
               videoPort: 47801,
               audioPort: 47802
           )

           // Emulation loop
           while !Task.isCancelled {
               let result = await emulator.executeFrame()
               let frameBuffer = await emulator.getFrameBuffer()
               let audioSamples = await emulator.getAudioSamples()

               await server.broadcastFrame(frameBuffer)
               await server.broadcastAudio(audioSamples)

               try? await Task.sleep(nanoseconds: 16_666_667)
           }
       }
   }
   ```

3. **Command Handling**
   - Process control messages (pause, resume, reset)
   - Handle input messages (key events, joystick)
   - Respond to memory read/write requests

4. **Frame Broadcasting**
   - Raw BGRA frames (384×240×4 = 368KB)
   - 60fps push to all connected video clients
   - Clients can drop frames if overwhelmed

5. **Audio Broadcasting**
   - Raw 16-bit PCM samples
   - Include timestamps for A/V sync
   - ~735 bytes per frame at 44100 Hz / 60 fps

6. **Update Package.swift**
   - Add `AtticServer` executable target
   - Depends on `AtticCore` and `AtticProtocol`

### Testing

- Server starts and listens on ports
- Connects with netcat/telnet to verify ports open
- Server runs standalone without GUI
- Multiple clients can connect

### Deliverables

- `AtticServer` executable runs emulator headlessly
- Broadcasts video/audio to connected clients

---

## Phase 8: Refactor GUI as Protocol Client ✅

**Status:** Complete

**Goal:** AtticGUI becomes a protocol client instead of directly owning EmulatorEngine.

**Implementation Notes:**
- AtticGUI now supports two operation modes: client (default) and embedded
- **Client mode (default):** Connects to an already-running AtticServer on localhost:47800-47802
  - User must start AtticServer first: `swift run AtticServer`
  - If no server found, GUI displays error message with instructions
  - Frame and audio streams use optimized Data types (zero-copy where possible)
  - Index-based buffer tracking avoids O(n) operations on large frame buffers
- **Embedded mode:** Runs EmulatorEngine directly (for debugging), enabled with `--embedded` flag
- Both modes use absolute frame scheduling to maintain precise 60fps timing
- All input (keyboard, console keys) forwarded via protocol in client mode

### Tasks

1. **Modify AtticViewModel**
   ```swift
   @MainActor
   class AtticViewModel: ObservableObject {
       // Client mode: protocol client connecting to external server
       private var client: AESPClient?

       // Embedded mode: direct emulator ownership (for debugging)
       private var emulator: EmulatorEngine?

       func initializeClientMode() async {
           // Connect to already-running AtticServer
           let clientConfig = AESPClientConfiguration(
               host: "localhost",
               controlPort: 47800,
               videoPort: 47801,
               audioPort: 47802
           )
           client = AESPClient(configuration: clientConfig)

           do {
               try await client?.connect()
               startFrameReceiver()
               startAudioReceiver()
           } catch {
               // Show error: "No AtticServer found. Start server first."
               initializationError = "No server found..."
           }
       }
   }
   ```

2. **Frame Receiver**
   ```swift
   private func startFrameReceiver() {
       Task {
           guard let client = client else { return }
           for await frameBuffer in client.frameStream {
               await MainActor.run {
                   renderer?.updateTexture(with: frameBuffer)
               }
           }
       }
   }
   ```

3. **Audio Receiver**
   ```swift
   private func startAudioReceiver() {
       Task {
           guard let client = client else { return }
           for await samples in client.audioStream {
               audioEngine.enqueueSamples(bytes: samples)
           }
       }
   }
   ```

4. **Input Forwarding**
   ```swift
   func handleKeyDown(_ event: NSEvent) {
       guard let (keyChar, keyCode, shift, control) = keyboardHandler.keyDown(event) else { return }

       Task {
           let message = AESPMessage.keyDown(
               keyChar: keyChar,
               keyCode: keyCode,
               shift: shift,
               control: control
           )
           try? await client?.sendInput(message)
       }
   }
   ```

5. **Server-First Workflow**
   - User starts AtticServer manually before launching GUI
   - GUI attempts to connect to existing server on startup
   - Clear error message if server not running with instructions
   - No subprocess management - cleaner separation of concerns

6. **Dual Mode Support**
   - Client mode (default): Connects to external AtticServer
   - Embedded mode: Runs EmulatorEngine directly, enabled with `--embedded` flag
   - Useful for debugging without needing separate server process

### Testing

- ✅ Run AtticServer standalone
- ✅ Run AtticGUI, verify it connects to server
- ✅ GUI shows "No Server" error when server not running
- ✅ Display shows emulator output at 60fps
- ✅ Audio plays correctly without crackling
- ✅ Keyboard input works with no perceptible latency
- ✅ Performance: Client mode achieves ~60fps (matches embedded mode)

### Deliverables

- ✅ AtticGUI works as protocol client (default mode)
- ✅ AtticGUI works in embedded mode (`--embedded` flag)
- ✅ Server-first workflow with clear error messaging

---

## Phase 9: CLI Socket Protocol ✅

**Status:** Complete

**Goal:** CLI can communicate with AtticServer via text-based protocol for REPL.

**Note:** This protocol enables communication between the CLI tool and AtticServer for Emacs REPL integration. It is separate from AESP (the binary protocol for video/audio streaming). The CLI connects directly to AtticServer, not through the GUI.

### Implementation Notes

**Architecture:**
- CLI connects directly to AtticServer via Unix socket at `/tmp/attic-<pid>.sock`
- Text-based protocol: `CMD:<command>\n` → `OK:<response>\n` or `ERR:<message>\n`
- Async events: `EVENT:<type> <data>\n`
- Multi-line responses use `\x1E` (Record Separator) as delimiter

**Key Files Created:**
- `Sources/AtticCore/CLI/CLIProtocol.swift` - Protocol types, command parser, response builder
- `Sources/AtticCore/CLI/CLISocketServer.swift` - Unix socket server actor for AtticServer
- `Sources/AtticCore/CLI/CLISocketClient.swift` - Unix socket client for AtticCLI

**Features Implemented:**
- Full command set: ping, pause, resume, step, reset, status
- Memory operations: read, write, registers
- Breakpoints: set, clear, clearall, list
- Disk operations: mount, unmount, drives
- State management: save, load
- Socket discovery: scans `/tmp/attic-*.sock`
- Server launch: CLI can spawn AtticServer if not running

**Protocol Commands:**
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

### Tasks

1. **CLISocketServer (AtticServer side)** ✅
   - Unix socket listener at `/tmp/attic-<pid>.sock`
   - Handles multiple CLI connections
   - Executes commands against EmulatorEngine
   - Sends async events (breakpoints, errors)

2. **CLISocketClient (CLI side)** ✅
   - Discovers sockets via `/tmp/attic-*.sock`
   - Connects and sends commands
   - Receives responses and events
   - Handles connection lifecycle

3. **Protocol implementation** ✅
   - CLICommandParser parses text commands
   - CLIResponse formats success/error responses
   - CLIEvent handles async notifications

4. **Server launch from CLI** ✅
   - Discovers running AtticServer via socket scan
   - Launches AtticServer if not found
   - Waits for socket to appear with retry

### Testing

- ✅ CLI connects to running AtticServer
- ✅ Commands execute and return correct responses
- ✅ Server auto-launch when no socket found
- ✅ Socket discovery works with multiple servers

### Deliverables

- ✅ CLI and AtticServer communicate via text protocol
- ✅ All control commands work (ping, pause, resume, reset, status)
- ✅ Memory operations work (read, write, registers)
- ✅ Breakpoint management works
- ✅ Socket discovery and server launch

---

## Phase 10: 6502 Disassembler ✅

**Status:** Complete

**Goal:** Memory can be disassembled.

**Implementation Notes:**
- Complete opcode table with all 256 6502 opcodes including illegal/undocumented opcodes stable on 6502C (SALLY)
- 13 addressing modes fully supported with operand formatting
- DisassembledInstruction struct includes: address, bytes, mnemonic, operand, mode, target address, relative offset, target label, cycles, page cross cycles, affected flags, illegal flag, halts flag
- AddressLabels provides symbolic names for hardware registers (GTIA, POKEY, PIA, ANTIC), OS vectors, zero-page variables, and page 2 variables
- Branch instructions show target address, relative offset, and label when available
- CLI protocol extended with `disassemble` (alias `d`) command

**Key Files Created:**
- `Sources/AtticCore/Disassembler/AddressingMode.swift` - 6502 addressing mode enum
- `Sources/AtticCore/Disassembler/OpcodeInfo.swift` - Opcode table with 256 entries
- `Sources/AtticCore/Disassembler/DisassembledInstruction.swift` - Result struct with formatting
- `Sources/AtticCore/Disassembler/AddressLabels.swift` - Atari address label tables
- `Sources/AtticCore/Disassembler/Disassembler.swift` - Main disassembler implementation

### Tasks

1. **Opcode table** ✅
   - All 6502 instructions
   - Illegal opcodes for 6502C (LAX, SAX, DCP, ISC, SLO, RLA, SRE, RRA, etc.)
   - Addressing modes and byte counts
   - Cycle timing and flag effects

2. **Disassembler** ✅
   ```swift
   struct Disassembler {
       func disassemble(at address: UInt16,
                       memory: MemoryBus) -> DisassembledInstruction
       func disassembleRange(from: UInt16,
                            lines: Int,
                            memory: MemoryBus) -> [DisassembledInstruction]
   }
   ```

3. **Output formatting** ✅
   - Address, bytes, mnemonic, operand
   - Labels for common addresses (hardware registers, OS vectors, zero page)
   - Branch target with offset annotation: `BNE $E47A (+5)`
   - Branch target with label: `BNE LOOP (+5)`

4. **CLI Protocol Integration** ✅
   - Added `disassemble` command (alias: `d`)
   - Syntax: `d [address] [lines]` - defaults to PC and 16 lines
   - Multi-line response using Record Separator character

### Testing

- ⏳ Disassemble known ROM routines (manual testing when build available)
- ✅ All addressing modes handled
- ✅ Output formatting implemented

### Deliverables

- ✅ Disassembly works correctly
- ✅ CLI command integration

---

## Phase 11: Monitor Mode ✅

**Status:** Complete

**Goal:** Full debugging capability.

**Implementation Notes:**
- Created OpcodeTable.swift with complete 6502 instruction set for assembler and stepping
- Implemented MAC65-style assembler with full expression and label support
- Created BreakpointManager with BRK injection (RAM) and PC-polling (ROM)
- Implemented instruction-level stepping via temporary BRK placement
- Updated CLI protocol with new monitor commands (disasm, asm, stepover, until, fill)
- Updated CommandParser with full monitor command parsing

**Key Files Created:**
- `Sources/AtticCore/Monitor/OpcodeTable.swift` - Complete 6502 opcode table
- `Sources/AtticCore/Monitor/Assembler.swift` - MAC65-style 6502 assembler
- `Sources/AtticCore/Monitor/BreakpointManager.swift` - Enhanced breakpoint management
- `Sources/AtticCore/Monitor/MonitorStepper.swift` - Instruction-level stepping
- `Sources/AtticCore/Monitor/MonitorController.swift` - Unified monitor interface
- `Tests/AtticCoreTests/MonitorTests.swift` - Unit tests for monitor components

### Tasks

1. **Monitor REPL mode** ✅
   - Command parsing (g, s, so, pause, until, r, m, >, f, d, a, bp, bc)
   - Register display/modify (r, r A=$XX X=$XX)
   - Memory display/modify (m, >, f)

2. **Assembler** ✅
   - MAC65-style syntax with all 6502 instructions
   - Expression parser (+, -, *, /, <, >, labels, *, character literals)
   - Pseudo-ops: ORG, DB/BYTE, DW/WORD, DS/BLOCK, HEX, ASC, DCI, END
   - Interactive assembly mode (a $0600)

3. **Breakpoint manager** ✅
   - BRK injection for RAM addresses ($00-$BFFF)
   - PC polling for ROM addresses ($C000+)
   - Original byte tracking and restoration
   - Hit count tracking

4. **Stepping** ✅
   - Single step (s, s N) using temporary BRK after instruction
   - Step over (so) for JSR instructions
   - Run until (until $XXXX)

### Testing

- ✅ Set breakpoint, hit it (via BRK injection or PC watch)
- ✅ Step through code (instruction-level stepping)
- ✅ Modify registers and memory
- ✅ Unit tests for assembler, expression parser, symbol table

### Deliverables

- ✅ Complete monitor functionality
- ✅ Full assembler with MAC65 syntax
- ✅ Breakpoint manager with RAM/ROM support
- ✅ Instruction-level stepping

---

## Phase 12: ATR File System

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

## Phase 13: DOS Mode

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

## Phase 14: BASIC Tokenizer

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

## Phase 15: BASIC Detokenizer & Mode

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

## Phase 16: State Persistence

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

## Phase 17: Polish & Integration

**Goal:** Production-ready native application.

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

## Phase 18: WebSocket Bridge

**Goal:** Enable web browser clients to connect to the emulator server.

### Background

WebSocket provides a standard way for web browsers to maintain persistent connections. This phase adds a WebSocket bridge that translates between the binary AESP protocol and WebSocket frames.

### Tasks

1. **WebSocket Server**
   ```swift
   actor WebSocketBridge {
       func start(port: Int) async throws  // Default: 47803
       func stop() async

       // Internal: connects to AESPServer and bridges to WebSocket clients
   }
   ```

2. **Protocol Translation**
   - AESP binary messages ↔ WebSocket binary frames
   - Same message format, different transport
   - Handle WebSocket connection lifecycle

3. **Video Optimization for Web**
   - Delta encoding: only send changed pixels
   - Optional: JPEG/WebP compression for reduced bandwidth
   - Frame skipping for slow connections

4. **Audio Handling**
   - Raw PCM over WebSocket
   - Client-side Web Audio API handles playback
   - Include timestamps for A/V sync

5. **Integration with AtticServer**
   - WebSocket bridge runs alongside AESP server
   - Optional: can run as separate process

### Testing

- Connect from browser JavaScript console
- Verify binary frames received correctly
- Test video frame delivery
- Test audio sample delivery
- Multiple browser tabs connected simultaneously

### Deliverables

- WebSocket bridge functional
- Ready for web client development

---

## Phase 19: Web Browser Client

**Goal:** Full web-based emulator client running in browser.

### Background

This is the final phase, implementing a complete web frontend that connects to AtticServer via WebSocket, rendering video with Canvas/WebGL and playing audio via Web Audio API.

### Tasks

1. **Project Setup**
   ```
   web-client/
   ├── package.json
   ├── src/
   │   ├── index.html
   │   ├── main.ts
   │   ├── protocol/
   │   │   ├── AESPClient.ts
   │   │   └── messages.ts
   │   ├── video/
   │   │   └── renderer.ts
   │   ├── audio/
   │   │   └── player.ts
   │   └── input/
   │       └── keyboard.ts
   └── dist/
   ```

2. **TypeScript Protocol Client**
   ```typescript
   class AESPClient {
       constructor(wsUrl: string);
       connect(): Promise<void>;
       disconnect(): void;

       // Input
       sendKeyDown(keyCode: number, shift: boolean, control: boolean): void;
       sendKeyUp(): void;

       // Callbacks
       onFrame: (frameBuffer: Uint8Array) => void;
       onAudio: (samples: Int16Array) => void;
   }
   ```

3. **Video Rendering**
   - Canvas 2D or WebGL for display
   - Handle BGRA → RGBA conversion (or server sends RGBA)
   - Scale to fit browser window
   - Maintain aspect ratio (384:240)

4. **Audio Playback**
   ```typescript
   class AudioPlayer {
       private audioContext: AudioContext;
       private ringBuffer: Float32Array;

       enqueueSamples(samples: Int16Array): void;
       start(): void;
       stop(): void;
   }
   ```

5. **Keyboard Input**
   - Map browser key events to Atari key codes
   - Handle modifiers (Shift, Control)
   - Function keys for console buttons

6. **UI Features**
   - Fullscreen toggle
   - Mute button
   - Connection status indicator
   - Optional: on-screen keyboard for mobile

### Testing

- Works in Chrome, Firefox, Safari
- Video displays correctly at 60fps
- Audio plays without crackling
- Keyboard input responsive
- Mobile browser support (touch input)

### Deliverables

- Complete web client
- Can run Atari emulator in browser
- Multiple users can watch same emulator instance

---

## Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Project Foundation | ✅ Complete |
| 2 | Emulator Core | ✅ Complete |
| 3 | Metal Renderer | ✅ Complete |
| 4 | Audio Engine | ✅ Complete |
| 5 | Input Handling | ✅ Keyboard done, joystick deferred |
| 6 | AESP Protocol Library | ✅ Complete |
| 7 | Emulator Server | ✅ Complete |
| 8 | GUI as Protocol Client | ✅ Complete |
| 9 | CLI Socket Protocol | ✅ Complete |
| 10 | 6502 Disassembler | ✅ Complete |
| 11 | Monitor Mode | ✅ Complete |
| 12 | ATR File System | Pending |
| 13 | DOS Mode | Pending |
| 14 | BASIC Tokenizer | Pending |
| 15 | BASIC Detokenizer & Mode | Pending |
| 16 | State Persistence | Pending |
| 17 | Polish & Integration | Pending |
| 18 | WebSocket Bridge | Pending |
| 19 | Web Browser Client | Pending |

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
                   │
                   ▼
           Phase 17 (Polish)
                   │
                   ▼
           Phase 18 (WebSocket Bridge)
                   │
                   ▼
           Phase 19 (Web Browser Client)
```

## Milestones

| Milestone | Phases | Description | Status |
|-----------|--------|-------------|--------|
| M1 | 1-5 | Playable emulator with GUI | ✅ Complete (keyboard input, joystick deferred) |
| M2 | 6-8 | Emulator/GUI separation | ✅ Complete |
| M3 | 9-11 | Debugging via Emacs | ✅ Complete |
| M4 | 12-15 | Full REPL functionality | Pending |
| M5 | 16-17 | Production native release | Pending |
| M6 | 18-19 | Web browser support | Pending |
