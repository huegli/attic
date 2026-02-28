# Plan: Port Attic CLI to Python

## Overview

Port the Attic CLI (`Sources/AtticCLI/`) from Swift to Python 3.13, producing a
new `Sources/AtticCLI-Python/` package managed with `uv`. The Python CLI will be
a **modern replacement** for the Swift CLI — same commands, same socket protocol,
but with enhanced terminal output leveraging modern emulators like **iTerm2** and
**Ghostty**. The Swift CLI remains unchanged; users choose which to run.

The Python CLI is a **pure protocol client**. All emulation happens in AtticServer
(Swift). The CLI only needs to: parse arguments, connect via Unix socket, run the
REPL loop, translate commands to protocol strings, and display responses. No
libatari800, no Metal, no Core Audio — just text I/O over a socket.

**Target terminals**: iTerm2 and Ghostty (macOS). No Emacs comint support — this
is a dedicated interactive terminal application that takes full advantage of modern
terminal capabilities including true color, inline images, Unicode, and styled text.

---

## Technology Choices

| Concern | Package | Rationale |
|---------|---------|-----------|
| **Environment/packaging** | `uv` + `pyproject.toml` | Fast, modern Python tooling; already used by AtticMCP-Python |
| **CLI argument parsing** | `click` | Mature, composable, supports `--help` generation; lighter than `typer` |
| **Line editing / REPL** | `prompt_toolkit` | Full readline replacement with history, keybindings, multi-line, tab completion, syntax highlighting |
| **Terminal output** | `rich` | True color output, styled tables, syntax highlighting, hex dumps, ATASCII rendering |
| **Inline images** | Kitty graphics protocol (custom, ~30 LOC) | Both iTerm2 and Ghostty support Kitty graphics protocol — single implementation, no extra dependency |
| **Socket client** | stdlib `socket` | Reuse pattern from `AtticMCP-Python/cli_client.py`; no external deps needed |
| **Async events** | `threading` | Background thread to read async `EVENT:` messages from socket; stdlib only |
| **Testing** | `pytest` | Standard Python test framework |

**Python version**: 3.13 (set in `pyproject.toml` as `requires-python = ">=3.13"`)

### Modern Terminal Features Used

| Feature | iTerm2 | Ghostty | Usage |
|---------|--------|---------|-------|
| **True color (24-bit)** | Yes | Yes | Syntax-highlighted disassembly, colored register diffs, ATASCII rendering |
| **Kitty graphics protocol** | Yes | Yes | `.screenshot` displays emulator screen inline in terminal |
| **OSC 8 hyperlinks** | Yes | Yes | Clickable file paths in disk directory listings and error messages |
| **OSC 9;4 progress bars** | Yes | Yes (v1.2+) | Native title-bar progress during long operations (disk format, state load) |
| **OSC 9/777 notifications** | Yes | Yes | Desktop notification when long-running BASIC program completes |
| **OSC 52 clipboard** | Yes | Yes | Copy disassembly or BASIC listings to system clipboard |
| **Unicode** | Full | Full | ATASCII graphics characters, box-drawing for tables, status indicators |
| **Styled underlines** | Yes | Yes | Curly underlines for error highlights in assembly mode |
| **24-bit background colors** | Yes | Yes | Memory dump with heat-map coloring for non-zero bytes |

---

## Project Structure

```
Sources/AtticCLI-Python/
├── pyproject.toml              # uv project: deps, entry point, build system
├── README.md                   # Usage and differences from Swift CLI
├── attic_cli/
│   ├── __init__.py             # Package marker, version constant
│   ├── __main__.py             # `python -m attic_cli` entry point
│   ├── main.py                 # Click CLI entry point, argument parsing
│   ├── cli_client.py           # Socket client (adapted from AtticMCP-Python)
│   ├── protocol.py             # Protocol constants, command enum, response parser
│   ├── repl.py                 # REPL loop: prompt_toolkit integration, mode dispatch
│   ├── modes/
│   │   ├── __init__.py
│   │   ├── base.py             # Base mode class with shared command handling
│   │   ├── monitor.py          # Monitor mode: registers, memory, disassembly, breakpoints, assembly
│   │   ├── basic.py            # BASIC mode: line entry, list, run, vars, file ops
│   │   └── dos.py              # DOS mode: disk management, file operations
│   ├── commands.py             # Global dot-commands (.help, .status, .reset, etc.)
│   ├── translator.py           # Command-to-protocol translation (maps user input → CMD: strings)
│   ├── help.py                 # Help text for all commands (mirrors Swift help system)
│   ├── display.py              # Output formatting: hex dumps, ATASCII, true color, multi-line
│   ├── terminal_images.py      # Inline image display via Kitty graphics protocol
│   ├── terminal_osc.py         # OSC helpers: hyperlinks, notifications, progress, clipboard
│   ├── server_launcher.py      # Find and launch AtticServer subprocess
│   └── history.py              # History file management (~/.attic_history)
└── tests/
    ├── conftest.py             # Shared fixtures (mock socket server, temp sockets)
    ├── test_protocol.py        # Protocol constants, command parsing, response parsing
    ├── test_translator.py      # Command translation (user input → protocol commands)
    ├── test_display.py         # Output formatting, ATASCII rendering
    ├── test_repl.py            # REPL mode switching, prompt generation
    ├── test_help.py            # Help text coverage
    └── test_integration.py     # Full subprocess integration (requires AtticServer)
```

