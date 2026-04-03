"""BASIC edit mode with diff-based reimport.

Opens the current BASIC program in an external editor.  When the user saves,
only the *changed* lines are injected back into the emulator -- deleted lines
are removed with a bare line-number injection, and added/modified lines are
injected in full.  This avoids the expensive (and screen-disruptive) pattern
of issuing NEW followed by a complete reimport.

For GUI editors (those that return immediately), a background daemon thread
watches the temp file for modifications and applies diffs automatically.
Terminal editors (vim, nano, etc.) block the REPL; the diff is applied once
when the editor exits.

Thread safety: ``_lock`` serialises all access to ``_previous_content``,
``_watcher_thread``, and ``_watcher_stop`` so the background watcher and
the main REPL thread never conflict.
"""

import logging
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from rich.console import Console

from .cli_client import CLISocketClient, escape_for_inject

logger = logging.getLogger(__name__)
console = Console()

# ---------------------------------------------------------------------------
# Module-level state
# ---------------------------------------------------------------------------

# Content last imported into the emulator (used as the "old" side of the diff).
_previous_content: str = ""

# Background file-watcher for GUI editors.
_watcher_thread: threading.Thread | None = None
_watcher_stop = threading.Event()

# Guards all mutable module state above.
_lock = threading.Lock()

# Client reference kept while the watcher is active so it can inject diffs.
_watcher_client: CLISocketClient | None = None

# Path to the temporary file currently being edited (if any).
_temp_path: str | None = None

# The editor subprocess, tracked so we can auto-stop when it exits.
_editor_proc: subprocess.Popen | None = None

# Known GUI editors -- we detect these to decide whether to watch the file
# in the background (GUI) or block until the process exits (terminal).
_GUI_EDITORS: set[str] = {
    "code", "subl", "sublime_text", "atom", "mate", "gedit", "kate",
    "mousepad", "pluma", "xed", "geany", "bbedit", "open",
}

# Terminal editors that block until the user quits.
_TERMINAL_EDITORS: set[str] = {
    "vim", "nvim", "vi", "nano", "pico", "emacs", "micro", "joe", "ne",
    "helix", "hx", "ed",
}


# ---------------------------------------------------------------------------
# Diff engine
# ---------------------------------------------------------------------------

def _parse_basic_lines(content: str) -> dict[int, str]:
    """Parse BASIC source text into a {line_number: full_line} mapping.

    Blank lines and lines that do not begin with a valid line number are
    silently ignored.  The *full* original line (number + body) is kept as
    the value so it can be injected verbatim.

    Args:
        content: Raw BASIC source text (e.g. from ``basic export``).

    Returns:
        Dictionary mapping line numbers to their complete source lines.
    """
    lines: dict[int, str] = {}
    for raw in content.strip().splitlines():
        raw = raw.strip()
        if not raw:
            continue
        parts = raw.split(None, 1)
        try:
            num = int(parts[0])
            lines[num] = raw
        except (ValueError, IndexError):
            # Not a numbered BASIC line -- skip.
            pass
    return lines


def _diff_programs(
    old_content: str, new_content: str
) -> tuple[list[tuple[int, str]], list[tuple[int, str]], list[int]]:
    """Compute the minimal set of changes between two BASIC programs.

    Args:
        old_content: The program text previously imported.
        new_content: The program text after the user edited it.

    Returns:
        A three-tuple of ``(added, modified, deleted)`` where:

        - *added*    -- list of ``(line_num, full_line)`` for new lines
        - *modified* -- list of ``(line_num, full_line)`` for changed lines
        - *deleted*  -- sorted list of line numbers that were removed
    """
    old = _parse_basic_lines(old_content)
    new = _parse_basic_lines(new_content)

    old_nums = set(old)
    new_nums = set(new)

    added = [(n, new[n]) for n in sorted(new_nums - old_nums)]
    deleted = sorted(old_nums - new_nums)
    modified = [
        (n, new[n]) for n in sorted(old_nums & new_nums) if old[n] != new[n]
    ]

    return added, modified, deleted


# ---------------------------------------------------------------------------
# Injection helpers
# ---------------------------------------------------------------------------

