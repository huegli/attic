---
title: "MOS 6502 CPU Specification — SALLY/6502C Variant"
version: "1.0.0"
date: "2026-03-27"
target_system: "Atari 800XL"
cpu_variant: "SALLY (6502C)"
clock_speed_ntsc: "1.79 MHz (1.7897725 MHz)"
clock_speed_pal: "1.77 MHz (1.7734475 MHz)"
address_space: "64KB (16-bit address bus)"
data_width: "8-bit"
endianness: "little-endian"
license: "Public Domain — Reference Specification"
---

# MOS 6502 CPU Specification — SALLY/6502C (Atari 800XL)

This document is a comprehensive, machine-parseable specification for the MOS Technology 6502 CPU as implemented in the Atari 800XL home computer (SALLY/6502C variant). It is designed to serve as a single authoritative reference for implementing a cycle-accurate emulator, generating test cases, and verifying correctness.

---

## 1. Architecture Overview

### 1.1 History

The MOS Technology 6502 was designed in 1975 by Chuck Peddle and a team of engineers who left Motorola. It was a low-cost, high-performance 8-bit microprocessor that powered many of the most influential home computers and game consoles of the late 1970s and 1980s, including the Apple II, Commodore 64, BBC Micro, and the Nintendo Entertainment System.

The 6502 features an 8-bit data bus, a 16-bit address bus (64KB address space), and a small register set optimized for efficient memory access through multiple addressing modes — particularly zero-page addressing, which provides fast access to the first 256 bytes of memory.

### 1.2 SALLY / 6502C Variant

The Atari 800XL uses the **SALLY** processor, also referred to as the **6502C**. This is a custom variant of the NMOS 6502 manufactured by MOS Technology specifically for Atari. SALLY is **functionally identical** to the standard NMOS 6502 in all aspects of instruction execution — all instruction behavior, timing, addressing modes, and flag handling are the same.

**Pin differences from standard 6502:**

| Pin | Standard 6502 | SALLY (6502C) | Purpose |
|-----|---------------|---------------|---------|
| 5 | NC | NC | No connection |
| 7 | SYNC | NC | SYNC signal not brought out |
| 34 | R/W̄ | NC | R/W̄ moved |
| 35 | NC | R/W̄ | Read/Write signal relocated |
| 36 | NC | HALT | Directly controlled by ANTIC for DMA |

The **HALT** pin (pin 36) is the key differentiator. When the ANTIC display co-processor needs to perform Direct Memory Access (DMA) to fetch display data, it asserts the HALT line. SALLY finishes its current clock cycle, then tri-states the address, data, and R/W̄ buses, releasing them for ANTIC. When ANTIC de-asserts HALT, SALLY resumes execution exactly where it stopped. This mechanism is transparent to software but steals cycles from the CPU, affecting real-time performance.

### 1.3 Co-Processors in the Atari 800XL

| Chip | Function | Address Range |
|------|----------|---------------|
| ANTIC | Display controller (DMA, display list processing) | $D400-$D4FF |
| GTIA | Graphics/color processor (player-missile, color registers) | $D000-$D0FF |
| POKEY | Sound generator, keyboard scanner, serial I/O, timers, IRQ management | $D200-$D2FF |
| PIA (6520) | Parallel I/O adapter (joystick ports, memory bank switching) | $D300-$D3FF |

---

## 2. Registers

### 2.1 Register Summary

| Register | Symbol | Width | Description | Reset Value |
|----------|--------|-------|-------------|-------------|
| Accumulator | A | 8-bit | Primary arithmetic/logic register | Undefined |
| Index Register X | X | 8-bit | Index register, also used for stack pointer transfer | Undefined |
| Index Register Y | Y | 8-bit | Index register | Undefined |
| Stack Pointer | SP | 8-bit | Points to next free location on stack ($0100-$01FF) | $FD (after reset sequence) |
| Program Counter | PC | 16-bit | Address of next instruction to execute | Value from $FFFC-$FFFD |
| Processor Status | P | 8-bit | Condition flags: NV-BDIZC | $34 (I=1, bits 5 and 4 set) |

### 2.2 Register Details

**Accumulator (A):** The primary register for all arithmetic (ADC, SBC) and logical (AND, ORA, EOR) operations. Load/store instructions (LDA/STA) transfer data between the accumulator and memory. The accumulator is also used for shift/rotate operations in accumulator addressing mode.

**Index Register X:** Used as a counter or offset in several addressing modes (ZP,X / ABS,X / (IND,X)). Also used to transfer values to/from the stack pointer (TXS/TSX). Available for increment (INX), decrement (DEX), compare (CPX), and load/store (LDX/STX).

**Index Register Y:** Used as an offset in addressing modes (ZP,Y / ABS,Y / (IND),Y). Available for increment (INY), decrement (DEY), compare (CPY), and load/store (LDY/STY).

**Stack Pointer (SP):** Points into page 1 of memory ($0100-$01FF). The full stack address is $01XX where XX is the SP value. SP decrements on push and increments on pull. On reset, SP is set to $FD (the CPU internally decrements it three times from its undefined value during the reset sequence, but no writes to the stack actually occur). SP wraps within the $0100-$01FF range.

**Program Counter (PC):** A 16-bit register holding the address of the next byte to be fetched. It has its own dedicated incrementer — advancing PC never costs an extra cycle, even when crossing page boundaries.

---

## 3. Processor Status Register (P)

### 3.1 Layout

```
Bit:  7   6   5   4   3   2   1   0
      N   V   -   B   D   I   Z   C
```

### 3.2 Flag Descriptions

| Bit | Symbol | Name | Description |
|-----|--------|------|-------------|
| 7 | N | Negative | Set if bit 7 of the result is set (result is negative in signed arithmetic). Cleared otherwise. |
| 6 | V | Overflow | Set if signed overflow occurred — the result of an addition or subtraction produced a value outside the signed range (-128 to +127). Cleared otherwise. |
| 5 | — | (Unused) | No physical flag. Always pushed to the stack as 1. |
| 4 | B | Break | Not a physical flag — it is a transient signal. When P is pushed to the stack by BRK or PHP, bit 4 is set to 1. When P is pushed by IRQ or NMI, bit 4 is set to 0. This allows interrupt handlers to distinguish hardware interrupts from BRK. Reading P via PLP or RTI ignores bits 4 and 5. |
| 3 | D | Decimal | When set, ADC and SBC operate in Binary-Coded Decimal (BCD) mode. When clear, they operate in binary mode. No other instructions are affected. On the NMOS 6502, D is **not** automatically cleared on reset or interrupt — software must explicitly CLD. |
| 2 | I | Interrupt Disable | When set, maskable interrupts (IRQ) are inhibited. When clear, IRQ is enabled. Does **not** affect NMI or BRK. Set by SEI, hardware interrupt sequence, and reset. Cleared by CLI or PLP/RTI. |
| 1 | Z | Zero | Set if the result of the last operation is zero. Cleared otherwise. |
| 0 | C | Carry | Set if an arithmetic operation produced a carry (ADC) or no borrow (SBC). Also receives the shifted-out bit from ASL, LSR, ROL, ROR. Used as input by ADC, SBC, ROL, ROR. Set by SEC, cleared by CLC. |

### 3.3 Flag Behavior on Stack Push/Pull

| Operation | Bit 5 | Bit 4 (B) |
|-----------|-------|-----------|
| PHP | 1 | 1 |
| BRK | 1 | 1 |
| IRQ | 1 | 0 |
| NMI | 1 | 0 |
| PLP (restore) | ignored | ignored |
| RTI (restore) | ignored | ignored |

When P is pulled from the stack by PLP or RTI, bits 4 and 5 of the byte on the stack are **ignored** — the B and unused bits in the actual status register are unaffected. There is no physical bit 4 or bit 5 in the P register.

---

## 4. Addressing Modes

The 6502 has 13 addressing modes. Each is described below with its effective address computation, byte count, and special behaviors.

### 4.1 Addressing Mode Summary

| # | Name | Abbreviation | Bytes | EA Computation |
|---|------|--------------|-------|----------------|
| 1 | Implied | IMP | 1 | No operand |
| 2 | Accumulator | ACC | 1 | Operates on A register |
| 3 | Immediate | IMM | 2 | Operand is byte at PC+1 |
| 4 | Zero Page | ZP | 2 | EA = operand |
| 5 | Zero Page,X | ZPX | 2 | EA = (operand + X) & $FF |
| 6 | Zero Page,Y | ZPY | 2 | EA = (operand + Y) & $FF |
| 7 | Relative | REL | 2 | EA = PC + signed_offset (after fetch) |
| 8 | Absolute | ABS | 3 | EA = operand16 |
| 9 | Absolute,X | ABX | 3 | EA = operand16 + X |
| 10 | Absolute,Y | ABY | 3 | EA = operand16 + Y |
| 11 | Indirect | IND | 3 | EA = [operand16] (JMP only) |
| 12 | Indexed Indirect | IZX | 2 | EA = [(operand + X) & $FF] |
| 13 | Indirect Indexed | IZY | 2 | EA = [operand] + Y |

### 4.2 Detailed Addressing Mode Descriptions

#### 4.2.1 Implied (IMP)

- **Bytes:** 1 (opcode only)
- **Description:** The instruction operates on a register or has an implicit operand. No memory address is computed.
- **Examples:** CLC, INX, RTS, NOP
- **Formula:** N/A

#### 4.2.2 Accumulator (ACC)

- **Bytes:** 1 (opcode only)
- **Description:** The instruction operates directly on the accumulator. This is essentially implied mode, but distinguished for shift/rotate instructions.
- **Examples:** ASL A, LSR A, ROL A, ROR A
- **Formula:** N/A (operand is the A register)

#### 4.2.3 Immediate (IMM)

- **Bytes:** 2 (opcode + 1 data byte)
- **Description:** The operand is the byte immediately following the opcode. No memory address is computed — the data IS the operand.
- **Examples:** LDA #$44, ADC #$10
- **Formula:** `value = memory[PC + 1]`

#### 4.2.4 Zero Page (ZP)

- **Bytes:** 2 (opcode + 1 address byte)
- **Description:** The operand byte specifies an address in zero page ($0000-$00FF). Only one byte is needed because the high byte is always $00.
- **Examples:** LDA $44, INC $80
- **Formula:** `EA = $00:operand`
- **Wrap behavior:** N/A — address is always within $0000-$00FF

#### 4.2.5 Zero Page,X (ZPX)

- **Bytes:** 2 (opcode + 1 base address byte)
- **Description:** The operand byte is added to the X register. The result **wraps within zero page** — the high byte is always $00.
- **Examples:** LDA $80,X
- **Formula:** `EA = (operand + X) & $FF` → effective address is `$00:((operand + X) & $FF)`
- **Wrap behavior:** If operand + X > $FF, the address wraps to the beginning of zero page. Example: operand=$F0, X=$20 → EA=$0010, NOT $0110.

#### 4.2.6 Zero Page,Y (ZPY)

- **Bytes:** 2 (opcode + 1 base address byte)
- **Description:** Same as ZP,X but uses the Y register. Wraps within zero page.
- **Examples:** LDX $80,Y, STX $80,Y
- **Formula:** `EA = (operand + Y) & $FF` → effective address is `$00:((operand + Y) & $FF)`
- **Wrap behavior:** Same as ZP,X — wraps within zero page.
- **Note:** Only LDX and STX use this mode.

#### 4.2.7 Relative (REL)

- **Bytes:** 2 (opcode + 1 signed offset byte)
- **Description:** Used exclusively by branch instructions. The operand is a signed 8-bit offset (-128 to +127) added to the program counter AFTER the branch instruction has been fetched (PC points to the instruction after the branch).
- **Examples:** BEQ label, BNE label
- **Formula:** `target = PC + 2 + sign_extend(operand)` where PC is the address of the branch opcode
- **Page crossing:** If the branch target is on a different page than PC+2, an extra cycle is consumed.

#### 4.2.8 Absolute (ABS)

- **Bytes:** 3 (opcode + 2 address bytes, little-endian)
- **Description:** The full 16-bit address is given as the operand. Low byte first, high byte second.
- **Examples:** LDA $4400, JMP $E000
- **Formula:** `EA = (memory[PC+2] << 8) | memory[PC+1]`

#### 4.2.9 Absolute,X (ABX)

- **Bytes:** 3 (opcode + 2 address bytes, little-endian)
- **Description:** The 16-bit base address is given in the operand. X is added to compute the effective address.
- **Examples:** LDA $4400,X, STA $4400,X
- **Formula:** `EA = ((memory[PC+2] << 8) | memory[PC+1]) + X`
- **Page crossing:** For READ instructions, if adding X causes the high byte of the address to change (i.e., `(base & $FF) + X > $FF`), an extra cycle is needed to fix up the high byte. For WRITE and RMW instructions, the penalty cycle ALWAYS occurs regardless of page crossing.

#### 4.2.10 Absolute,Y (ABY)

- **Bytes:** 3 (opcode + 2 address bytes, little-endian)
- **Description:** Same as ABS,X but uses the Y register.
- **Examples:** LDA $4400,Y, STA $4400,Y
- **Formula:** `EA = ((memory[PC+2] << 8) | memory[PC+1]) + Y`
- **Page crossing:** Same rules as ABS,X — penalty for reads only if page crossed; writes always take the extra cycle.

#### 4.2.11 Indirect (IND)

- **Bytes:** 3 (opcode + 2 pointer address bytes, little-endian)
- **Description:** Used only by JMP. The operand specifies a memory address that contains the actual target address (16-bit, little-endian).
- **Examples:** JMP ($0200)
- **Formula:** `ptr = (memory[PC+2] << 8) | memory[PC+1]; EA = (memory[ptr+1] << 8) | memory[ptr]`
- **BUG (NMOS 6502):** If the pointer address has its low byte equal to $FF (e.g., $02FF), the high byte of the target is fetched from $0200, NOT $0300. The CPU only increments the low byte of the pointer and wraps within the page.
  - `JMP ($02FF)` → low byte from $02FF, high byte from $0200 (NOT $0300)

#### 4.2.12 Indexed Indirect (IZX) — (ZP,X)

- **Bytes:** 2 (opcode + 1 zero-page base byte)
- **Description:** The operand byte is added to X, wrapping within zero page, to produce a pointer address. The 16-bit effective address is then read from that zero-page pointer location (little-endian). Both pointer bytes are fetched from zero page, wrapping if necessary.
- **Examples:** LDA ($40,X)
- **Formula:**
  ```
  ptr = (operand + X) & $FF
  EA_low = memory[$00:ptr]
  EA_high = memory[$00:((ptr + 1) & $FF)]
  EA = (EA_high << 8) | EA_low
  ```
- **Wrap behavior:** Both the pointer computation AND the two-byte pointer read wrap within zero page. If ptr=$FF, the high byte is read from $0000.

#### 4.2.13 Indirect Indexed (IZY) — (ZP),Y

- **Bytes:** 2 (opcode + 1 zero-page pointer byte)
- **Description:** The operand byte specifies a zero-page address containing a 16-bit base pointer (little-endian). Y is then added to this pointer to produce the effective address.
- **Examples:** LDA ($40),Y
- **Formula:**
  ```
  ptr = operand
  base_low = memory[$00:ptr]
  base_high = memory[$00:((ptr + 1) & $FF)]
  base = (base_high << 8) | base_low
  EA = base + Y
  ```
- **Wrap behavior:** The pointer read wraps within zero page (if operand=$FF, high byte from $0000). The final EA does NOT wrap — it can address the full 64KB space.
- **Page crossing:** For READ instructions, if `(base & $FF) + Y > $FF`, an extra cycle is needed. For WRITE instructions, the extra cycle ALWAYS occurs.

---

## 5. Complete Instruction Set Reference

All 56 official instructions are documented below. The following notation is used:

- **M** — Value read from memory at the effective address
- **A, X, Y, SP, PC, P** — CPU registers
- **C, Z, I, D, B, V, N** — Individual flags in P
- **+p** — Add 1 cycle if page boundary crossed (read instructions only)
- **Flags line** lists only the flags affected by the instruction

---

### 5.1 Arithmetic Instructions

#### ADC — Add with Carry

**Operation:** `A + M + C → A`

**Pseudocode:**
```python
if D == 0:  # Binary mode
    result = A + M + C
    C = 1 if result > 0xFF else 0
    V = 1 if ((A ^ result) & (M ^ result) & 0x80) else 0
    A = result & 0xFF
    N = (A >> 7) & 1
    Z = 1 if A == 0 else 0
else:  # Decimal (BCD) mode — see Section 10
    pass
```

**Flags:** N V Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $69 | 2 | 2 |
| ZP | $65 | 2 | 3 |
| ZPX | $75 | 2 | 4 |
| ABS | $6D | 3 | 4 |
| ABX | $7D | 3 | 4+p |
| ABY | $79 | 3 | 4+p |
| IZX | $61 | 2 | 6 |
| IZY | $71 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

#### SBC — Subtract with Carry (Borrow)

**Operation:** `A - M - (1 - C) → A`

