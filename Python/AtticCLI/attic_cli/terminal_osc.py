"""OSC escape sequence helpers for modern terminal integration.

OSC (Operating System Command) sequences enable rich terminal features
beyond basic text output. All target terminals (iTerm2, Ghostty) support
these sequences.

Sequences implemented:
- OSC 8:   Clickable hyperlinks
- OSC 9:   Desktop notifications
- OSC 9;4: Title-bar progress indicator
- OSC 52:  Copy to system clipboard
"""

import base64
import sys


def osc8_link(url: str, text: str) -> str:
    """Return text wrapped in an OSC 8 clickable hyperlink.

    The returned string contains escape codes that make the text
    clickable in terminals supporting OSC 8 (iTerm2, Ghostty, etc.).

    Args:
        url: The URL to link to (can be a file:// URL for local paths).
        text: The visible link text.
    """
    return f"\033]8;;{url}\033\\{text}\033]8;;\033\\"


def osc8_file_link(path: str, text: str | None = None) -> str:
    """Return text wrapped in an OSC 8 link to a local file.

    Args:
        path: Absolute filesystem path.
        text: Visible text. Defaults to the path itself.
    """
    display = text if text is not None else path
    return osc8_link(f"file://{path}", display)


def osc9_notify(message: str) -> None:
    """Send a desktop notification via OSC 9.

    Works in iTerm2 and Ghostty. The notification appears as a
    system-level alert.

    Args:
        message: The notification message text.
    """
    sys.stdout.write(f"\033]9;{message}\033\\")
    sys.stdout.flush()


def osc9_4_progress(value: int, max_value: int = 100) -> None:
    """Set the title-bar progress indicator via OSC 9;4.

    Shows a native progress bar in the terminal window's title bar.
    Supported by iTerm2 and Ghostty (v1.2+).

    Args:
        value: Current progress value (0 to max_value).
            Use -1 to clear/remove the progress indicator.
        max_value: Maximum value (default 100, treated as percentage).
    """
    if value < 0:
        # Clear progress
        sys.stdout.write("\033]9;4;0;0\033\\")
    else:
        # st=1 means "progress in progress", value is percentage
        pct = min(100, int(value * 100 / max_value)) if max_value > 0 else 0
        sys.stdout.write(f"\033]9;4;1;{pct}\033\\")
    sys.stdout.flush()


def osc52_copy(text: str) -> None:
    """Copy text to the system clipboard via OSC 52.

    Works in iTerm2 and Ghostty. The terminal handles the clipboard
    operation — no pbcopy needed.

    Args:
        text: The text to copy to the clipboard.
    """
    encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
    sys.stdout.write(f"\033]52;c;{encoded}\033\\")
    sys.stdout.flush()
