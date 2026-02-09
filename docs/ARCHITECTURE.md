# System Architecture

## Overview

The Attic Atari 800 XL Emulator is a macOS application that will evolve through two architectural phases:

### Current Architecture (Phases 1-5)

Two cooperating executables:

1. **AtticGUI** - SwiftUI application with Metal rendering and audio output
2. **attic** - Command-line REPL tool for Emacs integration

Both share a common core library (`AtticCore`) containing the emulator wrapper, REPL logic, tokenizers, and file format handlers.

### Server Architecture (Phases 6-8, complete)

Four executables with protocol-based communication:

1. **AtticServer** - Standalone emulator server process ✅ (Phase 7 complete)
2. **AtticGUI** - Protocol client with Metal rendering ✅ (Phase 8 complete - supports client and embedded modes)
3. **attic** - Command-line REPL tool (connects via text protocol)
4. **Web Client** - Browser-based client via WebSocket (Phases 18-19, future)

Supporting library:
- **AtticProtocol** - AESP protocol implementation ✅ (Phase 6 complete)

This separation enables:
- Multiple simultaneous clients viewing the same emulator
- Web browser access without native installation
- Easier testing and debugging of components in isolation

## Implementation Status

| Phase | Component | Status |
|-------|-----------|--------|
| 1 | Project Foundation | ✅ Complete |
| 2 | Emulator Core | ✅ Complete |
| 3 | Metal Renderer | ✅ Complete |
| 4 | Audio Engine | ✅ Complete |
| 5 | Input Handling | ✅ Complete (Keyboard only, joystick deferred) |
| 6 | AESP Protocol Library | ✅ Complete |
| 7 | Emulator Server | ✅ Complete |
| 8 | GUI as Protocol Client | ✅ Complete |
| 9-17 | REPL, Debugging, BASIC | Pending |
| 18-19 | Web Browser Support | Pending |

## Component Diagram

All AtticCore files are at the module top level (no subdirectories). Files are grouped logically below:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AtticCore                                       │
│                                                                              │
│  ┌─ Emulator ──────────────┐  ┌─ Monitor/Debugger ─────────────────────────┐ │
│  │ EmulatorEngine.swift    │  │ MonitorController.swift  Assembler.swift   │ │
│  │ LibAtari800Wrapper.swift│  │ MonitorStepper.swift  BreakpointManager.swift│ │
│  │ MemoryBus.swift         │  │ Disassembler.swift       OpcodeInfo.swift  │ │
│  │ StateMetadata.swift     │  │ DisassembledInstruction.swift              │ │
│  │                         │  │ AddressingMode.swift  AddressLabels.swift  │ │
│  │                         │  │ CPURegisters.swift                         │ │
│  └─────────────────────────┘  └────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─ BASIC ─────────────────────────────┐  ┌─ DOS/ATR ──────────────────────┐ │
│  │ BASICTokenizer.swift                │  │ ATRImage.swift   ATRError.swift│ │
│  │ BASICDetokenizer.swift              │  │ ATRFileSystem.swift            │ │
│  │ BASICToken.swift                    │  │ DiskManager.swift  DiskType.swift│ │
│  │ BASICMemoryLayout.swift             │  │ DirectoryEntry.swift           │ │
│  │ BASICLineHandler.swift              │  │ SectorLink.swift   VTOC.swift  │ │
│  │ BASICVariable.swift  BCDFloat.swift │  └────────────────────────────────┘ │
│  └─────────────────────────────────────┘                                     │
│                                                                              │
│  ┌─ REPL ──────────────────────────────┐  ┌─ CLI Socket ───────────────────┐ │
│  │ REPLEngine.swift                    │  │ CLIProtocol.swift              │ │
│  │ REPLMode.swift                      │  │ CLISocketClient.swift          │ │
│  │ CommandParser.swift                 │  │ CLISocketServer.swift          │ │
│  └─────────────────────────────────────┘  └────────────────────────────────┘ │
│                                                                              │
│  ┌─ Audio/Input ───────────────────────┐  ┌─ Module ───────────────────────┐ │
│  │ AudioEngine.swift                   │  │ AtticCore.swift                │ │
│  │ KeyboardInputHandler.swift          │  │ (public API exports)           │ │
│  └─────────────────────────────────────┘  └────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
           │                           │
           ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │   Attic.app     │◄───────►│  attic          │
    │                 │  Unix   │                 │
    │  SwiftUI Views  │ Socket  │  REPL Server    │
    │  Metal Renderer │         │  (stdio)        │
    │  GameController │         │                 │
    │  Core Audio     │         │                 │
    └─────────────────┘         └─────────────────┘
                                       │
                                       ▼
                                ┌─────────────────┐
                                │  Emacs comint   │
                                └─────────────────┘
