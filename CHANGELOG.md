# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-04-06

### Added
- Built-in TUI BASIC editor with Atari color scheme
- Web client build and bundling in make-app.sh

### Fixed
- BASIC token table corrected to match real Atari BASIC ROM — operator tokens
  extended to $12-$3C (5 new context-dependent paren tokens for array subscripts,
  DIM, and function calls), function tokens shifted to $3D-$54; verified against
  actual ROM memory dumps using MCP emulator tools
- VNT (Variable Name Table) parser fixed to handle ROM format where type suffix
  characters ($, () are stored as part of the variable name
- Detokenizer no longer inserts extra space after open parenthesis
- List command no longer fails when program contains line 0
- Keyboard case handling fixed for lowercase letter support
- Inject keys no longer uppercases all letters after boot/reset
- Caps Lock disabled and lowercase fixed in web client
- Shift key inversion corrected
- CX Stick gamepad detection fixed
- Breakpoint write tracking preserves original bytes correctly

### Changed
- Python CLI renamed, version synced, web URL shown in banner, quit handling improved
- WebSocket protocol detection added for client connections

### Removed
- Emacs integration support removed from project

## [0.5.0] - 2026-04-02

### Added
- `.edit` command for editing BASIC programs in an external editor ($VISUAL/$EDITOR/vim)
  with diff-based reimport — only changed, added, or deleted lines are injected back
- Background file watcher for GUI editors (VS Code, Sublime, etc.) applies changes on every save
- Editor auto-stop when the editor process exits
- `.sound` command to show current audio output state
- `--sound` CLI flag to enable audio output (sound is now off by default)
- Web client HTTP server auto-starts on launch with URL shown in banner

### Changed
- Sound is off by default when launching AtticServer via attic-py (use `--sound` to enable)
- Web client is always available without needing `.gui` command

### Removed
- `.gui` REPL command (web client auto-starts instead)
- `--headless` CLI flag (was parsed but never used)

## [0.4.1] - 2026-03-31

### Fixed
- Build failure on machines without Xcode (removed `#Preview` macros that require Xcode's PreviewsMacros plugin)

## [0.4.0] - 2026-03-31

### Added
- WebSocket bridge for web browser clients (Phase 18)
- Video delta encoding for efficient WebSocket streaming
- A/V sync broadcast to WebSocket clients
- Web browser client with Canvas 2D rendering and Web Audio (Phase 19)
- Gamepad support in web client with joystick overlay
- Game controller support (GameController framework) with joystick HUD overlay
- IOKit HID fallback for USB joysticks not recognized by GameController
- Dual launch modes: GUI mode (AESP TCP) and Web mode (`--no-aesp --websocket`)
- `--no-aesp` flag for AtticServer to disable AESP TCP ports
- `.gui` REPL command in Python CLI to serve web client via HTTP
- Auto-detect ROM path when Python CLI launches AtticServer

### Changed
- Python CLI now launches AtticServer with `--no-aesp --websocket` by default
- Web client canvas dynamically scales with browser window
- Updated documentation for dual launch modes and Phase 18-19 completion

## [0.3.1] - 2026-03-28

### Changed
- Bundle Python CLI (PyInstaller standalone binary) in Attic.app, replacing Swift CLI
- Add `python-cli` and `clean-python-cli` Makefile targets
- PyInstaller-aware AtticServer discovery in frozen app bundles

## [0.3.0] - 2026-03-28

### Added
- Python CLI port with full REPL, monitor, BASIC, and DOS modes (click + prompt_toolkit + rich)
- 6502-spec skill for Claude Code
- `make altirra` Makefile target to build AltirraOS Kernel and Altirra BASIC ROMs from source using MADS, copying results to `Resources/ROM/`

### Fixed
- Breakpoints and stepping: use BRK injection, handle `.breakpoint` in main loop
- BASIC load out-of-memory issue
- Monitor mode missing color coding in REPL hex dumps
- Monitor `m` command defaults to 16 bytes when count omitted
- Python CLI tab completion for dot-commands (.help, .status, etc.)
- Python CLI mode switching crash and screenshot/help

### Changed
- Moved Python packages from `Sources/` to `Python/` directory
- Consolidated 6502 docs: merged specs, extracted assembler/disassembler
- Moved `ALTIRRA.md` to `docs/ALTIRRA.md`
- Simplified MADS install instructions to macOS-only (removed Linux and pre-built binary options)

## [0.2.1] - 2026-02-28

### Fixed
- CLI: Handle shell escape characters in file path commands (e.g., paths with spaces or special characters)
- CLI: `.boot` with no arguments no longer errors unexpectedly
- CLI: DOS prompt now reflects the current drive after `cd`
- GUI: Double-clicking an Atari file in Finder routes to the running instance instead of launching a second copy
- GUI: Crop overscan margins to eliminate screen edge artifacts

## [0.2.0] - 2026-02-15

### Added
- Emacs-style line editing in the CLI REPL via libedit (Ctrl-A/E/K, arrow keys, word movement, kill/yank, etc.)
- Persistent command history across sessions, saved to `~/.attic_history`
- `LIST` command now supports line number ranges: `LIST 10`, `LIST 10-50`, `LIST 10-`, `LIST -50`. Works in both CLI BASIC mode and over the socket protocol.
- Drag-and-drop file loading in the GUI — drop ATR, XEX, BAS, CAS, or ROM files directly onto the emulator display
- CRT-like flash overlay on reset for visual feedback (white flash for cold reset, gray for warm)

### Fixed
- Reset flash animation uses opacity animation instead of transition for reliability

### Improved
- Test suite no longer hangs on interrupted runs: `make test` kills orphan processes before starting, and subprocess tearDown uses SIGKILL fallback

### Added
- Emacs-style line editing in the CLI REPL via libedit (Ctrl-A/E/K, arrow keys, word movement, kill/yank, etc.)
- Persistent command history across sessions, saved to `~/.attic_history`

## [0.1.2] - 2026-02-14

### Fixed
- ROM cartridge files (.rom) now load correctly instead of launching BASIC. Raw ROM dumps are auto-wrapped in a CART header so libatari800 can identify the cartridge type.
- `var` command no longer shows IEEE 754 rounding errors for integer BASIC variables (e.g. 114.99999999999999 instead of 115). BCD mantissa is now built as an integer before converting to Double.
- `.state save/load` now expands tilde (`~`) in file paths, consistent with other path-handling commands.

## [0.1.1] - 2026-02-14

### Fixed
- GUI survives laptop sleep without false server-lost alert
- Execute boot frames in bootFile() to initialize BASIC pointers correctly
- Correct VVT byte offsets for the `vars` command
- Write BRKKEY flag in sendBreak() so BASIC actually stops on BREAK

## [0.1.0] - 2026-02-14

Initial release. All 17 implementation phases complete (MVP).

### Added
- Emulator core via libatari800 wrapper (Phase 1-2)
- Metal renderer for 384x240 BGRA display at 60fps (Phase 3)
- Core Audio engine with 44.1kHz PCM output (Phase 4)
- Keyboard input handling (Phase 5)
- AESP binary protocol library with Control, Video, and Audio channels (Phase 6)
- Standalone emulator server (AtticServer) on ports 47800-47802 (Phase 7)
- SwiftUI GUI as AESP protocol client (Phase 8)
- CLI with Unix socket text protocol and Emacs comint compatibility (Phase 9)
- Joystick input via keyboard emulation (Phase 10)
- 6502 disassembler with address labels and all addressing modes (Phase 11)
- Monitor/debugger with BRK-based breakpoints, step, step-over, run-until (Phase 12)
- ATR disk image support (SD, ED, DD) with DOS 2.x/2.5 filesystem (Phase 13)
- DOS mode with full file management commands (Phase 14)
- BASIC tokenizer/detokenizer with memory injection (Phase 15)
- State save/load persistence (Phase 16)
- MCP server (Python/FastMCP) for Claude Code integration
- macOS .app bundle packaging (`make app`)

### Fixed
- Protocol freeze: both AESP and CLI protocols are now frozen at this version
