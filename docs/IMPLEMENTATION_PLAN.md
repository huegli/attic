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
- Client mode: Launches AtticServer automatically and connects via AESP protocol
- Embedded mode: Runs EmulatorEngine directly (for debugging), enabled with `--embedded` flag
- Frame and audio receivers use AsyncStreams from AESPClient
- All input (keyboard, console keys) forwarded via protocol in client mode

### Tasks

1. **Modify AtticViewModel**
   ```swift
   @MainActor
   class AtticViewModel: ObservableObject {
       // Before: owned EmulatorEngine directly
       // private let emulator: EmulatorEngine

       // After: protocol client
       private var client: AESPClient?
       private var serverProcess: Process?

       func startEmulator() async throws {
           // Launch AtticServer as subprocess
           serverProcess = try launchServer()

           // Connect via protocol
           client = AESPClient()
           try await client?.connect(
               host: "localhost",
               controlPort: 47800,
               videoPort: 47801,
               audioPort: 47802
           )

           // Start receiving frames
           startFrameReceiver()
           startAudioReceiver()
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

5. **Server Lifecycle**
   - Launch server on app start
   - Kill server on app quit
   - Handle server crashes gracefully

6. **Backward Compatibility**
   - Keep option to run embedded (without server) for debugging
   - Command-line flag: `--embedded` for old behavior

### Testing

- Run AtticServer standalone
- Run AtticGUI, verify it connects
- Display shows emulator output
- Audio plays correctly
- Keyboard input works with no perceptible latency
- Run two GUI clients, both receive frames

### Deliverables

- AtticGUI works as protocol client
- Can run with or without separate server

---

## Phase 9: CLI Socket Protocol

**Goal:** CLI can communicate with GUI via text-based protocol for REPL.

**Note:** This is the existing CLI/GUI communication for the Emacs REPL interface, separate from AESP. AESP is binary and optimized for video/audio; this protocol is text-based for debugging commands.

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

---

## Phase 10: 6502 Disassembler

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

## Phase 11: Monitor Mode

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
| 8 | GUI as Protocol Client | Pending |
| 9 | CLI Socket Protocol | Pending |
| 10 | 6502 Disassembler | Pending |
| 11 | Monitor Mode | Pending |
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
| M2 | 6-8 | Emulator/GUI separation | Pending |
| M3 | 9-11 | Debugging via Emacs | Pending |
| M4 | 12-15 | Full REPL functionality | Pending |
| M5 | 16-17 | Production native release | Pending |
| M6 | 18-19 | Web browser support | Pending |
