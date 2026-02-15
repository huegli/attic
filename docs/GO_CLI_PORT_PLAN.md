# Plan: Port attic CLI to Go

## Overview

Port the existing Swift AtticCLI (`Sources/AtticCLI/`) to a Go executable that
connects to AtticServer via the frozen CLI text protocol over Unix domain sockets.
The existing Go package in `go/atticprotocol/` already implements the full protocol
client library and will be used as the foundation.

---

## Current State

### What exists in Swift (to be ported)

| File | Lines | Purpose |
|------|-------|---------|
| `AtticCLI.swift` | 1300 | Main REPL loop, argument parsing, command translation (monitor/basic/dos modes), help system |
| `LineEditor.swift` | 242 | libedit wrapper for interactive line editing and persistent history |
| `CLISocketClient.swift` | 762 | Unix socket client with async event handling (in AtticCore, shared) |

### What exists in Go (reusable)

| File | Purpose |
|------|---------|
| `go/atticprotocol/client.go` | Thread-safe Unix socket client with goroutine-based event reader, context/timeout support |
| `go/atticprotocol/command.go` | All 103 command types with constructors and `Format()` methods |
| `go/atticprotocol/parser.go` | Full command parser and response parser |
| `go/atticprotocol/protocol.go` | Constants, socket discovery, PID validation |
| `go/atticprotocol/response.go` | Response and Event types |
| `go/atticprotocol/errors.go` | Categorized error types |
| `go/atticprotocol/protocol_test.go` | Comprehensive test suite |

The Go protocol library is **production-quality and protocol-complete**. It covers
all 103 command types, response/event parsing, socket discovery, and thread-safe
client communication. No protocol work is needed.

---

## Go-Native Alternative to libedit

### Recommendation: **ergochat/readline**

`github.com/ergochat/readline` (actively maintained fork of the popular
`chzyer/readline`) is the best fit for this project:

| Requirement | ergochat/readline |
|-------------|-------------------|
| Emacs-style keybindings (Ctrl-A/E/K/W/Y, arrows) | Default mode |
| Persistent file-backed history | Built-in |
| History search (Ctrl-R) | Built-in |
| Tab completion | Built-in (extensible) |
| TTY detection (interactive vs piped) | `FuncIsTerminal` config hook |
| Emacs comint compatibility | Works via simple fallback path |
| Cross-platform | macOS + Linux |
| Pure Go (no CGo) | Yes |
| License | MIT |
| Maintained | Yes (v0.1.3, Debian-packaged) |

### Dual-mode pattern (matching Swift implementation)

```go
func NewLineEditor() *LineEditor {
    if os.Getenv("INSIDE_EMACS") != "" || !term.IsTerminal(int(os.Stdin.Fd())) {
        // Non-interactive: simple bufio.Scanner, print prompt to stdout
        return &LineEditor{interactive: false}
    }
    // Interactive: ergochat/readline with Emacs keybindings + history
    rl, _ := readline.NewEx(&readline.Config{
        HistoryFile:     filepath.Join(homeDir, ".attic_history"),
        HistoryLimit:    500,
        UniqueEditLine:  true,
    })
    return &LineEditor{interactive: true, rl: rl}
}
```

### Runner-up: **reeflective/readline**

If richer features are needed later (vi mode, `.inputrc` support, syntax
highlighting, multi-line editing), `github.com/reeflective/readline` is the most
feature-complete Go readline library (v1.1.4, Jan 2026). It has a larger API
surface and more complex integration, so ergochat is preferred for the initial port.

---

## Project Structure

```
go/
├── atticprotocol/          # Existing protocol library (no changes needed)
│   ├── go.mod
│   ├── client.go
│   ├── command.go
│   ├── parser.go
│   ├── protocol.go
│   ├── response.go
│   ├── errors.go
│   └── protocol_test.go
│
└── attic/                  # NEW: CLI application
    ├── go.mod              # Module: github.com/attic/attic-cli
    ├── go.sum
    ├── main.go             # Entry point, argument parsing, main()
    ├── repl.go             # REPL loop, mode management, assembly sub-mode
    ├── translate.go        # Command translation (monitor/basic/dos → protocol)
    ├── help.go             # Help system (global + per-mode help text)
    ├── lineeditor.go       # Line editor wrapper (ergochat/readline + fallback)
    ├── server.go           # Server discovery, launch, lifecycle management
    └── repl_test.go        # Unit tests for command translation
```

---

## Implementation Plan

### Phase 1: Project Scaffolding

**Files:** `go/attic/go.mod`, `go/attic/main.go`

