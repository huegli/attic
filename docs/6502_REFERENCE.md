# 6502 Instruction Set Reference

## Overview

This document provides the 6502 instruction set reference needed to implement the monitor's assembler and disassembler.

## Registers

| Register | Size | Description |
|----------|------|-------------|
| A | 8-bit | Accumulator |
| X | 8-bit | Index register X |
| Y | 8-bit | Index register Y |
| S | 8-bit | Stack pointer (page 1: $0100-$01FF) |
| PC | 16-bit | Program counter |
| P | 8-bit | Processor status (flags) |

## Status Flags (P Register)

```
Bit 7 6 5 4 3 2 1 0
    N V - B D I Z C
```

| Bit | Flag | Name | Description |
|-----|------|------|-------------|
| 7 | N | Negative | Set if result bit 7 is set |
| 6 | V | Overflow | Set on signed overflow |
| 5 | - | Unused | Always 1 |
| 4 | B | Break | Set by BRK instruction |
| 3 | D | Decimal | Enable BCD arithmetic |
| 2 | I | Interrupt | Disable IRQ when set |
| 1 | Z | Zero | Set if result is zero |
| 0 | C | Carry | Carry/borrow flag |

## Addressing Modes

| Mode | Syntax | Example | Bytes | Description |
|------|--------|---------|-------|-------------|
| Implied | | `INX` | 1 | No operand |
| Accumulator | A | `ASL A` | 1 | Operates on A |
| Immediate | #$nn | `LDA #$00` | 2 | Literal value |
| Zero Page | $nn | `LDA $00` | 2 | Address $00-$FF |
| Zero Page,X | $nn,X | `LDA $00,X` | 2 | ZP + X (wraps) |
| Zero Page,Y | $nn,Y | `LDX $00,Y` | 2 | ZP + Y (wraps) |
| Absolute | $nnnn | `LDA $1234` | 3 | Full 16-bit address |
| Absolute,X | $nnnn,X | `LDA $1234,X` | 3 | Address + X |
| Absolute,Y | $nnnn,Y | `LDA $1234,Y` | 3 | Address + Y |
| Indirect | ($nnnn) | `JMP ($1234)` | 3 | Pointer (JMP only) |
| Indexed Indirect | ($nn,X) | `LDA ($00,X)` | 2 | ZP pointer + X |
| Indirect Indexed | ($nn),Y | `LDA ($00),Y` | 2 | ZP pointer, then + Y |
| Relative | $nn | `BNE $nn` | 2 | Signed offset (-128 to +127) |

## Complete Instruction Set

### Load/Store Operations

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $A9 | LDA | Immediate | 2 | 2 | N,Z |
| $A5 | LDA | Zero Page | 2 | 3 | N,Z |
| $B5 | LDA | Zero Page,X | 2 | 4 | N,Z |
| $AD | LDA | Absolute | 3 | 4 | N,Z |
| $BD | LDA | Absolute,X | 3 | 4+ | N,Z |
| $B9 | LDA | Absolute,Y | 3 | 4+ | N,Z |
| $A1 | LDA | (Indirect,X) | 2 | 6 | N,Z |
| $B1 | LDA | (Indirect),Y | 2 | 5+ | N,Z |
| $A2 | LDX | Immediate | 2 | 2 | N,Z |
| $A6 | LDX | Zero Page | 2 | 3 | N,Z |
| $B6 | LDX | Zero Page,Y | 2 | 4 | N,Z |
| $AE | LDX | Absolute | 3 | 4 | N,Z |
| $BE | LDX | Absolute,Y | 3 | 4+ | N,Z |
| $A0 | LDY | Immediate | 2 | 2 | N,Z |
| $A4 | LDY | Zero Page | 2 | 3 | N,Z |
| $B4 | LDY | Zero Page,X | 2 | 4 | N,Z |
| $AC | LDY | Absolute | 3 | 4 | N,Z |
| $BC | LDY | Absolute,X | 3 | 4+ | N,Z |
| $85 | STA | Zero Page | 2 | 3 | - |
| $95 | STA | Zero Page,X | 2 | 4 | - |
| $8D | STA | Absolute | 3 | 4 | - |
| $9D | STA | Absolute,X | 3 | 5 | - |
| $99 | STA | Absolute,Y | 3 | 5 | - |
| $81 | STA | (Indirect,X) | 2 | 6 | - |
| $91 | STA | (Indirect),Y | 2 | 6 | - |
| $86 | STX | Zero Page | 2 | 3 | - |
| $96 | STX | Zero Page,Y | 2 | 4 | - |
| $8E | STX | Absolute | 3 | 4 | - |
| $84 | STY | Zero Page | 2 | 3 | - |
| $94 | STY | Zero Page,X | 2 | 4 | - |
| $8C | STY | Absolute | 3 | 4 | - |

