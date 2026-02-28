# Plan: Port Attic CLI to Python

## Overview

Port the Attic CLI (`Sources/AtticCLI/`) from Swift to Python 3.13, producing a
new `Sources/AtticCLI-Python/` package managed with `uv`. The Python CLI will be
a **drop-in replacement** for the Swift CLI — same commands, same prompts, same
comint compatibility, same socket protocol. The Swift CLI remains unchanged; users
choose which to run.

The Python CLI is a **pure protocol client**. All emulation happens in AtticServer
(Swift). The CLI only needs to: parse arguments, connect via Unix socket, run the
REPL loop, translate commands to protocol strings, and display responses. No
libatari800, no Metal, no Core Audio — just text I/O over a socket.

---

## Technology Choices

| Concern | Package | Rationale |
|---------|---------|-----------|
| **Environment/packaging** | `uv` + `pyproject.toml` | Fast, modern Python tooling; already used by AtticMCP-Python |
| **CLI argument parsing** | `click` | Mature, composable, supports `--help` generation; lighter than `typer` |
| **Line editing / REPL** | `prompt_toolkit` | Full readline replacement with history, keybindings, multi-line, completion; works in both TTY and pipe (comint) modes |
| **Terminal output** | `rich` | Hex dumps, ATASCII rendering with ANSI codes, styled help text |
| **Socket client** | stdlib `socket` | Reuse pattern from `AtticMCP-Python/cli_client.py`; no external deps needed |
| **Async events** | `threading` | Background thread to read async `EVENT:` messages from socket; stdlib only |
| **Testing** | `pytest` + `pytest-asyncio` | Standard Python test framework |

**Python version**: 3.13 (set in `pyproject.toml` as `requires-python = ">=3.13"`)

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
│   ├── display.py              # Output formatting: hex dumps, ATASCII, multi-line handling
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
  - `@click.command()` with options: `--silent`, `--socket PATH`, `--plain`, `--headless`, `--version`, `--help`
  - Connect to server (discover or launch), then hand off to REPL

**Tests**: `test_protocol.py` — protocol constants, response parsing
**Milestone**: `uv run attic-py --version` prints version; `uv run attic-py` connects and shows banner

---

### Phase 2: REPL Core & Mode Framework

**Goal**: Working REPL loop with mode switching and global dot-commands.

**Files to create**:
- `attic_cli/repl.py` — Main REPL loop:
  - Use `prompt_toolkit.PromptSession` for interactive mode
  - Detect non-TTY (pipe/comint) and fall back to `input()` for comint compatibility
  - Mode enum: `MONITOR`, `BASIC`, `BASIC_TURBO`, `DOS`
  - Prompt generation per mode:
    - Monitor: `[monitor] $XXXX>` (PC from last status)
    - BASIC: `[basic] >` or `[basic:turbo] >`
    - DOS: `[dos] D1:>`
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
- `attic_cli/display.py` — Output formatting:
  - `format_memory_dump(data, address)` — hex dump with ASCII sidebar
  - `format_disassembly(lines)` — aligned columns
  - `format_registers(response)` — register display
  - `split_multiline(response)` — split on `\x1E`

**Tests**: `test_translator.py` — all monitor command translations
**Milestone**: Full monitor debugging session works identically to Swift CLI

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

**Goal**: Complete help system and polished terminal output.

**Files to create/update**:
- `attic_cli/help.py` — Full help text system:
  - Mode-specific help (monitor commands, BASIC commands, DOS commands)
  - Per-command detailed help with examples
  - Global commands help
  - Welcome banner with version
  - Use `rich` for styled output (bold headers, colored examples)
- `attic_cli/display.py` — Polish output:
  - ATASCII rendering with ANSI inverse video codes (when `--plain` not set)
  - Hex dump formatting with addresses and ASCII sidebar
  - Breakpoint event display with register state
  - Error messages with suggestions (match Swift style)

**Tests**: `test_help.py` — help text for all commands exists, `test_display.py` — ATASCII rendering
**Milestone**: `attic-py` is visually indistinguishable from Swift `attic`

---

### Phase 7: Async Events & Edge Cases

**Goal**: Handle async server events and comint compatibility.

**Updates**:
- `attic_cli/cli_client.py` — Background event reader:
  - Separate thread reads socket continuously
  - Events (`EVENT:breakpoint`, `EVENT:stopped`, `EVENT:error`) queued
  - REPL drains event queue before each prompt
- `attic_cli/repl.py` — Event handling:
  - Display breakpoint hit notifications with register state
  - Auto-switch to monitor mode on breakpoint hit
  - Handle `EVENT:stopped` for program completion
- Comint compatibility:
  - When stdin is not a TTY, disable prompt_toolkit, use `input()`
  - All output ends with proper prompt for comint pattern matching
  - Flush stdout after every output line

**Tests**: `test_integration.py` — subprocess tests with actual AtticServer
**Milestone**: Works in Emacs comint-mode; breakpoint events display correctly

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

### 1. Reuse existing socket client pattern
The `AtticMCP-Python/cli_client.py` already implements the socket protocol correctly.
The new CLI adapts this with additions for event handling and interactive use.

### 2. prompt_toolkit over readline
Python's built-in `readline` module is limited. `prompt_toolkit` provides:
- Proper history file support (matching the 500-entry `~/.attic_history`)
- Emacs-style keybindings out of the box
- Graceful fallback for non-TTY (pipe/comint)
- Future extensibility: tab completion for commands, syntax highlighting

### 3. Click over argparse/typer
`click` is a good middle ground — more powerful than `argparse`, less opinionated
than `typer`. The CLI's argument surface is small (5 flags), so this is lightweight.
`typer` would pull in Pydantic which is unnecessary for a simple CLI.

### 4. Synchronous socket I/O with background event thread
The CLI is fundamentally synchronous (read prompt → send command → show response).
Async events (breakpoint hits) are handled by a background thread that reads from
the socket and queues events. The REPL drains this queue before each prompt.
This avoids the complexity of `asyncio` for what is a simple line-oriented REPL.

### 5. No BASIC tokenizer in Python
The Swift CLI doesn't tokenize BASIC locally — it sends lines to AtticServer
via `basic line <content>` and the server handles tokenization. The Python CLI
does the same. No need to port `BASICTokenizer.swift`.

### 6. Shared history file
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
    "pytest-asyncio>=0.24",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| prompt_toolkit comint incompatibility | Detect non-TTY and fall back to raw `input()` |
| Event thread race conditions | Use `queue.Queue` (thread-safe) for event buffering |
| Socket client diverges from Swift | Reuse proven pattern from AtticMCP-Python |
| ATASCII rendering differences | Port exact escape sequences from Swift `ATASCIIRenderer` |
| Interactive assembly state | Track in `MonitorMode`, clean up on mode switch |
| History file format mismatch | Test interop with Swift CLI's history file |

---

## Estimated Effort per Phase

| Phase | Scope |
|-------|-------|
| Phase 1 | Skeleton, socket, launcher — foundational |
| Phase 2 | REPL loop, mode framework — architectural |
| Phase 3 | Monitor mode — largest command set |
| Phase 4 | BASIC mode — moderate |
| Phase 5 | DOS mode — moderate |
| Phase 6 | Help & display — polish |
| Phase 7 | Events & comint — integration |
| Phase 8 | Build system — small |
