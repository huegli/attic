"""Base mode class with shared command handling.

All REPL modes (monitor, BASIC, DOS) inherit from BaseMode and implement
the handle() and prompt() methods.
"""

from abc import ABC, abstractmethod

from ..cli_client import CLISocketClient


class BaseMode(ABC):
    """Abstract base class for REPL modes.

    Each mode defines how user input is translated to protocol commands
    and how the prompt is rendered.
    """

    @abstractmethod
    def handle(self, line: str, client: CLISocketClient) -> str | None:
        """Process a line of user input.

        Args:
            line: The raw input line from the user.
            client: Connected socket client for sending commands.

        Returns:
            Display text to show the user, or None for no output.
        """

    @abstractmethod
    def prompt(self) -> str:
        """Return the mode-specific prompt string.

        The prompt follows the format: [mode] context>
        For example: [monitor] $E000>
        """

    @abstractmethod
    def completions(self) -> list[str]:
        """Return available command names for tab completion."""