**Pseudocode:**
```python
if D == 0:  # Binary mode
    result = A - M - (1 - C)
    C = 1 if result >= 0 else 0  # No borrow
    V = 1 if ((A ^ result) & ((~M & 0xFF) ^ result) & 0x80) else 0
    # Equivalently: V = 1 if ((A ^ M) & (A ^ result) & 0x80) else 0
    A = result & 0xFF
    N = (A >> 7) & 1
    Z = 1 if A == 0 else 0
else:  # Decimal (BCD) mode — see Section 10
    pass
```

**Flags:** N V Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $E9 | 2 | 2 |
| ZP | $E5 | 2 | 3 |
| ZPX | $F5 | 2 | 4 |
| ABS | $ED | 3 | 4 |
| ABX | $FD | 3 | 4+p |
| ABY | $F9 | 3 | 4+p |
| IZX | $E1 | 2 | 6 |
| IZY | $F1 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

### 5.2 Logical Instructions

#### AND — Bitwise AND with Accumulator

**Operation:** `A & M → A`

**Pseudocode:**
```python
A = A & M
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $29 | 2 | 2 |
| ZP | $25 | 2 | 3 |
| ZPX | $35 | 2 | 4 |
| ABS | $2D | 3 | 4 |
| ABX | $3D | 3 | 4+p |
| ABY | $39 | 3 | 4+p |
| IZX | $21 | 2 | 6 |
| IZY | $31 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

#### ORA — Bitwise OR with Accumulator

**Operation:** `A | M → A`

**Pseudocode:**
```python
A = A | M
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $09 | 2 | 2 |
| ZP | $05 | 2 | 3 |
| ZPX | $15 | 2 | 4 |
| ABS | $0D | 3 | 4 |
| ABX | $1D | 3 | 4+p |
| ABY | $19 | 3 | 4+p |
| IZX | $01 | 2 | 6 |
| IZY | $11 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

#### EOR — Bitwise Exclusive OR with Accumulator

**Operation:** `A ^ M → A`

**Pseudocode:**
```python
A = A ^ M
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $49 | 2 | 2 |
| ZP | $45 | 2 | 3 |
| ZPX | $55 | 2 | 4 |
| ABS | $4D | 3 | 4 |
| ABX | $5D | 3 | 4+p |
| ABY | $59 | 3 | 4+p |
| IZX | $41 | 2 | 6 |
| IZY | $51 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

### 5.3 Shift and Rotate Instructions

#### ASL — Arithmetic Shift Left

**Operation:** `C ← [b7 ← b6 ← b5 ← b4 ← b3 ← b2 ← b1 ← b0] ← 0`

**Pseudocode:**
```python
if accumulator_mode:
    C = (A >> 7) & 1
    A = (A << 1) & 0xFF
    N = (A >> 7) & 1
    Z = 1 if A == 0 else 0
else:
    value = memory[EA]
    C = (value >> 7) & 1
    result = (value << 1) & 0xFF
    memory[EA] = result  # Write new value (preceded by dummy write of old value)
    N = (result >> 7) & 1
    Z = 1 if result == 0 else 0
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ACC | $0A | 1 | 2 |
| ZP | $06 | 2 | 5 |
| ZPX | $16 | 2 | 6 |
| ABS | $0E | 3 | 6 |
| ABX | $1E | 3 | 7 |

**Note:** Memory-targeting modes are Read-Modify-Write (RMW). The original value is written back to the address before the modified value (dummy write).

---

#### LSR — Logical Shift Right

**Operation:** `0 → [b7 → b6 → b5 → b4 → b3 → b2 → b1 → b0] → C`

**Pseudocode:**
```python
if accumulator_mode:
    C = A & 1
    A = A >> 1
    N = 0  # Always cleared (bit 7 is always 0 after shift)
    Z = 1 if A == 0 else 0
else:
    value = memory[EA]
    C = value & 1
    result = value >> 1
    memory[EA] = result
    N = 0
    Z = 1 if result == 0 else 0
```

**Flags:** N Z C (N is always cleared)

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ACC | $4A | 1 | 2 |
| ZP | $46 | 2 | 5 |
| ZPX | $56 | 2 | 6 |
| ABS | $4E | 3 | 6 |
| ABX | $5E | 3 | 7 |

---

#### ROL — Rotate Left through Carry

**Operation:** `C ← [b7 ← b6 ← b5 ← b4 ← b3 ← b2 ← b1 ← b0] ← C`

**Pseudocode:**
```python
if accumulator_mode:
    old_c = C
    C = (A >> 7) & 1
    A = ((A << 1) | old_c) & 0xFF
    N = (A >> 7) & 1
    Z = 1 if A == 0 else 0
else:
    old_c = C
    value = memory[EA]
    C = (value >> 7) & 1
    result = ((value << 1) | old_c) & 0xFF
    memory[EA] = result
    N = (result >> 7) & 1
    Z = 1 if result == 0 else 0
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ACC | $2A | 1 | 2 |
| ZP | $26 | 2 | 5 |
| ZPX | $36 | 2 | 6 |
| ABS | $2E | 3 | 6 |
| ABX | $3E | 3 | 7 |

---

#### ROR — Rotate Right through Carry

**Operation:** `C → [b7 → b6 → b5 → b4 → b3 → b2 → b1 → b0] → C`

**Pseudocode:**
```python
if accumulator_mode:
    old_c = C
    C = A & 1
    A = (A >> 1) | (old_c << 7)
    N = (A >> 7) & 1
    Z = 1 if A == 0 else 0
else:
    old_c = C
    value = memory[EA]
    C = value & 1
    result = (value >> 1) | (old_c << 7)
    memory[EA] = result
    N = (result >> 7) & 1
    Z = 1 if result == 0 else 0
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ACC | $6A | 1 | 2 |
| ZP | $66 | 2 | 5 |
| ZPX | $76 | 2 | 6 |
| ABS | $6E | 3 | 6 |
| ABX | $7E | 3 | 7 |

---

### 5.4 Increment and Decrement Instructions

#### INC — Increment Memory

**Operation:** `M + 1 → M`

**Pseudocode:**
```python
value = memory[EA]
result = (value + 1) & 0xFF
memory[EA] = result
N = (result >> 7) & 1
Z = 1 if result == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $E6 | 2 | 5 |
| ZPX | $F6 | 2 | 6 |
| ABS | $EE | 3 | 6 |
| ABX | $FE | 3 | 7 |

**Note:** RMW instruction — performs dummy write of original value before writing the incremented value.

---

#### DEC — Decrement Memory

**Operation:** `M - 1 → M`

**Pseudocode:**
```python
value = memory[EA]
result = (value - 1) & 0xFF
memory[EA] = result
N = (result >> 7) & 1
Z = 1 if result == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $C6 | 2 | 5 |
| ZPX | $D6 | 2 | 6 |
| ABS | $CE | 3 | 6 |
| ABX | $DE | 3 | 7 |

---

#### INX — Increment X Register

**Operation:** `X + 1 → X`

**Pseudocode:**
```python
X = (X + 1) & 0xFF
N = (X >> 7) & 1
Z = 1 if X == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $E8 | 1 | 2 |

---

#### DEX — Decrement X Register

**Operation:** `X - 1 → X`

**Pseudocode:**
```python
X = (X - 1) & 0xFF
N = (X >> 7) & 1
Z = 1 if X == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $CA | 1 | 2 |

---

#### INY — Increment Y Register

**Operation:** `Y + 1 → Y`

**Pseudocode:**
```python
Y = (Y + 1) & 0xFF
N = (Y >> 7) & 1
Z = 1 if Y == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $C8 | 1 | 2 |

---

#### DEY — Decrement Y Register

**Operation:** `Y - 1 → Y`

**Pseudocode:**
```python
Y = (Y - 1) & 0xFF
N = (Y >> 7) & 1
Z = 1 if Y == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $88 | 1 | 2 |

---

### 5.5 Compare Instructions

Compare instructions perform a subtraction without storing the result. The flags reflect the relationship between the register and the memory value.

- If register >= M: C = 1
- If register == M: Z = 1, C = 1
- If register < M: C = 0
- N reflects bit 7 of (register - M)

#### CMP — Compare Accumulator

**Operation:** `A - M` (result discarded)

**Pseudocode:**
```python
result = A - M
C = 1 if A >= M else 0
Z = 1 if A == M else 0
N = (result >> 7) & 1  # bit 7 of (A - M) & 0xFF
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $C9 | 2 | 2 |
| ZP | $C5 | 2 | 3 |
| ZPX | $D5 | 2 | 4 |
| ABS | $CD | 3 | 4 |
| ABX | $DD | 3 | 4+p |
| ABY | $D9 | 3 | 4+p |
| IZX | $C1 | 2 | 6 |
| IZY | $D1 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

#### CPX — Compare X Register

**Operation:** `X - M` (result discarded)

**Pseudocode:**
```python
result = X - M
C = 1 if X >= M else 0
Z = 1 if X == M else 0
N = (result >> 7) & 1
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $E0 | 2 | 2 |
| ZP | $E4 | 2 | 3 |
| ABS | $EC | 3 | 4 |

---

#### CPY — Compare Y Register

**Operation:** `Y - M` (result discarded)

**Pseudocode:**
```python
result = Y - M
C = 1 if Y >= M else 0
Z = 1 if Y == M else 0
N = (result >> 7) & 1
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $C0 | 2 | 2 |
| ZP | $C4 | 2 | 3 |
| ABS | $CC | 3 | 4 |

---

### 5.6 Load and Store Instructions

#### LDA — Load Accumulator

**Operation:** `M → A`

**Pseudocode:**
```python
A = M
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $A9 | 2 | 2 |
| ZP | $A5 | 2 | 3 |
| ZPX | $B5 | 2 | 4 |
| ABS | $AD | 3 | 4 |
| ABX | $BD | 3 | 4+p |
| ABY | $B9 | 3 | 4+p |
| IZX | $A1 | 2 | 6 |
| IZY | $B1 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

#### LDX — Load X Register

**Operation:** `M → X`

**Pseudocode:**
```python
X = M
N = (X >> 7) & 1
Z = 1 if X == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $A2 | 2 | 2 |
| ZP | $A6 | 2 | 3 |
| ZPY | $B6 | 2 | 4 |
| ABS | $AE | 3 | 4 |
| ABY | $BE | 3 | 4+p |

*p = +1 if page boundary crossed*

---

#### LDY — Load Y Register

**Operation:** `M → Y`

**Pseudocode:**
```python
Y = M
N = (Y >> 7) & 1
Z = 1 if Y == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMM | $A0 | 2 | 2 |
| ZP | $A4 | 2 | 3 |
| ZPX | $B4 | 2 | 4 |
| ABS | $AC | 3 | 4 |
| ABX | $BC | 3 | 4+p |

*p = +1 if page boundary crossed*

---

#### STA — Store Accumulator

**Operation:** `A → M`

**Pseudocode:**
```python
memory[EA] = A
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $85 | 2 | 3 |
| ZPX | $95 | 2 | 4 |
| ABS | $8D | 3 | 4 |
| ABX | $9D | 3 | 5 |
| ABY | $99 | 3 | 5 |
| IZX | $81 | 2 | 6 |
| IZY | $91 | 2 | 6 |

**Note:** Indexed modes (ABX, ABY, IZY) always take the same number of cycles regardless of page crossing. The dummy read of the potentially-incorrect address always occurs.

---

#### STX — Store X Register

**Operation:** `X → M`

**Pseudocode:**
```python
memory[EA] = X
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $86 | 2 | 3 |
| ZPY | $96 | 2 | 4 |
| ABS | $8E | 3 | 4 |

---

#### STY — Store Y Register

**Operation:** `Y → M`

**Pseudocode:**
```python
memory[EA] = Y
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $84 | 2 | 3 |
| ZPX | $94 | 2 | 4 |
| ABS | $8C | 3 | 4 |

---

### 5.7 Transfer Instructions

#### TAX — Transfer Accumulator to X

**Operation:** `A → X`

**Pseudocode:**
```python
X = A
N = (X >> 7) & 1
Z = 1 if X == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $AA | 1 | 2 |

---

#### TXA — Transfer X to Accumulator

**Operation:** `X → A`

**Pseudocode:**
```python
A = X
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $8A | 1 | 2 |

---

#### TAY — Transfer Accumulator to Y

**Operation:** `A → Y`

**Pseudocode:**
```python
Y = A
N = (Y >> 7) & 1
Z = 1 if Y == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $A8 | 1 | 2 |

---

#### TYA — Transfer Y to Accumulator

**Operation:** `Y → A`

**Pseudocode:**
```python
A = Y
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $98 | 1 | 2 |

---

#### TSX — Transfer Stack Pointer to X

**Operation:** `SP → X`

**Pseudocode:**
```python
X = SP
N = (X >> 7) & 1
Z = 1 if X == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $BA | 1 | 2 |

---

#### TXS — Transfer X to Stack Pointer

**Operation:** `X → SP`

**Pseudocode:**
```python
SP = X
```

**Flags:** None (no flags affected)

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $9A | 1 | 2 |

**Note:** TXS is the only transfer instruction that does NOT set N and Z flags.

---

### 5.8 Stack Instructions

#### PHA — Push Accumulator

**Operation:** `A → Stack`

**Pseudocode:**
```python
memory[0x0100 + SP] = A
SP = (SP - 1) & 0xFF
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $48 | 1 | 3 |

---

#### PLA — Pull Accumulator

**Operation:** `Stack → A`

**Pseudocode:**
```python
SP = (SP + 1) & 0xFF
A = memory[0x0100 + SP]
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $68 | 1 | 4 |

---

#### PHP — Push Processor Status

**Operation:** `P → Stack` (with B=1, bit 5=1)

**Pseudocode:**
```python
value = P | 0x30  # Set bits 4 (B) and 5 (unused) to 1
memory[0x0100 + SP] = value
SP = (SP - 1) & 0xFF
```

**Flags:** None (P register itself is not modified)

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $08 | 1 | 3 |

---

#### PLP — Pull Processor Status

**Operation:** `Stack → P`

**Pseudocode:**
```python
SP = (SP + 1) & 0xFF
value = memory[0x0100 + SP]
# Bits 4 and 5 of value are ignored (B and unused are not real flags)
P = (value & 0xCF) | (P & 0x30)
# Alternatively: P is set from value but bits 4,5 are discarded
# In practice: N, V, D, I, Z, C are restored from stack
```

**Flags:** All flags restored from stack (N, V, D, I, Z, C)

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $28 | 1 | 4 |

**Note:** Since I flag may change, this can enable or disable IRQ handling. Unlike CLI, PLP takes effect immediately — there is no one-instruction delay.

---

### 5.9 Branch Instructions

All branch instructions use Relative addressing mode (2 bytes). Cycle counts:
- **2 cycles** — branch not taken
- **3 cycles** — branch taken, target on same page
- **4 cycles** — branch taken, target on different page (page boundary crossed)

Page crossing is determined by comparing `(PC + 2)` (address of the next instruction) with the branch target address. If their high bytes differ, a page boundary was crossed.

#### BPL — Branch if Plus (N = 0)

**Operation:** Branch if N flag is clear.

**Pseudocode:**
```python
if N == 0:
    PC = PC + sign_extend(offset)  # offset is signed 8-bit
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $10 | 2 | 2/3/4 |

---

#### BMI — Branch if Minus (N = 1)

**Operation:** Branch if N flag is set.

**Pseudocode:**
```python
if N == 1:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $30 | 2 | 2/3/4 |

---

#### BVC — Branch if Overflow Clear (V = 0)

**Operation:** Branch if V flag is clear.

**Pseudocode:**
```python
if V == 0:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $50 | 2 | 2/3/4 |

---

#### BVS — Branch if Overflow Set (V = 1)

**Operation:** Branch if V flag is set.

**Pseudocode:**
```python
if V == 1:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $70 | 2 | 2/3/4 |

---

#### BCC — Branch if Carry Clear (C = 0)

**Operation:** Branch if C flag is clear.

**Pseudocode:**
```python
if C == 0:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $90 | 2 | 2/3/4 |

---

#### BCS — Branch if Carry Set (C = 1)

**Operation:** Branch if C flag is set.

**Pseudocode:**
```python
if C == 1:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $B0 | 2 | 2/3/4 |

---

#### BNE — Branch if Not Equal (Z = 0)

**Operation:** Branch if Z flag is clear.

**Pseudocode:**
```python
if Z == 0:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $D0 | 2 | 2/3/4 |

---

#### BEQ — Branch if Equal (Z = 1)

**Operation:** Branch if Z flag is set.

**Pseudocode:**
```python
if Z == 1:
    PC = PC + sign_extend(offset)
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| REL | $F0 | 2 | 2/3/4 |

---

### 5.10 Jump and Call Instructions

#### JMP — Jump

**Operation:** Load PC with the target address.