```

## Server Architecture Component Diagram (Phase 8 Complete)

With the Attic Emulator Server Protocol (AESP) implemented, the architecture now supports:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AtticServer (Process 1)                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                         AtticCore                                    ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  ││
│  │  │ EmulatorEngine  │  │   AudioEngine   │  │ KeyboardInputHandler│  ││
│  │  │ LibAtari800Wrap │  │   (samples)     │  │   (state tracking)  │  ││
│  │  └─────────────────┘  └─────────────────┘  └─────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                        AtticProtocol                                 ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐            ││
│  │  │ Control Port  │  │  Video Port   │  │  Audio Port   │            ││
│  │  │   :47800      │  │    :47801     │  │    :47802     │            ││
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘            ││
│  └──────────┼──────────────────┼──────────────────┼─────────────────────┘│
└─────────────┼──────────────────┼──────────────────┼──────────────────────┘
              │                  │                  │
    ┌─────────┴─────────┬────────┴──────────────────┤
    │                   │                           │
    ▼                   ▼                           ▼
┌─────────────────┐ ┌─────────────────┐     ┌─────────────────┐
│   AtticGUI      │ │   AtticGUI #2   │     │  WebSocket      │
│   (Process 2)   │ │   (Process 3)   │     │  Bridge :47803  │
│                 │ │                 │     │                 │
│  AESPClient     │ │  AESPClient     │     └────────┬────────┘
│  MetalRenderer  │ │  MetalRenderer  │              │
│  AVAudioEngine  │ │  AVAudioEngine  │              ▼
└─────────────────┘ └─────────────────┘     ┌─────────────────┐
                                            │   Web Browser   │
┌─────────────────┐                         │   (JavaScript)  │
│   attic CLI     │                         │                 │
│   (Process 4)   │                         │  Canvas/WebGL   │
│                 │                         │  Web Audio API  │
│  Text Protocol  │                         └─────────────────┘
│  (Unix Socket)  │
└─────────────────┘
        │
        ▼
┌─────────────────┐
│  Emacs comint   │
└─────────────────┘
```

## Communication Protocols

The Attic Emulator uses two communication protocols:

1. **AESP (Attic Emulator Server Protocol)** - Binary protocol for GUI/web clients
   - High-performance video/audio streaming at 60fps
   - Control, video, and audio on separate ports (47800-47802)
   - WebSocket bridge on port 47803 for web clients

2. **CLI Protocol** - Text-based protocol for REPL/Emacs integration
   - Line-based commands over Unix domain socket
   - Designed for Emacs comint mode compatibility

For complete protocol specifications including message formats, payload structures, and test coverage requirements, see **[PROTOCOL.md](PROTOCOL.md)**.

### Protocol Summary

| Protocol | Transport | Purpose |
|----------|-----------|---------|
| AESP Control | TCP :47800 | Commands, status, memory access |
| AESP Video | TCP :47801 | Raw BGRA frames (384×240×4 @ 60fps) |
| AESP Audio | TCP :47802 | 16-bit PCM (44.1kHz mono) |
| AESP WebSocket | TCP :47803 | Bridges all channels for web |
| CLI | Unix socket | Text-based REPL commands |

## Threading Model

### GUI Application Threads

```
Main Thread (UI)
├── SwiftUI view updates
├── User input handling
├── Menu actions
└── Socket command processing

Emulation Thread
├── libatari800 frame execution
├── Frame buffer generation
└── Audio sample generation

Audio Thread (Core Audio callback)
└── Pulls samples from ring buffer

Metal Rendering (Display Link)
└── 60Hz texture upload and draw
```

### Thread Synchronization

The `EmulatorEngine` actor serializes all access to libatari800:

```swift
actor EmulatorEngine {
    private var isRunning: Bool = false
    private var frameBuffer: UnsafeMutablePointer<UInt8>
    private var audioBuffer: RingBuffer<Float>
    
    func pause() async { ... }
    func resume() async { ... }
    func step(count: Int) async -> StepResult { ... }
    func readMemory(at address: UInt16, count: Int) async -> [UInt8] { ... }
    func writeMemory(at address: UInt16, bytes: [UInt8]) async { ... }
}
```