- Initialize Go module with dependency on `../atticprotocol` (replace directive)
  and `github.com/ergochat/readline`
- Implement argument parsing (hand-written, matching Swift):
  - `--silent` — pass to server on launch
  - `--plain` / `--atascii` — control ATASCII rendering mode
  - `--socket <path>` — connect to specific socket
  - `--headless` — skip GUI launch
  - `--help`, `-h` — print usage
  - `--version`, `-v` — print version
- Wire up: parse args → discover/connect → run REPL → cleanup

### Phase 2: Line Editor

**File:** `go/attic/lineeditor.go`

- Implement `LineEditor` struct with dual-mode operation:
  - **Interactive**: `ergochat/readline` with Emacs keybindings, 500-entry
    file-backed history at `~/.attic_history`, duplicate suppression
  - **Non-interactive**: `bufio.Scanner` on stdin, manual prompt printing to stdout
- Public interface:
  - `NewLineEditor() *LineEditor`
  - `GetLine(prompt string) (string, error)` — returns line or EOF error
  - `Close()` — save history, release resources
- TTY detection via `golang.org/x/term.IsTerminal()` or `INSIDE_EMACS` env var

### Phase 3: Server Discovery & Launch

**File:** `go/attic/server.go`

- `discoverAndConnect()` — use `atticprotocol.DiscoverSocket()` to find
  running server, fall back to launching new one
- `launchServer(silent bool)` — find AtticServer executable, launch via
  `os/exec.Cmd`, wait for socket to appear (4s timeout with polling)
- `shutdownServer(pid int)` — send SIGTERM to server process if we launched it
- Executable search order: same dir as CLI binary, then PATH, then common
  locations (`/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`)

### Phase 4: REPL Core

**File:** `go/attic/repl.go`

- Implement three modes with mode-switching:
  ```go
  type REPLMode int
  const (
      ModeMonitor REPLMode = iota
      ModeBasic
      ModeDOS
  )
  ```
- Mode prompts matching Swift exactly:
  - Monitor: `[monitor] $XXXX> ` (with current PC)
  - BASIC: `[basic] > `
  - DOS: `[dos] D1:> ` (with current drive)
- Main loop:
  1. Read line via `LineEditor.GetLine(prompt)`
  2. Handle EOF (Ctrl-D) → exit
  3. Skip empty lines (except in assembly mode)
  4. Route dot-commands locally (`.monitor`, `.basic`, `.dos`, `.help`, `.quit`, `.shutdown`)
  5. Translate mode-specific commands via `translateToProtocol()`
  6. Send to server via `atticprotocol.Client.SendRaw()`
  7. Display response (handle `\x1E` multi-line separator)
- Assembly sub-mode:
  - Entered when server responds with `"ASM $XXXX"`
  - Prompt changes to `$XXXX: `
  - Empty line or `.` exits
  - Lines sent as `asm input <instruction>`
  - Response contains next address after `\x1E` separator

### Phase 5: Command Translation

**File:** `go/attic/translate.go`

Port the three translation functions from Swift:

#### Monitor Commands
| User Input | Protocol Output |
|------------|-----------------|
| `g` | `resume` |
| `g $0600` | `registers pc=$0600` then `resume` (two commands) |
| `s [N]` | `step [N]` |
| `so` | `stepover` |
| `p` / `pause` | `pause` |
| `r` | `registers` |
| `r a=42` | `registers a=$42` |
| `m $addr [count]` | `read $addr [count]` |
| `> $addr bytes` | `write $addr bytes` |
| `f $start $end $val` | `fill $start $end $val` |
| `d [$addr] [lines]` | `disassemble [$addr] [lines]` |
| `a $addr` | `assemble $addr` |
| `b set $addr` / `bp $addr` | `breakpoint set $addr` |
| `b clear $addr` / `bc $addr` | `breakpoint clear $addr` |
| `b list` | `breakpoint list` |
| `until $addr` | `rununtil $addr` |

#### BASIC Commands
| User Input | Protocol Output |
|------------|-----------------|
| `list [range]` | `basic list [range] [atascii]` |
| `del N` | `basic del N` |
| `renum [start] [step]` | `basic renum [start] [step]` |
| `new` | `basic new` |
| `run` | `basic run` |
| `stop` | `basic stop` |
| `cont` | `basic cont` |
| `vars` | `basic vars` |
| `var X` | `basic var X` |
| `info` | `basic info` |
| `save D:FILE` | `basic save D:FILE` |
| `load D:FILE` | `basic load D:FILE` |
| `export path` | `basic export path` |
| `import path` | `basic import path` |
| `dir` | `basic dir` |
| `10 PRINT "HELLO"` | `inject keys 10\sPRINT\s"HELLO"\n` |