### Transfer Operations

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $AA | TAX | Implied | 1 | 2 | N,Z |
| $A8 | TAY | Implied | 1 | 2 | N,Z |
| $BA | TSX | Implied | 1 | 2 | N,Z |
| $8A | TXA | Implied | 1 | 2 | N,Z |
| $9A | TXS | Implied | 1 | 2 | - |
| $98 | TYA | Implied | 1 | 2 | N,Z |

### Arithmetic Operations

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $69 | ADC | Immediate | 2 | 2 | N,V,Z,C |
| $65 | ADC | Zero Page | 2 | 3 | N,V,Z,C |
| $75 | ADC | Zero Page,X | 2 | 4 | N,V,Z,C |
| $6D | ADC | Absolute | 3 | 4 | N,V,Z,C |
| $7D | ADC | Absolute,X | 3 | 4+ | N,V,Z,C |
| $79 | ADC | Absolute,Y | 3 | 4+ | N,V,Z,C |
| $61 | ADC | (Indirect,X) | 2 | 6 | N,V,Z,C |
| $71 | ADC | (Indirect),Y | 2 | 5+ | N,V,Z,C |
| $E9 | SBC | Immediate | 2 | 2 | N,V,Z,C |
| $E5 | SBC | Zero Page | 2 | 3 | N,V,Z,C |
| $F5 | SBC | Zero Page,X | 2 | 4 | N,V,Z,C |
| $ED | SBC | Absolute | 3 | 4 | N,V,Z,C |
| $FD | SBC | Absolute,X | 3 | 4+ | N,V,Z,C |
| $F9 | SBC | Absolute,Y | 3 | 4+ | N,V,Z,C |
| $E1 | SBC | (Indirect,X) | 2 | 6 | N,V,Z,C |
| $F1 | SBC | (Indirect),Y | 2 | 5+ | N,V,Z,C |

### Increment/Decrement

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $E6 | INC | Zero Page | 2 | 5 | N,Z |
| $F6 | INC | Zero Page,X | 2 | 6 | N,Z |
| $EE | INC | Absolute | 3 | 6 | N,Z |
| $FE | INC | Absolute,X | 3 | 7 | N,Z |
| $E8 | INX | Implied | 1 | 2 | N,Z |
| $C8 | INY | Implied | 1 | 2 | N,Z |
| $C6 | DEC | Zero Page | 2 | 5 | N,Z |
| $D6 | DEC | Zero Page,X | 2 | 6 | N,Z |
| $CE | DEC | Absolute | 3 | 6 | N,Z |
| $DE | DEC | Absolute,X | 3 | 7 | N,Z |
| $CA | DEX | Implied | 1 | 2 | N,Z |
| $88 | DEY | Implied | 1 | 2 | N,Z |