---

## Implementation Phases

### Phase 1: Project Skeleton & Socket Client

**Goal**: Standalone Python package that connects to AtticServer and can ping.

**Files to create**:
- `pyproject.toml` — project metadata, dependencies (`click`, `prompt_toolkit`, `rich`), entry point `attic-py = "attic_cli.main:cli"`
- `attic_cli/__init__.py` — `__version__ = "0.1.0"`
- `attic_cli/__main__.py` — `from .main import cli; cli()`
- `attic_cli/protocol.py` — Port protocol constants from `CLIProtocol.swift`:
  - `COMMAND_PREFIX`, `OK_PREFIX`, `ERROR_PREFIX`, `EVENT_PREFIX`
  - `MULTI_LINE_SEP` (0x1E)
  - Socket path pattern, timeouts
  - `CLIResponse` dataclass (success/error, payload, is_multiline)
  - Response parser function
- `attic_cli/cli_client.py` — Adapt from `AtticMCP-Python/cli_client.py`:
  - `CLISocketClient` class with `discover_socket()`, `connect()`, `disconnect()`, `send()`
  - Add background event reader thread (reads `EVENT:` lines, queues them)
  - Add `drain_events()` to check for pending events
- `attic_cli/server_launcher.py` — Port `ServerLauncher.swift`:
  - `find_server_executable()` — search PATH, `.build/release`, `.build/debug`, standard locations
  - `launch_server(silent, rom_path)` — spawn subprocess, poll for socket (4s timeout)
- `attic_cli/main.py` — Click entry point:
  - `@click.command()` with options: `--silent`, `--socket PATH`, `--headless`, `--version`, `--help`
  - Connect to server (discover or launch), then hand off to REPL
- `attic_cli/terminal_images.py` — Inline image display via Kitty graphics protocol:
  - `display_inline_image(path)` — render PNG inline in terminal
  - Both iTerm2 and Ghostty support the Kitty graphics protocol — single implementation
  - Implementation: base64-encode PNG file, send via APC escape sequences (`\033_Gf=100,a=T;{data}\033\\`)
  - Chunk large images into 4096-byte segments per Kitty protocol spec
  - `supports_kitty_graphics()` — detect support via `$TERM` / `$TERM_PROGRAM` env vars
  - Fallback: print file path if terminal doesn't support inline images
- `attic_cli/terminal_osc.py` — OSC escape sequence helpers:
  - `osc8_link(url, text)` — clickable hyperlink (OSC 8)
  - `osc9_notify(message)` — desktop notification (OSC 9)
  - `osc9_4_progress(value, max)` — title-bar progress bar (OSC 9;4)
  - `osc52_copy(text)` — copy to system clipboard (OSC 52)

**Tests**: `test_protocol.py` — protocol constants, response parsing
**Milestone**: `uv run attic-py --version` prints version; `uv run attic-py` connects and shows banner

---

### Phase 2: REPL Core & Mode Framework

**Goal**: Working REPL loop with mode switching and global dot-commands.

**Files to create**:
- `attic_cli/repl.py` — Main REPL loop:
  - Use `prompt_toolkit.PromptSession` for interactive input
  - Mode enum: `MONITOR`, `BASIC`, `BASIC_TURBO`, `DOS`
  - Styled prompts using prompt_toolkit's `HTML` or `ANSI` formatting:
    - Monitor: `[monitor] $XXXX>` with dim mode tag and bold address
    - BASIC: `[basic] >` or `[basic:turbo] >` with colored mode tag
    - DOS: `[dos] D1:>` with colored drive indicator
  - Tab completion for commands (mode-aware: only show valid commands for current mode)
  - Main loop: read line → check global commands → delegate to current mode handler
  - Handle EOF (Ctrl-D) as graceful exit
  - Handle Ctrl-C as cancel current line