### Emulation Loop

```swift
func emulationLoop() async {
    while !Task.isCancelled {
        if isRunning {
            // Execute one frame (~1/60 second of emulated time)
            libatari800_frame()
            
            // Check for breakpoint hits
            if let breakpoint = checkBreakpoints() {
                isRunning = false
                await notifyBreakpointHit(breakpoint)
            }
            
            // Copy frame buffer for rendering
            await updateFrameBuffer()
            
            // Generate audio samples
            await fillAudioBuffer()
        } else {
            // Paused - wait for resume signal
            await waitForResumeOrStep()
        }
    }
}
```

## Inter-Process Communication

The CLI communicates with the GUI via Unix domain socket using a text-based protocol. See **[PROTOCOL.md](PROTOCOL.md)** for complete command reference.

### Socket Architecture

```
CLI Process (attic)                 AtticServer Process
┌──────────────┐                    ┌──────────────┐
│   stdin ─────┼──► CommandParser   │              │
│              │         │          │  Socket      │
│  SocketClient│         ▼          │  Listener    │
│       │      │  CommandTranslator │      │       │
│       ▼      │         │          │      ▼       │
│   stdout ◄───┼── ResponseHandler◄─┼─ CommandProc │
└──────────────┘                    │      │       │
                                    │      ▼       │
                                    │ EmulatorEng  │
                                    └──────────────┘
```

### Message Flow

1. User types command in Emacs
2. Emacs sends to CLI via stdin
3. CLI translates command and sends to AtticServer via socket
4. AtticServer executes command against EmulatorEngine
5. AtticServer sends response via socket
6. CLI formats response and writes to stdout
7. Emacs displays in comint buffer

## Memory Architecture

### Atari 800 XL Memory Map

```
$0000-$00FF  Zero Page (256 bytes)
$0100-$01FF  Hardware Stack (256 bytes)
$0200-$02FF  OS Variables
$0300-$03FF  Device Handlers
$0400-$047F  Reserved
$0480-$057F  Floating Point Package
$0580-$05FF  Reserved
$0600-$3FFF  User RAM (14.5 KB)
$4000-$7FFF  User RAM (16 KB, can be under ROM)
$8000-$9FFF  Cartridge Area / RAM
$A000-$BFFF  BASIC ROM / RAM
$C000-$CFFF  OS ROM / RAM
$D000-$D0FF  GTIA Registers
$D100-$D1FF  Reserved
$D200-$D2FF  POKEY Registers
$D300-$D3FF  PIA Registers
$D400-$D4FF  ANTIC Registers
$D500-$D7FF  Reserved / Cartridge
$D800-$DFFF  Floating Point ROM / RAM
$E000-$FFFF  OS ROM
```

### Memory Access Layer

```swift
protocol MemoryBus {
    func read(_ address: UInt16) -> UInt8
    func write(_ address: UInt16, value: UInt8)
    func readBlock(from: UInt16, count: Int) -> [UInt8]
    func writeBlock(at: UInt16, bytes: [UInt8])
}
```

## Audio Pipeline

### Data Flow

```
libatari800 POKEY
       │
       ▼ (generates samples at ~1.79 MHz / 28 = ~64 kHz)
   Resampler
       │
       ▼ (downsample to 44.1 kHz)
   Ring Buffer (lock-free)
       │
       ▼ (pulled by audio thread)
   AVAudioSourceNode
       │
       ▼
   Audio Output
```

### Ring Buffer Design

```swift
struct AudioRingBuffer {
    private var buffer: [Float]
    private var readIndex: Int
    private var writeIndex: Int
    private let size: Int
    
    // Called from emulation thread
    mutating func write(_ samples: [Float]) -> Int
    
    // Called from audio thread
    mutating func read(into buffer: UnsafeMutablePointer<Float>, count: Int) -> Int
    
    var availableSamples: Int
}
```

## State Serialization

### Save State Format

