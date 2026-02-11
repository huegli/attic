# Atari 800 XL Emulator Project

## Project Overview

This is a macOS application that emulates the Atari 800 XL home computer. It uses a client-server architecture where the emulator runs as a standalone server (AtticServer) communicating with clients via the Attic Emulator Server Protocol (AESP). Clients include a native SwiftUI/Metal GUI and a CLI tool for REPL-based interaction designed to work with Emacs comint mode.

## Technology Stack

- **Language**: Swift 5.9+
- **Platform**: macOS 15+ (Sequoia)
- **UI Framework**: SwiftUI
- **Graphics**: Metal
- **Audio**: Core Audio (AVAudioEngine)
- **Networking**: Network framework (NWListener, NWConnection for AESP)
- **Emulation Core**: libatari800 (pre-compiled C library)
- **Game Input**: GameController framework

## Project Structure

```
attic/
├── Package.swift
├── .mcp.json                   # MCP server configuration for Claude Code
├── Sources/
│   ├── AtticCore/              # Shared library (emulator, REPL, tokenizer)
│   ├── AtticProtocol/          # AESP binary protocol (message types, server, client)
│   ├── AtticServer/            # Standalone emulator server executable
│   ├── AtticCLI/               # Command-line executable (attic)
│   ├── AtticGUI/               # SwiftUI + Metal application (AtticGUI)
│   └── AtticMCP/               # MCP server for Claude Code integration
├── Libraries/
│   └── libatari800/            # Pre-compiled emulator core
└── Resources/
    └── ROM/                    # User-provided Atari ROMs
```

## Key Architecture Decisions

1. **Client-Server Architecture**: Emulator runs as standalone AtticServer process, clients connect via AESP protocol
2. **AESP Protocol**: Binary protocol with three channels - Control (47800), Video (47801), Audio (47802)
3. **Separate Executables**: CLI and GUI are distinct client executables; CLI uses text protocol, GUI uses AESP
4. **CLI Launches GUI**: By default, CLI starts the GUI if not running; `--headless` flag for no-GUI operation
5. **BASIC Tokenization**: We tokenize BASIC source and inject into emulator memory rather than interpreting
6. **BRK-Based Breakpoints**: Debugger uses 6502 BRK instruction ($00) for breakpoints
7. **Emacs Integration**: REPL designed for comint compatibility with clear prompts
8. **MCP Integration**: AtticMCP server exposes emulator tools to AI assistants like Claude Code

## Implementation Status

See `docs/IMPLEMENTATION_PLAN.md` for detailed phase-by-phase progress. Summary:

**Complete:**
- Phase 1-5: libatari800 wrapper, Metal renderer, Audio engine, Keyboard input, BASIC interaction
- Phase 6: AESP Protocol Library (AtticProtocol module)
- Phase 7: Emulator Server (AtticServer executable)
- Phase 8: GUI as Protocol Client (AtticGUI connects to AtticServer via AESP)

**Pending:**
- Phase 9-17: CLI socket protocol, joystick input, 6502 disassembler, monitor mode, ATR filesystem, DOS mode, BASIC tokenizer, state save/load, polish
- Phase 18-19: WebSocket bridge and web browser client

## Key Files to Reference

- `docs/ARCHITECTURE.md` - System architecture details
- `docs/SPECIFICATION.md` - Complete feature specification
- `docs/PROTOCOL.md` - CLI/GUI socket protocol
- `docs/MCP_USAGE.md` - MCP server tools for Claude Code integration
- `docs/BASIC_TOKENIZER.md` - BASIC tokenization implementation
- `docs/ATR_FILESYSTEM.md` - ATR disk image format
- `docs/6502_REFERENCE.md` - 6502 instruction set reference
- `docs/REPL_COMMANDS.md` - All REPL commands
- `docs/IMPLEMENTATION_PLAN.md` - Step-by-step implementation guide

## Coding Guidelines

- Use Swift's structured concurrency (async/await, actors) for thread safety
- EmulatorEngine should be an actor to serialize access from multiple sources
- Memory operations on the emulator must pause execution first
- All REPL output must end with the appropriate prompt for comint compatibility
- Error messages should be detailed with suggestions for correction

## Testing Approach

- Unit tests for tokenizer, detokenizer, ATR parser, disassembler
- Integration tests for socket protocol
- Manual testing with Emacs comint for REPL interaction