### Logical Operations

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $29 | AND | Immediate | 2 | 2 | N,Z |
| $25 | AND | Zero Page | 2 | 3 | N,Z |
| $35 | AND | Zero Page,X | 2 | 4 | N,Z |
| $2D | AND | Absolute | 3 | 4 | N,Z |
| $3D | AND | Absolute,X | 3 | 4+ | N,Z |
| $39 | AND | Absolute,Y | 3 | 4+ | N,Z |
| $21 | AND | (Indirect,X) | 2 | 6 | N,Z |
| $31 | AND | (Indirect),Y | 2 | 5+ | N,Z |
| $09 | ORA | Immediate | 2 | 2 | N,Z |
| $05 | ORA | Zero Page | 2 | 3 | N,Z |
| $15 | ORA | Zero Page,X | 2 | 4 | N,Z |
| $0D | ORA | Absolute | 3 | 4 | N,Z |
| $1D | ORA | Absolute,X | 3 | 4+ | N,Z |
| $19 | ORA | Absolute,Y | 3 | 4+ | N,Z |
| $01 | ORA | (Indirect,X) | 2 | 6 | N,Z |
| $11 | ORA | (Indirect),Y | 2 | 5+ | N,Z |
| $49 | EOR | Immediate | 2 | 2 | N,Z |
| $45 | EOR | Zero Page | 2 | 3 | N,Z |
| $55 | EOR | Zero Page,X | 2 | 4 | N,Z |
| $4D | EOR | Absolute | 3 | 4 | N,Z |
| $5D | EOR | Absolute,X | 3 | 4+ | N,Z |
| $59 | EOR | Absolute,Y | 3 | 4+ | N,Z |
| $41 | EOR | (Indirect,X) | 2 | 6 | N,Z |
| $51 | EOR | (Indirect),Y | 2 | 5+ | N,Z |

### Shift/Rotate

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $0A | ASL | Accumulator | 1 | 2 | N,Z,C |
| $06 | ASL | Zero Page | 2 | 5 | N,Z,C |
| $16 | ASL | Zero Page,X | 2 | 6 | N,Z,C |
| $0E | ASL | Absolute | 3 | 6 | N,Z,C |
| $1E | ASL | Absolute,X | 3 | 7 | N,Z,C |
| $4A | LSR | Accumulator | 1 | 2 | N,Z,C |
| $46 | LSR | Zero Page | 2 | 5 | N,Z,C |
| $56 | LSR | Zero Page,X | 2 | 6 | N,Z,C |
| $4E | LSR | Absolute | 3 | 6 | N,Z,C |
| $5E | LSR | Absolute,X | 3 | 7 | N,Z,C |
| $2A | ROL | Accumulator | 1 | 2 | N,Z,C |
| $26 | ROL | Zero Page | 2 | 5 | N,Z,C |
| $36 | ROL | Zero Page,X | 2 | 6 | N,Z,C |
| $2E | ROL | Absolute | 3 | 6 | N,Z,C |
| $3E | ROL | Absolute,X | 3 | 7 | N,Z,C |
| $6A | ROR | Accumulator | 1 | 2 | N,Z,C |
| $66 | ROR | Zero Page | 2 | 5 | N,Z,C |
| $76 | ROR | Zero Page,X | 2 | 6 | N,Z,C |
| $6E | ROR | Absolute | 3 | 6 | N,Z,C |
| $7E | ROR | Absolute,X | 3 | 7 | N,Z,C |