def _reimport_diff(
    client: CLISocketClient,
    old_content: str,
    new_content: str,
) -> str:
    """Apply only the changed lines to the running BASIC program.

    Deleted lines are removed by injecting just the bare line number
    (the standard Atari BASIC way to delete a line).  Added and modified
    lines are injected in full.

    Args:
        client:      Connected CLI socket client.
        old_content: Previous BASIC source text.
        new_content: Updated BASIC source text.

    Returns:
        A human-readable summary of what was applied.
    """
    added, modified, deleted = _diff_programs(old_content, new_content)

    if not added and not modified and not deleted:
        return "[dim]No changes detected[/dim]"

    errors: list[str] = []

    # 1. Delete removed lines (inject bare line number + RETURN).
    for num in deleted:
        escaped = escape_for_inject(f"{num}\n")
        try:
            resp = client.send(f"inject keys {escaped}")
            if not resp.success:
                errors.append(f"delete {num}: {resp.payload}")
        except Exception as exc:
            errors.append(f"delete {num}: {exc}")

    # 2. Add new lines and overwrite modified lines.
    for num, full_line in sorted(added + modified):
        escaped = escape_for_inject(f"{full_line}\n")
        try:
            resp = client.send(f"inject keys {escaped}")
            if not resp.success:
                errors.append(f"line {num}: {resp.payload}")
        except Exception as exc:
            errors.append(f"line {num}: {exc}")

    parts: list[str] = []
    if added:
        parts.append(f"{len(added)} added")
    if modified:
        parts.append(f"{len(modified)} modified")
    if deleted:
        parts.append(f"{len(deleted)} deleted")
    summary = ", ".join(parts)

    if errors:
        err_text = "; ".join(errors)
        return f"Applied ({summary}) with errors: {err_text}"

    return f"Applied: {summary}"


def _reimport_full(client: CLISocketClient, content: str) -> str:
    """Clear the program and reimport all lines from scratch.

    Used on the very first import when there is no previous content to
    diff against.

    Args:
        client:  Connected CLI socket client.
        content: Complete BASIC source text to import.

    Returns:
        A human-readable summary.
    """
    lines = _parse_basic_lines(content)
    if not lines:
        return "[dim]No BASIC lines found in file[/dim]"

    # Issue NEW to clear the current program.
    # After sending NEW + Return, BASIC needs time to process the
    # command and display the "Ready" prompt before we can enter
    # new lines. A brief sleep lets the emulator's main loop catch up.
    escaped_new = escape_for_inject("NEW\n")
    try:
        resp = client.send(f"inject keys {escaped_new}")
        if not resp.success:
            return f"[red]Error sending NEW:[/red] {resp.payload}"
    except Exception as exc:
        return f"[red]Error sending NEW:[/red] {exc}"

    time.sleep(0.5)  # Let BASIC process NEW and show Ready prompt

    errors: list[str] = []
    for num in sorted(lines):
        escaped = escape_for_inject(f"{lines[num]}\n")
        try:
            resp = client.send(f"inject keys {escaped}")
            if not resp.success:
                errors.append(f"line {num}: {resp.payload}")
        except Exception as exc:
            errors.append(f"line {num}: {exc}")

    if errors:
        err_text = "; ".join(errors)
        return f"Imported {len(lines)} lines with errors: {err_text}"

    return f"Imported {len(lines)} lines"


# ---------------------------------------------------------------------------
# Editor detection
# ---------------------------------------------------------------------------

def _detect_editor() -> str:
    """Determine which editor to launch.

    Checks, in order:
    1. ``$VISUAL``
    2. ``$EDITOR``
    3. Falls back to ``vim``

    Returns:
        Editor command string (may include arguments, e.g. ``"code --wait"``).
    """
    for var in ("VISUAL", "EDITOR"):
        value = os.environ.get(var)
        if value:
            return value
    return "vim"


def _is_gui_editor(editor_cmd: str) -> bool:
    """Heuristically decide whether *editor_cmd* is a GUI application.

    GUI editors fork into the background, so the subprocess returns
    immediately.  Terminal editors block until the user quits.

    Args:
        editor_cmd: The editor command (possibly with flags).

    Returns:
        True if the editor is believed to be a GUI app.
    """
    # Extract the bare binary name from the command string.
    binary = Path(editor_cmd.split()[0]).name.lower()
    if binary in _GUI_EDITORS:
        return True
    if binary in _TERMINAL_EDITORS:
        return False
    # Unknown editor -- assume terminal (safer: we block and apply once).
    return False


# ---------------------------------------------------------------------------
# Background file watcher (for GUI editors)
# ---------------------------------------------------------------------------

