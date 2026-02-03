# AtticCLI Audit Report

**Date**: 2026-02-03
**Auditor**: Claude Code
**Scope**: Sources/AtticCLI/, Sources/AtticCore/CLI*.swift, related documentation

## Executive Summary

The AtticCLI module functions but has several documentation mismatches, redundant code (~105 lines), and incomplete command translation. The most significant issues are:

1. **Non-functional flags**: `--headless` and `--repl` are parsed but have no effect
2. **Dead code**: Local REPL implementation is never called
3. **Duplicated code**: fd_set helpers copied between client/server
4. **Incomplete translation**: Many documented commands not forwarded to server
5. **Doc mismatch**: Prompt format and command syntax differ from documentation

---

## 1. Documentation vs Implementation Mismatches

### 1.1 `--headless` Flag Non-Functional (CRITICAL)

The `--headless` flag is documented and parsed but **has no effect**.

**Code path:**
```
main() line 683:     launchServer(headless: args.headless, silent: args.silent)
                              ↓
launchServer() line 551-555:
    var arguments: [String] = []
    if silent {
        arguments.append("--silent")  // ✓ Used
    }
    // headless parameter is IGNORED - never added to arguments
```

**Location**: AtticCLI.swift:540-593

The `headless` parameter is received by `launchServer()` but never added to the AtticServer command-line arguments. Running `attic --headless` behaves identically to `attic`.

**Recommendation**: Either:
1. Pass `--headless` to AtticServer: `if headless { arguments.append("--headless") }`
2. Remove the flag entirely if headless mode isn't supported
3. Implement true local headless mode using `runLocalREPL()` (currently dead code)

### 1.2 `--repl` Flag Useless (MEDIUM)

The `--repl` flag is documented but **completely unnecessary**.

**Code analysis:**
```swift
// Line 48: Defaults to true
var repl: Bool = true

// Line 76-77: Can only set to true (already the default)
case "--repl":
    args.repl = true

// args.repl is NEVER READ anywhere in main() or elsewhere
```

**Location**: AtticCLI.swift:48, 76-77

The flag:
- Defaults to `true`
- Has no `--no-repl` counterpart
- Is never checked to make any decision

Running `attic --repl` is identical to running `attic`.

**Recommendation**: Remove `--repl` flag entirely - it serves no purpose.

### 1.3 Prompt Format Discrepancy (HIGH)

| Source | Format |
|--------|--------|
| REPL_COMMANDS.md:11 | `[monitor] $E477>` (with PC) |
| AtticCLI.swift:214 | `[monitor] >` (no PC) |

**Impact**: Loses debugging context; may break Emacs comint regex matching.

### 1.4 Breakpoint Command Syntax (MEDIUM)

| Source | Set Breakpoint | Clear Breakpoint |
|--------|---------------|------------------|
| REPL_COMMANDS.md:203-206 | `bp $600A` | `bc $600A` |
| AtticCLI.swift:432 | `b set $600A` | `b clear $600A` |
| CLIProtocol.swift:450 | `breakpoint set $600A` | `breakpoint clear $600A` |

**Impact**: Documented shortcuts (`bp`, `bc`) don't work as expected.

### 1.5 Missing Command Translations (HIGH)

Commands documented in `REPL_COMMANDS.md` but NOT translated in `AtticCLI.swift`:

**Monitor Mode** (AtticCLI.swift:406-435):
- `w` (watch memory) - not implemented
- `wc` (clear watch) - not implemented
- `a` (assemble) - not translated
- `f` (fill) - not translated (protocol uses `fill`)

**BASIC Mode** - All forwarded as `basic <input>` without specific handling:
- `del`, `renum` - line management
- `stop`, `cont` - execution control
- `vars` - variable listing
- `save`, `load` - ATR disk operations
- `dir` - directory listing

**DOS Mode** (AtticCLI.swift:439-455) - Only 3 commands handled:
- ✓ `mount`, `unmount`, `drives`
- ✗ `cd`, `type`, `dump`, `info`, `copy`, `rename`, `delete`, `lock`, `unlock`, `export`, `import`, `newdisk`, `format`

### 1.6 `.basic turbo` Mode (LOW)

- **Doc** (REPL_COMMANDS.md:29): Should switch to Turbo BASIC XL tokenizer
- **Code** (AtticCLI.swift:271): Accepts command but doesn't configure different tokenizer variant

