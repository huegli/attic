# BASIC Tokenizer Specification

## Overview

The BASIC tokenizer converts human-readable Atari BASIC source code into the tokenized format that the Atari BASIC ROM expects in memory. This allows entering BASIC programs through the REPL and injecting them directly into emulator memory.

## Atari BASIC Memory Layout

### Memory Pointers

These zero-page locations define the BASIC program structure:

| Pointer | Address | Description |
|---------|---------|-------------|
| LOMEM | $80-$81 | Start of BASIC memory |
| VNTP | $82-$83 | Variable Name Table Pointer |
| VNTD | $84-$85 | Variable Name Table Dummy End |
| VVTP | $86-$87 | Variable Value Table Pointer |
| STMTAB | $88-$89 | Statement Table (program start) |
| STMCUR | $8A-$8B | Current statement pointer |
| STARP | $8C-$8D | String/Array Table Pointer |
| RUNSTK | $8E-$8F | Runtime Stack Pointer |
| MEMTOP | $90-$91 | Top of BASIC memory |

### Memory Structure

```
LOMEM ($0700 typical)
├── Variable Name Table
│   └── Variable names with type indicators
VNTP
├── (empty byte $00)
VNTD
├── Variable Value Table
│   └── 8 bytes per variable
VVTP
├── Statement Table
│   └── Tokenized program lines
STMTAB
├── (end of program marker)
│
├── String/Array Storage
STARP
├── Runtime Stack (grows down)
RUNSTK
│
MEMTOP ($9FFF or $BFFF)
```

## Variable Name Table

### Format

Each variable name entry:
- Characters of variable name (1-128 characters)
- Last character has bit 7 set (OR with $80)
- Type suffix (if present) in last character

### Variable Types

