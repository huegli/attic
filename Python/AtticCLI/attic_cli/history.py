"""History file management for the Attic REPL.

Uses prompt_toolkit's FileHistory to persist command history to
~/.attic_history. This is compatible with the Swift CLI's libedit
history format, so users switching between CLIs keep their history.
"""

import os

from prompt_toolkit.history import FileHistory

# Shared history file — used by both Swift and Python CLIs.
HISTORY_PATH = os.path.expanduser("~/.attic_history")

# Maximum entries kept in the history file.
MAX_HISTORY_ENTRIES = 500


def get_history() -> FileHistory:
    """Return a FileHistory instance for the REPL.

    Creates the history file if it doesn't exist.
    """
    return FileHistory(HISTORY_PATH)