---

## 2. Unnecessary Dependencies

### 2.1 Unused `commandParser` Property

**Location**: CLISocketClient.swift:97

```swift
private let commandParser = CLICommandParser()
```

Never used - commands sent via `formatCommand()` or `sendRaw()`.

**Recommendation**: Remove this property.

### 2.2 REPLEngine Underutilized

AtticCLI imports AtticCore but reimplements mode switching and prompt generation locally (SocketREPLMode enum) instead of using REPLEngine's facilities.

### 2.3 AtticCore Import Analysis

AtticCLI imports the entire AtticCore module but only uses a subset:

| Symbol | Line(s) | Required? |
|--------|---------|-----------|
| `CLISocketClient` | 232, 515, 522, 645 | **Yes** - socket communication |
| `CLIProtocolConstants.socketPath()` | 578 | **Yes** - socket path generation |
| `AtticCore.fullTitle` | 145 | **Yes** - version display |
| `AtticCore.buildConfiguration` | 146 | **Yes** - version display |
| `AtticCore.welcomeBanner` | 168, 234 | **Yes** - welcome message |
| `REPLEngine` | 166 | **No** - only in dead `runLocalREPL()` |

**Analysis**: The import IS necessary for socket communication (`CLISocketClient`, `CLIProtocolConstants`). However:

1. `REPLEngine` is only referenced in dead code - removing `runLocalREPL()` eliminates this dependency
2. Version strings (`fullTitle`, `buildConfiguration`, `welcomeBanner`) could be moved to a lightweight `AtticVersion` module to reduce coupling
3. The core requirement is `CLISocketClient` and `CLIProtocolConstants` - these are essential

**Recommendation**: After removing dead code, consider whether a smaller `AtticProtocol` module (containing just CLI socket/protocol code) would be cleaner than depending on all of AtticCore.

---

## 3. Redundant Code

### 3.1 Duplicated fd_set Helpers (HIGH)

**Identical implementations in two files:**

| File | Lines | Functions |
|------|-------|-----------|
| CLISocketClient.swift | 644-667 | `fdZero`, `fdSet` |
| CLISocketServer.swift | 468-508 | `fdZero`, `fdSet`, `fdIsSet` |

**Recommendation**: Extract to shared `SocketHelpers.swift` in AtticCore.

### 3.2 Duplicated Socket Address Setup (MEDIUM)

Nearly identical sockaddr_un initialization code:
- CLISocketClient.swift:192-206
- CLISocketServer.swift:177-191

**Recommendation**: Create shared `UnixSocket.makeAddress(path:)` helper.

### 3.3 Dead Code: Local REPL (HIGH)

**Location**: AtticCLI.swift:166-200

```swift
@MainActor
static func runLocalREPL(repl: REPLEngine) async {
    // 35 lines of code never executed
}
```

The `main()` function always uses socket-based REPL via `runSocketREPL()`. The local REPL path is unreachable.

**Recommendation**: Remove `runLocalREPL()` and associated logic.

### 3.4 Redundant Mode Enum (MEDIUM)

| File | Enum |
|------|------|
| AtticCLI.swift:208-222 | `SocketREPLMode` |
| AtticCore/REPLEngine.swift | `REPLMode` |

Both represent the same concept (monitor/basic/dos) with similar properties.

**Recommendation**: Reuse `REPLMode` from AtticCore.

### 3.5 Duplicated Help Text (LOW)

| File | Function | Purpose |
|------|----------|---------|
| AtticCLI.swift:459-508 | `printHelp()` | CLI help |
| REPLEngine.swift:799-822 | `formatHelp()` | REPL help |

Similar content defined separately.

---

## 4. Simplification Opportunities

### 4.1 Simplify Command Flow

**Current flow** (inefficient):
```
User input
  → translateToProtocol() creates string
  → sendRaw() sends string to server
  → CLICommandParser.parse() on server parses string back to CLICommand
```

**Proposed flow** (direct):
```
User input
  → Parse to CLICommand directly
  → send(CLICommand) to server
  → Server executes CLICommand
```

### 4.2 Fix or Remove Non-Functional Flags

Two flags are non-functional:

**`--headless`** (see section 1.1): Parsed but never passed to AtticServer. Options:
1. **Quick fix**: Add `if headless { arguments.append("--headless") }` in `launchServer()`
2. **Proper fix**: Implement true local headless mode using `runLocalREPL()` with embedded emulator
3. **Remove**: Delete the flag and document that AtticServer is always required

**`--repl`** (see section 1.2): Defaults to true, can only be set to true, and is never read.
- **Remove**: Delete the flag entirely - it serves no purpose

### 4.3 Complete or Remove Partial Translations

`translateDOSCommand()` only handles 3 of 15+ documented commands, passing others through unparsed. Either:
- Complete all translations, or
- Remove the function and let server handle all DOS commands directly

---

## 5. Code Quality Metrics

### Lines of Code

| File | Lines | Issues |
|------|-------|--------|
| AtticCLI.swift | 714 | 35 lines dead code |
| CLIProtocol.swift | 845 | Well-structured |
| CLISocketClient.swift | 668 | 25 lines duplicated, 1 unused property |
| CLISocketServer.swift | 509 | 45 lines duplicated |
| **Total** | **2,736** | **~105 lines to consolidate** |

### Complexity Assessment

- **AtticCLI.swift**: Moderate complexity, clear structure
- **CLIProtocol.swift**: Well-organized with comprehensive error handling
- **CLISocketClient/Server**: Good actor isolation, proper async/await usage

---

## 6. Recommended Actions

### Critical Priority

| Action | Files | Effort |
|--------|-------|--------|
| Fix `--headless` flag (pass to server or remove) | AtticCLI.swift:551-555 | 15 min |
| Remove useless `--repl` flag | AtticCLI.swift:48, 76-77, 119 | 10 min |

### High Priority

| Action | Files | Effort |
|--------|-------|--------|
| Remove dead `runLocalREPL()` | AtticCLI.swift | 15 min |
| Extract fd_set helpers to shared file | CLISocketClient.swift, CLISocketServer.swift, new file | 30 min |
| Fix monitor prompt to show PC | AtticCLI.swift:214 | 15 min |

### Medium Priority

| Action | Files | Effort |
|--------|-------|--------|
| Remove unused `commandParser` | CLISocketClient.swift | 5 min |
| Reuse REPLMode instead of SocketREPLMode | AtticCLI.swift | 30 min |
| Complete command translations or document gaps | AtticCLI.swift, docs | 2 hrs |

### Low Priority

| Action | Files | Effort |
|--------|-------|--------|
| Add breakpoint shortcuts (bp, bc) | CLIProtocol.swift | 30 min |
| Update REPL_COMMANDS.md accuracy | docs/REPL_COMMANDS.md | 1 hr |
| Consolidate help text | AtticCLI.swift, REPLEngine.swift | 30 min |

---

## 7. Architecture Notes

### What Works Well

1. **Actor isolation**: Both CLISocketClient and CLISocketServer properly use actors for thread safety
2. **Protocol design**: Text-based CLI protocol is human-readable and debuggable
3. **Error handling**: Comprehensive error types with localized descriptions
4. **Async/await**: Modern concurrency patterns used throughout

### Areas for Improvement

1. **Command abstraction**: Direct CLICommand passing would be cleaner than string translation
2. **Shared utilities**: Socket helpers should be in a common location
3. **Documentation sync**: Docs and implementation should be kept in sync
4. **Mode consistency**: Single source of truth for REPL modes

---

## 8. Testing Recommendations

Current test coverage for CLI components is minimal. Recommended tests:

1. **CLICommandParser**: Unit tests for all command variants and error cases
2. **Socket communication**: Integration tests for client-server roundtrip
3. **Command translation**: Verify all documented commands are properly handled
4. **Mode switching**: Verify prompts match documentation

---

## Appendix: File Locations

```
Sources/
├── AtticCLI/
│   └── AtticCLI.swift          # Main CLI executable (714 lines)
└── AtticCore/
    ├── CLIProtocol.swift        # Protocol types and parser (845 lines)
    ├── CLISocketClient.swift    # Client socket implementation (668 lines)
    ├── CLISocketServer.swift    # Server socket implementation (509 lines)
    └── REPLEngine.swift         # REPL state machine (1087 lines)

docs/
├── REPL_COMMANDS.md            # Command reference (570 lines)
└── PROTOCOL.md                 # Protocol specification (1262 lines)
```
