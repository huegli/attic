"""Monitor mode handler for 6502 debugging.

Handles register display, memory dumps, disassembly, breakpoints,
and interactive assembly with syntax-highlighted output.
"""

from ..cli_client import CLISocketClient
from ..display import format_disassembly, format_memory_dump, format_registers
from ..protocol import MULTI_LINE_SEP
from ..translator import translate_monitor
from .base import BaseMode

# Commands that produce disassembly output
_DISASM_COMMANDS = {"disassemble"}
# Commands that produce memory dump output
_MEMORY_COMMANDS = {"read"}
# Commands that produce register output
_REGISTER_COMMANDS = {"registers"}

# Number of hex bytes shown per row in memory dumps
_DUMP_BYTES_PER_ROW = 16


def _format_raw_data(cmd: str, payload: str) -> str:
    """Convert raw 'data XX,XX,...' server response into formatted hex dump lines.

    The server returns comma-separated hex bytes (e.g. 'data A9,00,8D,...').
    format_memory_dump() expects lines like '$0600: A9 00 8D ...'.
    This function bridges the two by extracting the start address from the
    original 'read' command and grouping bytes into rows.
    """
    # Extract start address from command: "read $0600 16" → "$0600"
    cmd_parts = cmd.split()
    try:
        addr = int(cmd_parts[1].lstrip("$"), 16) if len(cmd_parts) > 1 else 0
    except ValueError:
        addr = 0

    # Strip "data " prefix and split comma-separated hex bytes
    data_str = payload[5:] if payload.startswith("data ") else payload
    byte_strs = [b.strip() for b in data_str.split(",") if b.strip()]

    # Group into rows of _DUMP_BYTES_PER_ROW and format as "$ADDR: HH HH ..."
    lines = []
    for i in range(0, len(byte_strs), _DUMP_BYTES_PER_ROW):
        row = byte_strs[i : i + _DUMP_BYTES_PER_ROW]
        lines.append(f"${addr + i:04X}: {' '.join(row)}")

    return MULTI_LINE_SEP.join(lines)


class MonitorMode(BaseMode):
    """Monitor (debugger) mode for 6502 CPU inspection and control.

    Provides commands for execution control, register manipulation,
    memory inspection, disassembly, breakpoints, and assembly.
    """

    def handle(self, line: str, client: CLISocketClient) -> str | None:
        """Process a monitor mode command with formatted output.

        Translates the user input, sends protocol commands, and applies
        display formatting (syntax-highlighted disassembly, heat-mapped
        memory dumps, colored registers).
        """
        commands = translate_monitor(line)
        results = []

        for cmd in commands:
            try:
                response = client.send(cmd)
                if not response.success:
                    results.append(f"[red]Error:[/red] {response.payload}")
                    break

                payload = response.payload
                if not payload:
                    continue

                # Apply format based on command type
                cmd_word = cmd.split()[0] if cmd else ""

                if cmd_word in _DISASM_COMMANDS:
                    results.append(format_disassembly(payload))
                elif cmd_word in _MEMORY_COMMANDS:
                    # Server returns raw "data XX,XX,..."; convert to
                    # addressed lines before applying color formatting.
                    formatted = _format_raw_data(cmd, payload)
                    results.append(format_memory_dump(formatted))
                elif cmd_word in _REGISTER_COMMANDS and "=" in payload:
                    results.append(format_registers(payload))
                elif MULTI_LINE_SEP in payload:
                    results.append(payload.replace(MULTI_LINE_SEP, "\n"))
                else:
                    results.append(payload)

            except Exception as exc:
                results.append(f"[red]Error:[/red] {exc}")
                break

        return "\n".join(results) if results else None

    def prompt(self) -> str:
        return "[monitor] > "

    def completions(self) -> list[str]:
        return [
            "g", "s", "p", "pause", "until",
            "r", "m", ">", "f",
            "d", "a",
            "b", "bp", "bc", "bl",
        ]
