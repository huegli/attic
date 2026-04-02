# Atari 800 XL Emulator Project

## Project Overview

This is a macOS application that emulates the Atari 800 XL home computer. It uses a client-server architecture where the emulator runs as a standalone server (AtticServer) communicating with clients via the Attic Emulator Server Protocol (AESP). Clients include a native SwiftUI/Metal GUI, a CLI tool for REPL-based interaction, and a browser-based web client.

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
│   └── AtticMCP/               # MCP server (Swift, archived — see README.md)
├── Libraries/
│   └── libatari800/            # Pre-compiled emulator core
├── Python/
│   ├── AtticCLI/               # Python CLI (click + prompt_toolkit + rich)
│   └── AtticMCP/               # MCP server (Python/FastMCP, active)
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
7. **MCP Integration**: AtticMCP server exposes emulator tools to AI assistants like Claude Code

## Versioning

This project uses [Semantic Versioning](https://semver.org/). See `CHANGELOG.md` for release history.

### Single Source of Truth

The version string in `Sources/AtticCore/AtticCore.swift` (`AtticCore.version`) is the
**single source of truth** for all version numbers. When the version is bumped, these
locations are updated automatically or must be kept in sync:

| Location | How it stays in sync |
|----------|---------------------|
| `Sources/AtticCore/AtticCore.swift` | **Primary** — edit here |
| `Sources/AtticGUI/Info.plist` | Must be updated to match |
| `scripts/make-app.sh` output | Auto-injected from AtticCore.swift at build time |
| About dialog (`AtticApp.swift`) | Reads `AtticCore.version` directly |
| Git tag | Create `vX.Y.Z` tag at release commit |
| `CHANGELOG.md` | Add new `## [X.Y.Z]` section |

### Version Update Rules

- **Version bumps are user-initiated only.** Never bump the version without an explicit request.
- **Patch** (0.1.x): All automated tests must pass (`make test`).
- **Minor** (0.x.0): Tests must pass, plus the user must complete manual testing of all features added or changed in the minor release.
- **Major** (x.0.0): Tests must pass, plus the user must complete manual testing of all core features.

### Protocol Freeze

Both AESP and CLI Protocol specifications are **frozen**. No protocol changes unless accompanied by a major version bump. See `docs/PROTOCOL.md`.

## Implementation Status

See `docs/IMPLEMENTATION_PLAN.md` for detailed phase-by-phase progress. Summary:

**Complete (v0.1.0 — MVP):**
- Phase 1-5: libatari800 wrapper, Metal renderer, Audio engine, Keyboard input, BASIC interaction
- Phase 6: AESP Protocol Library (AtticProtocol module)
- Phase 7: Emulator Server (AtticServer executable)
- Phase 8: GUI as Protocol Client (AtticGUI connects to AtticServer via AESP)
- Phase 9-17: CLI socket protocol, joystick input, 6502 disassembler, monitor mode, ATR filesystem, DOS mode, BASIC tokenizer, state save/load, polish
- Phase 18-19: WebSocket bridge and web browser client

**Dual Launch Modes:**
- **GUI mode**: AtticGUI launches AtticServer with AESP TCP enabled (default)
- **Web mode**: `attic-py` launches AtticServer with `--no-aesp --websocket`; `.gui` REPL command serves the web client

## Key Files to Reference

- `CHANGELOG.md` - Release history (Semantic Versioning)
- `docs/ARCHITECTURE.md` - System architecture details
- `docs/SPECIFICATION.md` - Complete feature specification (includes versioning policy)
- `docs/PROTOCOL.md` - CLI/GUI socket protocol (FROZEN)
- `docs/MCP_USAGE.md` - MCP server tools for Claude Code integration
- `docs/BASIC_TOKENIZER.md` - BASIC tokenization implementation
- `docs/ATR_FILESYSTEM.md` - ATR disk image format
- `docs/6502_SPECIFICATION.md` - Complete 6502 CPU specification (SALLY/6502C)
- `docs/ASSEM_DISSASSEM.md` - Assembler, disassembler, and breakpoint implementation
- `docs/REPL_COMMANDS.md` - All REPL commands
- `docs/IMPLEMENTATION_PLAN.md` - Step-by-step implementation guide

## Coding Guidelines

- Use Swift's structured concurrency (async/await, actors) for thread safety
- EmulatorEngine should be an actor to serialize access from multiple sources
- Memory operations on the emulator must pause execution first
- Error messages should be detailed with suggestions for correction

## Testing Approach

- Unit tests for tokenizer, detokenizer, ATR parser, disassembler
- Integration tests for socket protocol
- Manual testing with terminal REPL and web client

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

This project includes an MCP server (AtticMCP) implemented in Python using FastMCP that allows Claude Code to directly interact with the Atari 800 XL emulator. The source is in `Python/AtticMCP/` and the `.mcp.json` file in the project root configures this integration.

### Prerequisites

AtticServer must be running before using MCP tools:

```bash
swift run AtticServer
```

The MCP server requires Python 3.10+ and uv. It is launched automatically by Claude Code via `.mcp.json`.

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
| `emulator_assemble_block` | Assemble multiple instructions as a block |
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

# Tests (full suite ~61s)
swift test

# Tests via Makefile (see docs/TESTING.md for details)
make test-smoke    # Fast feedback, skips slow integration suites (~3s)
make test-unit     # Pure unit tests only (~2s)
make test-basic    # BASIC tokenizer/detokenizer (<1s)
make test-asm      # Assembler/disassembler/6502 (<1s)
make test-atr      # ATR filesystem (<1s)
make test-core     # Core emulator types + frame rate (<1s)
make test-perf     # Performance: frame rate, audio, memory (~2s)
make test-error    # Error handling: missing ROMs, invalid files, network (<1s)
make test-state    # State persistence save/load/integrity (<1s)
make test-multiclient # Multi-client: multiple GUIs, CLI+GUI together (~12s)
make test-protocol # AESP protocol (messages, server, E2E) (~15s)
make test-cli      # CLI parsing, sockets, subprocesses (~37s)
make test-server   # AtticServer subprocess tests (~7s)
make test          # Full suite (~61s)
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


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
