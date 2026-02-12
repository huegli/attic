# AtticCLI Audit Report

**Date**: 2026-02-12
**Auditor**: Claude Code
**Scope**: Sources/AtticCLI/, Sources/AtticCore/CLI*.swift, related documentation
**Branch**: main (post-cleanup)

## Executive Summary

The AtticCLI module has been significantly improved since the initial audit. Several issues have been addressed:

**Fixed:**
- `--repl` flag removed (was useless)
- `runLocalREPL()` dead code removed
- Server launch logic refactored to shared `ServerLauncher` class
- New commands added (`.screenshot`, `.boot`)
- BASIC mode now uses key injection for natural input

**Remaining Issues:**
1. **`--headless` flag**: Still parsed but explicitly unused (documented as "kept for API compatibility")
2. **Duplicated code**: fd_set helpers still copied between client/server
3. **Unused property**: `commandParser` in CLISocketClient still unused
4. **Incomplete translations**: Some documented commands still not forwarded

---

## 1. Resolved Issues (from previous audit)

### 1.1 `--repl` Flag - FIXED

The useless `--repl` flag has been completely removed:
- Removed from `Arguments` struct
- Removed from argument parsing
- Removed from help text

### 1.2 Dead Code `runLocalREPL()` - FIXED

The entire `runLocalREPL()` function (previously lines 166-200) has been removed. The CLI is now documented as a "pure protocol client" that always connects to AtticServer.

### 1.3 Server Launch Logic - IMPROVED

Server launching has been refactored from inline code to a shared `ServerLauncher` class in AtticCore:
- `findServerExecutable()` moved to `ServerLauncher`
- Launch logic now in `ServerLauncher.launchServer(options:)`
- Returns structured `ServerLaunchResult` enum
- Shared between CLI, GUI, and MCP

### 1.4 Server Lifecycle Tracking - NEW

New `launchedServerPid` property tracks whether this CLI session launched the server:
- `.shutdown` only terminates server if CLI launched it
- Prevents accidentally killing a shared server

---

## 2. Remaining Issues

### 2.1 `--headless` Flag Unused (LOW)

**Location**: AtticCLI.swift

The `--headless` flag is still parsed but explicitly documented as unused:

```swift
/// - Parameters:
///   - headless: Whether to run without GUI (unused, kept for API compatibility).
///   - silent: Whether to disable audio.
static func launchServer(headless: Bool, silent: Bool) -> String? {
    let options = ServerLaunchOptions(silent: silent)
    // headless is not passed to options
```

**Status**: Documented as intentional. The flag exists for potential future use or API stability.

**Recommendation**: Either implement headless mode in `ServerLaunchOptions` or remove the flag entirely with a deprecation notice.

### 2.2 Unused `commandParser` Property (LOW)

**Location**: CLISocketClient.swift:103

```swift
private let commandParser = CLICommandParser()
```

Never used - commands sent via `formatCommand()` or `sendRaw()`.

**Recommendation**: Remove this property.

### 2.3 Duplicated fd_set Helpers (MEDIUM)

**Identical implementations in two files:**

| File | Lines | Functions |
|------|-------|-----------|
| CLISocketClient.swift | 707-730 | `fdZero`, `fdSet` |
| CLISocketServer.swift | 468-508 | `fdZero`, `fdSet`, `fdIsSet` |

**Recommendation**: Extract to shared `SocketHelpers.swift` in AtticCore.

### 2.4 Prompt Format Discrepancy (MEDIUM)

| Source | Format |
|--------|--------|
| REPL_COMMANDS.md | `[monitor] $E477>` (with PC) |
| AtticCLI.swift | `[monitor] >` (no PC) |

**Impact**: Loses debugging context; may affect Emacs comint regex matching.

### 2.5 Incomplete Command Translations (LOW)

**DOS Mode** - Only 3 commands explicitly handled in `translateDOSCommand()`:
- ✓ `mount`, `unmount`, `drives`
- Other commands pass through untranslated

**Note**: This may be intentional if the server handles raw DOS commands.

---

## 3. New Features Added

### 3.1 New Commands

| Command | Translation | Purpose |
|---------|-------------|---------|
| `.screenshot` | `screenshot` | Take screenshot |
| `.screenshot <path>` | `screenshot <path>` | Take screenshot to path |
| `.boot <path>` | `boot <path>` | Boot with file (ATR, XEX, BAS) |

### 3.2 BASIC Mode Key Injection

New `translateBASICCommand()` function:
- `LIST` → `basic list` (protocol command for clean listing)
- Everything else → `inject keys <escaped>\n` (natural keyboard input)

This is a significant improvement - BASIC input now goes through the emulator's keyboard handler for authentic behavior.

### 3.3 Improved Shutdown Behavior

The `.shutdown` command now checks `launchedServerPid`:
- If CLI launched the server: sends shutdown command AND `kill(pid, SIGTERM)`
- If server was already running: just disconnects, leaves server running

---

## 4. Code Quality Metrics

### Lines of Code (Updated)

| File | Lines | Change |
|------|-------|--------|
| AtticCLI.swift | 637 | -77 lines |
| CLIProtocol.swift | ~845 | unchanged |
| CLISocketClient.swift | ~730 | unchanged |
| CLISocketServer.swift | ~509 | unchanged |
| ServerLauncher.swift | ~150 | NEW |

### Complexity Assessment

- **AtticCLI.swift**: Simplified, cleaner structure
- **ServerLauncher.swift**: Well-designed, reusable component
- Code is more modular with shared server launch logic

---

## 5. Recommended Actions

### Medium Priority

| Action | Files | Effort |
|--------|-------|--------|
| Extract fd_set helpers to shared file | CLISocketClient.swift, CLISocketServer.swift | 30 min |
| Fix monitor prompt to show PC | AtticCLI.swift | 15 min |
| Remove unused `commandParser` | CLISocketClient.swift | 5 min |

### Low Priority

| Action | Files | Effort |
|--------|-------|--------|
| Decide on `--headless` flag (implement or remove) | AtticCLI.swift, ServerLauncher.swift | 30 min |
| Update REPL_COMMANDS.md for new commands | docs/REPL_COMMANDS.md | 15 min |

---

## 6. AtticCore Dependency Analysis (Updated)

AtticCLI now uses from AtticCore:

| Symbol | Required? |
|--------|-----------|
| `CLISocketClient` | **Yes** - socket communication |
| `CLIProtocolConstants` | **Yes** - protocol constants |
| `ServerLauncher` | **Yes** - server auto-launch |
| `ServerLaunchOptions` | **Yes** - launch configuration |
| `ServerLaunchResult` | **Yes** - launch result handling |
| `AtticCore.fullTitle` | **Yes** - version display |
| `AtticCore.buildConfiguration` | **Yes** - version display |
| `AtticCore.welcomeBanner` | **Yes** - welcome message |

**Note**: `REPLEngine` is no longer imported (dead code removed).

---

## 7. Architecture Notes

### Improvements

1. **Clean separation**: CLI is now purely a protocol client
2. **Shared utilities**: `ServerLauncher` reused across CLI, GUI, MCP
3. **Better lifecycle management**: Tracks server ownership for clean shutdown
4. **Natural BASIC input**: Key injection provides authentic emulator interaction

### File Structure

```
Sources/
├── AtticCLI/
│   └── AtticCLI.swift          # CLI executable (637 lines, -77)
└── AtticCore/
    ├── CLIProtocol.swift        # Protocol types and parser
    ├── CLISocketClient.swift    # Client socket implementation
    ├── CLISocketServer.swift    # Server socket implementation
    └── ServerLauncher.swift     # NEW: Shared server launch utility
```
