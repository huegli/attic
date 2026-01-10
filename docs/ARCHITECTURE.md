# System Architecture

## Overview

The Atari 800 XL Emulator is a macOS application consisting of two cooperating executables:

1. **Atari800GUI** - SwiftUI application with Metal rendering and audio output
2. **Atari800CLI** - Command-line REPL tool for Emacs integration

Both share a common core library (`Atari800Core`) containing the emulator wrapper, REPL logic, tokenizers, and file format handlers.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Atari800Core                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │   Emulator/     │  │    Monitor/     │  │      BASIC/         │  │
│  │ EmulatorEngine  │  │   Monitor       │  │  BasicTokenizer     │  │
│  │ LibAtari800Wrap │  │   Disassembler  │  │  BasicDetokenizer   │  │
│  │ MemoryBus       │  │   Assembler     │  │  TokenTables        │  │
│  │ StateManager    │  │   BreakpointMgr │  │  BasicMemoryLayout  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │      DOS/       │  │      REPL/      │  │      Audio/         │  │
│  │   ATRImage      │  │   REPLEngine    │  │   AudioEngine       │  │
│  │   AtariFileSys  │  │   CommandParser │  │                     │  │
│  │   DOSCommands   │  │   MonitorMode   │  │                     │  │
│  │                 │  │   BasicMode     │  │                     │  │
│  │                 │  │   DOSMode       │  │                     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
           │                           │
           ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │   Atari800GUI   │◄───────►│   Atari800CLI   │
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

### Socket Architecture

The GUI opens a Unix domain socket at `/tmp/atari800-<pid>.sock` on startup. The CLI connects to this socket to send commands and receive responses/events.

```
CLI Process                          GUI Process
┌──────────────┐                    ┌──────────────┐
│   stdin ─────┼──► CommandParser   │              │
│              │         │          │  Socket      │
│   REPLEngine │         ▼          │  Listener    │
│       │      │    SocketClient ──►│      │       │
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
3. CLI parses command and sends to GUI via socket
4. GUI executes command against EmulatorEngine
5. GUI sends response via socket
6. CLI formats response and writes to stdout
7. Emacs displays in comint buffer

### Async Events

The GUI can send unsolicited events (breakpoint hits, emulator stopped). The CLI must handle these and display appropriately:

```
EVENT:breakpoint $600A
* Breakpoint hit at $600A
  A=$4F X=$00 Y=$03 S=$F7 P=N.....C
[monitor] $600A>
```

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
    magic: [UInt8; 4] = "A8XL"
    version: UInt16
    timestamp: UInt64
    
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
    let magic: String = "A8XL"
    let version: Int = 1
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