**Pseudocode:**
```python
# Absolute mode:
PC = operand16

# Indirect mode:
ptr = operand16
low = memory[ptr]
# BUG: high byte fetched from (ptr & 0xFF00) | ((ptr + 1) & 0x00FF)
high = memory[(ptr & 0xFF00) | ((ptr + 1) & 0x00FF)]
PC = (high << 8) | low
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ABS | $4C | 3 | 3 |
| IND | $6C | 3 | 5 |

**Warning (Indirect mode bug):** If the pointer operand has its low byte equal to $FF, the CPU fetches the low byte of the target from $xxFF and the high byte from $xx00 (same page), NOT from $xx00+$100 (next page). Example: `JMP ($10FF)` reads the low byte from $10FF and the high byte from $1000.

---

#### JSR — Jump to Subroutine

**Operation:** Push return address (PC - 1) to stack, then jump.

**Pseudocode:**
```python
# PC is currently pointing to the third byte of JSR instruction
# Push (PC - 1) — the address of the last byte of the JSR instruction
return_addr = PC + 2  # Address of byte AFTER JSR instruction
push_addr = return_addr - 1  # Address of last byte of JSR instruction
memory[0x0100 + SP] = (push_addr >> 8) & 0xFF  # Push PCH
SP = (SP - 1) & 0xFF
memory[0x0100 + SP] = push_addr & 0xFF  # Push PCL
SP = (SP - 1) & 0xFF
PC = operand16  # Jump to target
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ABS | $20 | 3 | 6 |

**Note:** JSR pushes the address of the LAST BYTE of the JSR instruction (PC+2), not the address of the next instruction (PC+3). RTS compensates by adding 1 to the pulled address.

---

#### RTS — Return from Subroutine

**Operation:** Pull return address from stack, increment, and jump.

**Pseudocode:**
```python
SP = (SP + 1) & 0xFF
low = memory[0x0100 + SP]
SP = (SP + 1) & 0xFF
high = memory[0x0100 + SP]
PC = ((high << 8) | low) + 1  # +1 because JSR pushed PC-1
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $60 | 1 | 6 |

---

#### RTI — Return from Interrupt

**Operation:** Pull P from stack, then pull PC from stack.

**Pseudocode:**
```python
SP = (SP + 1) & 0xFF
P = memory[0x0100 + SP]  # Bits 4,5 ignored
SP = (SP + 1) & 0xFF
low = memory[0x0100 + SP]
SP = (SP + 1) & 0xFF
high = memory[0x0100 + SP]
PC = (high << 8) | low  # NO +1 — returns to exact address
```

**Flags:** All flags restored from stack (N, V, D, I, Z, C)

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $40 | 1 | 6 |

**Note:** Unlike RTS, RTI returns to the exact address on the stack (no +1 adjustment). The interrupt sequence pushes the exact return address. Also, restoring I flag via RTI takes effect immediately.

---

### 5.11 Flag Instructions

#### CLC — Clear Carry Flag

**Operation:** `0 → C`

**Pseudocode:**
```python
C = 0
```

**Flags:** C = 0

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $18 | 1 | 2 |

---

#### SEC — Set Carry Flag

**Operation:** `1 → C`

**Pseudocode:**
```python
C = 1
```

**Flags:** C = 1

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $38 | 1 | 2 |

---

#### CLI — Clear Interrupt Disable

**Operation:** `0 → I`

**Pseudocode:**
```python
I = 0
```

**Flags:** I = 0

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $58 | 1 | 2 |

**Note:** The effect of CLI is delayed by one instruction. The instruction following CLI can still execute before a pending IRQ is serviced. This is because the interrupt line is sampled on the last cycle of an instruction, but the I flag change doesn't take effect until that sampling point.

---

#### SEI — Set Interrupt Disable

**Operation:** `1 → I`

**Pseudocode:**
```python
I = 1
```

**Flags:** I = 1

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $78 | 1 | 2 |

**Note:** Like CLI, SEI's effect is delayed by one instruction. A pending IRQ can still be recognized during the instruction immediately following SEI.

---

#### CLV — Clear Overflow Flag

**Operation:** `0 → V`

**Pseudocode:**
```python
V = 0
```

**Flags:** V = 0

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $B8 | 1 | 2 |

**Note:** There is no "Set Overflow" instruction. V can be set by hardware via the SO pin, or by ADC/SBC/BIT instructions.

---

#### CLD — Clear Decimal Mode

**Operation:** `0 → D`

**Pseudocode:**
```python
D = 0
```

**Flags:** D = 0

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $D8 | 1 | 2 |

---

#### SED — Set Decimal Mode

**Operation:** `1 → D`

**Pseudocode:**
```python
D = 1
```

**Flags:** D = 1

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $F8 | 1 | 2 |

---

### 5.12 Miscellaneous Instructions

#### BIT — Test Bits in Memory

**Operation:** `A & M` (result is NOT stored)

**Pseudocode:**
```python
value = memory[EA]
Z = 1 if (A & value) == 0 else 0
N = (value >> 7) & 1  # Bit 7 of MEMORY value, not result
V = (value >> 6) & 1  # Bit 6 of MEMORY value, not result
```

**Flags:** N V Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $24 | 2 | 3 |
| ABS | $2C | 3 | 4 |

**Note:** BIT is unusual — N and V are set from the memory value directly (bits 7 and 6), NOT from the AND result. Z is set from the AND result. This makes BIT useful for testing hardware register bits without modifying A.

---

#### BRK — Force Break (Software Interrupt)

**Operation:** Push PC+2, push P (with B=1), load IRQ vector, set I.

**Pseudocode:**
```python
PC = PC + 1  # Skip the padding byte
# Push PC (which is now PC+2 relative to the BRK opcode)
memory[0x0100 + SP] = (PC >> 8) & 0xFF  # Push PCH
SP = (SP - 1) & 0xFF
memory[0x0100 + SP] = PC & 0xFF  # Push PCL
SP = (SP - 1) & 0xFF
# Push P with B=1 and bit 5=1
memory[0x0100 + SP] = P | 0x30
SP = (SP - 1) & 0xFF
# Set interrupt disable
I = 1
# Load IRQ vector
PC = memory[0xFFFE] | (memory[0xFFFF] << 8)
```

**Flags:** I = 1 (B is set in the pushed value only, not in P register)

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $00 | 1* | 7 |

*BRK is encoded as a single byte ($00), but it has a padding byte after it. The PC pushed to the stack is PC+2 (the address after both the BRK opcode and its padding byte). The padding byte is skipped when returning via RTI.

**Note:** BRK uses the IRQ vector at $FFFE-$FFFF. Interrupt handlers can distinguish BRK from a hardware IRQ by examining bit 4 (B) of the pushed P value on the stack.

---

#### NOP — No Operation

**Operation:** No operation. Advances PC and consumes cycles.

**Pseudocode:**
```python
# Nothing
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| IMP | $EA | 1 | 2 |

---

## 6. Complete Opcode Matrix (16×16)

All 256 opcodes are shown. Official opcodes display the mnemonic. Unofficial/illegal opcodes are shown with their common names. `JAM` indicates opcodes that halt the processor.

Each cell shows the mnemonic and addressing mode abbreviation.

```
|     | x0       | x1       | x2       | x3       | x4       | x5       | x6       | x7       | x8       | x9       | xA       | xB       | xC       | xD       | xE       | xF       |
|-----|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|
| 0x  | BRK imp  | ORA izx  | JAM      | SLO izx  | NOP zp   | ORA zp   | ASL zp   | SLO zp   | PHP imp  | ORA imm  | ASL acc  | ANC imm  | NOP abs  | ORA abs  | ASL abs  | SLO abs  |
| 1x  | BPL rel  | ORA izy  | JAM      | SLO izy  | NOP zpx  | ORA zpx  | ASL zpx  | SLO zpx  | CLC imp  | ORA aby  | NOP imp  | SLO aby  | NOP abx  | ORA abx  | ASL abx  | SLO abx  |
| 2x  | JSR abs  | AND izx  | JAM      | RLA izx  | BIT zp   | AND zp   | ROL zp   | RLA zp   | PLP imp  | AND imm  | ROL acc  | ANC imm  | BIT abs  | AND abs  | ROL abs  | RLA abs  |
| 3x  | BMI rel  | AND izy  | JAM      | RLA izy  | NOP zpx  | AND zpx  | ROL zpx  | RLA zpx  | SEC imp  | AND aby  | NOP imp  | RLA aby  | NOP abx  | AND abx  | ROL abx  | RLA abx  |
| 4x  | RTI imp  | EOR izx  | JAM      | SRE izx  | NOP zp   | EOR zp   | LSR zp   | SRE zp   | PHA imp  | EOR imm  | LSR acc  | ALR imm  | JMP abs  | EOR abs  | LSR abs  | SRE abs  |
| 5x  | BVC rel  | EOR izy  | JAM      | SRE izy  | NOP zpx  | EOR zpx  | LSR zpx  | SRE zpx  | CLI imp  | EOR aby  | NOP imp  | SRE aby  | NOP abx  | EOR abx  | LSR abx  | SRE abx  |
| 6x  | RTS imp  | ADC izx  | JAM      | RRA izx  | NOP zp   | ADC zp   | ROR zp   | RRA zp   | PLA imp  | ADC imm  | ROR acc  | ARR imm  | JMP ind  | ADC abs  | ROR abs  | RRA abs  |
| 7x  | BVS rel  | ADC izy  | JAM      | RRA izy  | NOP zpx  | ADC zpx  | ROR zpx  | RRA zpx  | SEI imp  | ADC aby  | NOP imp  | RRA aby  | NOP abx  | ADC abx  | ROR abx  | RRA abx  |
| 8x  | NOP imm  | STA izx  | NOP imm  | SAX izx  | STY zp   | STA zp   | STX zp   | SAX zp   | DEY imp  | NOP imm  | TXA imp  | ANE imm  | STY abs  | STA abs  | STX abs  | SAX abs  |
| 9x  | BCC rel  | STA izy  | JAM      | SHA izy  | STY zpx  | STA zpx  | STX zpy  | SAX zpy  | TYA imp  | STA aby  | TXS imp  | TAS aby  | SHY abx  | STA abx  | SHX aby  | SHA aby  |
| Ax  | LDY imm  | LDA izx  | LDX imm  | LAX izx  | LDY zp   | LDA zp   | LDX zp   | LAX zp   | TAY imp  | LDA imm  | TAX imp  | LXA imm  | LDY abs  | LDA abs  | LDX abs  | LAX abs  |
| Bx  | BCS rel  | LDA izy  | JAM      | LAX izy  | LDY zpx  | LDA zpx  | LDX zpy  | LAX zpy  | CLV imp  | LDA aby  | TSX imp  | LAS aby  | LDY abx  | LDA abx  | LDX aby  | LAX aby  |
| Cx  | CPY imm  | CMP izx  | NOP imm  | DCP izx  | CPY zp   | CMP zp   | DEC zp   | DCP zp   | INY imp  | CMP imm  | DEX imp  | SBX imm  | CPY abs  | CMP abs  | DEC abs  | DCP abs  |
| Dx  | BNE rel  | CMP izy  | JAM      | DCP izy  | NOP zpx  | CMP zpx  | DEC zpx  | DCP zpx  | CLD imp  | CMP aby  | NOP imp  | DCP aby  | NOP abx  | CMP abx  | DEC abx  | DCP abx  |
| Ex  | CPX imm  | SBC izx  | NOP imm  | ISC izx  | CPX zp   | SBC zp   | INC zp   | ISC zp   | INX imp  | SBC imm  | NOP imp  | USBC imm | CPX abs  | SBC abs  | INC abs  | ISC abs  |
| Fx  | BEQ rel  | SBC izy  | JAM      | ISC izy  | NOP zpx  | SBC zpx  | INC zpx  | ISC zpx  | SED imp  | SBC aby  | NOP imp  | ISC aby  | NOP abx  | SBC abx  | INC abx  | ISC abx  |
```

### 6.1 Opcode-to-Instruction Lookup Table

For machine parsing, here is a flat lookup of all 256 opcodes:

| Opcode | Mnemonic | Mode | Bytes | Cycles | Official |
|--------|----------|------|-------|--------|----------|
| $00 | BRK | IMP | 1 | 7 | Yes |
| $01 | ORA | IZX | 2 | 6 | Yes |
| $02 | JAM | IMP | 1 | — | No |
| $03 | SLO | IZX | 2 | 8 | No |
| $04 | NOP | ZP | 2 | 3 | No |
| $05 | ORA | ZP | 2 | 3 | Yes |
| $06 | ASL | ZP | 2 | 5 | Yes |
| $07 | SLO | ZP | 2 | 5 | No |
| $08 | PHP | IMP | 1 | 3 | Yes |
| $09 | ORA | IMM | 2 | 2 | Yes |
| $0A | ASL | ACC | 1 | 2 | Yes |
| $0B | ANC | IMM | 2 | 2 | No |
| $0C | NOP | ABS | 3 | 4 | No |
| $0D | ORA | ABS | 3 | 4 | Yes |
| $0E | ASL | ABS | 3 | 6 | Yes |
| $0F | SLO | ABS | 3 | 6 | No |
| $10 | BPL | REL | 2 | 2+ | Yes |
| $11 | ORA | IZY | 2 | 5+p | Yes |
| $12 | JAM | IMP | 1 | — | No |
| $13 | SLO | IZY | 2 | 8 | No |
| $14 | NOP | ZPX | 2 | 4 | No |
| $15 | ORA | ZPX | 2 | 4 | Yes |
| $16 | ASL | ZPX | 2 | 6 | Yes |
| $17 | SLO | ZPX | 2 | 6 | No |
| $18 | CLC | IMP | 1 | 2 | Yes |
| $19 | ORA | ABY | 3 | 4+p | Yes |
| $1A | NOP | IMP | 1 | 2 | No |
| $1B | SLO | ABY | 3 | 7 | No |
| $1C | NOP | ABX | 3 | 4+p | No |
| $1D | ORA | ABX | 3 | 4+p | Yes |
| $1E | ASL | ABX | 3 | 7 | Yes |
| $1F | SLO | ABX | 3 | 7 | No |
| $20 | JSR | ABS | 3 | 6 | Yes |
| $21 | AND | IZX | 2 | 6 | Yes |
| $22 | JAM | IMP | 1 | — | No |
| $23 | RLA | IZX | 2 | 8 | No |
| $24 | BIT | ZP | 2 | 3 | Yes |
| $25 | AND | ZP | 2 | 3 | Yes |
| $26 | ROL | ZP | 2 | 5 | Yes |
| $27 | RLA | ZP | 2 | 5 | No |
| $28 | PLP | IMP | 1 | 4 | Yes |
| $29 | AND | IMM | 2 | 2 | Yes |
| $2A | ROL | ACC | 1 | 2 | Yes |
| $2B | ANC | IMM | 2 | 2 | No |
| $2C | BIT | ABS | 3 | 4 | Yes |
| $2D | AND | ABS | 3 | 4 | Yes |
| $2E | ROL | ABS | 3 | 6 | Yes |
| $2F | RLA | ABS | 3 | 6 | No |
| $30 | BMI | REL | 2 | 2+ | Yes |
| $31 | AND | IZY | 2 | 5+p | Yes |
| $32 | JAM | IMP | 1 | — | No |
| $33 | RLA | IZY | 2 | 8 | No |
| $34 | NOP | ZPX | 2 | 4 | No |
| $35 | AND | ZPX | 2 | 4 | Yes |
| $36 | ROL | ZPX | 2 | 6 | Yes |
| $37 | RLA | ZPX | 2 | 6 | No |
| $38 | SEC | IMP | 1 | 2 | Yes |
| $39 | AND | ABY | 3 | 4+p | Yes |
| $3A | NOP | IMP | 1 | 2 | No |
| $3B | RLA | ABY | 3 | 7 | No |
| $3C | NOP | ABX | 3 | 4+p | No |
| $3D | AND | ABX | 3 | 4+p | Yes |
| $3E | ROL | ABX | 3 | 7 | Yes |
| $3F | RLA | ABX | 3 | 7 | No |
| $40 | RTI | IMP | 1 | 6 | Yes |
| $41 | EOR | IZX | 2 | 6 | Yes |
| $42 | JAM | IMP | 1 | — | No |
| $43 | SRE | IZX | 2 | 8 | No |
| $44 | NOP | ZP | 2 | 3 | No |
| $45 | EOR | ZP | 2 | 3 | Yes |
| $46 | LSR | ZP | 2 | 5 | Yes |
| $47 | SRE | ZP | 2 | 5 | No |
| $48 | PHA | IMP | 1 | 3 | Yes |
| $49 | EOR | IMM | 2 | 2 | Yes |
| $4A | LSR | ACC | 1 | 2 | Yes |
| $4B | ALR | IMM | 2 | 2 | No |
| $4C | JMP | ABS | 3 | 3 | Yes |
| $4D | EOR | ABS | 3 | 4 | Yes |
| $4E | LSR | ABS | 3 | 6 | Yes |
| $4F | SRE | ABS | 3 | 6 | No |
| $50 | BVC | REL | 2 | 2+ | Yes |
| $51 | EOR | IZY | 2 | 5+p | Yes |
| $52 | JAM | IMP | 1 | — | No |
| $53 | SRE | IZY | 2 | 8 | No |
| $54 | NOP | ZPX | 2 | 4 | No |
| $55 | EOR | ZPX | 2 | 4 | Yes |
| $56 | LSR | ZPX | 2 | 6 | Yes |
| $57 | SRE | ZPX | 2 | 6 | No |
| $58 | CLI | IMP | 1 | 2 | Yes |
| $59 | EOR | ABY | 3 | 4+p | Yes |
| $5A | NOP | IMP | 1 | 2 | No |
| $5B | SRE | ABY | 3 | 7 | No |
| $5C | NOP | ABX | 3 | 4+p | No |
| $5D | EOR | ABX | 3 | 4+p | Yes |
| $5E | LSR | ABX | 3 | 7 | Yes |
| $5F | SRE | ABX | 3 | 7 | No |
| $60 | RTS | IMP | 1 | 6 | Yes |
| $61 | ADC | IZX | 2 | 6 | Yes |
| $62 | JAM | IMP | 1 | — | No |
| $63 | RRA | IZX | 2 | 8 | No |
| $64 | NOP | ZP | 2 | 3 | No |
| $65 | ADC | ZP | 2 | 3 | Yes |
| $66 | ROR | ZP | 2 | 5 | Yes |
| $67 | RRA | ZP | 2 | 5 | No |
| $68 | PLA | IMP | 1 | 4 | Yes |
| $69 | ADC | IMM | 2 | 2 | Yes |
| $6A | ROR | ACC | 1 | 2 | Yes |
| $6B | ARR | IMM | 2 | 2 | No |
| $6C | JMP | IND | 3 | 5 | Yes |
| $6D | ADC | ABS | 3 | 4 | Yes |
| $6E | ROR | ABS | 3 | 6 | Yes |
| $6F | RRA | ABS | 3 | 6 | No |
| $70 | BVS | REL | 2 | 2+ | Yes |
| $71 | ADC | IZY | 2 | 5+p | Yes |
| $72 | JAM | IMP | 1 | — | No |
| $73 | RRA | IZY | 2 | 8 | No |
| $74 | NOP | ZPX | 2 | 4 | No |
| $75 | ADC | ZPX | 2 | 4 | Yes |
| $76 | ROR | ZPX | 2 | 6 | Yes |
| $77 | RRA | ZPX | 2 | 6 | No |
| $78 | SEI | IMP | 1 | 2 | Yes |
| $79 | ADC | ABY | 3 | 4+p | Yes |
| $7A | NOP | IMP | 1 | 2 | No |
| $7B | RRA | ABY | 3 | 7 | No |
| $7C | NOP | ABX | 3 | 4+p | No |
| $7D | ADC | ABX | 3 | 4+p | Yes |
| $7E | ROR | ABX | 3 | 7 | Yes |
| $7F | RRA | ABX | 3 | 7 | No |
| $80 | NOP | IMM | 2 | 2 | No |
| $81 | STA | IZX | 2 | 6 | Yes |
| $82 | NOP | IMM | 2 | 2 | No |
| $83 | SAX | IZX | 2 | 6 | No |
| $84 | STY | ZP | 2 | 3 | Yes |
| $85 | STA | ZP | 2 | 3 | Yes |
| $86 | STX | ZP | 2 | 3 | Yes |
| $87 | SAX | ZP | 2 | 3 | No |
| $88 | DEY | IMP | 1 | 2 | Yes |
| $89 | NOP | IMM | 2 | 2 | No |
| $8A | TXA | IMP | 1 | 2 | Yes |
| $8B | ANE | IMM | 2 | 2 | No |
| $8C | STY | ABS | 3 | 4 | Yes |
| $8D | STA | ABS | 3 | 4 | Yes |
| $8E | STX | ABS | 3 | 4 | Yes |
| $8F | SAX | ABS | 3 | 4 | No |
| $90 | BCC | REL | 2 | 2+ | Yes |
| $91 | STA | IZY | 2 | 6 | Yes |
| $92 | JAM | IMP | 1 | — | No |
| $93 | SHA | IZY | 2 | 6 | No |
| $94 | STY | ZPX | 2 | 4 | Yes |
| $95 | STA | ZPX | 2 | 4 | Yes |
| $96 | STX | ZPY | 2 | 4 | Yes |
| $97 | SAX | ZPY | 2 | 4 | No |
| $98 | TYA | IMP | 1 | 2 | Yes |
| $99 | STA | ABY | 3 | 5 | Yes |
| $9A | TXS | IMP | 1 | 2 | Yes |
| $9B | TAS | ABY | 3 | 5 | No |
| $9C | SHY | ABX | 3 | 5 | No |
| $9D | STA | ABX | 3 | 5 | Yes |
| $9E | SHX | ABY | 3 | 5 | No |
| $9F | SHA | ABY | 3 | 5 | No |
| $A0 | LDY | IMM | 2 | 2 | Yes |
| $A1 | LDA | IZX | 2 | 6 | Yes |
| $A2 | LDX | IMM | 2 | 2 | Yes |
| $A3 | LAX | IZX | 2 | 6 | No |
| $A4 | LDY | ZP | 2 | 3 | Yes |
| $A5 | LDA | ZP | 2 | 3 | Yes |
| $A6 | LDX | ZP | 2 | 3 | Yes |
| $A7 | LAX | ZP | 2 | 3 | No |
| $A8 | TAY | IMP | 1 | 2 | Yes |
| $A9 | LDA | IMM | 2 | 2 | Yes |
| $AA | TAX | IMP | 1 | 2 | Yes |
| $AB | LXA | IMM | 2 | 2 | No |
| $AC | LDY | ABS | 3 | 4 | Yes |
| $AD | LDA | ABS | 3 | 4 | Yes |
| $AE | LDX | ABS | 3 | 4 | Yes |
| $AF | LAX | ABS | 3 | 4 | No |
| $B0 | BCS | REL | 2 | 2+ | Yes |
| $B1 | LDA | IZY | 2 | 5+p | Yes |
| $B2 | JAM | IMP | 1 | — | No |
| $B3 | LAX | IZY | 2 | 5+p | No |
| $B4 | LDY | ZPX | 2 | 4 | Yes |
| $B5 | LDA | ZPX | 2 | 4 | Yes |
| $B6 | LDX | ZPY | 2 | 4 | Yes |
| $B7 | LAX | ZPY | 2 | 4 | No |
| $B8 | CLV | IMP | 1 | 2 | Yes |
| $B9 | LDA | ABY | 3 | 4+p | Yes |
| $BA | TSX | IMP | 1 | 2 | Yes |
| $BB | LAS | ABY | 3 | 4+p | No |
| $BC | LDY | ABX | 3 | 4+p | Yes |
| $BD | LDA | ABX | 3 | 4+p | Yes |
| $BE | LDX | ABY | 3 | 4+p | Yes |
| $BF | LAX | ABY | 3 | 4+p | No |
| $C0 | CPY | IMM | 2 | 2 | Yes |
| $C1 | CMP | IZX | 2 | 6 | Yes |
| $C2 | NOP | IMM | 2 | 2 | No |
| $C3 | DCP | IZX | 2 | 8 | No |
| $C4 | CPY | ZP | 2 | 3 | Yes |
| $C5 | CMP | ZP | 2 | 3 | Yes |
| $C6 | DEC | ZP | 2 | 5 | Yes |
| $C7 | DCP | ZP | 2 | 5 | No |
| $C8 | INY | IMP | 1 | 2 | Yes |
| $C9 | CMP | IMM | 2 | 2 | Yes |
| $CA | DEX | IMP | 1 | 2 | Yes |
| $CB | SBX | IMM | 2 | 2 | No |
| $CC | CPY | ABS | 3 | 4 | Yes |
| $CD | CMP | ABS | 3 | 4 | Yes |
| $CE | DEC | ABS | 3 | 6 | Yes |
| $CF | DCP | ABS | 3 | 6 | No |
| $D0 | BNE | REL | 2 | 2+ | Yes |
| $D1 | CMP | IZY | 2 | 5+p | Yes |
| $D2 | JAM | IMP | 1 | — | No |
| $D3 | DCP | IZY | 2 | 8 | No |
| $D4 | NOP | ZPX | 2 | 4 | No |
| $D5 | CMP | ZPX | 2 | 4 | Yes |
| $D6 | DEC | ZPX | 2 | 6 | Yes |
| $D7 | DCP | ZPX | 2 | 6 | No |
| $D8 | CLD | IMP | 1 | 2 | Yes |
| $D9 | CMP | ABY | 3 | 4+p | Yes |
| $DA | NOP | IMP | 1 | 2 | No |
| $DB | DCP | ABY | 3 | 7 | No |
| $DC | NOP | ABX | 3 | 4+p | No |
| $DD | CMP | ABX | 3 | 4+p | Yes |
| $DE | DEC | ABX | 3 | 7 | Yes |
| $DF | DCP | ABX | 3 | 7 | No |
| $E0 | CPX | IMM | 2 | 2 | Yes |
| $E1 | SBC | IZX | 2 | 6 | Yes |
| $E2 | NOP | IMM | 2 | 2 | No |
| $E3 | ISC | IZX | 2 | 8 | No |
| $E4 | CPX | ZP | 2 | 3 | Yes |
| $E5 | SBC | ZP | 2 | 3 | Yes |
| $E6 | INC | ZP | 2 | 5 | Yes |
| $E7 | ISC | ZP | 2 | 5 | No |
| $E8 | INX | IMP | 1 | 2 | Yes |
| $E9 | SBC | IMM | 2 | 2 | Yes |
| $EA | NOP | IMP | 1 | 2 | Yes |
| $EB | USBC | IMM | 2 | 2 | No |
| $EC | CPX | ABS | 3 | 4 | Yes |
| $ED | SBC | ABS | 3 | 4 | Yes |
| $EE | INC | ABS | 3 | 6 | Yes |
| $EF | ISC | ABS | 3 | 6 | No |
| $F0 | BEQ | REL | 2 | 2+ | Yes |
| $F1 | SBC | IZY | 2 | 5+p | Yes |
| $F2 | JAM | IMP | 1 | — | No |
| $F3 | ISC | IZY | 2 | 8 | No |
| $F4 | NOP | ZPX | 2 | 4 | No |
| $F5 | SBC | ZPX | 2 | 4 | Yes |
| $F6 | INC | ZPX | 2 | 6 | Yes |
| $F7 | ISC | ZPX | 2 | 6 | No |
| $F8 | SED | IMP | 1 | 2 | Yes |
| $F9 | SBC | ABY | 3 | 4+p | Yes |
| $FA | NOP | IMP | 1 | 2 | No |
| $FB | ISC | ABY | 3 | 7 | No |
| $FC | NOP | ABX | 3 | 4+p | No |
| $FD | SBC | ABX | 3 | 4+p | Yes |
| $FE | INC | ABX | 3 | 7 | Yes |
| $FF | ISC | ABX | 3 | 7 | No |

---

## 7. Cycle-by-Cycle Bus Activity

This section documents what happens on the address bus, data bus, and R/W̄ line during every clock cycle of every instruction type. This is essential for cycle-accurate emulation.

**Key conventions:**
- `PC++` means PC is incremented during this cycle
- `ADL` = Address Low byte, `ADH` = Address High byte
- `BAL` = Base Address Low, `BAH` = Base Address High
- `IAL` = Indirect Address Low
- `PCL` = Program Counter Low, `PCH` = Program Counter High
- `R` = Read, `W` = Write

### 7.1 Implied / Accumulator (2 cycles)

Used by: NOP, CLC, SEC, CLI, SEI, CLV, CLD, SED, TAX, TXA, TAY, TYA, TSX, TXS, INX, DEX, INY, DEY, ASL A, LSR A, ROL A, ROR A

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch next byte (and discard — dummy read), do NOT increment PC |

### 7.2 Immediate (2 cycles)

Used by: LDA #, LDX #, LDY #, ADC #, SBC #, AND #, ORA #, EOR #, CMP #, CPX #, CPY #, BIT # (65C02 only)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch operand byte, PC++ |

### 7.3 Zero Page Read (3 cycles)

Used by: LDA zp, LDX zp, LDY zp, ADC zp, SBC zp, AND zp, ORA zp, EOR zp, CMP zp, CPX zp, CPY zp, BIT zp

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page address (ZPA), PC++ |
| 3 | $00:ZPA | R | Read data from zero-page address |

### 7.4 Zero Page,X / Zero Page,Y Read (4 cycles)

Used by: LDA zp,X / LDX zp,Y / LDY zp,X / ADC zp,X / SBC zp,X / AND zp,X / ORA zp,X / EOR zp,X / CMP zp,X

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page base address (BAL), PC++ |
| 3 | $00:BAL | R | Read from base address (dummy read — discarded), add index |
| 4 | $00:(BAL+index)&$FF | R | Read data from effective zero-page address |

### 7.5 Absolute Read (4 cycles)

Used by: LDA abs, LDX abs, LDY abs, ADC abs, SBC abs, AND abs, ORA abs, EOR abs, CMP abs, CPX abs, CPY abs, BIT abs

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch address low byte (ADL), PC++ |
| 3 | PC | R | Fetch address high byte (ADH), PC++ |
| 4 | ADH:ADL | R | Read data from effective address |

### 7.6 Absolute,X / Absolute,Y Read (4 or 5 cycles)

Used by: LDA abs,X / LDA abs,Y / LDX abs,Y / LDY abs,X / ADC abs,X / ADC abs,Y / SBC abs,X / SBC abs,Y / AND abs,X / AND abs,Y / ORA abs,X / ORA abs,Y / EOR abs,X / EOR abs,Y / CMP abs,X / CMP abs,Y

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch base address low byte (BAL), PC++ |
| 3 | PC | R | Fetch base address high byte (BAH), PC++ |
| 4 | BAH:(BAL+index)&$FF | R | Read from (possibly wrong) effective address. If no page crossing (BAL+index ≤ $FF), this is the correct address and data is valid — skip cycle 5. |
| 5* | BAH+carry:(BAL+index)&$FF | R | Read from correct effective address (high byte fixed up) |

*Cycle 5 only occurs if page boundary was crossed: `(BAL + index) > $FF`*

### 7.7 Indexed Indirect (IZX) Read (6 cycles)

Used by: LDA (zp,X), ORA (zp,X), AND (zp,X), EOR (zp,X), ADC (zp,X), SBC (zp,X), CMP (zp,X)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page base byte (BAL), PC++ |
| 3 | $00:BAL | R | Dummy read from base address, add X to BAL |
| 4 | $00:(BAL+X)&$FF | R | Fetch effective address low byte (EAL) |
| 5 | $00:(BAL+X+1)&$FF | R | Fetch effective address high byte (EAH) |
| 6 | EAH:EAL | R | Read data from effective address |

### 7.8 Indirect Indexed (IZY) Read (5 or 6 cycles)

Used by: LDA (zp),Y, ORA (zp),Y, AND (zp),Y, EOR (zp),Y, ADC (zp),Y, SBC (zp),Y, CMP (zp),Y

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page pointer address (IAL), PC++ |
| 3 | $00:IAL | R | Fetch base address low byte (BAL) |
| 4 | $00:(IAL+1)&$FF | R | Fetch base address high byte (BAH) |
| 5 | BAH:(BAL+Y)&$FF | R | Read from (possibly wrong) effective address. If no page crossing, data is valid — skip cycle 6. |
| 6* | BAH+carry:(BAL+Y)&$FF | R | Read from correct effective address (high byte fixed up) |

*Cycle 6 only occurs if page boundary was crossed: `(BAL + Y) > $FF`*

### 7.9 Zero Page Write (3 cycles)

Used by: STA zp, STX zp, STY zp

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page address (ZPA), PC++ |
| 3 | $00:ZPA | W | Write register value to zero-page address |

### 7.10 Zero Page,X / Zero Page,Y Write (4 cycles)

Used by: STA zp,X / STX zp,Y / STY zp,X

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page base address (BAL), PC++ |
| 3 | $00:BAL | R | Dummy read from base address, add index |
| 4 | $00:(BAL+index)&$FF | W | Write register value to effective zero-page address |

### 7.11 Absolute Write (4 cycles)

Used by: STA abs, STX abs, STY abs

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch address low byte (ADL), PC++ |
| 3 | PC | R | Fetch address high byte (ADH), PC++ |
| 4 | ADH:ADL | W | Write register value to effective address |

### 7.12 Absolute,X / Absolute,Y Write (5 cycles — ALWAYS)

Used by: STA abs,X / STA abs,Y

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch base address low byte (BAL), PC++ |
| 3 | PC | R | Fetch base address high byte (BAH), PC++ |
| 4 | BAH:(BAL+index)&$FF | R | Read from (possibly wrong) address — dummy read, ALWAYS occurs |
| 5 | BAH+carry:(BAL+index)&$FF | W | Write register value to correct effective address |

**IMPORTANT:** Store instructions with indexed absolute addressing ALWAYS take 5 cycles, regardless of whether a page boundary was crossed. The dummy read on cycle 4 always occurs. This can trigger side effects on hardware registers.

### 7.13 Indexed Indirect (IZX) Write (6 cycles)