def _watch_file(path: str, client: CLISocketClient) -> None:
    """Poll *path* for modifications and inject diffs into the emulator.

    Runs on a daemon thread.  Checks the file's mtime every second and,
    when it changes, computes a diff against ``_previous_content`` and
    injects the changes.

    This function is the ``target`` for ``_watcher_thread``.

    Args:
        path:   Path to the temporary BASIC file being edited.
        client: Connected CLI socket client for injecting keys.
    """
    global _previous_content

    last_mtime: float = 0.0
    try:
        last_mtime = os.path.getmtime(path)
    except OSError:
        pass

    while not _watcher_stop.is_set():
        # Sleep in short intervals so we can respond to stop quickly.
        _watcher_stop.wait(timeout=1.0)
        if _watcher_stop.is_set():
            break

        # Auto-stop if the editor process has exited (user closed the
        # file or quit the editor). Requires the editor to keep its
        # process alive while the file is open — for VS Code, set
        # VISUAL="code --wait".
        if _editor_proc is not None and _editor_proc.poll() is not None:
            # Do a final reimport if the file changed since last import
            try:
                current_mtime = os.path.getmtime(path)
                if current_mtime > last_mtime:
                    new_content = Path(path).read_text(encoding="utf-8")
                    with _lock:
                        old = _previous_content
                        result = _reimport_diff(client, old, new_content)
                        _previous_content = new_content
                        console.print(f"\n[dim][edit] Editor exited — {result}[/dim]")
            except OSError:
                pass
            console.print("[dim][edit] Editor exited — watcher stopped[/dim]")
            _watcher_stop.set()
            break

        try:
            current_mtime = os.path.getmtime(path)
        except OSError:
            # File may have been deleted -- editor closed.
            continue

        if current_mtime <= last_mtime:
            continue

        last_mtime = current_mtime

        try:
            new_content = Path(path).read_text(encoding="utf-8")
        except OSError:
            continue

        with _lock:
            old = _previous_content
            result = _reimport_diff(client, old, new_content)
            _previous_content = new_content
            console.print(f"\n[dim][edit][/dim] {result}")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def start_tui_edit(client: CLISocketClient) -> str:
    """Export the current BASIC program and open it in the built-in TUI editor.

    Uses the full-screen prompt_toolkit editor (tui_editor) instead of an
    external editor.  When the user saves (Ctrl+S), only changed lines are
    diffed and reimported.  If the user quits without saving (Ctrl+Q), no
    changes are applied.

    Args:
        client: Connected CLI socket client.

    Returns:
        A status message for the REPL to display.
    """
    global _previous_content

    with _lock:
        if _watcher_thread is not None and _watcher_thread.is_alive():
            return (
                "[dim]External edit session already active. "
                "Use .edit stop to end it first.[/dim]"
            )

    # --- Export current program ---
    fd, tmp_path = tempfile.mkstemp(suffix=".bas", prefix="attic-edit-")
    os.close(fd)

    try:
        resp = client.send(f"basic export {tmp_path}")
        if not resp.success:
            if "no program" in resp.payload.lower():
                Path(tmp_path).write_text("", encoding="utf-8")
            else:
                os.unlink(tmp_path)
                return f"[red]Error exporting BASIC:[/red] {resp.payload}"
    except Exception as exc:
        os.unlink(tmp_path)
        return f"[red]Error exporting BASIC:[/red] {exc}"

    try:
        current_content = Path(tmp_path).read_text(encoding="utf-8")
    except Exception as exc:
        os.unlink(tmp_path)
        return f"[red]Error reading temp file:[/red] {exc}"
    finally:
        # Temp file no longer needed — editor works in-memory.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    with _lock:
        _previous_content = current_content

    # --- Launch built-in TUI editor ---
    from .tui_editor import run_editor

    new_content = run_editor(current_content)

    if new_content is None:
        return "[dim]Editor quit — no changes applied[/dim]"

    # --- Apply diff ---
    with _lock:
        old = _previous_content
        if old:
            result = _reimport_diff(client, old, new_content)
        else:
            result = _reimport_full(client, new_content)
        _previous_content = new_content

    return result