```
Atari800State {
    magic: [UInt8; 4] = "ATTC"
    version: UInt8
    flags: UInt8
    reserved: [UInt8; 10]
    
    // CPU State
    cpu: {
        A, X, Y, S, P: UInt8
        PC: UInt16
    }
    
    // Memory
    ram: [UInt8; 65536]
    
    // Custom Chips
    antic: AnticState
    gtia: GtiaState
    pokey: PokeyState
    pia: PiaState
    
    // Mounted Disks
    disks: [{
        drive: UInt8
        path: String
        modified: Bool
    }]
    
    // Breakpoints (optional, for debugging sessions)
    breakpoints: [UInt16]
}
```

### Serialization Strategy

libatari800 likely has its own state save format. We'll use that for the emulator core and wrap it with our metadata:

```swift
struct StateFile: Codable {
    let magic: String = "ATTC"
    let version: UInt8 = 1
    let flags: UInt8 = 0
    let timestamp: Date
    let libatari800State: Data  // Opaque blob from libatari800
    let mountedDisks: [MountedDisk]
    let breakpoints: [UInt16]
}
```

## Error Handling Strategy

### Error Types

```swift
enum EmulatorError: Error {
    case romNotFound(String)
    case invalidROM(String)
    case stateLoadFailed(String)
    case stateSaveFailed(String)
}

enum REPLError: Error {
    case invalidCommand(String, suggestion: String?)
    case invalidAddress(String)
    case invalidValue(String)
    case fileNotFound(String)
    case diskFull
    case syntaxError(line: Int, column: Int, message: String, suggestion: String?)
}

enum SocketError: Error {
    case connectionFailed(String)
    case timeout
    case protocolError(String)
}
```

### Error Presentation

All errors should be formatted for terminal display:

```swift
protocol REPLFormattable {
    func format() -> String
}

extension REPLError: REPLFormattable {
    func format() -> String {
        switch self {
        case .syntaxError(let line, let column, let message, let suggestion):
            var output = "Error at line \(line), column \(column):\n"
            output += "  \(message)\n"
            if let suggestion = suggestion {
                output += "  Suggestion: \(suggestion)\n"
            }
            return output
        // ... other cases
        }
    }
}
```

## Configuration

### Application Defaults

```swift
struct EmulatorConfiguration {
    var machineType: MachineType = .atari800XL
    var ramSize: Int = 64  // KB
    var basicEnabled: Bool = true
    var palMode: Bool = false  // NTSC by default
    var audioEnabled: Bool = true
    var audioSampleRate: Int = 44100
}
```

### ROM Locations

ROMs are loaded from the application bundle:

```swift
func romPath(for rom: ROMType) -> URL? {
    Bundle.main.url(forResource: rom.filename, 
                    withExtension: "ROM", 
                    subdirectory: "ROM")
}

enum ROMType {
    case osXL      // ATARIXL.ROM
    case basic     // ATARIBAS.ROM

    var filename: String {
        switch self {
        case .osXL: return "ATARIXL"
        case .basic: return "ATARIBAS"
        }
    }
}
```

## Implementation Choices (Phases 1-4)

This section documents significant architectural decisions made during implementation that differ from or extend the original design.

### Phase 1: Project Foundation

#### Static Library vs Dynamic Library

**Original Design:** Specification mentioned `libatari800.dylib` in the bundle.

**Implementation:** We use a static library (`libatari800.a`) linked directly into the executables.

**Rationale:**
- Simpler deployment - no framework/dylib path management
- SPM's `systemLibrary` target works well with static libraries
- Single binary distribution without bundle dependencies
- Eliminates runtime linking issues

**Trade-offs:**
- Larger binary size (library embedded in both CLI and GUI)
- Must rebuild if library changes

#### Module Map for C Interop

```
Libraries/libatari800/
├── include/
│   └── libatari800.h
├── lib/
│   └── libatari800.a
└── module.modulemap
```

The `module.modulemap` enables Swift to import C types directly:
```
module CAtari800 {
    header "include/libatari800.h"
    link "atari800"
    export *
}
```

### Phase 2: Emulator Core

#### Actor Model for Thread Safety

**Implementation:** `EmulatorEngine` is a Swift actor.

```swift
public actor EmulatorEngine {
    private let wrapper: LibAtari800Wrapper
    // ... all state serialized through actor
}
```

**Key Benefits:**
- Automatic serialization of all access to emulator state
- Safe concurrent access from UI thread and emulation loop
- No manual locking required
- Compiler-enforced `await` for cross-isolation calls

