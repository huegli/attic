"""Monitor mode handler for 6502 debugging.

Handles register display, memory dumps, disassembly, breakpoints,
and interactive assembly with syntax-highlighted output.
"""

from ..cli_client import CLISocketClient
from ..display import format_monitor_response
from ..protocol import MULTI_LINE_SEP
from ..translator import translate_monitor
from .base import BaseMode


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

                # Apply monitor-specific formatting (disassembly,
                # memory dump, registers) via shared display logic.
                formatted = format_monitor_response(cmd, payload)
                if formatted:
                    results.append(formatted)
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