## Comments
- Add detailed comments to all the files that make up this project.
- Assume that the reader has some good general understanding of programing but is a beginner in Swift and not familiar with particular MacOS Application specific programming patterns and conventions like protocols, SwiftUI, Metal etc.
- Highlight in particular best practices to use for MacOS App Development using Swift
- IMPORTANT: Keep the comments updated as you make changes to the code!!!

## Issue Tracking with Beads

This project uses [Beads](https://github.com/steveyegge/beads) (`bd`) for issue tracking. Beads stores issues directly in the repository (`.beads/issues.jsonl`), making it perfect for AI-assisted development workflows.

### Quick Reference

```bash
# See what's ready to work on
bd ready

# Create an issue
bd create "Implement feature X" -p 1

# Update status
bd update <id> --status in_progress

# Close when done
bd close <id> --reason "Completed and tested"

# Sync before ending session
bd sync
```

### For AI Agents

**Starting a session:**
- Run `bd ready` to find actionable work
- Review issue details with `bd show <id>`

**During development:**
- Update status: `bd update <id> --status in_progress`
- Add notes: `bd update <id> --notes "Found issue in X"`
- Create new issues for discovered work

**Ending a session ("landing the plane"):**
1. Close completed issues
2. Create issues for remaining work
3. Run `bd sync` to push changes
4. Verify with `git status`

**WARNING**: Never use `bd edit` (opens interactive editor). Use `bd update` with flags instead.

See `BEADS-QUICKSTART.md` for complete setup and usage instructions.

## MCP Integration (Claude Code)

This project includes an MCP server (AtticMCP) that allows Claude Code to directly interact with the Atari 800 XL emulator. The `.mcp.json` file in the project root configures this integration.

### Prerequisites

AtticServer must be running before using MCP tools:

```bash
swift run AtticServer
```

### Available Tools

When working in this repository, Claude Code has access to these emulator tools:

| Tool | Description |
|------|-------------|
| `emulator_status` | Get emulator state (running/paused, PC, disks, breakpoints) |
| `emulator_pause` | Pause emulation |
| `emulator_resume` | Resume emulation |
| `emulator_reset` | Reset emulator (cold/warm) |
| `emulator_read_memory` | Read bytes from memory |
| `emulator_write_memory` | Write bytes to memory (must be paused) |
| `emulator_get_registers` | Get CPU registers (A, X, Y, S, P, PC) |
| `emulator_set_registers` | Set CPU registers (must be paused) |
| `emulator_execute_frames` | Run for N frames |
| `emulator_disassemble` | Disassemble 6502 code |
| `emulator_set_breakpoint` | Set breakpoint |
| `emulator_clear_breakpoint` | Clear breakpoint |
| `emulator_list_breakpoints` | List all breakpoints |
| `emulator_press_key` | Simulate key press |
| `emulator_screenshot` | Capture display as PNG screenshot |
| `emulator_list_basic` | List BASIC program in memory |

See `docs/MCP_USAGE.md` for detailed documentation and examples.

## External Dependencies

- libatari800: https://github.com/atari800/atari800
- ROMs: User must provide ATARIXL.ROM and ATARIBAS.ROM
- Beads: https://github.com/steveyegge/beads (for issue tracking)

## Building & Running

### Using Swift CLI

```bash
# Build all targets (debug)
swift build

# Build all targets (release, optimized)
swift build -c release

# Run emulator server (required for GUI in client mode)
swift run AtticServer
swift run AtticServer --rom-path ~/ROMs

# Run GUI (launches AtticServer automatically)
swift run AtticGUI

# Run CLI
swift run attic --repl

# Run headless
swift run attic --headless

# Run headless without audio
swift run attic --headless --silent

# Tests
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
| AtticCore | Shared library (emulator, audio, input) |
| AtticProtocol | AESP protocol library |

**To build and run:**
1. Select the desired scheme from the scheme selector (top-left of Xcode)
2. Press `Cmd+R` to build and run, or `Cmd+B` to build only

**Build configurations:**
- **Debug** — Includes debug symbols, no optimization, assertions enabled
- **Release** — Optimized build, suitable for distribution

**Debugging in Xcode:**
- Set breakpoints by clicking in the gutter next to any line
- Use `Debug > View Debugging > Capture View Hierarchy` for SwiftUI issues
- Use `Debug > Capture GPU Workload` for Metal rendering issues
- Clean build if needed: `Cmd+Shift+K` or delete `~/Library/Developer/Xcode/DerivedData/Attic-*`

**Note:** Linker warnings about "macOS version (26.0) than being linked (15.0)" from libatari800 are benign and can be ignored.
