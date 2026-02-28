"""BASIC mode handler for program editing and execution.

Handles line entry, listing, running, variables, and file operations
for both standard Atari BASIC and Turbo BASIC XL.
"""

from ..cli_client import CLISocketClient
from ..protocol import MULTI_LINE_SEP
from ..translator import translate_basic
from .base import BaseMode


class BasicMode(BaseMode):
    """BASIC mode for entering and managing BASIC programs.

    Supports numbered line entry (injected as keystrokes), program
    listing with ATASCII rendering, and file operations on both
    ATR disk images and the host filesystem.
    """

    def __init__(self, *, turbo: bool = False) -> None:
        self.turbo = turbo

    def handle(self, line: str, client: CLISocketClient) -> str | None:
        """Process a BASIC mode command."""
        commands = translate_basic(line, atascii=True)
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

                if MULTI_LINE_SEP in payload:
                    results.append(payload.replace(MULTI_LINE_SEP, "\n"))
                else:
                    results.append(payload)

            except Exception as exc:
                results.append(f"[red]Error:[/red] {exc}")
                break

        return "\n".join(results) if results else None

    def prompt(self) -> str:
        if self.turbo:
            return "[basic:turbo] > "
        return "[basic] > "

    def completions(self) -> list[str]:
        return [
            "list", "del", "run", "stop", "cont", "new",
            "vars", "var", "info", "renum",
            "save", "load", "import", "export", "dir",
        ]