**Swift 6 Strict Concurrency:**
The code is written for Swift 6's strict concurrency checking:
- All types crossing actor boundaries must be `Sendable`
- `@unchecked Sendable` used for wrapper types that are internally thread-safe
- `@preconcurrency import` for C library imports

#### Frame Buffer Design

**Original Design:** Frame buffer as raw pointer.

**Implementation:** Copy-based frame buffer with BGRA conversion:

```swift
public func getFrameBuffer() -> [UInt8] {
    wrapper.getFrameBufferBGRA()  // Returns copied [UInt8] array
}
```

**Rationale:**
- `[UInt8]` is `Sendable` and can safely cross actor boundaries
- Avoids pointer lifetime issues
- Palette conversion (indexed → BGRA) happens inside the actor
- Slight memory overhead acceptable for 384×240×4 = 369KB per frame

#### NTSC Palette

The 256-color Atari palette is built into `LibAtari800Wrapper`:
- Computed once at initialization
- Stored as `[UInt32]` in BGRA format for direct Metal upload
- Standard NTSC color approximation with 16 hues × 16 luminances

### Phase 3: Metal Renderer

#### Embedded Shaders

**Original Design:** Separate `.metal` shader files.

**Implementation:** Shaders embedded as Swift string literal:

```swift
private static let shaderSource = """
#include <metal_stdlib>
using namespace metal;
// ... shader code
"""
```

**Rationale:**
- SPM resource bundling for `.metal` files is complex
- Embedded shaders compile at runtime via `device.makeLibrary(source:)`
- Single source of truth - no separate file to keep in sync
- Acceptable compile time (~100ms at first launch)

#### @MainActor for Metal Classes

**Implementation:** `MetalRenderer` is `@MainActor`:

```swift
@MainActor
public class MetalRenderer: NSObject, MTKViewDelegate {
    // ...
}
```

**Rationale:**
- MTKView properties are main-actor isolated in Swift 6
- Metal device configuration must happen on main thread
- Delegate callbacks naturally arrive on main thread
- Eliminates concurrency warnings

#### Thread-Safe Texture Updates

```swift
private let textureLock = NSLock()
private var pendingFrameBuffer: [UInt8]?

public func updateTexture(with pixels: [UInt8]) {
    textureLock.lock()
    pendingFrameBuffer = pixels
    textureLock.unlock()
}

private func uploadPendingFrame() {
    // Called in draw() on render thread
    textureLock.lock()
    guard let pixels = pendingFrameBuffer else { ... }
    pendingFrameBuffer = nil
    textureLock.unlock()
    // Upload to Metal texture
}
```

**Pattern:** Producer-consumer with atomic swap - emulation produces frames, render thread consumes them.

### Phase 4: Audio Engine

#### Ring Buffer Capacity

**Original Design:** "~23ms latency target" with 1024 sample buffer.

**Implementation:** 8192 sample ring buffer (~185ms at 44100 Hz).

```swift
public static let ringBufferCapacity: Int = 8192
```

**Rationale:**
- Real-time audio needs buffer headroom for timing variations
- Emulation frame timing (16.67ms) has inherent jitter
- Larger buffer prevents underruns at cost of slightly higher latency
- Actual latency still feels responsive for emulation use case

#### Sample Format Conversion

**Implementation:** Supports both 8-bit and 16-bit PCM from libatari800:

```swift
if emulatorSampleSize == 16 {
    // 16-bit signed PCM → Float
    samples = int16Samples.map { Float($0) / 32768.0 * volume }
} else {
    // 8-bit unsigned PCM → Float
    samples = uint8Samples.map { (Float($0) - 128.0) / 128.0 * volume }
}
```

**Key Decisions:**
- libatari800 configured with `-audio16` flag for better quality
- Conversion to Float happens in `AudioEngine`, not in actor
- Volume applied during conversion for efficiency

#### Sendable Audio Buffer

**Challenge:** Raw pointers are not `Sendable` in Swift 6.

**Solution:** Added `getAudioSamples() -> [UInt8]` to EmulatorEngine:

```swift
public func getAudioSamples() -> [UInt8] {
    let (pointer, count) = wrapper.getAudioBuffer()
    guard let pointer = pointer, count > 0 else { return [] }
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}
```

**Trade-off:** Extra copy vs. type safety. Acceptable because:
- Audio buffers are small (~735 bytes per frame at 44100 Hz / 60 fps)
- Copy happens once per frame
- Enables clean actor boundaries