Used by: STA (zp,X)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page base byte (BAL), PC++ |
| 3 | $00:BAL | R | Dummy read from base address, add X to BAL |
| 4 | $00:(BAL+X)&$FF | R | Fetch effective address low byte (EAL) |
| 5 | $00:(BAL+X+1)&$FF | R | Fetch effective address high byte (EAH) |
| 6 | EAH:EAL | W | Write register value to effective address |

### 7.14 Indirect Indexed (IZY) Write (6 cycles — ALWAYS)

Used by: STA (zp),Y

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page pointer address (IAL), PC++ |
| 3 | $00:IAL | R | Fetch base address low byte (BAL) |
| 4 | $00:(IAL+1)&$FF | R | Fetch base address high byte (BAH) |
| 5 | BAH:(BAL+Y)&$FF | R | Read from (possibly wrong) address — dummy read, ALWAYS occurs |
| 6 | BAH+carry:(BAL+Y)&$FF | W | Write register value to correct effective address |

**IMPORTANT:** Like indexed absolute writes, STA (zp),Y ALWAYS takes 6 cycles regardless of page crossing.

### 7.15 Zero Page Read-Modify-Write (5 cycles)

Used by: ASL zp, LSR zp, ROL zp, ROR zp, INC zp, DEC zp

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page address (ZPA), PC++ |
| 3 | $00:ZPA | R | Read value from zero-page address |
| 4 | $00:ZPA | W | Write ORIGINAL value back (dummy write) |
| 5 | $00:ZPA | W | Write MODIFIED value |

**IMPORTANT:** Cycle 4 writes the original (unmodified) value back to the address before cycle 5 writes the new value. This double-write is significant for hardware registers (e.g., writing to a POKEY or GTIA register).

### 7.16 Zero Page,X Read-Modify-Write (6 cycles)

Used by: ASL zp,X / LSR zp,X / ROL zp,X / ROR zp,X / INC zp,X / DEC zp,X

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch zero-page base address (BAL), PC++ |
| 3 | $00:BAL | R | Dummy read from base address, add X |
| 4 | $00:(BAL+X)&$FF | R | Read value from effective zero-page address |
| 5 | $00:(BAL+X)&$FF | W | Write ORIGINAL value back (dummy write) |
| 6 | $00:(BAL+X)&$FF | W | Write MODIFIED value |

### 7.17 Absolute Read-Modify-Write (6 cycles)

Used by: ASL abs, LSR abs, ROL abs, ROR abs, INC abs, DEC abs

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch address low byte (ADL), PC++ |
| 3 | PC | R | Fetch address high byte (ADH), PC++ |
| 4 | ADH:ADL | R | Read value from effective address |
| 5 | ADH:ADL | W | Write ORIGINAL value back (dummy write) |
| 6 | ADH:ADL | W | Write MODIFIED value |

### 7.18 Absolute,X Read-Modify-Write (7 cycles — ALWAYS)

Used by: ASL abs,X / LSR abs,X / ROL abs,X / ROR abs,X / INC abs,X / DEC abs,X

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch base address low byte (BAL), PC++ |
| 3 | PC | R | Fetch base address high byte (BAH), PC++ |
| 4 | BAH:(BAL+X)&$FF | R | Read from (possibly wrong) address — dummy read, ALWAYS occurs |
| 5 | BAH+carry:(BAL+X)&$FF | R | Read value from correct effective address |
| 6 | BAH+carry:(BAL+X)&$FF | W | Write ORIGINAL value back (dummy write) |
| 7 | BAH+carry:(BAL+X)&$FF | W | Write MODIFIED value |

**IMPORTANT:** RMW instructions with ABS,X addressing ALWAYS take 7 cycles, regardless of page crossing.

### 7.19 Branch Instructions (2, 3, or 4 cycles)

Used by: BPL, BMI, BVC, BVS, BCC, BCS, BNE, BEQ

**Not taken (2 cycles):**

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch offset byte, PC++. Test condition — not taken, done. |

**Taken, no page crossing (3 cycles):**

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch offset byte, PC++. Test condition — taken. |
| 3 | PC | R | Dummy read from PC (old PCH, new PCL), add offset to PCL. No page crossing — done. |

**Taken, page crossing (4 cycles):**

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Fetch offset byte, PC++. Test condition — taken. |
| 3 | PC (wrong PCH) | R | Dummy read from wrong address (old PCH, new PCL). Page crossing detected. |
| 4 | PC (correct) | R | Dummy read from correct PC address. Fix up PCH. Done. |

### 7.20 Stack Push — PHA / PHP (3 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Dummy read of next byte (discarded) |
| 3 | $01:SP | W | Push register to stack, SP-- |

### 7.21 Stack Pull — PLA / PLP (4 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode, PC++ |
| 2 | PC | R | Dummy read of next byte (discarded) |
| 3 | $01:SP | R | Dummy read from current SP (pre-increment) |
| 4 | $01:SP+1 | R | Read value from stack, SP++ |

### 7.22 BRK (7 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode ($00), PC++ |
| 2 | PC | R | Read padding byte (discarded), PC++ |
| 3 | $01:SP | W | Push PCH, SP-- |
| 4 | $01:SP | W | Push PCL, SP-- |
| 5 | $01:SP | W | Push P (with B=1, bit 5=1), SP-- |
| 6 | $FFFE | R | Fetch interrupt vector low byte |
| 7 | $FFFF | R | Fetch interrupt vector high byte → PCH, set I flag |

### 7.23 JSR (6 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode ($20), PC++ |
| 2 | PC | R | Fetch target address low byte (ADL), PC++ |
| 3 | $01:SP | R | Internal operation (dummy read of stack) |
| 4 | $01:SP | W | Push PCH, SP-- |
| 5 | $01:SP | W | Push PCL, SP-- |
| 6 | PC | R | Fetch target address high byte (ADH) → PC = ADH:ADL |

**Note:** The address pushed is the address of the third byte of the JSR instruction (PC after fetching only the low byte of the target). RTS adds 1 to this address.

### 7.24 RTS (6 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode ($60), PC++ |
| 2 | PC | R | Dummy read of next byte (discarded) |
| 3 | $01:SP | R | Dummy read from current SP (pre-increment) |
| 4 | $01:SP+1 | R | Pull PCL from stack, SP++ |
| 5 | $01:SP+1 | R | Pull PCH from stack, SP++ |
| 6 | PC | R | Dummy read from PC, then PC++ (increment restored PC) |

### 7.25 RTI (6 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode ($40), PC++ |
| 2 | PC | R | Dummy read of next byte (discarded) |
| 3 | $01:SP | R | Dummy read from current SP (pre-increment) |
| 4 | $01:SP+1 | R | Pull P from stack, SP++ |
| 5 | $01:SP+1 | R | Pull PCL from stack, SP++ |
| 6 | $01:SP+1 | R | Pull PCH from stack, SP++ → PC = PCH:PCL |

### 7.26 JMP Absolute (3 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode ($4C), PC++ |
| 2 | PC | R | Fetch target address low byte (ADL), PC++ |
| 3 | PC | R | Fetch target address high byte (ADH) → PC = ADH:ADL |

### 7.27 JMP Indirect (5 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Fetch opcode ($6C), PC++ |
| 2 | PC | R | Fetch pointer address low byte (IAL), PC++ |
| 3 | PC | R | Fetch pointer address high byte (IAH), PC++ |
| 4 | IAH:IAL | R | Fetch target address low byte (ADL) |
| 5 | IAH:(IAL+1)&$FF | R | Fetch target address high byte (ADH) → PC = ADH:ADL |

**Bug:** On cycle 5, only the low byte of the pointer is incremented. If IAL=$FF, the high byte is fetched from IAH:$00, not (IAH+1):$00.

### 7.28 Hardware Interrupt — IRQ / NMI (7 cycles)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Read opcode (discarded — same instruction would have executed), PC NOT incremented |
| 2 | PC | R | Read next byte (discarded), PC NOT incremented |
| 3 | $01:SP | W | Push PCH, SP-- |
| 4 | $01:SP | W | Push PCL, SP-- |
| 5 | $01:SP | W | Push P (B=0, bit 5=1), SP-- |
| 6 | vector | R | Fetch vector low byte ($FFFE for IRQ, $FFFA for NMI) |
| 7 | vector+1 | R | Fetch vector high byte, set I flag → PC = new vector address |

### 7.29 Reset Sequence (7 cycles, special)

| Cycle | Address Bus | R/W | Description |
|-------|-------------|-----|-------------|
| 1 | PC | R | Read (discarded) |
| 2 | PC | R | Read (discarded) |
| 3 | $01:SP | R | Read from stack (no write occurs despite internal "push"), SP-- |
| 4 | $01:SP | R | Read from stack (no write occurs), SP-- |
| 5 | $01:SP | R | Read from stack (no write occurs), SP-- |
| 6 | $FFFC | R | Fetch reset vector low byte |
| 7 | $FFFD | R | Fetch reset vector high byte → PC, set I flag |

**Note:** During reset, cycles 3-5 appear like pushes but are reads (R/W̄ stays high). This means the stack contents are NOT modified during reset. SP ends up decremented by 3 from its pre-reset value.

---

## 8. Interrupt Handling

### 8.1 Reset

- **Trigger:** RESET pin held low, then released.
- **Sequence:** 7 cycles (see Section 7.29).
- **Post-reset state:**
  - PC = value from $FFFC (low) and $FFFD (high)
  - I flag = 1 (interrupts disabled)
  - SP = (previous SP) - 3 (typically $FD if SP was undefined/random $00)
  - A, X, Y = **undefined** (NOT cleared)
  - D flag = **undefined** (software should CLD early in boot code)
  - No writes to memory occur during the reset sequence
- **Notes:** The Atari OS boot code at the reset vector handles initializing registers and setting up the machine state.

### 8.2 IRQ (Maskable Interrupt)

- **Trigger:** Level-triggered — active while the /IRQ pin is held low.
- **Masking:** When I flag is set (I=1), IRQ is inhibited. When I flag is clear (I=0), IRQ is serviced.
- **Sampling:** The /IRQ line is sampled during the **last cycle** of each instruction (before the interrupt sequence begins). If /IRQ is low and I=0 at that sample point, the interrupt is recognized.
- **Sequence:** 7 cycles (see Section 7.28).
- **Effects:**
  - PC pushed is the address of the NEXT instruction (the one that would have executed)
  - P pushed with B=0, bit 5=1
  - I flag set to 1 (prevents nested IRQs unless handler explicitly clears I)
  - PC loaded from $FFFE-$FFFF (IRQ/BRK vector)
- **Atari 800XL:** IRQ is used by POKEY for timer interrupts, keyboard scanning, serial I/O, and break key. The PIA (PORTA/PORTB) can also generate IRQs.

### 8.3 NMI (Non-Maskable Interrupt)

- **Trigger:** Edge-triggered — triggered on the **falling edge** (high-to-low transition) of the /NMI pin.
- **Masking:** Cannot be masked by the I flag.
- **Detection:** An internal NMI flag is set on the falling edge. This flag is cleared when the NMI sequence begins (acknowledged).
- **Sequence:** 7 cycles (see Section 7.28), but uses vector at $FFFA-$FFFB.
- **Effects:**
  - PC pushed is the address of the NEXT instruction
  - P pushed with B=0, bit 5=1
  - I flag set to 1
  - PC loaded from $FFFA-$FFFB (NMI vector)
- **Atari 800XL:** NMI is generated by ANTIC for Display List Interrupts (DLI) and VBI (Vertical Blank Interrupt), and by the RESET key (active low).

### 8.4 BRK (Software Interrupt)

- **Trigger:** Execution of the BRK ($00) opcode.
- **Sequence:** 7 cycles (see Section 7.22).
- **Effects:**
  - PC pushed is PC+2 (address of BRK opcode + 2, skipping the padding byte)
  - P pushed with B=1, bit 5=1 (this distinguishes BRK from IRQ)
  - I flag set to 1
  - PC loaded from $FFFE-$FFFF (shared with IRQ vector)
- **Distinguishing BRK from IRQ:** The interrupt handler should examine bit 4 of the P value pulled from the stack. If bit 4 = 1, the interrupt was caused by BRK. If bit 4 = 0, it was a hardware IRQ.

### 8.5 Interrupt Priority and Edge Cases

**Priority (highest to lowest):**
1. RESET (highest — overrides everything)
2. NMI
3. IRQ/BRK (lowest)

**Critical edge cases:**

1. **SEI/CLI delayed effect:** The I flag change from SEI or CLI takes effect one instruction late. This is because the interrupt-pending check occurs on the last cycle of the current instruction, but the flag is written as part of that same instruction's execution. Consequence: After `CLI`, a pending IRQ fires after the NEXT instruction completes, not immediately.

2. **RTI restores I immediately:** Unlike CLI, RTI restores the I flag from the stack and the new value takes effect for the next instruction's interrupt check. There is no one-instruction delay.

3. **NMI hijacking IRQ vector fetch:** If an NMI edge occurs during cycles 6-7 of the IRQ sequence (while the CPU is fetching the IRQ vector), the NMI can "hijack" the vector fetch — the CPU may read from the NMI vector ($FFFA-$FFFB) instead of the IRQ vector. Specifically, if NMI is detected between cycle 6 and 7, cycle 7 may fetch from $FFFB instead of $FFFF.

4. **BRK + IRQ collision:** If an IRQ is pending on the same cycle that a BRK instruction's interrupt sequence begins, the CPU services the IRQ (reads from $FFFE-$FFFF) but the B flag is still set to 1 in the pushed P byte. The IRQ handler will see B=1 and think it was a BRK.

5. **NMI + BRK collision:** If an NMI occurs while a BRK is being executed, the NMI vector ($FFFA-$FFFB) is used but B=1 is still pushed to the stack.

6. **Short NMI pulses:** If the NMI line goes low and returns high too quickly (less than approximately 2.5 CPU cycles during interrupt handling), the NMI edge may not be properly detected and can be lost.

7. **Taken branches delay interrupts:** When a branch instruction is taken, interrupt recognition is delayed by one instruction. This is because the branch's extra cycle(s) are part of its execution and the interrupt check occurs at the end of the instruction.

8. **SALLY HALT behavior:** When ANTIC asserts the HALT line, SALLY finishes its current clock cycle and then tri-states the bus. It remains halted until ANTIC releases HALT. The CPU resumes on the exact cycle where it stopped — no state is lost. This is transparent to software but affects real-time cycle counting and interrupt latency.

---

## 9. Decimal (BCD) Mode — NMOS 6502 Behavior

### 9.1 Overview

When the D (Decimal) flag is set, ADC and SBC operate in Binary-Coded Decimal mode. Each byte is treated as two BCD digits (each nibble represents 0-9), allowing values from 00 to 99.

**CRITICAL:** The NMOS 6502 (including SALLY) has specific decimal mode behavior that differs from the CMOS 65C02. The N, Z, and V flags behave differently and often non-intuitively on NMOS parts.

### 9.2 ADC in Decimal Mode

```python
# NMOS 6502 ADC Decimal Mode — Complete Algorithm
def adc_decimal(A, M, C):
    # Step 1: Binary addition (for flag computation)
    binary_result = A + M + C

    # Step 2: Low nibble
    low = (A & 0x0F) + (M & 0x0F) + C
    if low > 9:
        low = low + 6  # BCD correction

    # Step 3: High nibble computation
    high = (A >> 4) + (M >> 4) + (1 if low > 0x0F else 0)

    # Step 4: N flag — based on bit 7 of intermediate result
    # The intermediate result after low nibble correction
    intermediate = (high << 4) | (low & 0x0F)
    N = (intermediate >> 7) & 1

    # Step 5: V flag — based on signed binary overflow
    V = 1 if ((A ^ intermediate) & (M ^ intermediate) & 0x80) else 0

    # Step 6: Z flag — based on BINARY result (NMOS quirk!)
    Z = 1 if (binary_result & 0xFF) == 0 else 0

    # Step 7: High nibble BCD correction
    if high > 9:
        high = high + 6

    # Step 8: C flag — valid BCD carry
    C = 1 if high > 0x0F else 0

    # Step 9: Final result
    A = ((high & 0x0F) << 4) | (low & 0x0F)

    return A, N, V, Z, C
```

**Key NMOS quirks:**
- **Z flag:** Based on the binary (non-BCD) result. `$49 + $51 + 0` in binary = $9A (non-zero), so Z=0, even though the BCD result is $00.
- **N flag:** Based on bit 7 of an intermediate result BEFORE the high nibble BCD correction.
- **V flag:** Based on the binary signed overflow, not meaningful for BCD.
- **C flag:** Valid and correct for BCD — set if the BCD result exceeds 99.

### 9.3 SBC in Decimal Mode