#### DOS Commands
| User Input | Protocol Output |
|------------|-----------------|
| `mount N path` | `mount N path` |
| `unmount N` | `unmount N` |
| `drives` | `drives` |
| `cd N` | `dos cd N` |
| `dir [pattern]` | `dos dir [pattern]` |
| `info file` | `dos info file` |
| `type file` | `dos type file` |
| `dump file` | `dos dump file` |
| `copy src dst` | `dos copy src dst` |
| `rename old new` | `dos rename old new` |
| `delete file` | `dos delete file` |
| `lock file` | `dos lock file` |
| `unlock file` | `dos unlock file` |
| `export file path` | `dos export file path` |
| `import path [file]` | `dos import path [file]` |
| `newdisk path [type]` | `dos newdisk path [type]` |
| `format` | `dos format` |

### Phase 6: Help System

**File:** `go/attic/help.go`

- Port all help text from Swift's four dictionaries:
  - `globalHelp` — 11 entries (dot-commands)
  - `monitorHelp` — 14 entries
  - `basicHelp` — 11 entries
  - `dosHelp` — 13 entries
- `.help` — show overview for current mode
- `.help <topic>` — look up in global + mode-specific dictionaries
- Case-insensitive, strip leading dot from topic

### Phase 7: Testing

**File:** `go/attic/repl_test.go`

- Unit tests for all command translation functions
- Test each monitor/basic/dos command produces correct protocol output
- Test edge cases: hex address parsing, multi-word arguments, keystroke escaping
- Test dot-command routing (local vs forwarded)
- Test assembly mode state transitions

### Phase 8: Build & Integration

- Add Makefile targets for Go CLI build:
  ```makefile
  go-build:
      cd go/attic && go build -o ../../.build/attic-go .
  go-test:
      cd go/attic && go test ./...
  ```
- Verify the Go CLI can connect to a running AtticServer and execute commands
- Verify Emacs comint compatibility (prompt format, piped input)
- Verify history persistence across sessions

---

## Key Design Decisions

### 1. Reuse existing Go protocol library as-is

The `go/atticprotocol` package is already complete and protocol-compatible.
The CLI will use `Client.SendRaw()` for most operations (matching the Swift
pattern where commands are translated to protocol strings), and typed
`Client.Send(Command)` where convenient.

### 2. ergochat/readline over alternatives

- **Over chzyer/readline**: ergochat is the actively maintained fork
- **Over peterh/liner**: liner is unmaintained since 2022
- **Over reeflective/readline**: Simpler API, sufficient features for this use case
- **Over bubbletea/bubbline**: Bubbletea has documented input-loss issues with
  piped input, making it unsuitable for Emacs comint integration

### 3. Hand-written argument parsing (no cobra/pflag)

The Swift CLI uses a simple hand-written parser. The Go port should match this
simplicity — only 6 flags, no subcommands. Adding a dependency like cobra would
be over-engineering.

### 4. SendRaw over typed Send

The Swift CLI translates user commands into protocol strings and sends them raw.
The Go CLI should follow the same pattern for consistency and simplicity. The
typed `Command` API is useful for tab completion or future features but is not
needed for the initial port.

### 5. Same history file location

Both Swift and Go CLIs use `~/.attic_history`. This means switching between them
preserves command history. The Go CLI should use the same 500-entry limit and
duplicate suppression.

---

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `github.com/ergochat/readline` | v0.1.3+ | Line editing, history, completion |
| `golang.org/x/term` | latest | TTY detection (`IsTerminal()`) |
| `../atticprotocol` (local) | — | CLI protocol client library |

No other external dependencies. Everything else uses Go standard library.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| ergochat/readline has fewer users than chzyer | It's the official maintained fork; Debian-packaged; API-compatible |
| Go CLI may diverge from Swift CLI behavior | Comprehensive translation tests; test against same AtticServer |
| Server launch logic is macOS-specific (executable search) | Use `exec.LookPath` for PATH search; configurable search paths |
| Assembly mode state machine is subtle | Port directly from Swift; add specific test cases for state transitions |

---

## Out of Scope

- Tab completion for commands (future enhancement)
- Syntax highlighting (future; consider reeflective/readline upgrade)
- Windows support (AtticServer is macOS-only)
- Replacing the Swift CLI (both can coexist, connecting to same server)
- Protocol changes (frozen)
