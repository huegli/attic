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

- macOS 15.0 (Sequoia) or later
- Atari 800 XL ROM files (not included)
  - `ATARIXL.ROM` — 16KB OS ROM
  - `ATARIBAS.ROM` — 8KB BASIC ROM

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/attic.git
cd attic

# Build
swift build -c release

# Run the GUI
swift run Attic.app

# Or use the CLI
swift run attic --repl
```

Place your ROM files in `~/.config/attic/roms/` or in the app bundle's `Resources/ROM/` directory.

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

```
┌─────────────┐         ┌─────────────┐
│  AtticGUI   │◄───────►│  AtticCLI   │
│             │  Unix   │             │
│  SwiftUI    │ Socket  │  REPL       │
│  Metal      │         │             │
│  Audio      │         └──────┬──────┘
└─────────────┘                │
                               ▼
                        ┌─────────────┐
                        │   Emacs     │
                        │  comint     │
                        └─────────────┘
```

The GUI owns the emulator core. The CLI connects over a Unix socket, making it possible to debug from your editor while watching the display update in real time.

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