```python
# NMOS 6502 SBC Decimal Mode — Complete Algorithm
def sbc_decimal(A, M, C):
    # Step 1: Binary subtraction (for N, V, Z flags)
    binary_result = A - M - (1 - C)

    # Step 2: Z flag — based on BINARY result (NMOS quirk!)
    Z = 1 if (binary_result & 0xFF) == 0 else 0

    # Step 3: N flag — based on binary result
    N = (binary_result >> 7) & 1

    # Step 4: V flag — based on binary signed overflow
    V = 1 if ((A ^ binary_result) & ((~M & 0xFF) ^ binary_result) & 0x80) else 0
    # Equivalently: V = 1 if ((A ^ M) & (A ^ binary_result) & 0x80) else 0

    # Step 5: Low nibble BCD subtraction
    low = (A & 0x0F) - (M & 0x0F) - (1 - C)
    if low < 0:
        low = ((low - 6) & 0x0F) | ((A & 0xF0) - (M & 0xF0) - 0x10)
    else:
        low = (low & 0x0F) | ((A & 0xF0) - (M & 0xF0))

    # Step 6: High nibble BCD correction
    if low < 0:
        low = low + 0x60  # Adjust if borrow from high nibble

    # Step 7: C flag — valid
    C = 0 if binary_result < 0 else 1

    # Step 8: Final result
    A = low & 0xFF

    return A, N, V, Z, C
```

**Key NMOS quirks for SBC decimal:**
- **Z flag:** Based on binary result, not BCD result (same quirk as ADC).
- **N flag:** Based on binary result.
- **V flag:** Based on binary overflow, not meaningful for BCD.
- **C flag:** Valid — clear if borrow occurred (same as binary mode).

### 9.4 Invalid BCD Input

When nibble values exceed 9 (e.g., $0A-$0F), the NMOS 6502 produces deterministic but undocumented results. The internal correction logic still applies BCD fixups, but the results are not useful BCD values. The exact behavior has been thoroughly documented through chip-level analysis and testing.

For emulation purposes: if targeting accuracy with Tom Harte's test suite, the full internal algorithm (including invalid BCD handling) must be implemented. If only targeting valid BCD usage, the algorithms above are sufficient.

### 9.5 Decimal Mode Timing

Unlike the CMOS 65C02 (which adds one extra cycle for ADC/SBC in decimal mode), the **NMOS 6502 takes the same number of cycles** for ADC and SBC regardless of whether the D flag is set. There is no cycle penalty for decimal mode.

---

## 10. Undocumented / Illegal Opcodes

The NMOS 6502 has 151 official opcodes, leaving 105 unused opcode slots. Due to the combinatorial logic of the instruction decoder, these unused opcodes perform deterministic (if unintended) operations. Some are stable and well-understood; others depend on analog properties of the chip and are unreliable.

### 10.1 Stable Illegal Opcodes

These opcodes produce consistent, predictable results across all NMOS 6502 chips and are used by some Atari software.

#### SLO (ASO) — Shift Left OR

**Operation:** ASL memory, then ORA result with A.

**Pseudocode:**
```python
value = memory[EA]
C = (value >> 7) & 1
value = (value << 1) & 0xFF
memory[EA] = value
A = A | value
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $07 | 2 | 5 |
| ZPX | $17 | 2 | 6 |
| ABS | $0F | 3 | 6 |
| ABX | $1F | 3 | 7 |
| ABY | $1B | 3 | 7 |
| IZX | $03 | 2 | 8 |
| IZY | $13 | 2 | 8 |

---

#### RLA — Rotate Left AND

**Operation:** ROL memory, then AND result with A.

**Pseudocode:**
```python
value = memory[EA]
old_c = C
C = (value >> 7) & 1
value = ((value << 1) | old_c) & 0xFF
memory[EA] = value
A = A & value
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $27 | 2 | 5 |
| ZPX | $37 | 2 | 6 |
| ABS | $2F | 3 | 6 |
| ABX | $3F | 3 | 7 |
| ABY | $3B | 3 | 7 |
| IZX | $23 | 2 | 8 |
| IZY | $33 | 2 | 8 |

---

#### SRE (LSE) — Shift Right Exclusive OR

**Operation:** LSR memory, then EOR result with A.

**Pseudocode:**
```python
value = memory[EA]
C = value & 1
value = value >> 1
memory[EA] = value
A = A ^ value
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $47 | 2 | 5 |
| ZPX | $57 | 2 | 6 |
| ABS | $4F | 3 | 6 |
| ABX | $5F | 3 | 7 |
| ABY | $5B | 3 | 7 |
| IZX | $43 | 2 | 8 |
| IZY | $53 | 2 | 8 |

---

#### RRA — Rotate Right Add

**Operation:** ROR memory, then ADC result with A.

**Pseudocode:**
```python
value = memory[EA]
old_c = C
C = value & 1
value = (value >> 1) | (old_c << 7)
memory[EA] = value
# Now perform ADC with the rotated value
# (follows full ADC logic including decimal mode)
result = A + value + C
C = 1 if result > 0xFF else 0
V = 1 if ((A ^ result) & (value ^ result) & 0x80) else 0
A = result & 0xFF
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
# Note: If D flag is set, decimal mode ADC applies
```

**Flags:** N V Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $67 | 2 | 5 |
| ZPX | $77 | 2 | 6 |
| ABS | $6F | 3 | 6 |
| ABX | $7F | 3 | 7 |
| ABY | $7B | 3 | 7 |
| IZX | $63 | 2 | 8 |
| IZY | $73 | 2 | 8 |

---

#### SAX (AXS) — Store A AND X

**Operation:** Store the result of A AND X into memory. No flags affected.

**Pseudocode:**
```python
memory[EA] = A & X
```

**Flags:** None

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $87 | 2 | 3 |
| ZPY | $97 | 2 | 4 |
| ABS | $8F | 3 | 4 |
| IZX | $83 | 2 | 6 |

---

#### LAX — Load A and X

**Operation:** Load both A and X from memory.

**Pseudocode:**
```python
A = memory[EA]
X = A
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
```

**Flags:** N Z

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $A7 | 2 | 3 |
| ZPY | $B7 | 2 | 4 |
| ABS | $AF | 3 | 4 |
| ABY | $BF | 3 | 4+p |
| IZX | $A3 | 2 | 6 |
| IZY | $B3 | 2 | 5+p |

*p = +1 if page boundary crossed*

---

#### DCP (DCM) — Decrement and Compare

**Operation:** DEC memory, then CMP result with A.

**Pseudocode:**
```python
value = memory[EA]
value = (value - 1) & 0xFF
memory[EA] = value
result = A - value
C = 1 if A >= value else 0
Z = 1 if A == value else 0
N = (result >> 7) & 1
```

**Flags:** N Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $C7 | 2 | 5 |
| ZPX | $D7 | 2 | 6 |
| ABS | $CF | 3 | 6 |
| ABX | $DF | 3 | 7 |
| ABY | $DB | 3 | 7 |
| IZX | $C3 | 2 | 8 |
| IZY | $D3 | 2 | 8 |

---

#### ISC (ISB) — Increment and Subtract with Carry

**Operation:** INC memory, then SBC result from A.

**Pseudocode:**
```python
value = memory[EA]
value = (value + 1) & 0xFF
memory[EA] = value
# Now perform SBC with the incremented value
# (follows full SBC logic including decimal mode)
result = A - value - (1 - C)
C = 1 if result >= 0 else 0
V = 1 if ((A ^ result) & ((~value & 0xFF) ^ result) & 0x80) else 0
A = result & 0xFF
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
# Note: If D flag is set, decimal mode SBC applies
```

**Flags:** N V Z C

| Mode | Opcode | Bytes | Cycles |
|------|--------|-------|--------|
| ZP | $E7 | 2 | 5 |
| ZPX | $F7 | 2 | 6 |
| ABS | $EF | 3 | 6 |
| ABX | $FF | 3 | 7 |
| ABY | $FB | 3 | 7 |
| IZX | $E3 | 2 | 8 |
| IZY | $F3 | 2 | 8 |

---

#### ANC — AND with Carry

**Operation:** AND immediate with A, then copy bit 7 of result to C.

**Pseudocode:**
```python
A = A & M
N = (A >> 7) & 1
Z = 1 if A == 0 else 0
C = N  # C = bit 7 of result
```

**Flags:** N Z C

| Opcode | Bytes | Cycles |
|--------|-------|--------|
| $0B | 2 | 2 |
| $2B | 2 | 2 |

---

#### ALR (ASR) — AND then Shift Right

**Operation:** AND immediate with A, then LSR A.

**Pseudocode:**
```python
A = A & M
C = A & 1
A = A >> 1
N = 0  # Always 0 after LSR
Z = 1 if A == 0 else 0
```

**Flags:** N Z C

| Opcode | Bytes | Cycles |
|--------|-------|--------|
| $4B | 2 | 2 |

---

#### ARR — AND then Rotate Right (Special)

**Operation:** AND immediate with A, then ROR A, with special flag behavior.

**Pseudocode:**
```python
A = A & M
if D == 0:  # Binary mode
    A = (A >> 1) | (C << 7)
    N = (A >> 7) & 1
    Z = 1 if A == 0 else 0
    C = (A >> 6) & 1  # Bit 6 of result
    V = ((A >> 6) ^ (A >> 5)) & 1  # Bit 6 XOR Bit 5
else:  # Decimal mode — complex behavior
    temp = A
    A = (A >> 1) | (C << 7)
    N = C  # N = old C
    Z = 1 if A == 0 else 0
    V = ((temp ^ A) >> 6) & 1
    # Low nibble fixup
    if (temp & 0x0F) + (temp & 0x01) > 5:
        A = (A & 0xF0) | ((A + 6) & 0x0F)
    # High nibble fixup
    if (temp & 0xF0) + (temp & 0x10) > 0x50:
        A = (A + 0x60) & 0xFF
        C = 1
    else:
        C = 0