### Emulation Loop Architecture

The emulation loop runs at 60fps, coordinating video and audio:

```
┌─────────────────────────────────────────────────────────────┐
│                   AtticViewModel (MainActor)                 │
│                                                              │
│   emulationLoop() async {                                    │
│       while !Task.isCancelled {                              │
│           if isRunning {                                     │
│               // 1. Execute emulation                        │
│               let result = await emulator.executeFrame()     │
│                                                              │
│               // 2. Get video frame (Sendable [UInt8])       │
│               let frameBuffer = await emulator.getFrameBuffer()│
│                                                              │
│               // 3. Get audio samples (Sendable [UInt8])     │
│               let audioSamples = await emulator.getAudioSamples()│
│                                                              │
│               // 4. Update display                           │
│               renderer?.updateTexture(with: frameBuffer)     │
│                                                              │
│               // 5. Feed audio                               │
│               audioEngine.enqueueSamples(bytes: audioSamples)│
│           }                                                  │
│           // Sleep to maintain 60fps                         │
│           try? await Task.sleep(nanoseconds: 16_666_667)     │
│       }                                                      │
│   }                                                          │
└─────────────────────────────────────────────────────────────┘
```

**Key Design Decisions:**
- Loop runs on `@MainActor` (AtticViewModel)
- Actor boundary crossings use `await` and Sendable types
- Frame timing uses `Task.sleep`, not display link (simpler for now)
- Audio and video buffers extracted after each frame

### Phase 5: Keyboard Input

#### NSEvent Local Monitor vs First Responder

**Original Design:** Make an NSView first responder to receive keyboard events.

**Implementation:** Use `NSEvent.addLocalMonitorForEvents` to capture keyboard events at the application level.

```swift
keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    if event.modifierFlags.contains(.command) {
        return event  // Let menu shortcuts through
    }
    self?.onKeyDown?(event)
    return nil  // Consume event (prevents system beep)
}
```

**Rationale:**
- First responder status is unreliable in SwiftUI layouts
- NSViewRepresentable views may not receive proper focus
- Local monitors capture all keyboard events sent to the app
- Works regardless of which view has focus within the window

**Trade-offs:**
- Monitors must be properly removed in deinit to prevent leaks
- All keys go to emulator (Command combinations excluded for menu shortcuts)

#### Application Activation Policy

**Challenge:** Running via `swift run` treats the app as a background process.

**Implementation:** Set activation policy in AppDelegate:

```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
}

func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)
}
```

**Rationale:**
- `.regular` policy makes app show in Dock with menu bar
- `activate(ignoringOtherApps:)` brings app to foreground
- Without this, keyboard events go to terminal, not GUI

#### Keyboard Handler Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    KeyEventView (SwiftUI)                    │
│                 NSViewRepresentable wrapper                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  KeyCaptureNSView (AppKit)                   │
│              Sets up NSEvent local monitors                  │
│     - keyDown monitor → onKeyDown callback                   │
│     - keyUp monitor → onKeyUp callback                       │
│     - flagsChanged monitor → onFlagsChanged callback         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               AtticViewModel (handleKeyDown, etc.)           │
│                                                              │
│   1. Update modifier state in KeyboardInputHandler           │
│   2. Convert Mac keyCode → Atari AKEY_* constant             │
│   3. Send to EmulatorEngine via pressKey/releaseKey          │
│   4. Update console keys (START/SELECT/OPTION)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                KeyboardInputHandler (AtticCore)              │
│                                                              │
│   - Maps Mac virtual key codes to Atari key codes            │
│   - Tracks modifier state (Shift, Control)                   │
│   - Tracks console keys (F1=START, F2=SELECT, F3=OPTION)     │
│   - Handles special keys (arrows, backtick=ATARI key)        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    EmulatorEngine (Actor)                    │
│                                                              │
│   pressKey(keyChar:keyCode:shift:control:)                   │
│   releaseKey()                                               │
│   setConsoleKeys(start:select:option:)                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  LibAtari800Wrapper                          │
│                                                              │
│   Uses input_template_t structure:                           │
│   - input.keychar = AKEY_* constant                          │
│   - input.keycode = scancode                                 │
│   - input.shift/control = modifier state                     │
│   - input.start/select/option = console keys                 │
│                                                              │
│   Called via libatari800_input_frame(&input)                 │
└─────────────────────────────────────────────────────────────┘
```

#### Key Mapping Table

The `KeyboardInputHandler` maps Mac virtual key codes to Atari `AKEY_*` constants:

| Mac Key Code | Mac Key | Atari AKEY |
|--------------|---------|------------|
| 0 | A | AKEY_a (0x3F) |
| 1 | S | AKEY_s (0x3E) |
| ... | ... | ... |
| 122 | F1 | START (console) |
| 120 | F2 | SELECT (console) |
| 99 | F3 | OPTION (console) |
| 50 | ` | AKEY_ATARI (Atari key) |
| 123-126 | Arrows | AKEY_LEFT/RIGHT/DOWN/UP |

