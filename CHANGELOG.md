# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `LIST` command now supports line number ranges: `LIST 10`, `LIST 10-50`, `LIST 10-`, `LIST -50`. Works in both CLI BASIC mode and over the socket protocol.

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