### Compare

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $C9 | CMP | Immediate | 2 | 2 | N,Z,C |
| $C5 | CMP | Zero Page | 2 | 3 | N,Z,C |
| $D5 | CMP | Zero Page,X | 2 | 4 | N,Z,C |
| $CD | CMP | Absolute | 3 | 4 | N,Z,C |
| $DD | CMP | Absolute,X | 3 | 4+ | N,Z,C |
| $D9 | CMP | Absolute,Y | 3 | 4+ | N,Z,C |
| $C1 | CMP | (Indirect,X) | 2 | 6 | N,Z,C |
| $D1 | CMP | (Indirect),Y | 2 | 5+ | N,Z,C |
| $E0 | CPX | Immediate | 2 | 2 | N,Z,C |
| $E4 | CPX | Zero Page | 2 | 3 | N,Z,C |
| $EC | CPX | Absolute | 3 | 4 | N,Z,C |
| $C0 | CPY | Immediate | 2 | 2 | N,Z,C |
| $C4 | CPY | Zero Page | 2 | 3 | N,Z,C |
| $CC | CPY | Absolute | 3 | 4 | N,Z,C |
| $24 | BIT | Zero Page | 2 | 3 | N,V,Z |
| $2C | BIT | Absolute | 3 | 4 | N,V,Z |

### Branch

| Opcode | Mnemonic | Mode | Bytes | Cycles | Condition |
|--------|----------|------|-------|--------|-----------|
| $90 | BCC | Relative | 2 | 2/3/4 | C = 0 |
| $B0 | BCS | Relative | 2 | 2/3/4 | C = 1 |
| $F0 | BEQ | Relative | 2 | 2/3/4 | Z = 1 |
| $30 | BMI | Relative | 2 | 2/3/4 | N = 1 |
| $D0 | BNE | Relative | 2 | 2/3/4 | Z = 0 |
| $10 | BPL | Relative | 2 | 2/3/4 | N = 0 |
| $50 | BVC | Relative | 2 | 2/3/4 | V = 0 |
| $70 | BVS | Relative | 2 | 2/3/4 | V = 1 |

Branch cycles: 2 if not taken, 3 if taken, 4 if taken and crosses page.

### Jump/Call

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $4C | JMP | Absolute | 3 | 3 | - |
| $6C | JMP | Indirect | 3 | 5 | - |
| $20 | JSR | Absolute | 3 | 6 | - |
| $60 | RTS | Implied | 1 | 6 | - |
| $40 | RTI | Implied | 1 | 6 | All |

### Stack

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $48 | PHA | Implied | 1 | 3 | - |
| $08 | PHP | Implied | 1 | 3 | - |
| $68 | PLA | Implied | 1 | 4 | N,Z |
| $28 | PLP | Implied | 1 | 4 | All |

### Flags

| Opcode | Mnemonic | Mode | Bytes | Cycles | Effect |
|--------|----------|------|-------|--------|--------|
| $18 | CLC | Implied | 1 | 2 | C = 0 |
| $D8 | CLD | Implied | 1 | 2 | D = 0 |
| $58 | CLI | Implied | 1 | 2 | I = 0 |
| $B8 | CLV | Implied | 1 | 2 | V = 0 |
| $38 | SEC | Implied | 1 | 2 | C = 1 |
| $F8 | SED | Implied | 1 | 2 | D = 1 |
| $78 | SEI | Implied | 1 | 2 | I = 1 |

### System

| Opcode | Mnemonic | Mode | Bytes | Cycles | Flags |
|--------|----------|------|-------|--------|-------|
| $00 | BRK | Implied | 1 | 7 | B,I |
| $EA | NOP | Implied | 1 | 2 | - |

## Disassembler Implementation

### Opcode Table Structure

```swift
struct OpcodeInfo {
    let mnemonic: String
    let mode: AddressingMode
    let bytes: Int
    let cycles: Int
    let pageCross: Bool  // +1 cycle on page cross
}

enum AddressingMode {
    case implied
    case accumulator
    case immediate
    case zeroPage
    case zeroPageX
    case zeroPageY
    case absolute
    case absoluteX
    case absoluteY
    case indirect
    case indexedIndirect  // (zp,X)
    case indirectIndexed  // (zp),Y
    case relative
}

let opcodeTable: [UInt8: OpcodeInfo] = [
    0x00: OpcodeInfo(mnemonic: "BRK", mode: .implied, bytes: 1, cycles: 7, pageCross: false),
    0x01: OpcodeInfo(mnemonic: "ORA", mode: .indexedIndirect, bytes: 2, cycles: 6, pageCross: false),
    // ... etc
]
```