**Special Handling:**
- F1/F2/F3 set console keys rather than regular key codes
- Backtick (`) maps to ATARI key for inverse video toggle
- Shift and Control states forwarded directly to emulator
- Command key combinations excluded to allow menu shortcuts

#### Console Buttons UI

The START/SELECT/OPTION buttons in the control panel:
- Reflect keyboard state (highlight when F1/F2/F3 pressed)
- Support mouse press/release for click interaction
- Use `DragGesture(minimumDistance: 0)` for proper press detection

```swift
ConsoleButton(
    label: "START",
    key: "F1",
    isPressed: viewModel.keyboardHandler.startPressed,
    onPress: { Task { await emulator.setConsoleKeys(start: true, ...) } },
    onRelease: { Task { await emulator.setConsoleKeys(start: false, ...) } }
)
```

### Phase 14: BASIC Tokenizer

This phase implements BASIC program entry via the REPL. Key architectural decisions:

#### Tokenization Location: Server-Side

Tokenization happens in **AtticServer**, not in the CLI client. The CLI sends raw BASIC text via the existing socket protocol, and the server tokenizes and injects into emulator memory.

**Rationale**: Keeps the emulator logic centralized. CLI remains a thin client.

#### State Management: Emulator-Primary

The emulator memory is the **single source of truth** for BASIC programs. Swift does not maintain a shadow copy of the program or variable tables.

- When entering a line: Parse, tokenize, inject into emulator memory
- When listing: Read from emulator memory, detokenize
- No caching of program state in Swift

**Implications**:
- Each line entry reads current BASIC pointers from zero page
- Variable table lookups scan emulator memory
- Programs loaded via Atari DOS are immediately visible

#### Injection Timing: Line-by-Line (Immediate)

Each BASIC line is tokenized and injected **immediately** when entered, exactly like real Atari BASIC.

**Process for entering `10 PRINT "HELLO"`**:
1. Parse the line number and content
2. Read current BASIC pointers from zero page (VNTP, VVTP, STMTAB, etc.)
3. Scan existing variable table in emulator memory
4. Add any new variables to VNT/VVT
5. Tokenize the statement
6. Insert/replace the line in the statement table
7. Update all BASIC pointers in zero page
8. Return success response

#### Variable Creation: On First Reference

Variables are created in the Variable Name Table when first encountered during tokenization, matching Atari BASIC behavior.

**Example**:
```
10 LET X=5     <- Variable X created in VNT, entry added to VVT
20 PRINT X     <- Variable X looked up, index used in tokenized form
30 LET Y=X+1   <- Variable Y created, X looked up
```

#### Tokenizer Architecture: Stateless Struct

The tokenizer is a **stateless struct** that operates on input and emulator state:

```swift
struct BASICTokenizer {
    /// Tokenizes a BASIC line and returns the tokenized bytes.
    /// Does NOT modify emulator memory - caller handles injection.
    func tokenizeLine(
        _ line: String,
        existingVariables: [BASICVariable]
    ) throws -> TokenizedLine
}
```

The `REPLEngine` or `BASICLineHandler` coordinates:
1. Reading current state from emulator
2. Calling tokenizer
3. Writing results back to emulator

#### Error Reporting: Immediate

Errors are reported immediately when a line is entered, matching Atari BASIC behavior.

**Response format**:
```
OK:Line 10 stored (23 bytes)
```
or
```
ERR:Syntax error at column 15: Unknown keyword 'PRIMT'. Did you mean 'PRINT'?
```

#### Turbo BASIC: Deferred

Turbo BASIC XL support is **deferred to a future phase**. Phase 14 implements standard Atari BASIC only. The `REPLMode.basic(variant:)` enum already supports `.turbo` for future use.
