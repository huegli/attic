# Atari 800 XL Emulator Project

## Project Overview

This is a macOS application that emulates the Atari 800 XL home computer. It consists of two executables: a GUI application with Metal rendering and a CLI tool for REPL-based interaction designed to work with Emacs comint mode.

## Technology Stack

- **Language**: Swift 5.9+
- **Platform**: macOS 15+ (Sequoia)
- **UI Framework**: SwiftUI
- **Graphics**: Metal
- **Audio**: Core Audio (AVAudioEngine)
- **Emulation Core**: libatari800 (pre-compiled C library)
- **Game Input**: GameController framework

## Project Structure

```
attic/
├── Package.swift
├── Sources/
│   ├── AtticCore/              # Shared library (emulator, REPL, tokenizer)
│   ├── AtticCLI/               # Command-line executable (attic)
│   └── AtticGUI/               # SwiftUI + Metal application (AtticGUI)
├── Libraries/
│   └── libatari800/            # Pre-compiled emulator core
└── Resources/
    └── ROM/                    # User-provided Atari ROMs
```

## Key Architecture Decisions

1. **Separate Executables**: CLI and GUI are distinct executables communicating via Unix domain socket
2. **CLI Launches GUI**: By default, CLI starts the GUI if not running; `--headless` flag for no-GUI operation
3. **BASIC Tokenization**: We tokenize BASIC source and inject into emulator memory rather than interpreting
4. **BRK-Based Breakpoints**: Debugger uses 6502 BRK instruction ($00) for breakpoints
5. **Emacs Integration**: REPL designed for comint compatibility with clear prompts

## Implementation Priority

1. libatari800 Swift wrapper
2. Metal renderer
3. Audio engine
4. Socket protocol (CLI/GUI communication)
5. 6502 disassembler
6. Monitor mode
7. ATR file system parser
8. DOS mode
9. BASIC tokenizer/detokenizer
10. State save/load

## Key Files to Reference

- `docs/ARCHITECTURE.md` - System architecture details
- `docs/SPECIFICATION.md` - Complete feature specification
- `docs/PROTOCOL.md` - CLI/GUI socket protocol
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

## External Dependencies

- libatari800: https://github.com/atari800/atari800
- ROMs: User must provide ATARIXL.ROM and ATARIBAS.ROM

## Common Commands

```bash
# Build
swift build

# Run GUI
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
