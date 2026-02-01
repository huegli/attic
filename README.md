# Attic

**A macOS Atari 800 XL emulator with Emacs integration**

Attic is an Atari 800 XL emulator designed for developers and retrocomputing enthusiasts. It pairs a native SwiftUI/Metal GUI with a powerful REPL interface that integrates seamlessly with Emacs.

## Features

- **Native macOS app** — SwiftUI interface with Metal rendering at 60fps
- **Emacs integration** — Full comint-mode REPL for debugging, BASIC programming, and disk management
- **6502 monitor** — Disassembler, assembler, breakpoints, memory inspection, and single-stepping
- **BASIC mode** — Enter and edit Atari BASIC programs directly from your terminal
- **DOS mode** — Mount, browse, and manipulate ATR disk images
- **Dual architecture** — GUI and CLI as separate processes communicating over Unix socket

## Requirements

- macOS 26.0 or later
- Atari 800 XL ROM files (not included)
  - `ATARIXL.ROM` — 16KB OS ROM
  - `ATARIBAS.ROM` — 8KB BASIC ROM

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/attic.git
cd attic
```

Place your ROM files in one of these locations:
- `Resources/ROM/` (project directory)
- `~/.attic/ROM/`
- `~/Library/Application Support/Attic/ROM/`

Required ROM files:
- `ATARIXL.ROM` — 16KB Atari XL OS ROM
- `ATARIBAS.ROM` — 8KB Atari BASIC ROM

## Building & Running

Attic can be built and run using either the Swift command-line tools or Xcode.

### Using Swift CLI

```bash
# Build all targets (debug)
swift build

# Build all targets (release, optimized)
swift build -c release

# Run the GUI application
swift run AtticGUI

# Run the CLI in headless mode
swift run attic --headless

# Run the CLI with audio disabled
swift run attic --headless --silent

# Run the emulator server (AESP protocol)
swift run AtticServer
swift run AtticServer --rom-path /path/to/roms

# Run tests
swift test
```

### Using Xcode

This is a Swift Package Manager project. Open it in Xcode by double-clicking `Package.swift` or:

```bash
open Package.swift
```

**Available Schemes:**

| Scheme | Description |
|--------|-------------|
| AtticGUI | Main GUI application (SwiftUI + Metal) |
| AtticServer | Standalone emulator server (AESP protocol) |
| attic | Command-line REPL tool |
| AtticCore | Shared framework (emulator, audio, input) |
| AtticProtocol | AESP protocol framework |

**To build and run:**
1. Select the desired scheme from the scheme selector (top-left of Xcode)
2. Press `Cmd+R` to build and run, or `Cmd+B` to build only

**Build configurations:**
- **Debug** — Includes debug symbols, no optimization, assertions enabled
- **Release** — Optimized build, suitable for distribution

### Project Structure

```
Attic/
├── Sources/
│   ├── AtticCore/        # Shared library (emulator engine, audio, input)
│   ├── AtticProtocol/    # AESP binary protocol (server/client communication)
│   ├── AtticServer/      # Standalone emulator server executable
│   ├── AtticCLI/         # Command-line REPL executable
│   └── AtticGUI/         # SwiftUI + Metal GUI application
├── Libraries/
│   └── libatari800/      # Pre-compiled Atari 800 emulator core
├── Resources/
│   └── ROM/              # Place ROM files here
├── Tests/
│   └── AtticCoreTests/   # Unit tests
└── Package.swift         # Swift Package Manager configuration (open in Xcode)
```

## Debugging

### Debugging with Xcode

1. **Set breakpoints**: Click in the gutter next to any line of Swift code
2. **Run in debug mode**: Press `Cmd+R` (Debug is the default configuration)
3. **Use the debug console**: View variables, evaluate expressions with LLDB

**Useful debug features:**
- **View hierarchy debugger**: `Debug > View Debugging > Capture View Hierarchy`
- **Memory graph**: `Debug > Debug Memory Graph`
- **GPU debugger**: `Debug > Capture GPU Workload` (for Metal rendering issues)

**Console commands (LLDB):**
```lldb
# Print a variable
po variableName

# Print emulator state
po await emulator.state

# Examine memory (emulator's virtual memory)
# Set a breakpoint in EmulatorEngine and use:
po self.readMemory(at: 0x600)

# Continue execution
c

# Step over
n

# Step into
s
```

### Debugging with Swift CLI + LLDB

```bash
# Build with debug symbols
swift build

# Run with LLDB
lldb .build/debug/AtticGUI

# In LLDB:
(lldb) run
(lldb) breakpoint set --file EmulatorEngine.swift --line 150
(lldb) breakpoint set --name "EmulatorEngine.executeFrame"
```

### Debugging the Emulator

The REPL monitor mode provides 6502-level debugging:

```
# Switch to monitor mode
[basic] > .monitor

# Disassemble at address
[monitor] $E477> d $E477 8

# Set a breakpoint
[monitor] $E477> bp $600A