- `attic_cli/modes/base.py` — `BaseMode` ABC:
  - `handle(line, client) -> str | None` — process input, return display text
  - `prompt() -> str` — return mode-specific prompt
- `attic_cli/commands.py` — Global dot-commands (available in all modes):
  - `.monitor` / `.basic` / `.basic turbo` / `.dos` — mode switching
  - `.help [topic]` — contextual help
  - `.status` — emulator status
  - `.reset` / `.warmstart` — cold/warm reset
  - `.screenshot [path]`
  - `.screen` — read text screen
  - `.boot <path>`
  - `.state save|load <path>`
  - `.quit` — disconnect, leave server running
  - `.shutdown` — disconnect and stop server
- `attic_cli/history.py` — History management:
  - Load/save `~/.attic_history` (prompt_toolkit `FileHistory`)
  - Max 500 entries (match Swift)

**Tests**: `test_repl.py` — mode switching, prompt generation
**Milestone**: REPL starts, shows banner, switches modes, `.status` works

---

### Phase 3: Monitor Mode

**Goal**: Full monitor mode with all debugging commands.

**Files to create/update**:
- `attic_cli/modes/monitor.py` — `MonitorMode(BaseMode)`:
  - **Execution**: `g [addr]` (go/resume), `s [n]` (step), `p`/`pause`
  - **Registers**: `r` (display), `r a=42 pc=E000` (set)
  - **Memory**: `m $addr [count]` (dump), `> $addr bytes` (write)
  - **Assembly**: `a $addr [instruction]` (assemble), interactive assembly mode
  - **Breakpoints**: `b set|clear|list $addr`
  - **Disassembly**: `d [$addr] [lines]`
  - Track interactive assembly state (in_assembly, next_address)
- `attic_cli/translator.py` — `translate_monitor(line) -> list[str]`:
  - `g $addr` → `["registers pc=$addr", "resume"]` (multi-command expansion)
  - `m $0600 16` → `["read $0600 16"]`
  - `d` → `["disassemble"]`
  - etc.
- `attic_cli/display.py` — Rich-powered output formatting:
  - `format_memory_dump(data, address)` — hex dump with true-color heat-map for non-zero bytes, ASCII sidebar
  - `format_disassembly(lines)` — syntax-highlighted 6502 assembly (mnemonics, operands, addresses in distinct colors)
  - `format_registers(response)` — register table with changed values highlighted
  - `split_multiline(response)` — split on `\x1E`

**Tests**: `test_translator.py` — all monitor command translations
**Milestone**: Full monitor debugging session works — with richer output than Swift CLI

---

### Phase 4: BASIC Mode

**Goal**: Full BASIC mode with all program editing commands.

**Files to create/update**:
- `attic_cli/modes/basic.py` — `BasicMode(BaseMode)`:
  - **Line entry**: numbered lines (`10 PRINT "HELLO"`) → `basic line <content>`
  - **Non-numbered input**: inject as keystrokes via `inject keys` with escaping
  - **Program control**: `list [range]`, `run`, `stop`, `cont`, `new`
  - **Line editing**: `del 30` / `del 10-50`, `renum [start] [step]`
  - **Variables**: `vars`, `var X`
  - **File ops (ATR)**: `save D:FILE`, `load D:FILE`
  - **File ops (host)**: `import ~/path`, `export ~/path`
  - **Info**: `info`, `dir [drive]`
  - Track turbo BASIC variant for prompt
  - Escape handling for `inject keys`: spaces→`\s`, tabs→`\t`, etc.

**Tests**: `test_translator.py` — BASIC command translations, escape handling
**Milestone**: Enter, edit, list, run, save/load BASIC programs

---

### Phase 5: DOS Mode

**Goal**: Full DOS mode with all disk management commands.

**Files to create/update**:
- `attic_cli/modes/dos.py` — `DosMode(BaseMode)`:
  - **Disk management**: `mount N path`, `unmount N`, `drives`, `cd N`
  - **Directory**: `dir [pattern]`
  - **File info**: `info FILE`, `type FILE`, `dump FILE`
  - **File ops**: `copy SRC DST`, `rename OLD NEW`, `delete FILE`
  - **File protection**: `lock FILE`, `unlock FILE`
  - **Disk creation**: `newdisk path [sd|ed|dd]`, `format`
  - Track current drive number for prompt

**Tests**: `test_translator.py` — DOS command translations
**Milestone**: Full disk management works identically to Swift CLI

---

### Phase 6: Help System & Display Polish

**Goal**: Complete help system and visually superior terminal output.