```

**Flags:** N V Z C (special behavior)

| Opcode | Bytes | Cycles |
|--------|-------|--------|
| $6B | 2 | 2 |

---

#### SBX (AXS) — A AND X Subtract Immediate

**Operation:** (A AND X) minus immediate → X. Like CMP but stores result in X.

**Pseudocode:**
```python
temp = A & X
result = temp - M
C = 1 if temp >= M else 0
X = result & 0xFF
N = (X >> 7) & 1
Z = 1 if X == 0 else 0
```

**Flags:** N Z C

| Opcode | Bytes | Cycles |
|--------|-------|--------|
| $CB | 2 | 2 |

**Note:** The subtraction does NOT use the carry flag (unlike SBC). It behaves like CMP in that regard.

---

#### USBC — Unofficial SBC

**Operation:** Identical to official SBC (including decimal mode).

| Opcode | Bytes | Cycles |
|--------|-------|--------|
| $EB | 2 | 2 |

---

### 10.2 Unofficial NOP Variants

These opcodes perform no useful operation but may read from memory (potentially triggering hardware side effects) and advance PC by varying amounts.

| Type | Opcodes | Bytes | Cycles | Notes |
|------|---------|-------|--------|-------|
| 1-byte NOP | $1A, $3A, $5A, $7A, $DA, $FA | 1 | 2 | Same as official NOP |
| 2-byte NOP (IMM) | $80, $82, $89, $C2, $E2 | 2 | 2 | Read and discard immediate byte |
| 2-byte NOP (ZP) | $04, $44, $64 | 2 | 3 | Read from zero-page address (discarded) |
| 2-byte NOP (ZPX) | $14, $34, $54, $74, $D4, $F4 | 2 | 4 | Read from ZP,X address (discarded) |
| 3-byte NOP (ABS) | $0C | 3 | 4 | Read from absolute address (discarded) |
| 3-byte NOP (ABX) | $1C, $3C, $5C, $7C, $DC, $FC | 3 | 4+p | Read from ABS,X address (discarded) |

*p = +1 if page boundary crossed*

**Note:** The reads performed by multi-byte NOPs can trigger side effects when addressing hardware registers.

### 10.3 JAM / KIL / HLT — Halt Processor

These opcodes lock up the processor. The CPU enters a state where it continuously puts $FFFF on the address bus and performs reads, but never advances. Only a hardware RESET can recover.

**Opcodes:** $02, $12, $22, $32, $42, $52, $62, $72, $92, $B2, $D2, $F2

### 10.4 Unstable Illegal Opcodes

> **WARNING:** The following opcodes have behavior that depends on analog properties of the NMOS 6502 chip — temperature, voltage, chip revision, and manufacturing variations all affect the results. They are NOT reliably reproducible and should NOT be used in software that must run on all hardware.

#### ANE (XAA) — $8B

**Operation:** `A = (A | MAGIC) & X & M`

Where MAGIC is a chip-dependent constant, most commonly $EE or $FF on NMOS 6502, but varies per chip. Some chips show $00.

**Flags:** N Z

---

#### LXA (LAX immediate) — $AB

**Operation:** `A = X = (A | MAGIC) & M`

Same MAGIC constant issue as ANE.

**Flags:** N Z

---

#### SHA (AHX) — $93 (IZY), $9F (ABY)

**Operation:** `memory[EA] = A & X & (high_byte_of_address + 1)`

The stored value and the effective address high byte can be corrupted due to a timing glitch — if a page boundary is crossed, the high byte of the address used for the write is AND'd with the stored value.

**Flags:** None

---

#### SHX (SXA) — $9E (ABY)

**Operation:** `memory[EA] = X & (high_byte_of_address + 1)`

Same page-crossing instability as SHA.

**Flags:** None

---

#### SHY (SYA) — $9C (ABX)

**Operation:** `memory[EA] = Y & (high_byte_of_address + 1)`

Same page-crossing instability as SHA.

**Flags:** None

---

#### TAS (SHS) — $9B (ABY)

**Operation:** `SP = A & X; memory[EA] = SP & (high_byte_of_address + 1)`

Combines setting the stack pointer with the SHA-style unstable write.

**Flags:** None

---

#### LAS (LAR) — $BB (ABY)

**Operation:** `A = X = SP = memory[EA] & SP`

**Flags:** N Z

| Opcode | Bytes | Cycles |
|--------|-------|--------|
| $BB | 3 | 4+p |

---

## 11. Atari 800XL Memory Map

### 11.1 Address Space Overview

| Address Range | Size | Description |
|---------------|------|-------------|
| $0000-$00FF | 256 bytes | Zero Page — fast access for all ZP addressing modes |
| $0100-$01FF | 256 bytes | Hardware stack — used by PHA/PLA/PHP/PLP/JSR/RTS/RTI/BRK/interrupts |
| $0200-$02FF | 256 bytes | OS vectors and variables (VDSLST, VVBLKI, etc.) |
| $0300-$04FF | 512 bytes | Device handler table, misc OS variables |
| $0500-$057F | 128 bytes | Spare / available |
| $0580-$05FF | 128 bytes | Floating point workspace, misc |
| $0600-$06FF | 256 bytes | Page 6 — traditionally user-available |
| $0700-$9FFF | ~38 KB | User RAM (upper bound depends on display list and screen memory) |
| $A000-$BFFF | 8 KB | BASIC ROM (when enabled) or RAM |
| $C000-$CFFF | 4 KB | OS ROM area or RAM |
| $D000-$D0FF | 256 bytes | GTIA hardware registers |
| $D100-$D1FF | 256 bytes | Unused / expansion |
| $D200-$D2FF | 256 bytes | POKEY hardware registers |
| $D300-$D3FF | 256 bytes | PIA (6520) registers |
| $D400-$D4FF | 256 bytes | ANTIC hardware registers |
| $D500-$D5FF | 256 bytes | Cartridge control / expansion |
| $D600-$D7FF | 512 bytes | Unused |
| $D800-$FFFF | 10 KB | OS ROM or RAM |

### 11.2 Interrupt Vectors

| Address | Vector | Description |
|---------|--------|-------------|
| $FFFA-$FFFB | NMI | Non-Maskable Interrupt vector |
| $FFFC-$FFFD | RESET | Reset vector (entry point on power-on/reset) |
| $FFFE-$FFFF | IRQ/BRK | Maskable Interrupt / Break vector |

**Note:** On the Atari 800XL, these vectors are in OS ROM and point to the Atari OS interrupt handlers. The OS then dispatches to user-configurable shadow vectors in low memory (e.g., VVBLKI at $0222 for VBI, VDSLST at $0200 for DLI).

### 11.3 PORTB Memory Control ($D301)

The PIA PORTB register at $D301 controls bank switching of ROM/RAM:

| Bit | Function |
|-----|----------|
| 0 | OS ROM enable: 0 = RAM replaces OS ROM at $C000-$CFFF and $D800-$FFFF; 1 = OS ROM active |
| 1 | BASIC enable: 0 = BASIC ROM at $A000-$BFFF; 1 = RAM at $A000-$BFFF |
| 2-6 | Unused on 800XL (active on 130XE for extended memory banking) |
| 7 | Self-test ROM: 0 = Self-test ROM visible at $5000-$57FF; 1 = RAM |

**Note:** When OS ROM is banked out (bit 0 = 0), the interrupt vectors at $FFFA-$FFFF come from RAM. Software must ensure valid vectors are present in RAM before disabling OS ROM, or the system will crash on the next interrupt.

### 11.4 Hardware Registers

#### 11.4.1 ANTIC ($D400-$D40F) — Display Processor

**Write-only:**

| Address | Name | Description |
|---------|------|-------------|
| $D400 | DMACTL | DMA control (playfield width, P/M enable, DL enable) |
| $D401 | CHACTL | Character control (inverse, blank, reflect) |
| $D402 | DLISTL | Display list pointer low byte |
| $D403 | DLISTH | Display list pointer high byte |
| $D404 | HSCROL | Horizontal fine scroll (0-15 color clocks) |
| $D405 | VSCROL | Vertical fine scroll (0-15 scan lines) |
| $D407 | PMBASE | Player/missile base address (high byte) |
| $D409 | CHBASE | Character set base address (high byte) |
| $D40A | WSYNC | Wait for horizontal sync (any write halts CPU) |
| $D40E | NMIEN | NMI enable (bit 6 = VBI, bit 7 = DLI) |
| $D40F | NMIRES | NMI reset (any write acknowledges NMI) |

**Read-only:**

| Address | Name | Description |
|---------|------|-------------|
| $D40B | VCOUNT | Vertical line counter (scan line / 2) |
| $D40C | PENH | Light pen horizontal position |
| $D40D | PENV | Light pen vertical position |
| $D40F | NMIST | NMI status (bit 5 = RESET, bit 6 = VBI, bit 7 = DLI) |

#### 11.4.2 GTIA ($D000-$D01F) — Graphics

**Write-only:**

| Address | Name | Description |
|---------|------|-------------|
| $D000-$D003 | HPOSP0-3 | Player horizontal positions |
| $D004-$D007 | HPOSM0-3 | Missile horizontal positions |
| $D008-$D00B | SIZEP0-3 | Player sizes |
| $D00C | SIZEM | Missile sizes |
| $D00D-$D010 | GRAFP0-3 | Player graphics patterns |
| $D011 | GRAFM | Missile graphics patterns |
| $D012-$D015 | COLPM0-3 | Player/missile colors |
| $D016-$D019 | COLPF0-3 | Playfield colors |
| $D01A | COLBK | Background color |
| $D01B | PRIOR | Priority and GTIA mode select |
| $D01C | VDELAY | Vertical delay for P/M graphics |
| $D01D | GRACTL | Graphics control |
| $D01E | HITCLR | Clear all collision registers |

**Read-only:**

| Address | Name | Description |
|---------|------|-------------|
| $D000-$D003 | M0PF-M3PF | Missile-to-playfield collisions |
| $D004-$D007 | P0PF-P3PF | Player-to-playfield collisions |
| $D008-$D00B | M0PL-M3PL | Missile-to-player collisions |
| $D00C-$D00F | P0PL-P3PL | Player-to-player collisions |
| $D010-$D013 | TRIG0-3 | Joystick trigger buttons |
| $D014 | PAL | PAL/NTSC detection |
| $D01F | CONSOL | Console keys (START, SELECT, OPTION) |

#### 11.4.3 POKEY ($D200-$D20F) — Audio/Keyboard/Serial

**Write-only:**

| Address | Name | Description |
|---------|------|-------------|
| $D200 | AUDF1 | Audio channel 1 frequency |
| $D201 | AUDC1 | Audio channel 1 control (distortion + volume) |
| $D202 | AUDF2 | Audio channel 2 frequency |
| $D203 | AUDC2 | Audio channel 2 control |
| $D204 | AUDF3 | Audio channel 3 frequency |
| $D205 | AUDC3 | Audio channel 3 control |
| $D206 | AUDF4 | Audio channel 4 frequency |
| $D207 | AUDC4 | Audio channel 4 control |
| $D208 | AUDCTL | Audio control (clock sources, filters, channel pairing) |
| $D209 | STIMER | Start/reset all timers |
| $D20A | SKREST | Serial port status reset |
| $D20B | POTGO | Start potentiometer scan |
| $D20D | SEROUT | Serial output data |
| $D20E | IRQEN | IRQ enable mask |
| $D20F | SKCTL | Serial port control |

**Read-only:**

| Address | Name | Description |
|---------|------|-------------|
| $D200-$D207 | POT0-7 | Paddle (potentiometer) values |
| $D208 | ALLPOT | Potentiometer scan status |
| $D209 | KBCODE | Keyboard scan code |
| $D20A | RANDOM | Random number from polynomial counter |
| $D20D | SERIN | Serial input data |
| $D20E | IRQST | IRQ status (active-low) |
| $D20F | SKSTAT | Serial/keyboard status |

#### 11.4.4 PIA ($D300-$D303) — Peripheral Interface

| Address | Name | Description |
|---------|------|-------------|
| $D300 | PORTA | Joystick port data (active-low direction bits) |
| $D301 | PORTB | System control / bank switching |
| $D302 | PACTL | Port A control (bit 2 selects DDR vs data register) |
| $D303 | PBCTL | Port B control (bit 2 selects DDR vs data register) |

When PACTL/PBCTL bit 2 = 0, accessing PORTA/PORTB reads the Data Direction Register
(DDR) instead of the data register.

### 11.5 ANTIC DMA Cycle Stealing

ANTIC shares the address bus with the 6502 and steals CPU cycles for memory fetches. The
CPU is halted during DMA cycles. Out of 114 machine cycles per scan line:

**Base overhead (when DMA enabled):**
- Memory refresh: 9 cycles per scan line
- Display list fetch: 1 cycle per scan line
- Display list extra byte (LMS operand): 1 additional cycle when present

**Player/Missile DMA:** 5 cycles (1 missile + 4 players)

**Playfield DMA** (varies by ANTIC display mode):

| ANTIC Mode | Display Type | Bytes/Line | DMA Cycles (normal width) |
|------------|-------------|------------|--------------------------|
| Blank | — | 0 | 0 |
| 2 (BASIC 0) | 40-col text | 40 + char data | ~40-90 (varies by row) |
| 6 (BASIC 1) | 20-col text | 20 + char data | ~20-40 |
| 8 (BASIC 3) | 40-pixel map | 10 | ~10 |
| D (BASIC 6) | 160-pixel map | 40 | ~40 |
| F (BASIC 8) | 320-pixel map | 40 | ~40 |

In text modes, the first scan line of each character row fetches both screen data and
character bitmap data (~90 cycles stolen), while subsequent lines only fetch character
data (~50 cycles stolen).

**Vertical blank:** No playfield DMA occurs, leaving ~105 cycles per line for the CPU.

### 11.6 Timing

| Parameter | NTSC | PAL |
|-----------|------|-----|
| CPU clock | 1.7897725 MHz | 1.7734475 MHz |
| Color clocks / scan line | 228 | 228 |
| Machine cycles / scan line | 114 | 114 |
| Scan lines / frame | 262 | 312 |
| Machine cycles / frame | 29,868 | 35,568 |
| Frame rate | ~59.92 Hz | ~49.86 Hz |

**Relationship:** 1 machine cycle = 2 color clocks. CPU clock = color clock / 2.

### 11.7 WSYNC

Writing any value to WSYNC ($D40A) halts the 6502 until the start of horizontal blank
on the current scan line. The CPU resumes at approximately cycle 105-110, with 4-9
cycles of HBLANK remaining before the next visible line begins.

The number of cycles consumed by a WSYNC write varies depending on when in the scan line
the write occurs.

### 11.8 Interrupt Sources

**NMI (from ANTIC):**

| Source | NMIEN Bit | Description |
|--------|-----------|-------------|
| DLI | Bit 7 | Display List Interrupt — triggered per display list instruction |
| VBI | Bit 6 | Vertical Blank Interrupt — at start of vertical blank |

**IRQ (from POKEY):**

| Source | IRQEN Bit | Description |
|--------|-----------|-------------|
| Timer 1 | Bit 0 | Audio channel 1 countdown |
| Timer 2 | Bit 1 | Audio channel 2 countdown |
| Timer 4 | Bit 2 | Audio channel 4 countdown |
| Serial In | Bit 3 | Serial input data ready |
| Serial Out | Bit 4 | Serial output buffer empty |
| Serial Done | Bit 5 | Serial transmission complete |
| Keyboard | Bit 6 | Key pressed |
| BREAK | Bit 7 | BREAK key pressed |

### 11.9 OS Interrupt Dispatch

The OS ROM provides default interrupt handlers that dispatch through RAM vectors:

| Vector Address | Name | Purpose |
|----------------|------|---------|
| $0200/$0201 | VDSLST | Display List Interrupt handler |
| $0206/$0207 | BRKKEY | BRK instruction handler |
| $0208/$0209 | VKEYBD | Keyboard IRQ handler |
| $020A/$020B | VSERIN | Serial input ready handler |
| $020C/$020D | VSEROR | Serial output ready handler |
| $020E/$020F | VSEROC | Serial output complete handler |
| $0210/$0211 | VTIMR1 | Timer 1 handler |
| $0212/$0213 | VTIMR2 | Timer 2 handler |
| $0214/$0215 | VTIMR4 | Timer 4 handler |
| $0222/$0223 | VVBLKI | Immediate Vertical Blank handler |
| $0224/$0225 | VVBLKD | Deferred Vertical Blank handler |

The OS VBI handler updates the real-time clock ($0012-$0014), reads controller inputs
into shadow registers, and copies shadow color registers ($02C0-$02C8) to hardware.

---

## 12. Known Edge Cases and Emulator Notes

This section collects behaviors that are commonly implemented incorrectly in emulators. Each item is numbered for reference.

### 12.1 JMP Indirect Page-Boundary Bug

`JMP ($xxFF)` fetches the low byte from $xxFF and the high byte from $xx00, NOT from $xx00+$100. Only the low byte of the pointer is incremented; it wraps within the 256-byte page.

**Example:** `JMP ($02FF)` → low byte from $02FF, high byte from $0200.

### 12.2 BRK + IRQ Collision

If an IRQ is pending when BRK starts its interrupt sequence, the IRQ takes over (IRQ vector is used), but the B flag in the pushed P byte is still 1. The handler sees B=1 and incorrectly thinks a BRK occurred.

### 12.3 NMI + BRK Collision

If an NMI fires during BRK execution, the NMI vector ($FFFA-$FFFB) is used instead of the IRQ vector, but B=1 is still pushed.

### 12.4 Read-Modify-Write Double Write

RMW instructions (ASL, LSR, ROL, ROR, INC, DEC and their illegal equivalents) perform a **dummy write** of the original (unmodified) value to the effective address before writing the final modified value. This matters for hardware registers:

- Writing to POKEY's STIMER ($D209) with a RMW instruction triggers the timer restart TWICE.
- Writing to ANTIC's WSYNC with a RMW instruction causes a double WSYNC.

### 12.5 Dummy Reads on Indexed Addressing

Indexed addressing modes (ABS,X / ABS,Y / (ZP),Y) always read from the "wrong" address (before high-byte fixup) even if a page boundary is not crossed (for writes and RMW) or before determining the correct address (for reads). This can trigger hardware register side effects.

For write instructions (STA abs,X, STA abs,Y, STA (zp),Y), the dummy read ALWAYS occurs — there is no page-crossing optimization.

### 12.6 Stack Wrapping

The stack pointer wraps within $0100-$01FF. If SP is $00 and a push occurs, the value is written to $0100 and SP wraps to $FF. If SP is $FF and a pull occurs, it wraps to $00 and reads from $0100. The stack never extends into page 0 ($0000-$00FF) or page 2 ($0200-$02FF).

### 12.7 Zero Page Indexing Wraps

ZP,X and ZP,Y addressing modes wrap within the zero page ($00-$FF). If the base address plus index exceeds $FF, it wraps to the beginning of zero page. Example: `LDA $F0,X` with X=$20 reads from $0010, not $0110.

The same applies to the pointer address in (ZP,X) mode: `LDA ($FF,X)` with X=$01 reads the pointer from $0000-$0001.

### 12.8 Decimal Mode N/Z Flags (NMOS)

On the NMOS 6502, the Z flag after ADC/SBC in decimal mode reflects the **binary** result, not the BCD result. The N flag reflects an intermediate computation. This is the most commonly misimplemented behavior in 6502 emulators. See Section 9 for full details.

### 12.9 SEI/CLI Delayed Effect

After SEI, the instruction IMMEDIATELY following SEI can still be interrupted by an IRQ (if one is pending). After CLI, a pending IRQ is not serviced until after the instruction following CLI completes. This is because the interrupt line is checked on the last cycle of each instruction, and the flag change from SEI/CLI is committed during that same instruction's execution.

### 12.10 RTI vs RTS Return Address

- **RTI:** Returns to the EXACT address pulled from the stack (no adjustment). The interrupt sequence pushes the address of the next instruction.
- **RTS:** Returns to the address pulled from the stack PLUS ONE. JSR pushes the address of its last byte (PC-1).

### 12.11 BRK Skips a Byte

BRK pushes PC+2 to the stack (the address two bytes after the BRK opcode). The byte immediately after BRK ($01 position) is a "padding byte" or "BRK signature" that is skipped. RTI returns to the byte AFTER the padding byte. Some software uses this padding byte to pass a parameter to the BRK handler.

### 12.12 Indirect,X Pointer Wrapping

The pointer address in (ZP,X) mode wraps within zero page. If the computed pointer address is $FF, the low byte of the effective address is read from $00FF and the high byte from $0000 (NOT $0100).

### 12.13 SALLY HALT / ANTIC DMA

When ANTIC needs bus access for DMA (fetching display list data, character data, player-missile data, or screen memory), it asserts the HALT line. SALLY finishes its current clock cycle and tri-states the bus. ANTIC performs its DMA reads, then releases HALT. SALLY resumes exactly where it stopped.

**Emulation impact:** The CPU "loses" cycles during ANTIC DMA. The number of stolen cycles varies per scanline depending on the display mode, character width, player-missile resolution, and display list instruction type. Accurate cycle counting requires modeling ANTIC DMA timing.

### 12.14 Initial State After Reset

- A, X, Y are **NOT cleared** — they retain whatever value they had before reset (or random values on power-up).
- SP is decremented by 3 during the reset sequence (internal push simulation), but **no writes to the stack occur**. If SP was $00 before reset, it becomes $FD.
- PC is loaded from the reset vector at $FFFC-$FFFD.
- I flag is set to 1 (interrupts disabled).
- D flag is **undefined** — software should execute CLD early in the boot sequence.
- N, V, Z, C flags are undefined after power-up.

---

## 13. Test Vectors

These test cases can be used to verify emulator correctness. Each test specifies the initial CPU state, the operation performed, and the expected results.

### 13.1 ADC — Binary Mode

#### Test: ADC Binary — Simple Add, No Carry
```
Initial:  A=$10 C=0 D=0
Operation: ADC #$20
Expected: A=$30 N=0 V=0 Z=0 C=0
```

#### Test: ADC Binary — With Carry In
```
Initial:  A=$50 C=1 D=0
Operation: ADC #$50
Expected: A=$A1 N=1 V=1 Z=0 C=0
Note: $50+$50+1 = $A1. Signed: 80+80+1 = 161 → overflow (V=1). A=$A1 → bit 7 set (N=1).
```

#### Test: ADC Binary — Carry Out
```
Initial:  A=$FF C=0 D=0
Operation: ADC #$01
Expected: A=$00 N=0 V=0 Z=1 C=1
Note: $FF+$01 = $100 → C=1, result = $00.
```

#### Test: ADC Binary — Overflow Detection
```
Initial:  A=$7F C=0 D=0
Operation: ADC #$01
Expected: A=$80 N=1 V=1 Z=0 C=0
Note: 127+1 = 128 → signed overflow (V=1). Result is negative (N=1).
```

### 13.2 ADC — Decimal Mode

#### Test: ADC Decimal — Simple BCD Add
```
Initial:  A=$15 C=0 D=1
Operation: ADC #$27
Expected: A=$42 N=0 V=0 Z=0 C=0
Note: 15 + 27 = 42 BCD
```

#### Test: ADC Decimal — BCD Carry
```
Initial:  A=$49 C=1 D=1
Operation: ADC #$50
Expected: A=$00 N=0 V=? Z=0 C=1
Note: 49+50+1 = 100 BCD → C=1, A=$00. Z=0 on NMOS because binary result ($49+$50+$01=$9A) is non-zero.
```

#### Test: ADC Decimal — Z Flag Quirk
```
Initial:  A=$50 C=0 D=1
Operation: ADC #$50
Expected: A=$00 N=1 V=1 Z=0 C=1
Note: 50+50 = 100 BCD → A=$00, C=1. But Z=0 (NMOS quirk: binary $50+$50=$A0, non-zero).
      N=1 (intermediate result bit 7 is set before high nibble fixup).