# View registers
[monitor] $E477> r

# Step one instruction
[monitor] $E477> s

# Continue execution
[monitor] $E477> g

# View memory
[monitor] $E477> m $0600 32
```

### Common Issues

**Build fails with "module 'CAtari800' not found":**
- Ensure `Libraries/libatari800/lib/libatari800.a` exists
- Ensure `Libraries/libatari800/include/libatari800.h` exists
- Check that `Libraries/libatari800/module.modulemap` is present

**"ROM not found" error at runtime:**
- Place `ATARIXL.ROM` and `ATARIBAS.ROM` in `Resources/ROM/`
- Or specify path: `swift run AtticServer --rom-path /path/to/roms`

**Xcode can't find frameworks:**
- Clean build folder: `Cmd+Shift+K`
- Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/Attic-*`
- Rebuild: `Cmd+B`

**Linker warnings about macOS version:**
- These are benign warnings from libatari800 and can be ignored

## Usage

### GUI

Launch `Attic.app` to start the emulator. The Atari boots directly to the BASIC `READY` prompt.

### CLI

```bash
# Start REPL (launches GUI automatically)
attic --repl

# Connect to running GUI
attic --socket /tmp/attic-12345.sock

# Run headless (no GUI)
attic --headless
```

### REPL Modes

Switch between modes with dot-commands:

```
[basic] > .monitor
[monitor] $E477> .dos  
[dos] D1:> .basic
[basic] >
```

**Monitor mode** — Debug 6502 code:
```
[monitor] $E477> d $E477 8
$E477  A9 00     LDA #$00
$E479  8D 00 D4  STA $D400
...

[monitor] $E477> bp $E479
Breakpoint set at $E479

[monitor] $E477> g
```

**BASIC mode** — Write programs:
```
[basic] > 10 FOR I=1 TO 10
[basic] > 20 PRINT I
[basic] > 30 NEXT I
[basic] > run
```

**DOS mode** — Manage disks:
```
[dos] D1:> mount 1 ~/disks/games.atr
[dos] D1:> dir
 GAME1    COM    28
 GAME2    COM    45
 2 files, 73 sectors used
```

## Emacs Integration

Add to your init file:

```elisp
(add-to-list 'load-path "/path/to/attic/emacs")
(require 'attic)
```

Then `M-x attic-run` to start the REPL in a comint buffer.

Key bindings in `attic-mode`:
| Key | Command |
|-----|---------|
| `C-c C-m` | Switch to monitor |
| `C-c C-b` | Switch to BASIC |
| `C-c C-d` | Switch to DOS |
| `C-c C-g` | Go (resume) |
| `C-c C-n` | Step instruction |
| `C-c C-p` | Pause |

## Architecture

Attic uses a client-server architecture where the emulator runs as a standalone server process:

```
                         ┌─────────────────┐
                         │  AtticServer    │
                         │  (Emulator)     │
                         │                 │
                         │  libatari800    │
                         └───────┬─────────┘
                                 │ AESP Protocol
              ┌──────────────────┼──────────────────┐
              │                  │                  │
              ▼                  ▼                  ▼
       ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
       │  AtticGUI   │    │  AtticCLI   │    │  (Future)   │
       │             │    │             │    │  Web Client │
       │  SwiftUI    │    │  REPL       │    │             │
       │  Metal      │    │             │    │  WebSocket  │
       │  Audio      │    └──────┬──────┘    └─────────────┘
       └─────────────┘           │
                                 ▼
                          ┌─────────────┐
                          │   Emacs     │
                          │  comint     │
                          └─────────────┘
```

**AESP (Attic Emulator Server Protocol):**
- Binary protocol over TCP for efficient video/audio streaming
- Control port (47800): Commands, status, memory access, input events
- Video port (47801): 60fps frame broadcasts (384x240 BGRA)
- Audio port (47802): 44.1kHz PCM audio streaming

Multiple clients can connect to the same server, making it possible to debug from your editor while watching the display update in real time.

## Documentation

See the `docs/` directory for detailed specifications:

- [Architecture](docs/ARCHITECTURE.md) — System design and threading model
- [REPL Commands](docs/REPL_COMMANDS.md) — Complete command reference
- [BASIC Tokenizer](docs/BASIC_TOKENIZER.md) — How BASIC programs are encoded
- [ATR File System](docs/ATR_FILESYSTEM.md) — Disk image format
- [6502 Reference](docs/6502_REFERENCE.md) — Instruction set and opcodes
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md) — Development roadmap

## Acknowledgments

- [libatari800](https://github.com/atari800/atari800) — The emulation core
- [Altirra](https://virtualdub.org/altirra.html) — Reference for hardware accuracy
- [Mapping the Atari](https://www.atariarchives.org/mapping/) — Essential memory map documentation

## License

MIT License. See [LICENSE](LICENSE) for details.

---

*Attic is not affiliated with Atari, Inc. Atari and the Atari 800 XL are trademarks of Atari Interactive, Inc.*