**Files to create/update**:
- `attic_cli/help.py` — Full help text system:
  - Mode-specific help (monitor commands, BASIC commands, DOS commands)
  - Per-command detailed help with examples using `rich.panel.Panel` and `rich.table.Table`
  - Global commands help
  - Welcome banner with version and Atari-styled ASCII art
  - Syntax-highlighted example commands
- `attic_cli/display.py` — Rich-powered output:
  - ATASCII rendering with true color (24-bit backgrounds for inverse video, not just ANSI reverse)
  - 6502 disassembly with syntax highlighting (mnemonic colors by instruction category: load/store, branch, arithmetic, etc.)
  - Memory dump with heat-map coloring (zero bytes dim, non-zero bright, I/O registers highlighted)
  - Register display with diff highlighting (changed values since last `r` command shown in bold/color)
  - Breakpoint event display with register state in a `rich.panel.Panel`
  - Error messages with styled suggestions using `rich.console.Console`
  - File paths as OSC 8 clickable hyperlinks (both iTerm2 and Ghostty support this)
- `attic_cli/terminal_images.py` — Inline screenshot display:
  - `.screenshot` renders the Atari screen inline in the terminal
  - Single protocol: Kitty graphics protocol (supported by both iTerm2 and Ghostty)
  - Fallback: save file and print path as OSC 8 clickable link
- `attic_cli/terminal_osc.py` — Enhanced terminal integration:
  - OSC 9;4 progress bar during `format` and `state load` operations
  - OSC 9 desktop notification when long-running BASIC program completes
  - OSC 52 clipboard copy for `.copy` command (copy disassembly/listing to clipboard)

**Tests**: `test_help.py` — help text for all commands exists, `test_display.py` — ATASCII rendering, `test_terminal_images.py` — protocol detection
**Milestone**: `attic-py` is visually *superior* to the Swift CLI with modern terminal features

---

### Phase 7: Async Events & Terminal Polish

**Goal**: Handle async server events with rich terminal notifications.

**Updates**:
- `attic_cli/cli_client.py` — Background event reader:
  - Separate thread reads socket continuously
  - Events (`EVENT:breakpoint`, `EVENT:stopped`, `EVENT:error`) queued
  - REPL drains event queue before each prompt
- `attic_cli/repl.py` — Event handling:
  - Display breakpoint hit notifications in a `rich.panel.Panel` with register state
  - Auto-switch to monitor mode on breakpoint hit (with visual mode-switch indicator)
  - Handle `EVENT:stopped` for program completion
  - Use prompt_toolkit's `patch_stdout` to cleanly interrupt the prompt for async events

**Tests**: `test_integration.py` — subprocess tests with actual AtticServer
**Milestone**: Breakpoint events display as rich panels; inline screenshots work in iTerm2 and Ghostty

---

### Phase 8: Integration & Makefile

**Goal**: Integrated into the project build system.

**Updates**:
- `Makefile` — Add Python CLI test targets:
  - `make test-pycli-unit` — unit tests only
  - `make test-pycli` — full suite including integration
- Verify all commands produce identical output to Swift CLI
- Document in `README.md` within the package

**Milestone**: `uv run attic-py` is a fully functional replacement for `swift run attic`

---

## Key Design Decisions

### 1. Modern terminals only — no Emacs comint
The Swift CLI was designed for dual use in interactive terminals and Emacs comint
mode. The Python CLI drops comint support entirely and targets modern GPU-accelerated
terminals (iTerm2, Ghostty). This unlocks true color, inline images, styled text,
and clickable hyperlinks. Users who need Emacs integration can continue using the
Swift CLI.

### 2. Kitty graphics protocol for inline images
The `.screenshot` command displays the Atari screen inline in the terminal instead
of just saving a file. Both iTerm2 and Ghostty support the **Kitty graphics protocol**,
so a single ~30-line implementation covers both terminals. No external library needed —
just base64-encode the PNG and send via APC escape sequences.

The implementation follows the Kitty graphics protocol spec: images are transmitted
as base64-encoded data in chunked 4096-byte segments. The protocol uses
`\033_G<control-data>;<payload>\033\\` escape sequences.

Terminal detection uses `$TERM_PROGRAM` and `$TERM` environment variables.
Fallback: save file and print path as an OSC 8 clickable hyperlink.

### 2a. OSC escape sequences for terminal integration
Beyond images, several OSC sequences enhance the experience:
- **OSC 8**: Clickable hyperlinks for file paths (e.g., disk directory, error locations)
- **OSC 9;4**: Native progress bar in title bar during disk format / state load
- **OSC 9**: Desktop notification when a long-running BASIC program completes
- **OSC 52**: Copy disassembly or BASIC listing to system clipboard

