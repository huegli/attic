"""Output formatting for rich terminal display.

Provides Rich-powered formatting for hex dumps, disassembly, registers,
ATASCII text, and other emulator output. Designed for true-color terminals
(iTerm2, Ghostty).
"""

from rich.console import Console
from rich.style import Style
from rich.text import Text

from .protocol import MULTI_LINE_SEP

console = Console()

# --- Instruction category colors for 6502 disassembly ---

# Load/Store: blue
_LOAD_STORE = {"LDA", "LDX", "LDY", "STA", "STX", "STY"}
# Arithmetic/Logic: green
_ARITHMETIC = {
    "ADC", "SBC", "AND", "ORA", "EOR", "ASL", "LSR", "ROL", "ROR",
    "INC", "DEC", "INX", "INY", "DEX", "DEY", "CMP", "CPX", "CPY",
    "BIT",
}
# Branch/Jump: yellow
_BRANCH = {
    "JMP", "JSR", "RTS", "RTI", "BCC", "BCS", "BEQ", "BNE",
    "BMI", "BPL", "BVC", "BVS",
}
# Stack: magenta
_STACK = {"PHA", "PLA", "PHP", "PLP", "TXS", "TSX"}
# Flag: cyan
_FLAG = {"CLC", "SEC", "CLD", "SED", "CLI", "SEI", "CLV"}
# Transfer: white
_TRANSFER = {"TAX", "TAY", "TXA", "TYA"}
# System: red
_SYSTEM = {"BRK", "NOP"}


def _mnemonic_color(mnemonic: str) -> str:
    """Return a Rich color name for a 6502 mnemonic."""
    upper = mnemonic.upper()
    if upper in _LOAD_STORE:
        return "blue"
    if upper in _ARITHMETIC:
        return "green"
    if upper in _BRANCH:
        return "yellow"
    if upper in _STACK:
        return "magenta"
    if upper in _FLAG:
        return "cyan"
    if upper in _TRANSFER:
        return "white"
    if upper in _SYSTEM:
        return "red"
    return "white"


def format_disassembly(raw: str) -> str:
    """Format disassembly output with syntax highlighting.

    Input format (one line per instruction):
        $E000  A9 00     LDA #$00

    Returns Rich markup string with colored mnemonics.
    """
    lines = split_multiline(raw)
    result_lines = []

    for line in lines:
        # Try to parse the disassembly format
        parts = line.split()
        if len(parts) >= 3 and parts[0].startswith("$"):
            # Address and hex bytes are dim
            addr = parts[0]
            # Find the mnemonic (first uppercase 3-letter word after hex bytes)
            mnemonic_idx = None
            for i, part in enumerate(parts[1:], 1):
                # Hex bytes are 2 chars; mnemonic is 3 uppercase letters
                if len(part) == 3 and part.isalpha():
                    mnemonic_idx = i
                    break

            if mnemonic_idx is not None:
                mnemonic = parts[mnemonic_idx]
                color = _mnemonic_color(mnemonic)
                hex_bytes = " ".join(parts[1:mnemonic_idx])
                operand = " ".join(parts[mnemonic_idx + 1 :])

                formatted = (
                    f"[dim]{addr}[/dim]  "
                    f"[dim]{hex_bytes:<10s}[/dim]"
                    f"[{color}]{mnemonic}[/{color}]"
                )
                if operand:
                    formatted += f" {operand}"
                result_lines.append(formatted)
                continue

        # Fallback: return line as-is
        result_lines.append(line)

    return "\n".join(result_lines)


def format_registers(raw: str) -> str:
    """Format register display with highlighting.

    Input format: A=$FF X=$00 Y=$00 S=$FD P=$34 PC=$E000

    Returns Rich markup string with register names bold and values colored.
    """
    parts = raw.split()
    formatted = []

    for part in parts:
        if "=" in part:
            name, value = part.split("=", 1)
            formatted.append(f"[bold]{name}[/bold]=[cyan]{value}[/cyan]")
        else:
            formatted.append(part)

    return "  ".join(formatted)


def format_memory_dump(raw: str) -> str:
    """Format a memory dump with heat-map coloring.

    Input format: $0600: A9 00 8D 00 D4 ...

    Zero bytes are dimmed; non-zero bytes are shown in brighter colors.
    I/O register addresses ($D000-$D7FF) are highlighted.
    """
    lines = split_multiline(raw)
    result_lines = []

    for line in lines:
        if not line.strip():
            result_lines.append(line)
            continue

        # Try to parse "ADDR: HH HH HH ... | ASCII"
        colon_idx = line.find(":")
        if colon_idx < 0:
            result_lines.append(line)
            continue

        addr_str = line[:colon_idx].strip()
        rest = line[colon_idx + 1 :]

        # Check if this is an I/O address range
        try:
            addr = int(addr_str.lstrip("$"), 16)
            is_io = 0xD000 <= addr <= 0xD7FF
        except ValueError:
            is_io = False

        # Split into hex part and ASCII part
        pipe_idx = rest.find("|")
        if pipe_idx >= 0:
            hex_part = rest[:pipe_idx]
            ascii_part = rest[pipe_idx:]
        else:
            hex_part = rest
            ascii_part = ""

        # Colorize individual hex bytes
        colored_bytes = []
        for token in hex_part.split():
            if len(token) == 2:
                try:
                    val = int(token, 16)
                    if val == 0:
                        colored_bytes.append(f"[dim]{token}[/dim]")
                    elif is_io:
                        colored_bytes.append(f"[bold magenta]{token}[/bold magenta]")
                    else:
                        colored_bytes.append(f"[bold]{token}[/bold]")
                except ValueError:
                    colored_bytes.append(token)
            else:
                colored_bytes.append(token)

        formatted = f"[cyan]{addr_str}[/cyan]: {' '.join(colored_bytes)}"
        if ascii_part:
            formatted += f" [dim]{ascii_part}[/dim]"
        result_lines.append(formatted)

    return "\n".join(result_lines)


def split_multiline(raw: str) -> list[str]:
    """Split a protocol response containing 0x1E separators into lines."""
    if MULTI_LINE_SEP in raw:
        return raw.split(MULTI_LINE_SEP)
    return [raw] if raw else []
