---
name: 6502-spec
description: Look up 6502 CPU details — opcodes, addressing modes, cycle timing, flags, interrupts, hardware registers, undocumented opcodes, or test vectors. Use when working on emulator core, assembler, disassembler, monitor, or debugging 6502 code.
allowed-tools: Read, Grep
argument-hint: [topic or mnemonic]
---

# 6502 CPU Specification Reference

Look up information from the comprehensive 6502 CPU specification for the Atari 800XL (SALLY/6502C variant).

## How to use

The user's query is: `$ARGUMENTS`

1. **If a specific mnemonic** (e.g., `ADC`, `LDA`, `BNE`): use Grep to find `^#### <MNEMONIC> —` in the spec file, then Read ~30 lines from that offset to get the full instruction entry.

2. **If a topic keyword**: match it to a section below and Read the corresponding line range.

3. **If no arguments**: list the available topics from the section map below.

## Specification file

**Path:** `docs/6502_SPECIFICATION.md`

## Section Map

Use these line ranges with `Read(offset, limit)` to load the relevant section:

| Topic | Section | Lines | Range |
|-------|---------|-------|-------|
| Architecture & SALLY variant | 1 | 21-55 | ~35 lines |
| Registers | 2 | 56-82 | ~27 lines |
| Status flags (P register) | 3 | 83-119 | ~37 lines |
| Addressing modes | 4 | 120-261 | ~142 lines |
| **Instruction set (all)** | **5** | **262-1576** | **~1315 lines** |
| ��� Arithmetic (ADC, SBC) | 5.1 | 274-344 | ~71 lines |
| — Logical (AND, ORA, EOR) | 5.2 | 345-430 | ~86 lines |
| — Shift/Rotate (ASL, LSR, ROL, ROR) | 5.3 | 431-566 | ~136 lines |
| — Inc/Dec (INC, DEC, INX, DEX, INY, DEY) | 5.4 | 567-694 | ~128 lines |
| — Compare (CMP, CPX, CPY, BIT) | 5.5 | 695-776 | ~82 lines |
| — Load/Store (LDA, LDX, LDY, STA, STX, STY) | 5.6 | 777-919 | ~143 lines |
| — Transfer (TAX, TXA, TAY, TYA, TSX, TXS) | 5.7 | 920-1035 | ~116 lines |
| — Stack (PHA, PLA, PHP, PLP) | 5.8 | 1036-1118 | ~83 lines |
| — Branch (BPL, BMI, BVC, BVS, BCC, BCS, BNE, BEQ) | 5.9 | 1119-1271 | ~153 lines |
| — Jump/Call (JMP, JSR, RTS, RTI) | 5.10 | 1272-1374 | ~103 lines |
| — Flag instructions (CLC, SEC, CLI, SEI, CLV, CLD, SED) | 5.11 | 1375-1501 | ~127 lines |
| — Misc (BIT, BRK, NOP) | 5.12 | 1502-1576 | ~75 lines |
| Complete opcode matrix (16x16) | 6 | 1577-1868 | ~292 lines |
| Cycle-by-cycle bus activity | 7 | 1869-2242 | ~374 lines |
| Interrupt handling (Reset, IRQ, NMI, BRK) | 8 | 2243-2321 | ~79 lines |
| Decimal (BCD) mode | 9 | 2322-2431 | ~110 lines |
| Undocumented / illegal opcodes | 10 | 2432-2886 | ~455 lines |
| Atari 800XL memory map | 11.1-11.3 | 2887-2934 | ~48 lines |
| Hardware registers (ANTIC, GTIA, POKEY, PIA) | 11.4 | 2935-3041 | ~107 lines |
| ANTIC DMA, timing, WSYNC | 11.5-11.7 | 3042-3092 | ~51 lines |
| Interrupt sources & OS dispatch | 11.8-11.9 | 3093-3137 | ~45 lines |
| Edge cases & emulator notes | 12 | 3138-3216 | ~79 lines |
| Test vectors | 13 | 3217-3584 | ~368 lines |
| Testing & verification (suites, order, bugs) | 14 | 3586-3766 | ~181 lines |
| References | 15 | 3768-3791 | ~24 lines |

## Companion document

For assembler, disassembler, and breakpoint **implementation details** (Swift code, data structures), read `docs/ASSEM_DISSASSEM.md` instead.

## Keyword-to-section mapping

When the user's query matches one of these keywords, read the corresponding section:

- `opcode`, `matrix`, `hex`, `lookup` → Section 6 (opcode matrix)
- `cycle`, `timing`, `bus` → Section 7 (cycle-by-cycle bus activity)
- `interrupt`, `irq`, `nmi`, `reset`, `vector` → Section 8 (interrupt handling)
- `decimal`, `bcd` → Section 9 (decimal mode)
- `illegal`, `undocumented`, `unofficial` → Section 10 (undocumented opcodes)
- `memory map`, `address space` → Section 11.1-11.3
- `antic`, `gtia`, `pokey`, `pia`, `hardware`, `register` → Section 11.4
- `dma`, `wsync`, `scan line` → Section 11.5-11.7
- `edge case`, `bug`, `quirk` → Section 12
- `test vector` → Section 13
- `test suite`, `verification`, `dormann`, `harte` → Section 14
- `flag`, `status`, `N`, `V`, `Z`, `C` (alone) → Section 3
- `addressing`, `mode`, `zero page`, `indirect`, `indexed` → Section 4
- `assembler`, `disassembler`, `breakpoint` → companion doc `docs/ASSEM_DISSASSEM.md`
- Any 3-letter mnemonic (e.g., `ADC`, `LDA`) → Grep for it in section 5