### 3. Reuse existing socket client pattern
The `AtticMCP-Python/cli_client.py` already implements the socket protocol correctly.
The new CLI adapts this with additions for event handling and interactive use.

### 4. prompt_toolkit for rich interactive input
`prompt_toolkit` provides:
- Persistent history file (`~/.attic_history`, 500 entries)
- Emacs and vi-style keybindings
- Tab completion for commands (mode-aware)
- `patch_stdout` for clean async event display during prompt
- Styled prompts with ANSI formatting

### 5. Rich for output formatting
`rich` provides true-color output, tables, panels, syntax highlighting, and
progress indicators — all of which work natively in iTerm2 and Ghostty. Used for:
- Syntax-highlighted 6502 disassembly
- Heat-mapped memory dumps
- Register diff display
- Styled help panels
- OSC 8 hyperlinks for file paths

### 6. Click over argparse/typer
`click` is a good middle ground — more powerful than `argparse`, less opinionated
than `typer`. The CLI's argument surface is small (4 flags), so this is lightweight.
`typer` would pull in Pydantic which is unnecessary for a simple CLI.

### 7. Synchronous socket I/O with background event thread
The CLI is fundamentally synchronous (read prompt → send command → show response).
Async events (breakpoint hits) are handled by a background thread that reads from
the socket and queues events. The REPL drains this queue before each prompt.
This avoids the complexity of `asyncio` for what is a simple line-oriented REPL.

### 8. No BASIC tokenizer in Python
The Swift CLI doesn't tokenize BASIC locally — it sends lines to AtticServer
via `basic line <content>` and the server handles tokenization. The Python CLI
does the same. No need to port `BASICTokenizer.swift`.

### 9. Shared history file
Both Swift and Python CLIs use `~/.attic_history`. This is intentional — if a
user switches between them, their history follows. `prompt_toolkit.FileHistory`
is compatible with the libedit format.

---

## Dependencies (pyproject.toml)

```toml
[project]
name = "attic-cli"
version = "0.1.0"
description = "Python CLI for the Attic Atari 800 XL emulator"
requires-python = ">=3.13"
dependencies = [
    "click>=8.1",
    "prompt-toolkit>=3.0",
    "rich>=13.0",
]

[project.scripts]
attic-py = "attic_cli.main:cli"

[dependency-groups]
dev = [
    "pytest>=8.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

**Dependency notes**:
- Only 3 runtime dependencies — all well-maintained, widely-used packages.
- Inline images use the Kitty graphics protocol implemented directly (~30 LOC,
  just base64 + escape sequences) — no image library dependency needed.
- `Pillow` is _not_ required — screenshots are PNG files produced by AtticServer;
  we just read and transmit the raw bytes.
- OSC escape sequences (hyperlinks, notifications, progress, clipboard) are
  implemented directly using stdlib — no additional dependencies.

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Kitty protocol differences between Ghostty and Kitty terminal | Test on Ghostty specifically; avoid animation features (known divergence between Ghostty and Kitty) |
| Kitty protocol support in iTerm2 | iTerm2 added Kitty graphics support; test with current version; fallback to file path if image display fails |
| Event thread race conditions | Use `queue.Queue` (thread-safe) for event buffering |
| Socket client diverges from Swift | Reuse proven pattern from AtticMCP-Python |
| ATASCII rendering differences | Port exact character mapping from Swift `atasciiGraphicsTable`; use true color for inverse video |
| Interactive assembly state | Track in `MonitorMode`, clean up on mode switch |
| Terminal detection in nested sessions (tmux, ssh) | Check `$TERM_PROGRAM`, `$TERM`, and `$LC_TERMINAL` for robust detection |
| OSC sequence support varies | All target OSC sequences (8, 9, 9;4, 52) are well-supported by both iTerm2 and Ghostty; graceful degradation for unknown terminals |
| History file format mismatch | Test interop with Swift CLI's history file |

---

## Estimated Effort per Phase

| Phase | Scope |
|-------|-------|
| Phase 1 | Skeleton, socket, launcher, terminal image detection — foundational |
| Phase 2 | REPL loop, mode framework, tab completion — architectural |
| Phase 3 | Monitor mode — largest command set, syntax-highlighted output |
| Phase 4 | BASIC mode — moderate |
| Phase 5 | DOS mode — moderate |
| Phase 6 | Help system, Rich display, inline images — polish |
| Phase 7 | Async events, terminal notifications — integration |
| Phase 8 | Build system — small |