| Type | Suffix | Example |
|------|--------|---------|
| Numeric | none | `A`, `COUNT` |
| String | $ | `A$`, `NAME$` |
| Array | ( | `A(`, `GRID(` |
| String Array | $( | `A$(` |

### Example

Variable `NAME$`:
```
$4E $41 $4D $C5  ('N', 'A', 'M', 'E' | $80)
$24              ('$' - string indicator)
```

## Variable Value Table

### Format

8 bytes per variable, regardless of type:

**Numeric Variable:**
- Bytes 0-5: 6-byte BCD floating point value
- Bytes 6-7: unused (typically $00)

**String Variable:**
- Bytes 0-1: String length (16-bit, little-endian)
- Bytes 2-3: String address (16-bit, little-endian)
- Bytes 4-7: unused

**Array Variable:**
- Bytes 0-1: Array offset from STARP
- Bytes 2-7: Dimension information

## Statement Table

### Line Format

Each line has this structure:

```
┌─────────────┬──────────────┬─────────────────────┬─────┐
│ Line Number │ Next Line    │ Tokenized           │ EOL │
│ (2 bytes)   │ Offset       │ Statements          │     │
│ little-end  │ (1 byte)     │                     │     │
└─────────────┴──────────────┴─────────────────────┴─────┘
```

- **Line Number**: 16-bit little-endian (0-32767)
- **Next Line Offset**: Bytes from start of this line to start of next
- **Tokenized Statements**: Variable-length encoded content
- **EOL**: End of line marker ($16)

### End of Program

The program ends with:
```
$00 $00 $00
```
(Line number 0 with offset 0)

## Token Encoding

### Statement Tokens ($00-$36)

| Token | Statement | Token | Statement |
|-------|-----------|-------|-----------|
| $00 | REM | $01 | DATA |
| $02 | INPUT | $03 | COLOR |
| $04 | LIST | $05 | ENTER |
| $06 | LET | $07 | IF |
| $08 | FOR | $09 | NEXT |
| $0A | GOTO | $0B | GO TO |
| $0C | GOSUB | $0D | TRAP |
| $0E | BYE | $0F | CONT |
| $10 | COM | $11 | CLOSE |
| $12 | CLR | $13 | DEG |
| $14 | DIM | $15 | END |
| $16 | NEW | $17 | OPEN |
| $18 | LOAD | $19 | SAVE |
| $1A | STATUS | $1B | NOTE |
| $1C | POINT | $1D | XIO |
| $1E | ON | $1F | POKE |
| $20 | PRINT | $21 | RAD |
| $22 | READ | $23 | RESTORE |
| $24 | RETURN | $25 | RUN |
| $26 | STOP | $27 | POP |
| $28 | ? (PRINT) | $29 | GET |
| $2A | PUT | $2B | GRAPHICS |
| $2C | PLOT | $2D | POSITION |
| $2E | DOS | $2F | DRAWTO |
| $30 | SETCOLOR | $31 | LOCATE |
| $32 | SOUND | $33 | LPRINT |
| $34 | CSAVE | $35 | CLOAD |
| $36 | (implied LET) | | |

### Operator Tokens ($37-$5A)

| Token | Operator | Token | Operator |
|-------|----------|-------|----------|
| $37 | , | $38 | $ (string) |
| $39 | : | $3A | ; |
| $3B | EOL | $3C | GOTO (in ON) |
| $3D | GOSUB (in ON) | $3E | TO |
| $3F | STEP | $40 | THEN |
| $41 | # | $42 | <= |
| $43 | <> | $44 | >= |
| $45 | < | $46 | > |
| $47 | = | $48 | ^ |
| $49 | * | $4A | + |
| $4B | - | $4C | / |
| $4D | NOT | $4E | OR |
| $4F | AND | $50 | ( |
| $51 | ) | $52 | = (assign) |
| $53 | = (compare) | $54 | <= |
| $55 | <> | $56 | >= |
| $57 | < | $58 | > |
| $59 | = | $5A | + (unary) |
| $5B | - (unary) | $5C | ( (array) |

### Function Tokens ($5D-$7F)

| Token | Function | Token | Function |
|-------|----------|-------|----------|
| $5D | STR$ | $5E | CHR$ |
| $5F | USR | $60 | ASC |
| $61 | VAL | $62 | LEN |
| $63 | ADR | $64 | ATN |
| $65 | COS | $66 | PEEK |
| $67 | SIN | $68 | RND |
| $69 | FRE | $6A | EXP |
| $6B | LOG | $6C | CLOG |
| $6D | SQR | $6E | SGN |
| $6F | ABS | $70 | INT |
| $71 | PADDLE | $72 | STICK |
| $73 | PTRIG | $74 | STRIG |

### Numeric Constants

Numeric constants are encoded as:

```
$0E <6-byte BCD floating point>
```

Or for positive integers 0-255:
```
$0D <1-byte value>
```

Or for larger integers:
```
$0E <6-byte BCD>
```

### String Constants

```
$0F <length> <characters...>
```

- Length is 1 byte (0-255)
- Characters are ATASCII

### Variable References

```
<variable-index>
```

Where variable-index is the position in the Variable Name Table (0-127), plus $80 for the first variable.

## BCD Floating Point Format

Atari BASIC uses 6-byte BCD floating point:

```
Byte 0: Exponent (excess-64, sign in bit 7)
Bytes 1-5: 10-digit BCD mantissa (2 digits per byte)
```

### Examples

| Value | Bytes |
|-------|-------|
| 0 | 00 00 00 00 00 00 |
| 1 | 40 01 00 00 00 00 |
| 10 | 41 01 00 00 00 00 |
| 100 | 42 01 00 00 00 00 |
| 3.14159 | 40 03 14 15 90 00 |
| -1 | C0 01 00 00 00 00 |

### Conversion Algorithm

```swift
func encodeBCD(_ value: Double) -> [UInt8] {
    if value == 0 {
        return [0, 0, 0, 0, 0, 0]
    }
    
    let isNegative = value < 0
    let absValue = abs(value)
    
    // Calculate exponent
    var exponent = Int(floor(log10(absValue))) + 1
    
    // Normalize to get mantissa
    var mantissa = absValue / pow(10, Double(exponent - 1))
    
    // Build BCD digits
    var digits: [UInt8] = []
    for _ in 0..<10 {
        let digit = Int(mantissa)
        digits.append(UInt8(digit))
        mantissa = (mantissa - Double(digit)) * 10
    }
    
    // Pack into bytes
    var result: [UInt8] = []
    
    // Exponent byte (excess-64, sign in bit 7)
    var expByte = UInt8(exponent + 64)
    if isNegative {
        expByte |= 0x80
    }
    result.append(expByte)
    
    // Pack digit pairs
    for i in stride(from: 0, to: 10, by: 2) {
        result.append((digits[i] << 4) | digits[i + 1])
    }
    
    return result
}
```

## Tokenization Process

### 1. Lexical Analysis

Break input line into tokens:

```swift
enum LexToken {
    case lineNumber(Int)
    case keyword(String)
    case identifier(String)
    case numericLiteral(Double)
    case stringLiteral(String)
    case operator(String)
    case punctuation(Character)
}
```

### 2. Keyword Recognition

Match keywords permissively:
- Full keyword: `PRINT`
- Abbreviation: `PR.` (any keyword can be abbreviated with `.`)
- Special: `?` for PRINT, `.` for REM

### 3. Variable Resolution

Build or update the Variable Name Table:
1. Look up identifier in existing table
2. If not found, add to table
3. Return index for tokenization

### 4. Expression Encoding

Expressions are encoded in a modified infix notation with operator precedence built in:
- Operators and operands alternate
- Function calls include argument count
- Parentheses are explicit

### 5. Line Assembly

Combine all tokens with proper markers:
1. Line number (2 bytes)
2. Line length (1 byte, filled in at end)
3. Statement tokens
4. EOL marker ($16)

## Turbo BASIC XL Extensions

Turbo BASIC XL adds additional tokens:

### Additional Statements ($38+)

| Token | Statement |
|-------|-----------|
| $38 | DPOKE |
| $39 | MOVE |
| $3A | -MOVE |
| $3B | *F |
| $3C | REPEAT |
| $3D | UNTIL |
| ... | ... |

### Detection

Turbo BASIC XL is detected by:
1. Explicit mode switch (`.basic turbo`)
2. Presence of Turbo BASIC XL on mounted disk

## Detokenization

Reverse process for LIST command:

### Algorithm

```swift
func detokenize(from address: UInt16) -> String {
    var output = ""
    var addr = address
    
    while true {
        // Read line number
        let lineNum = readWord(addr)
        if lineNum == 0 { break }
        
        // Read line length
        let length = readByte(addr + 2)
        
        output += "\(lineNum) "
        
        // Process tokens
        var pos = addr + 3
        while pos < addr + UInt16(length) {
            let token = readByte(pos)
            output += decodeToken(token, at: &pos)
        }
        
        output += "\n"
        addr += UInt16(length)
    }
    
    return output
}
```

## Error Handling

### Syntax Errors

```swift
struct TokenizerError {
    let line: Int
    let column: Int
    let message: String
    let context: String      // Portion of line around error
    let suggestion: String?  // Helpful fix suggestion
}
```

### Error Types

| Error | Description | Suggestion |
|-------|-------------|------------|
| Unknown keyword | Token not recognized | "Did you mean X?" |
| Unterminated string | Missing closing quote | "Add closing quote" |
| Invalid line number | Out of range 0-32767 | "Use line 1-32767" |
| Expression error | Malformed expression | Show expected format |
| Too many variables | >128 variables | "Reduce variable count" |
| Line too long | >256 bytes tokenized | "Split into multiple lines" |

### Error Display Format

```
Error at line 10, column 15:
  10 PRINT HELLO
              ^^^^
Unrecognized identifier 'HELLO'
  Suggestion: For a string, use "HELLO" (in quotes)
              For a variable, 'HELLO' will be created
```

## Memory Injection

After tokenization, inject into emulator memory:

```swift
func injectBASIC(program: TokenizedProgram) async {
    await emulator.pause()
    
    // Write Variable Name Table
    let vntStart: UInt16 = 0x0700
    await emulator.writeMemory(at: vntStart, bytes: program.variableNames)
    
    // Write Variable Value Table  
    let vvtStart = vntStart + UInt16(program.variableNames.count) + 1
    await emulator.writeMemory(at: vvtStart, bytes: program.variableValues)
    
    // Write Statement Table
    let stmtStart = vvtStart + UInt16(program.variableValues.count)
    await emulator.writeMemory(at: stmtStart, bytes: program.statements)
    
    // Update BASIC pointers
    await emulator.writeWord(at: 0x82, value: vntStart)           // VNTP
    await emulator.writeWord(at: 0x84, value: vvtStart - 1)       // VNTD
    await emulator.writeWord(at: 0x86, value: vvtStart)           // VVTP
    await emulator.writeWord(at: 0x88, value: stmtStart)          // STMTAB
    await emulator.writeWord(at: 0x8A, value: stmtStart)          // STMCUR
    
    let endOfProgram = stmtStart + UInt16(program.statements.count)
    await emulator.writeWord(at: 0x8C, value: endOfProgram)       // STARP
    
    await emulator.resume()
}
```

## File I/O

### Import (.BAS from host)

1. Read file as macOS text (UTF-8 with LF line endings)
2. Convert any non-ATASCII characters
3. Parse and tokenize
4. Inject into memory

### Export (.BAS to host)

1. Detokenize from memory
2. Convert ATASCII to UTF-8
3. Write with LF line endings

### Save to ATR

1. Tokenize (or read from memory if already tokenized)
2. Create Atari DOS file header
3. Write to disk image using DOS file system