def start_edit(client: CLISocketClient) -> str:
    """Export the current BASIC program and open it in an external editor.

    For terminal editors the REPL blocks until the editor exits, then the
    diff is applied.  For GUI editors a background watcher is started and
    control returns to the REPL immediately; use ``stop_edit()`` to end
    the session.

    Args:
        client: Connected CLI socket client.

    Returns:
        A status message for the REPL to display.
    """
    global _previous_content, _watcher_thread, _watcher_client, _temp_path

    with _lock:
        if _watcher_thread is not None and _watcher_thread.is_alive():
            return (
                "[dim]Edit session already active. "
                "Use .edit stop to end it first.[/dim]"
            )

    # --- Export current program to a temp file ---
    # Create temp file first so we can pass the path to basic export.
    fd, tmp_path = tempfile.mkstemp(suffix=".bas", prefix="attic-edit-")
    os.close(fd)

    try:
        resp = client.send(f"basic export {tmp_path}")
        if not resp.success:
            # "No program" is fine — start with an empty file
            if "no program" in resp.payload.lower():
                Path(tmp_path).write_text("", encoding="utf-8")
            else:
                os.unlink(tmp_path)
                return f"[red]Error exporting BASIC:[/red] {resp.payload}"
    except Exception as exc:
        os.unlink(tmp_path)
        return f"[red]Error exporting BASIC:[/red] {exc}"

    # Read back the exported content for diffing later.
    try:
        current_content = Path(tmp_path).read_text(encoding="utf-8")
    except Exception as exc:
        os.unlink(tmp_path)
        return f"[red]Error reading temp file:[/red] {exc}"

    editor = _detect_editor()
    is_gui = _is_gui_editor(editor)

    with _lock:
        _previous_content = current_content
        _temp_path = tmp_path

    if is_gui:
        # --- GUI editor: launch and watch in background ---
        # Build the command; honour flags like "code --wait".
        # We keep the Popen handle so the watcher can detect when the
        # editor exits and auto-stop.
        global _editor_proc
        cmd_parts = editor.split() + [tmp_path]
        try:
            _editor_proc = subprocess.Popen(cmd_parts)
        except Exception as exc:
            _cleanup_temp()
            return f"[red]Error launching editor:[/red] {exc}"

        # Start background watcher daemon thread.
        with _lock:
            _watcher_stop.clear()
            _watcher_client = client
            _watcher_thread = threading.Thread(
                target=_watch_file,
                args=(tmp_path, client),
                daemon=True,
            )
            _watcher_thread.start()

        return (
            f"[dim]Opened {editor.split()[0]} — editing {tmp_path}\n"
            f"Changes will be applied automatically on save.\n"
            f"Stops when editor exits, or use .edit stop.\n"
            f"Tip: set VISUAL=\"code --wait\" for VS Code auto-stop.[/dim]"
        )

    else:
        # --- Terminal editor: block until exit, then apply diff ---
        cmd_parts = editor.split() + [tmp_path]
        try:
            subprocess.run(cmd_parts, check=True)
        except subprocess.CalledProcessError as exc:
            _cleanup_temp()
            return f"[red]Editor exited with error:[/red] {exc}"
        except FileNotFoundError:
            _cleanup_temp()
            return f"[red]Editor not found:[/red] {editor}"

        # Read back the edited content and apply the diff.
        try:
            new_content = Path(tmp_path).read_text(encoding="utf-8")
        except OSError as exc:
            _cleanup_temp()
            return f"[red]Error reading edited file:[/red] {exc}"

        with _lock:
            old = _previous_content
            if old:
                result = _reimport_diff(client, old, new_content)
            else:
                result = _reimport_full(client, new_content)
            _previous_content = new_content

        _cleanup_temp()
        return result


def stop_edit() -> str:
    """Stop the background file watcher and clean up the temp file.

    Called by the ``.edit stop`` REPL command.

    Returns:
        A status message for the REPL to display.
    """
    global _watcher_thread, _watcher_client, _editor_proc

    with _lock:
        if _watcher_thread is None or not _watcher_thread.is_alive():
            _editor_proc = None
            _cleanup_temp()
            return "[dim]No edit session active[/dim]"

        _watcher_stop.set()

    # Wait for the watcher thread to finish (outside the lock).
    _watcher_thread.join(timeout=3.0)

    with _lock:
        _watcher_thread = None
        _watcher_client = None
        _editor_proc = None

    path = _cleanup_temp()
    if path:
        return f"Edit session ended (temp file removed: {path})"
    return "Edit session ended"


def cleanup() -> None:
    """Clean up any active edit session.

    Called from the REPL's ``finally`` block to ensure the watcher thread
    and temp file are cleaned up on exit.
    """
    global _watcher_thread, _watcher_client

    with _lock:
        if _watcher_thread is not None and _watcher_thread.is_alive():
            _watcher_stop.set()

    if _watcher_thread is not None:
        _watcher_thread.join(timeout=3.0)

    with _lock:
        _watcher_thread = None
        _watcher_client = None

    _cleanup_temp()


def is_active() -> bool:
    """Return True if an edit session is currently active.

    An edit session is active when a background file watcher is running
    (GUI editor mode).
    """
    with _lock:
        return _watcher_thread is not None and _watcher_thread.is_alive()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _cleanup_temp() -> str | None:
    """Remove the temporary edit file if it exists.

    Returns:
        The path that was removed, or None if there was nothing to clean up.
    """
    global _temp_path

    path = _temp_path
    _temp_path = None
    if path is not None:
        try:
            os.unlink(path)
        except OSError:
            pass
    return path
