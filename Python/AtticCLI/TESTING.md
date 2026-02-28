# Manual Testing Plan — Python CLI (Phases 1–5)

## Prerequisites

```bash
# Terminal 1: Start the server
swift run AtticServer

# Terminal 2: Run the Python CLI
cd Python/AtticCLI
uv run attic-py
```

---

## 1. Startup & Connection

| # | Test | Expected |
|---|------|----------|
| 1.1 | `uv run attic-py --version` | Prints `attic-py, version 0.1.0` |
| 1.2 | `uv run attic-py --help` | Shows all options (--silent, --socket, --headless, --version) |
| 1.3 | `uv run attic-py` (server running) | Banner, `Connected to AtticServer (pid ...)`, REPL prompt `[basic] >` |
| 1.4 | `uv run attic-py` (no server running) | Attempts to auto-launch AtticServer, then connects |
| 1.5 | `uv run attic-py --socket /tmp/bogus.sock` | Error: "Connection failed: ..." and exit |

## 2. REPL Basics

| # | Test | Expected |
|---|------|----------|
| 2.1 | Press Enter on empty line | No output, prompt re-displayed |
| 2.2 | Ctrl-C | Cancels current line, shows new prompt |
| 2.3 | Ctrl-D | Prints "Goodbye", exits cleanly |
| 2.4 | Up/Down arrows | History navigation works |
| 2.5 | Tab key | Shows completion suggestions for current mode |
| 2.6 | Quit and restart | Previous commands available in history (persisted to ~/.attic_history) |

## 3. Global Dot-Commands

| # | Test | Expected |
|---|------|----------|
| 3.1 | `.help` | Two Rich tables: Global Commands + BASIC Mode Commands |
| 3.2 | `.help boot` | Rich panel with `.boot` usage details |
| 3.3 | `.help g` | Shows help for monitor's `g` (go/resume) command |
| 3.4 | `.help nonexistent` | "No help available for 'nonexistent'" |
| 3.5 | `.status` | Emulator status (running state, PC, disks, breakpoints) |
| 3.6 | `.screen` | Text screen content (24 lines of GRAPHICS 0 text) |
| 3.7 | `.reset` | Cold reset the emulator |
| 3.8 | `.warmstart` | Warm reset (like pressing RESET key) |
| 3.9 | `.screenshot` | Inline image in iTerm2/Ghostty, or file path fallback in other terminals |
| 3.10 | `.screenshot /tmp/test.png` | Saves screenshot to specified path |
| 3.11 | `.boguscmd` | "Unknown command: .boguscmd" |

## 4. Mode Switching

| # | Test | Expected |
|---|------|----------|
| 4.1 | `.monitor` | "Switched to monitor mode", prompt → `[monitor] >` |
| 4.2 | `.basic` | "Switched to BASIC mode", prompt → `[basic] >` |
| 4.3 | `.basic turbo` | "Switched to Turbo BASIC mode", prompt → `[basic:turbo] >` |
| 4.4 | `.dos` | "Switched to DOS mode", prompt → `[dos] D1:>` |
| 4.5 | Tab after `.monitor` | Only monitor commands (g, r, d, m, etc.) + global dot-commands |
| 4.6 | Tab after `.basic` | Only BASIC commands (list, run, etc.) + global dot-commands |
| 4.7 | Tab after `.dos` | Only DOS commands (mount, dir, etc.) + global dot-commands |

## 5. Monitor Mode

Switch with `.monitor`, then:

| # | Test | Expected |
|---|------|----------|
| 5.1 | `r` | Register display: bold names, cyan values (A, X, Y, S, P, PC) |
| 5.2 | `r a=$42` | Sets accumulator to $42 |
| 5.3 | `p` | Pauses emulator |
| 5.4 | `d` | Disassembly from current PC — color-coded mnemonics |
| 5.5 | `d $E000 10` | 10 lines of disassembly from $E000 |
| 5.6 | `m $0600` | Hex dump — zero bytes dimmed, non-zero bold |
| 5.7 | `m $D000 16` | I/O register range — bytes shown in magenta |
| 5.8 | `> $0600 A9,42,60` | Write 3 bytes to $0600 |
| 5.9 | `m $0600 3` | Verify bytes: A9 42 60 |
| 5.10 | `b $0600` | Set breakpoint at $0600 |
| 5.11 | `bl` | List breakpoints — should show $0600 |
| 5.12 | `bc $0600` | Clear breakpoint at $0600 |
| 5.13 | `bc *` | Clear all breakpoints |
| 5.14 | `s` | Step one instruction |
| 5.15 | `s 5` | Step 5 instructions |
| 5.16 | `g` | Resume execution |
| 5.17 | `g $E000` | Set PC to $E000 and resume (two commands) |
| 5.18 | `f $0600 $06FF $00` | Fill memory range with zeros |