```

### 13.3 SBC — Binary Mode

#### Test: SBC Binary — Simple Subtract
```
Initial:  A=$50 C=1 D=0
Operation: SBC #$20
Expected: A=$30 N=0 V=0 Z=0 C=1
Note: $50-$20-0 = $30. No borrow → C=1.
```

#### Test: SBC Binary — Borrow
```
Initial:  A=$20 C=1 D=0
Operation: SBC #$50
Expected: A=$D0 N=1 V=0 Z=0 C=0
Note: $20-$50 = -$30 → A=$D0. Borrow occurred → C=0.
```

#### Test: SBC Binary — With Borrow In
```
Initial:  A=$50 C=0 D=0
Operation: SBC #$20
Expected: A=$2F N=0 V=0 Z=0 C=1
Note: $50-$20-1 = $2F.
```

### 13.4 SBC — Decimal Mode

#### Test: SBC Decimal — Simple BCD Subtract
```
Initial:  A=$50 C=1 D=1
Operation: SBC #$25
Expected: A=$25 N=0 V=0 Z=0 C=1
Note: 50 - 25 = 25 BCD. No borrow → C=1.
```

#### Test: SBC Decimal — BCD Borrow
```
Initial:  A=$10 C=1 D=1
Operation: SBC #$20
Expected: A=$90 N=1 V=0 Z=0 C=0
Note: 10 - 20 = -10 → A=$90 BCD, C=0 (borrow).
      Z=0 (NMOS: binary $10-$20=$F0, non-zero).
      N=1 (from binary result bit 7).
```

### 13.5 Logical Operations

#### Test: AND
```
Initial:  A=$FF
Operation: AND #$0F
Expected: A=$0F N=0 Z=0
```

#### Test: ORA
```
Initial:  A=$F0
Operation: ORA #$0F
Expected: A=$FF N=1 Z=0
```

#### Test: EOR
```
Initial:  A=$FF
Operation: EOR #$FF
Expected: A=$00 N=0 Z=1
```

### 13.6 Shift and Rotate

#### Test: ASL — Accumulator
```
Initial:  A=$80
Operation: ASL A
Expected: A=$00 N=0 Z=1 C=1
Note: Bit 7 ($80) shifts into C.
```

#### Test: LSR — Accumulator
```
Initial:  A=$01
Operation: LSR A
Expected: A=$00 N=0 Z=1 C=1
Note: Bit 0 shifts into C.
```

#### Test: ROL — With Carry
```
Initial:  A=$80 C=1
Operation: ROL A
Expected: A=$01 N=0 Z=0 C=1
Note: Old C (1) rotates into bit 0. Old bit 7 (1) rotates into C.
```

#### Test: ROR — With Carry
```
Initial:  A=$01 C=1
Operation: ROR A
Expected: A=$80 N=1 Z=0 C=1
Note: Old C (1) rotates into bit 7. Old bit 0 (1) rotates into C.
```

### 13.7 Increment and Decrement

#### Test: INC — Wrap Around
```
Initial:  Memory[$10]=$FF
Operation: INC $10
Expected: Memory[$10]=$00 N=0 Z=1
```

#### Test: DEC — Wrap Around
```
Initial:  Memory[$10]=$00
Operation: DEC $10
Expected: Memory[$10]=$FF N=1 Z=0
```

#### Test: INX — Wrap Around
```
Initial:  X=$FF
Operation: INX
Expected: X=$00 N=0 Z=1
```

### 13.8 Compare

#### Test: CMP — Equal
```
Initial:  A=$42
Operation: CMP #$42
Expected: N=0 Z=1 C=1
```

#### Test: CMP — Greater
```
Initial:  A=$42
Operation: CMP #$20
Expected: N=0 Z=0 C=1
Note: $42-$20=$22, positive result.
```

#### Test: CMP — Less
```
Initial:  A=$20
Operation: CMP #$42
Expected: N=1 Z=0 C=0
Note: $20-$42=$DE, bit 7 set → N=1. A < M → C=0.
```

### 13.9 Branch Instructions

#### Test: BEQ — Taken, Same Page
```
Initial:  PC=$0200 Z=1
Memory: $0200: $F0 $05 (BEQ +5)
Expected: PC=$0207 Cycles=3
Note: $0202 + $05 = $0207. Same page → 3 cycles.
```

#### Test: BEQ — Taken, Page Cross Forward
```
Initial:  PC=$02F0 Z=1
Memory: $02F0: $F0 $20 (BEQ +32)
Expected: PC=$0312 Cycles=4
Note: $02F2 + $20 = $0312. Page crossed ($02 → $03) → 4 cycles.
```

#### Test: BNE — Not Taken
```
Initial:  PC=$0200 Z=1
Memory: $0200: $D0 $05 (BNE +5)
Expected: PC=$0202 Cycles=2
Note: Z=1, so BNE not taken → 2 cycles.
```

#### Test: BPL — Taken, Page Cross Backward
```
Initial:  PC=$0300 N=0
Memory: $0300: $10 $FC (BPL -4)
Expected: PC=$02FE Cycles=4
Note: $0302 + (-4) = $02FE. Page crossed ($03 → $02) → 4 cycles.
```

### 13.10 JMP Indirect — Bug Test

#### Test: JMP Indirect — Normal
```
Initial:  PC=$0200
Memory: $0200: $6C $00 $03 (JMP ($0300))
         $0300: $40
         $0301: $80
Expected: PC=$8040
Note: Normal indirect jump — low byte from $0300, high byte from $0301.
```

#### Test: JMP Indirect — Page Boundary Bug
```
Initial:  PC=$0200
Memory: $0200: $6C $FF $02 (JMP ($02FF))
         $02FF: $40
         $0300: $80  ← NOT used
         $0200: $50  ← Used for high byte (wraps to $0200)
Expected: PC=$5040
Note: Bug! Low byte from $02FF ($40), high byte from $0200 ($50), NOT $0300.
```

### 13.11 Stack Operations

#### Test: PHA / PLA Round-Trip
```
Initial:  A=$42 SP=$FF
Operation: PHA
Expected: Memory[$01FF]=$42 SP=$FE

Operation: PLA
Expected: A=$42 SP=$FF N=0 Z=0
```

#### Test: PHP / PLP — B Flag Behavior
```
Initial:  P=$00 (all flags clear)
Operation: PHP
Expected: Memory[stack] = $30 (bits 4 and 5 set: B=1, unused=1)
Note: P register itself is unchanged ($00).

Operation: PLP (pulling $30 back)
Expected: P = $00 (bits 4 and 5 are ignored on pull)
Note: Only N, V, D, I, Z, C are restored from stack.
```

### 13.12 BRK

#### Test: BRK — Basic Operation
```
Initial:  PC=$0200 SP=$FF P=$00
Memory: $0200: $00 $EA (BRK, padding byte $EA)
         $FFFE: $00 $04 (IRQ vector = $0400)
Expected:
  Memory[$01FF] = $02 (PCH of $0202)
  Memory[$01FE] = $02 (PCL of $0202)
  Memory[$01FD] = $30 (P with B=1, bit5=1)
  SP = $FC
  PC = $0400
  I = 1
Cycles: 7
```

### 13.13 Flag Instructions

#### Test: CLC / SEC
```
Operation: SEC
Expected: C=1
Operation: CLC
Expected: C=0
```

#### Test: CLV
```
Initial:  V=1
Operation: CLV
Expected: V=0
```

#### Test: CLD / SED
```
Operation: SED
Expected: D=1
Operation: CLD
Expected: D=0
```

### 13.14 BIT Test

#### Test: BIT — Zero Result
```
Initial:  A=$0F
Memory: $10=$F0
Operation: BIT $10
Expected: Z=1 N=1 V=1
Note: A & M = $0F & $F0 = $00 → Z=1. N = bit 7 of M ($F0) = 1. V = bit 6 of M ($F0) = 1.
```

#### Test: BIT — Non-Zero Result
```
Initial:  A=$FF
Memory: $10=$3F
Operation: BIT $10
Expected: Z=0 N=0 V=0
Note: A & M = $FF & $3F = $3F → Z=0. N = bit 7 of M ($3F) = 0. V = bit 6 of M ($3F) = 0.
```

#### Test: BIT — Mixed
```
Initial:  A=$80
Memory: $10=$C0
Operation: BIT $10
Expected: Z=0 N=1 V=1
Note: A & M = $80 & $C0 = $80 → Z=0. N = bit 7 of M = 1. V = bit 6 of M = 1.
```

---

## 14. Testing and Verification

### 14.1 Test Suites

#### Klaus Dormann's 6502 Functional Test

The most widely used 6502 verification suite. A single assembly program that exercises
every documented opcode.

**How it works:** The test runs from address $0400. Each section sets up inputs, executes
an instruction, and compares results. On failure, execution traps in a tight `JMP *`
loop. On success, PC reaches a known success address.

**Detection:**
- **Pass:** PC reaches the success address (typically $3469)
- **Fail:** PC stops advancing (trapped in a 2-byte loop); the trap address identifies
  which test failed

**Usage:**
1. Load the 64KB binary image at $0000
2. Set PC to $0400
3. Run until PC reaches success address or stops advancing
4. Optional: disable decimal tests initially (`disable_decimal` configuration)

**Repository:** `github.com/Klaus2m5/6502_65C02_functional_tests`

#### Tom Harte's ProcessorTests (SingleStepTests)

JSON-based cycle-accurate test suite providing 10,000 test cases per opcode (2,560,000
total). The gold standard for cycle-level accuracy.

**Format per test case:**

```json
{
  "name": "A9 0001",
  "initial": {
    "pc": 1234, "s": 253, "a": 0, "x": 0, "y": 0, "p": 36,
    "ram": [[1234, 169], [1235, 66]]
  },
  "final": {
    "pc": 1236, "s": 253, "a": 66, "x": 0, "y": 0, "p": 36,
    "ram": [[1234, 169], [1235, 66]]
  },
  "cycles": [
    [1234, 169, "read"],
    [1235, 66, "read"]
  ]
}
```

**Usage:**
1. Load initial state (registers + RAM)
2. Execute exactly one instruction
3. Compare final state (registers + RAM)
4. Optionally verify the cycle-by-cycle bus trace

**Repository:** `github.com/SingleStepTests/ProcessorTests`

#### Acid800

Atari-specific system-level test suite by Avery Lee (author of Altirra). Tests
ANTIC/GTIA/POKEY/PIA behavior and CPU-ANTIC interaction timing. Useful after the CPU
core passes functional tests, to verify system integration.

### 14.2 Recommended Testing Order

**Phase 1 — Infrastructure and basic instructions:**
- Memory bus, registers, PC advancement
- NOP, LDA/STA/LDX/STX/LDY/STY (immediate, zero page, absolute)
- TAX, TAY, TXA, TYA, TSX, TXS
- Verify N, Z flags for loads and transfers

**Phase 2 — Arithmetic and logic:**
- AND, ORA, EOR (immediate first, then all modes)
- ADC, SBC (binary mode only)
- CMP, CPX, CPY
- INC, DEC, INX, DEX, INY, DEY
- ASL, LSR, ROL, ROR (accumulator, then memory)

**Phase 3 — Control flow:**
- JMP absolute, JMP indirect (test page boundary bug)
- JSR, RTS
- All 8 branch instructions
- BRK, RTI

**Phase 4 — Stack and flags:**
- PHA, PLA, PHP, PLP
- SEC, CLC, SED, CLD, SEI, CLI, CLV
- BIT

**Phase 5 — Complete addressing modes:**
- Zero Page,X / Zero Page,Y (verify wrapping)
- Absolute,X / Absolute,Y (verify page crossing)
- (Indirect,X) / (Indirect),Y (verify zero page wrapping)

**Phase 6 — Decimal mode:**
- ADC in decimal mode
- SBC in decimal mode
- Verify NMOS flag behavior (N, V, Z from binary result)

**Phase 7 — Cycle accuracy:**
- Add cycle counting
- Implement dummy reads/writes
- RMW write-back behavior
- Branch page crossing timing

**Phase 8 — Undocumented opcodes (if needed):**
- Implement stable illegal opcodes used by Atari software
- JAM detection

**When to run each suite:**
- After Phase 3: Run Klaus Dormann with decimal mode disabled
- After Phase 6: Run Klaus Dormann with decimal mode enabled
- After Phase 7: Run Tom Harte's ProcessorTests
- After Phase 8: Run Tom Harte's tests for undocumented opcodes

### 14.3 Common Implementation Bugs

| Bug | Description | Test to Catch |
|-----|-------------|---------------|
| BRK return address off-by-one | BRK pushes PC+2, not PC+1 | Klaus Dormann |
| PHP B flag | PHP always pushes B=1, bit5=1 | Klaus Dormann |
| SBC carry sense | SBC = ADC(~M), carry must be included | Klaus Dormann |
| V flag formula | `V = (A^result) & (operand^result) & $80` | Klaus Dormann |
| BIT N/V from memory | N=M[7], V=M[6], not from AND result | Klaus Dormann |
| JMP indirect wrap | $xxFF wraps to $xx00, not $(xx+1)00 | Klaus Dormann |
| Decimal Z flag | Z from binary result, not BCD (NMOS) | Klaus Dormann |
| RMW write-back | Original value written before modified | Tom Harte |
| Indexed store timing | STA abs,X always 5 cycles | Tom Harte |
| Stack reset state | S = $FD after reset, not $FF | Manual |
| I flag not clearing D | NMOS interrupts leave D unchanged | Manual |
| Zero page wrapping | (zp+X) & $FF in indexed modes | Klaus Dormann |
| Branch page cross | +1 cycle when target on different page | Tom Harte |
| CLI/SEI interrupt delay | IRQ delayed one instruction after CLI | Tom Harte |

### 14.4 Decimal Mode Testing

Bruce Clark's "Decimal Mode in NMOS 6502" provides test vectors covering all 131,072
input combinations for ADC and SBC in decimal mode. Available at:
`6502.org/tutorials/decimal_mode.html`

### 14.5 Test Verification Pseudocode

For automated testing against Tom Harte's suite:

```
for each test_case in test_file:
    // Setup
    cpu.reset()
    cpu.PC = test_case.initial.pc
    cpu.A  = test_case.initial.a
    cpu.X  = test_case.initial.x
    cpu.Y  = test_case.initial.y
    cpu.S  = test_case.initial.s
    cpu.P  = test_case.initial.p
    for (addr, value) in test_case.initial.ram:
        memory[addr] = value

    // Execute one instruction
    cycles_used = cpu.step()

    // Verify final state
    assert cpu.PC == test_case.final.pc
    assert cpu.A  == test_case.final.a
    assert cpu.X  == test_case.final.x
    assert cpu.Y  == test_case.final.y
    assert cpu.S  == test_case.final.s
    assert cpu.P  == test_case.final.p
    for (addr, value) in test_case.final.ram:
        assert memory[addr] == value

    // Optionally verify cycle trace
    assert cycles_used == len(test_case.cycles)
    for i, (addr, data, rw) in enumerate(test_case.cycles):
        assert bus_log[i].address == addr
        assert bus_log[i].data    == data
        assert bus_log[i].rw      == rw
```

---

## 15. References

1. John Pickens, "NMOS 6502 Opcodes" — [6502.org Tutorials](http://www.6502.org/tutorials/6502opcodes.html)
2. Andrew Jacobs, "6502 Addressing Modes" — [NesDev / Obelisk 6502 Guide](https://www.nesdev.org/obelisk-6502-guide/addressing.html)
3. NESdev Wiki, "Status Flags" — [NESdev Wiki](https://www.nesdev.org/wiki/Status_flags)
4. Norbert Landsteiner, '6502 "Illegal" Opcodes Demystified' — [mass:werk](https://www.masswerk.at/nowgobang/2021/6502-illegal-opcodes)
5. Michael Steil, "How MOS 6502 Illegal Opcodes Really Work" — [pagetable.com](https://www.pagetable.com/?p=39)
6. Bruce Clark, "6502 Decimal Mode" — [6502.org Tutorials](http://6502.org/tutorials/decimal_mode.html)
7. NESdev / Visual6502 Wiki, "6502 Timing of Interrupt Handling" — [NESdev Wiki](https://www.nesdev.org/wiki/Visual6502wiki/6502_Timing_of_Interrupt_Handling)
8. 6502.org, "Investigating Interrupts" — [6502.org Tutorials](http://6502.org/tutorials/interrupts.html)
9. Atari Archives, "The XL/XE Memory Map" — [Atari Archives](https://www.atariarchives.org/mapping/appendix12.php)
10. AtariWiki, "Atari Memory Map" — [AtariWiki](https://atariwiki.org/wiki/Wiki.jsp?page=Memory+Map)
11. US Home Automation, "Atari 600XL/800XL & 65816 — SALLY Details" — [ushomeautomation.com](https://ushomeautomation.com/Projects/Atari/65816.html)
12. Ken Shirriff, "6502 Overflow Flag Explained" — [righto.com](http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html)
13. Wikipedia, "Atari 8-bit Computers" — [Wikipedia](https://en.wikipedia.org/wiki/Atari_8-bit_computers)
14. MOS Technology, "MOS 6502 Datasheet" — [Princeton University](https://www.princeton.edu/~mae412/HANDOUTS/Datasheets/6502.pdf)
15. Tom Harte, "Processor Tests — 6502" — [GitHub](https://github.com/TomHarte/ProcessorTests/tree/main/6502)
16. Klaus Dormann, "6502 Functional Tests" — [GitHub](https://github.com/Klaus2m5/6502_65C02_functional_tests)
17. Avery Lee, "Acid800 Test Suite" — [Altirra](https://www.virtualdub.org/altirra.html)

---

*End of MOS 6502 CPU Specification — SALLY/6502C (Atari 800XL)*
*Document version 1.0.0 — Generated 2026-03-27*
