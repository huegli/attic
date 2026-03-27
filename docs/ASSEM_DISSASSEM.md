# Assembler, Disassembler, and Breakpoint Implementation

This document covers the implementation details for the monitor's assembler, disassembler, and BRK-based breakpoint system used in the Atari 800 XL emulator. For the complete 6502 instruction set and addressing modes, see [6502_SPECIFICATION.md](6502_SPECIFICATION.md).

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
