# Phase 14: BASIC Tokenizer - Design Document

## Overview

This document captures the architectural decisions and implementation plan for Phase 14: BASIC Tokenizer.

## Architectural Decisions

### 1. Tokenization Location: Server-Side

Tokenization happens in **AtticServer**, not in the CLI client. The CLI sends raw BASIC text via the existing socket protocol, and the server tokenizes and injects into emulator memory.

**Rationale**: Keeps the emulator logic centralized. CLI remains a thin client.

### 2. State Management: Emulator-Primary

The emulator memory is the **single source of truth** for BASIC programs. Swift does not maintain a shadow copy of the program or variable tables.

- When entering a line: Parse, tokenize, inject into emulator memory
- When listing: Read from emulator memory, detokenize (Phase 15)
- No caching of program state in Swift

**Implications**:
- Each line entry must read current BASIC pointers from zero page
- Variable table lookups scan emulator memory
- Programs loaded via Atari DOS are immediately visible

### 3. Injection Timing: Line-by-Line (Immediate)

Each BASIC line is tokenized and injected **immediately** when entered, exactly like real Atari BASIC.

**Process for entering `10 PRINT "HELLO"`**:
1. Parse the line number and content
2. Read current BASIC pointers from zero page (VNTP, VVTP, STMTAB, etc.)
3. Scan existing variable table in emulator memory
4. Add any new variables to VNT/VVT
5. Tokenize the statement
6. Insert/replace the line in the statement table
7. Update all BASIC pointers in zero page
8. Return success response

### 4. Variable Creation: On First Reference

Variables are created in the Variable Name Table when first encountered during tokenization, matching Atari BASIC behavior.

**Example**:
```
10 LET X=5     <- Variable X created in VNT, entry added to VVT
20 PRINT X     <- Variable X looked up, index used in tokenized form
30 LET Y=X+1   <- Variable Y created, X looked up
```

### 5. NEW and Disk Load: Clear Variable Table

- `NEW` command: Clears statement table and variable tables in emulator memory
- Loading from disk: The loaded program replaces memory contents; Swift reads fresh state

### 6. Turbo BASIC: Deferred

Turbo BASIC XL support is **deferred to a future phase**. Phase 14 implements standard Atari BASIC only.

The `REPLMode.basic(variant:)` enum already supports `.turbo` for future use.

### 7. Error Reporting: Immediate

Errors are reported immediately when a line is entered, matching Atari BASIC behavior.

**Response format**:
```
OK:Line 10 stored (23 bytes)
```
or
```
ERR:Syntax error at column 15: Unknown keyword 'PRIMT'. Did you mean 'PRINT'?
```

### 8. Socket Protocol: Existing Text Protocol

BASIC lines use the existing CLI socket protocol. No new command types needed.

**Protocol flow**:
```
Client: CMD:basic 10 PRINT "HELLO"
Server: OK:Line 10 stored (18 bytes)

Client: CMD:basic RUN
Server: OK:Running

Client: CMD:basic LIST
Server: OK:10 PRINT "HELLO"
```

For direct line entry in BASIC mode:
```
Client: CMD:10 PRINT "HELLO"
Server: OK:Line 10 stored (18 bytes)
```

### 9. Tokenizer Architecture: Stateless Struct

The tokenizer is a **stateless struct** that operates on input and emulator state.

```swift
struct BASICTokenizer {
    /// Tokenizes a BASIC line and returns the tokenized bytes.
    /// Does NOT modify emulator memory - caller handles injection.
    func tokenizeLine(
        _ line: String,
        existingVariables: [BASICVariable]
    ) throws -> TokenizedLine
}
```

The `REPLEngine` or a new `BASICLineHandler` coordinates:
1. Reading current state from emulator
2. Calling tokenizer
3. Writing results back to emulator

---

## Module Structure

```
Sources/AtticCore/BASIC/
├── BASICTokenizer.swift       # Stateless tokenizer (lexer + encoder)
├── BASICToken.swift           # Token type enums and lookup tables
├── BASICVariable.swift        # Variable types and VNT/VVT structures
├── BASICMemoryLayout.swift    # Memory pointer constants and helpers
├── BASICLineHandler.swift     # Coordinates tokenization + memory injection
└── BCDFloat.swift             # 6-byte BCD floating-point conversion
```

### File Responsibilities

#### BASICToken.swift
- `BASICStatementToken` enum (REM=$00, DATA=$01, ... CLOAD=$35)
- `BASICOperatorToken` enum (comma=$37, ... unary minus=$5B)
- `BASICFunctionToken` enum (STR$=$5D, ... STRIG=$74)
- Lookup tables for keyword → token conversion
- Abbreviation support (e.g., `PR.` → PRINT)

#### BASICVariable.swift
- `BASICVariableType` enum (numeric, string, array, stringArray)
- `BASICVariable` struct (name, type, index)
- VNT encoding/decoding helpers
- VVT structure (8 bytes per variable)