## 6. Interactive Assembly

From monitor mode:

| # | Test | Expected |
|---|------|----------|
| 6.1 | `a $0600` | "Entering assembly mode at $0600", prompt → `$0600:` |
| 6.2 | Type `LDA #$42` | Shows assembled bytes, prompt advances (e.g. `$0602:`) |
| 6.3 | Type `STA $D01A` | Assembles STA absolute, prompt advances |
| 6.4 | Type `RTS` | Assembles RTS |
| 6.5 | Type `.` or empty line | Exits assembly mode, prompt → `[monitor] >` |
| 6.6 | `d $0600 3` | Verify assembled instructions match what was entered |
| 6.7 | Ctrl-D during assembly | Exits assembly mode (sends `asm end`) |

## 7. BASIC Mode

Switch with `.basic`, then:

| # | Test | Expected |
|---|------|----------|
| 7.1 | `NEW` | Clears program (injected as keystrokes) |
| 7.2 | `10 PRINT "HELLO"` | Enters line (spaces escaped as `\s` in protocol) |
| 7.3 | `20 GOTO 10` | Enters second line |
| 7.4 | `list` | Lists program with ATASCII rendering |
| 7.5 | `list 10` | Lists only line 10 |
| 7.6 | `RUN` | Runs the program (injected as keystrokes) |
| 7.7 | `.warmstart` | Stop the running program |
| 7.8 | `del 20` | Deletes line 20 |
| 7.9 | `list` | Verify line 20 is gone |
| 7.10 | `vars` | Shows BASIC variables |
| 7.11 | `info` | Program information (size, line count) |
| 7.12 | `dir` | Directory listing of current drive |
| 7.13 | `export /tmp/test.bas` | Export program to host file |
| 7.14 | `NEW` then `import /tmp/test.bas` | Re-import, verify with `list` |
| 7.15 | `renum` | Renumber lines starting from 10 |

## 8. DOS Mode

Switch with `.dos`, then:

| # | Test | Expected |
|---|------|----------|
| 8.1 | `drives` | Lists all 8 drive slots |
| 8.2 | `newdisk /tmp/test.atr` | Creates a new blank ATR disk image |
| 8.3 | `mount 1 /tmp/test.atr` | Mounts disk to D1: |
| 8.4 | `dir` | Directory listing of D1: (empty disk) |
| 8.5 | `format` | Formats the disk |
| 8.6 | `cd 2` | Switches to D2:, prompt → `[dos] D2:>` |
| 8.7 | `cd 1` | Back to D1:, prompt → `[dos] D1:>` |
| 8.8 | `unmount 1` | Unmounts D1: |
| 8.9 | Check prompt after unmount | If current drive was unmounted, resets to D1: |

## 9. Terminal Features (iTerm2 / Ghostty only)

| # | Test | Expected |
|---|------|----------|
| 9.1 | `.screenshot` | Image displayed inline in terminal (Kitty graphics protocol) |
| 9.2 | `.help` | Rich tables render with borders and colors, not raw markup |
| 9.3 | Disassembly | Color-coded: LDA/STA blue, JMP/BEQ yellow, ADC/SBC green, etc. |
| 9.4 | Memory dump at $0600 | Zero bytes dimmed, non-zero bold |
| 9.5 | Memory dump at $D000 | I/O register bytes in magenta |
| 9.6 | Register display | Bold register names, cyan values |

## 10. Exit & Reconnection

| # | Test | Expected |
|---|------|----------|
| 10.1 | `.quit` | "Goodbye", CLI exits, server keeps running |
| 10.2 | Restart CLI after `.quit` | Discovers existing server, reconnects |
| 10.3 | `.shutdown` | CLI exits and stops the server |
| 10.4 | Kill server while CLI is running | Next command shows connection error gracefully |

## 11. Edge Cases

| # | Test | Expected |
|---|------|----------|
| 11.1 | Very long input line | Handled without crash |
| 11.2 | Invalid hex in monitor (`> $0600 ZZ`) | Server error displayed cleanly |
| 11.3 | Invalid address (`m $FFFFF`) | Server error displayed |
| 11.4 | Run `uv run python -m attic_cli` | Same as `uv run attic-py` |

---

## What to Watch For

- **Prompt consistency**: Prompt always matches current mode and state
- **Color rendering**: Rich markup tags (e.g. `[bold]`) must not appear as literal text
- **No tracebacks**: Errors should show clean `Error:` messages, never Python stack traces
- **Tab completion**: Mode-aware — only shows valid commands for the current mode
- **History**: Persists across sessions in `~/.attic_history`