### Disassembly Function

```swift
func disassemble(at address: UInt16, memory: MemoryBus) -> (instruction: String, length: Int) {
    let opcode = memory.read(address)
    
    guard let info = opcodeTable[opcode] else {
        return (String(format: "???  $%02X", opcode), 1)
    }
    
    switch info.mode {
    case .implied:
        return (info.mnemonic, 1)
        
    case .accumulator:
        return ("\(info.mnemonic) A", 1)
        
    case .immediate:
        let value = memory.read(address + 1)
        return (String(format: "%@ #$%02X", info.mnemonic, value), 2)
        
    case .zeroPage:
        let addr = memory.read(address + 1)
        return (String(format: "%@ $%02X", info.mnemonic, addr), 2)
        
    case .zeroPageX:
        let addr = memory.read(address + 1)
        return (String(format: "%@ $%02X,X", info.mnemonic, addr), 2)
        
    case .zeroPageY:
        let addr = memory.read(address + 1)
        return (String(format: "%@ $%02X,Y", info.mnemonic, addr), 2)
        
    case .absolute:
        let low = UInt16(memory.read(address + 1))
        let high = UInt16(memory.read(address + 2))
        let addr = (high << 8) | low
        return (String(format: "%@ $%04X", info.mnemonic, addr), 3)
        
    case .absoluteX:
        let low = UInt16(memory.read(address + 1))
        let high = UInt16(memory.read(address + 2))
        let addr = (high << 8) | low
        return (String(format: "%@ $%04X,X", info.mnemonic, addr), 3)
        
    case .absoluteY:
        let low = UInt16(memory.read(address + 1))
        let high = UInt16(memory.read(address + 2))
        let addr = (high << 8) | low
        return (String(format: "%@ $%04X,Y", info.mnemonic, addr), 3)
        
    case .indirect:
        let low = UInt16(memory.read(address + 1))
        let high = UInt16(memory.read(address + 2))
        let addr = (high << 8) | low
        return (String(format: "%@ ($%04X)", info.mnemonic, addr), 3)
        
    case .indexedIndirect:
        let addr = memory.read(address + 1)
        return (String(format: "%@ ($%02X,X)", info.mnemonic, addr), 2)
        
    case .indirectIndexed:
        let addr = memory.read(address + 1)
        return (String(format: "%@ ($%02X),Y", info.mnemonic, addr), 2)
        
    case .relative:
        let offset = Int8(bitPattern: memory.read(address + 1))
        let target = UInt16(Int(address) + 2 + Int(offset))
        return (String(format: "%@ $%04X", info.mnemonic, target), 2)
    }
}
```

### Disassembly Output Format

```
$E477  A9 00     LDA #$00
$E479  8D 00 D4  STA $D400
$E47C  A9 01     LDA #$01
$E47E  8D 01 D4  STA $D401
$E481  4C 77 E4  JMP $E477
```

## Assembler Implementation

### Parsing

```swift
struct AssemblyLine {
    let label: String?
    let mnemonic: String?
    let operand: String?
    let comment: String?
}

func parseLine(_ line: String) -> AssemblyLine {
    // Handle: LABEL: MNEMONIC OPERAND ; COMMENT
    // Examples:
    //   LOOP: LDA #$00
    //   STA $D400
    //   BNE LOOP ; branch back
}
```

### Operand Parsing