#### BASICMemoryLayout.swift
- Zero page pointer addresses (LOMEM=$80, VNTP=$82, etc.)
- Helper functions to read/write BASIC pointers
- Memory region calculations

#### BCDFloat.swift
- `BCDFloat` struct for 6-byte BCD representation
- `encode(_ value: Double) -> [UInt8]`
- `decode(_ bytes: [UInt8]) -> Double`
- Special handling for zero, integers 0-255

#### BASICTokenizer.swift
- `BASICLexer` - breaks input into lexical tokens
- `BASICTokenizer` - converts lexical tokens to byte representation
- `TokenizedLine` - result struct with bytes, variables, metadata

#### BASICLineHandler.swift
- `BASICLineHandler` actor - coordinates with EmulatorEngine
- `enterLine(_:)` - full pipeline: read state → tokenize → inject
- `deleteLine(_:)` - remove a line from statement table
- `newProgram()` - clear all BASIC memory
- `runProgram()` - trigger RUN in emulator

---

## Token Encoding Reference

### Line Format
```
┌─────────────┬──────────────┬─────────────────────┬─────┐
│ Line Number │ Next Line    │ Tokenized           │ EOL │
│ (2 bytes)   │ Offset       │ Statements          │     │
│ little-end  │ (1 byte)     │                     │$16  │
└─────────────┴──────────────┴─────────────────────┴─────┘
```

### Numeric Constants
- Small integer (0-255): `$0D <byte>`
- BCD float: `$0E <6 bytes>`

### String Constants
- `$0F <length> <characters...>`

### Variable References
- Variable index + $80 (first variable = $80, second = $81, etc.)

---

## Implementation Order

### Step 1: Foundation Types
1. `BASICToken.swift` - All token enums and tables
2. `BASICVariable.swift` - Variable type definitions
3. `BASICMemoryLayout.swift` - Memory constants
4. `BCDFloat.swift` - BCD conversion

### Step 2: Tokenizer Core
5. `BASICTokenizer.swift` - Lexer and tokenizer

### Step 3: Integration
6. `BASICLineHandler.swift` - Memory injection coordinator
7. Update `REPLEngine.swift` - Wire up BASIC commands
8. Update `CLISocketServer.swift` - Handle BASIC protocol

### Step 4: Testing
9. Unit tests for BCD conversion
10. Unit tests for tokenizer (known programs)
11. Integration tests via CLI protocol

---

## Test Cases

### BCD Float Conversion
```swift
// Zero
XCTAssertEqual(BCDFloat.encode(0), [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

// Small integers
XCTAssertEqual(BCDFloat.encode(1), [0x40, 0x01, 0x00, 0x00, 0x00, 0x00])
XCTAssertEqual(BCDFloat.encode(10), [0x41, 0x01, 0x00, 0x00, 0x00, 0x00])

// Pi
XCTAssertEqual(BCDFloat.encode(3.14159), [0x40, 0x03, 0x14, 0x15, 0x90, 0x00])

// Negative
XCTAssertEqual(BCDFloat.encode(-1), [0xC0, 0x01, 0x00, 0x00, 0x00, 0x00])
```

### Simple Program Tokenization
```
10 PRINT "HELLO"
```
Expected bytes:
- Line number: `$0A $00` (10 in little-endian)
- Offset: `$0E` (14 bytes total)
- PRINT token: `$20`
- Space (implicit)
- String marker: `$0F`
- String length: `$05`
- "HELLO": `$48 $45 $4C $4C $4F`
- EOL: `$16`

### Variable Reference
```
10 LET X=5
20 PRINT X
```
Line 10:
- LET token: `$06`
- Variable X: `$80` (first variable, index 0 + $80)
- Equals: `$52`
- Small int marker: `$0D`
- Value 5: `$05`

Line 20:
- PRINT token: `$20`
- Variable X: `$80` (same variable reference)

---

## Error Messages

| Condition | Error Message |
|-----------|---------------|
| Unknown keyword | `Syntax error at column N: Unknown keyword 'XXX'. Did you mean 'YYY'?` |
| Unterminated string | `Syntax error at column N: Unterminated string literal` |
| Invalid line number | `Line number must be 0-32767` |
| Line too long | `Line too long (max 256 bytes tokenized)` |
| Too many variables | `Too many variables (max 128)` |
| Invalid character | `Invalid character 'X' at column N` |

---

## Open Items for Phase 15

- Detokenizer for LIST command
- VARS command implementation
- Import/Export to host filesystem
- Save/Load to ATR disk images

---

## References

- `docs/BASIC_TOKENIZER.md` - Full tokenization specification
- `docs/IMPLEMENTATION_PLAN.md` - Phase overview
- Atari BASIC Reference Manual
- De Re Atari - Chapter on BASIC internals
