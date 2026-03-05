"""DOS mode handler for disk management and file operations.

Handles mounting/unmounting disk images, directory listings, file
operations (copy, rename, delete), and disk creation/formatting.
"""

from ..cli_client import CLISocketClient
from ..protocol import MULTI_LINE_SEP
from ..translator import translate_dos
from .base import BaseMode


class DosMode(BaseMode):
    """DOS mode for ATR disk image management.

    Provides commands for mounting drives, browsing directories,
    manipulating files on Atari disk images, and creating new disks.
    """

    def __init__(self) -> None:
        self.current_drive = 1

    def handle(self, line: str, client: CLISocketClient) -> str | None:
        """Process a DOS mode command."""
        commands = translate_dos(line)
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

                # Track drive changes
                if cmd.startswith("dos cd ") and payload.startswith("D"):
                    try:
                        self.current_drive = int(payload[1:payload.index(":")])
                    except (ValueError, IndexError):
                        pass

                # Track unmount of current drive
                if cmd.startswith("unmount "):
                    try:
                        drive_num = int(cmd.split()[1])
                        if drive_num == self.current_drive:
                            self.current_drive = 1
                    except (ValueError, IndexError):
                        pass

                if MULTI_LINE_SEP in payload:
                    results.append(payload.replace(MULTI_LINE_SEP, "\n"))
                else:
                    results.append(payload)

            except Exception as exc:
                results.append(f"[red]Error:[/red] {exc}")
                break

        return "\n".join(results) if results else None

    def prompt(self) -> str:
        return f"[dos] D{self.current_drive}:> "

    def completions(self) -> list[str]:
        return [
            "mount", "unmount", "umount", "drives", "cd",
            "dir", "info", "type", "dump",
            "copy", "cp", "rename", "ren", "delete", "del",
            "lock", "unlock",
            "export", "import",
            "newdisk", "format",
        ]