```swift
enum ParsedOperand {
    case none                           // Implied
    case accumulator                    // A
    case immediate(UInt8)               // #$nn or #nn
    case zeroPage(UInt8)                // $nn
    case zeroPageX(UInt8)               // $nn,X
    case zeroPageY(UInt8)               // $nn,Y
    case absolute(UInt16)               // $nnnn
    case absoluteX(UInt16)              // $nnnn,X
    case absoluteY(UInt16)              // $nnnn,Y
    case indirect(UInt16)               // ($nnnn)
    case indexedIndirect(UInt8)         // ($nn,X)
    case indirectIndexed(UInt8)         // ($nn),Y
    case label(String)                  // For branches/jumps
}

func parseOperand(_ text: String) -> ParsedOperand {
    let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
    
    if trimmed.isEmpty {
        return .none
    }
    
    if trimmed == "A" {
        return .accumulator
    }
    
    if trimmed.hasPrefix("#") {
        let value = parseNumber(String(trimmed.dropFirst()))
        return .immediate(UInt8(value & 0xFF))
    }
    
    // ... continue for other modes
}

func parseNumber(_ text: String) -> Int {
    if text.hasPrefix("$") {
        return Int(text.dropFirst(), radix: 16) ?? 0
    } else if text.hasPrefix("%") {
        return Int(text.dropFirst(), radix: 2) ?? 0
    } else {
        return Int(text) ?? 0
    }
}
```

### Assembly Output

```swift
func assemble(mnemonic: String, operand: ParsedOperand) -> [UInt8]? {
    // Look up opcode based on mnemonic and addressing mode
    guard let opcode = findOpcode(mnemonic: mnemonic, mode: operand.mode) else {
        return nil
    }
    
    var bytes: [UInt8] = [opcode]
    
    switch operand {
    case .none, .accumulator:
        break
        
    case .immediate(let value), .zeroPage(let value), 
         .zeroPageX(let value), .zeroPageY(let value),
         .indexedIndirect(let value), .indirectIndexed(let value):
        bytes.append(value)
        
    case .absolute(let addr), .absoluteX(let addr), 
         .absoluteY(let addr), .indirect(let addr):
        bytes.append(UInt8(addr & 0xFF))
        bytes.append(UInt8(addr >> 8))
        
    case .label(_):
        // Resolve label to address, then calculate relative offset or absolute
        break
    }
    
    return bytes
}
```

## BRK-Based Breakpoints

### How BRK Works

1. CPU encounters BRK ($00)
2. PC + 2 pushed to stack (allows signature byte after BRK)
3. Status register pushed with B flag set
4. PC loaded from IRQ vector ($FFFE-$FFFF)

### Breakpoint Implementation

```swift
struct Breakpoint {
    let address: UInt16
    let originalByte: UInt8
    var hitCount: Int = 0
    var enabled: Bool = true
}

class BreakpointManager {
    private var breakpoints: [UInt16: Breakpoint] = [:]
    private let memory: MemoryBus
    
    func set(at address: UInt16) throws {
        guard breakpoints[address] == nil else {
            throw BreakpointError.alreadySet(address)
        }
        
        let original = memory.read(address)
        memory.write(address, value: 0x00)  // BRK opcode
        
        breakpoints[address] = Breakpoint(
            address: address,
            originalByte: original
        )
    }
    
    func clear(at address: UInt16) throws {
        guard let bp = breakpoints[address] else {
            throw BreakpointError.notFound(address)
        }
        
        memory.write(address, value: bp.originalByte)
        breakpoints.removeValue(forKey: address)
    }
    
    func isBreakpoint(at address: UInt16) -> Bool {
        return breakpoints[address] != nil
    }
    
    func getOriginalByte(at address: UInt16) -> UInt8? {
        return breakpoints[address]?.originalByte
    }
}
```

### Single-Step After Breakpoint

```swift
func stepFromBreakpoint(at address: UInt16) {
    // 1. Temporarily restore original instruction
    if let original = breakpointManager.getOriginalByte(at: address) {
        memory.write(address, value: original)
    }
    
    // 2. Execute one instruction
    emulator.step(count: 1)
    
    // 3. Re-install breakpoint if still enabled
    if breakpointManager.isBreakpoint(at: address) {
        memory.write(address, value: 0x00)
    }
}
```
