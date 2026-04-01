"""BASIC Edit Mode - Edit programs in external text editor.

This module provides run_edit_mode() which:
- Resolves editor from VISUAL/EDITOR environment variables (defaults to vim)
- Exports the current BASIC program to a temporary file via 'basic export'
- Launches the user's editor on the temporary file
- Watches for file saves (mtime polling) and reimports on each save
- For terminal editors: waits for exit, reimports if changed
- For GUI editors: watches for saves, waits for user Enter to finish
- Reimports the edited program via 'basic new' + 'basic import'
- Handles Ctrl-C gracefully without leaving temp files behind
"""

import logging
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from rich.console import Console

from .cli_client import CLISocketClient, CLIError

logger = logging.getLogger(__name__)
console = Console()


# =============================================================================
# MARK: - Editor Detection
# =============================================================================


def _detect_editor() -> str:
    """Detect the user's preferred text editor.

    Priority order:
    1. VISUAL environment variable
    2. EDITOR environment variable
    3. Default: 'vim'

    Returns:
        Editor command string (e.g., 'vim', 'nano', 'emacs --nw')
    """
    editor = os.environ.get("VISUAL")
    if editor:
        return editor

    editor = os.environ.get("EDITOR")
    if editor:
        return editor

    return "vim"


def _is_gui_editor(editor_cmd: str) -> bool:
    """Detect if the editor is a GUI application vs terminal-based.

    GUI editors launch a separate window and return immediately (or shortly
    after), while terminal editors take over the current TTY and block until
    the user quits.

    Args:
        editor_cmd: The editor command string (e.g., 'vim', 'code --wait')

    Returns:
        True if detected as GUI editor, False for terminal editors.
    """
    # Extract the executable name from the command string
    exe_name = Path(editor_cmd.strip().split()[0]).name.lower() if editor_cmd else ""

    # Known terminal editors — these need the TTY
    terminal_editors = {
        "vim", "vi", "nvim", "nano", "pico", "micro", "ne",
        "emacs", "mg", "jed", "joe", "mcedit", "ed", "ex",
    }

    if exe_name in terminal_editors:
        return False

    # Known GUI editors
    gui_editors = {
        "code", "codium",          # VS Code / VSCodium
        "atom",                    # Atom
        "subl", "sublime_text",    # Sublime Text
        "mate", "textmate",        # TextMate
        "gedit", "kate", "kwrite", # Linux GUI editors
        "bbedit", "nova",          # macOS GUI editors
    }

    if exe_name in gui_editors:
        return True

    # macOS .app bundles are GUI
    if ".app" in editor_cmd.lower():
        return True

    # Default to terminal editor (safer — won't break the TTY)
    return False


# =============================================================================
# MARK: - Edit Mode Entry Point
# =============================================================================


def run_edit_mode(
    client: CLISocketClient,
    path: str | None = None,
) -> str | None:
    """Edit the current BASIC program in an external editor.

    This function implements the full edit mode workflow:
    1. Export the current BASIC program to a file
    2. Launch the user's editor on that file
    3. Watch for saves and reimport on each change
    4. Clean up temporary files (if we created them)

    Args:
        client: Connected CLI socket client.
        path: Optional file path provided by the user (e.g., '~/prog.bas').
            If provided, the file is preserved after editing.
            If None, a temp file is created and cleaned up on exit.

    Returns:
        - A status message string to display, or None for silent success.
    """
    # Determine whether we're using a user-provided path or a temp file
    user_provided_path = path is not None
    if user_provided_path:
        edit_file = Path(path).expanduser().resolve()
    else:
        # Create a temp file — we'll clean it up when done
        fd, tmp_path = tempfile.mkstemp(suffix=".bas", prefix="attic-edit-")
        os.close(fd)
        edit_file = Path(tmp_path)

    try:
        # Step 1: Detect editor first so we know whether to suppress output
        editor_cmd = _detect_editor()
        gui_editor = _is_gui_editor(editor_cmd)

        # Step 2: Export the current BASIC program
        # Suppress export message for terminal editors — they take over the
        # screen immediately, so any output would garble the editor display.
        export_msg = _export_program(client, edit_file, quiet=not gui_editor)
        if export_msg is not None:
            return export_msg  # Error message

        # Step 3: Launch the editor
        if gui_editor:
            result_msg = _run_gui_editor(editor_cmd, edit_file, client)
        else:
            result_msg = _run_terminal_editor(editor_cmd, edit_file, client)

        return result_msg

    except KeyboardInterrupt:
        # Final reimport on Ctrl-C so work isn't lost
        console.print("\n[dim]Edit interrupted — reimporting current file...[/dim]")
        _reimport_program(client, edit_file)
        return "Edit cancelled (program reimported)"

    finally:
        # Clean up temp file only if we created it
        if not user_provided_path and edit_file.exists():
            try:
                edit_file.unlink()
                logger.debug("Cleaned up temp file: %s", edit_file)
            except OSError as exc:
                logger.warning("Failed to clean up temp file: %s", exc)


# =============================================================================
# MARK: - Export / Import Helpers
# =============================================================================


def _export_program(client: CLISocketClient, path: Path, quiet: bool = False) -> str | None:
    """Export the current BASIC program to a file.

    If the emulator has no program, creates an empty file so the user
    can start writing from scratch in the editor.

    Args:
        client: Connected CLI socket client.
        path: Path to export the program to.
        quiet: If True, suppress the success message (useful before
            launching a terminal editor that takes over the screen).

    Returns None on success, or an error message string on failure.
    """
    try:
        response = client.send(f"basic export {path}")
        if not response.success:
            # "No program" is not an error — create an empty file
            if "no program" in response.payload.lower():
                path.write_text("", encoding="utf-8")
                if not quiet:
                    console.print("[dim]No program in memory — starting with empty file[/dim]")
                return None
            return f"[red]Failed to export program:[/red] {response.payload}"
        if not quiet:
            console.print(f"[dim]{response.payload}[/dim]")
        return None
    except CLIError as exc:
        return f"[red]Failed to export program:[/red] {exc}"


def _reimport_program(client: CLISocketClient, path: Path) -> str | None:
    """Reimport a BASIC program: clear with NEW, then import from file.

    Uses 'basic new' which resets all BASIC memory pointers (VNT, VVT,
    STMTAB, STARP, RUNSTK, MEMTOP) to a clean state. This is essential
    because 'basic del' only updates STARP, leaving RUNSTK and variable
    tables stale, which causes 'Out of memory' errors on subsequent import.

    Returns None on success, or an error message string on failure.
    """
    try:
        # Clear the entire BASIC state (variables, program, pointers)
        new_response = client.send("basic new")
        if not new_response.success:
            return f"[red]Failed to clear program:[/red] {new_response.payload}"

        # Import the edited file
        import_response = client.send(f"basic import {path}")
        if not import_response.success:
            return f"[red]Failed to import program:[/red] {import_response.payload}"

        console.print(f"[dim]{import_response.payload}[/dim]")
        return None
    except CLIError as exc:
        return f"[red]Failed to reimport program:[/red] {exc}"


# =============================================================================
# MARK: - Terminal Editor
# =============================================================================


def _run_terminal_editor(
    editor_cmd: str,
    path: Path,
    client: CLISocketClient,
) -> str | None:
    """Edit a file with a terminal-based editor (vim, nano, etc.).

    The editor runs in the foreground, taking control of the terminal.
    After the editor exits, we check if the file was modified and reimport.

    Returns a status message or None for silent success.
    """
    # Record initial mtime to detect changes
    try:
        initial_mtime = path.stat().st_mtime
    except OSError:
        initial_mtime = 0.0

    # Launch editor in foreground — it inherits stdin/stdout/stderr
    # so it gets full control of the terminal (required for vim, nano, etc.)
    try:
        # Split the command to handle editors with arguments (e.g., 'emacs -nw')
        cmd_parts = editor_cmd.split() + [str(path)]
        returncode = subprocess.call(cmd_parts)

        if returncode != 0:
            logger.warning("Editor exited with code %d", returncode)
            # Non-zero exit doesn't necessarily mean failure — some editors
            # use non-zero for various reasons. Check mtime to determine
            # if changes were made.

    except FileNotFoundError:
        return f"[red]Editor not found:[/red] {editor_cmd}"
    except Exception as exc:
        return f"[red]Editor error:[/red] {exc}"

    # Check if file was modified
    try:
        final_mtime = path.stat().st_mtime
    except OSError:
        final_mtime = 0.0

    if final_mtime <= initial_mtime:
        return "[dim]File not modified — program unchanged[/dim]"

    # Reimport the edited program
    err = _reimport_program(client, path)
    if err:
        return err

    return "[green]Program updated from editor[/green]"


# =============================================================================
# MARK: - GUI Editor
# =============================================================================


def _run_gui_editor(
    editor_cmd: str,
    path: Path,
    client: CLISocketClient,
) -> str | None:
    """Edit a file with a GUI editor (VS Code, Sublime, etc.).

    GUI editors return immediately after launching. We enter a watch loop
    that polls the file's mtime and reimports on each save. The user
    presses Enter in the CLI to finish editing.

    Returns a status message or None for silent success.
    """
    # Launch editor — stdin/stdout detached since it opens its own window
    try:
        cmd_parts = editor_cmd.split() + [str(path)]
        subprocess.Popen(
            cmd_parts,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return f"[red]Editor not found:[/red] {editor_cmd}"
    except Exception as exc:
        return f"[red]Editor error:[/red] {exc}"

    console.print(
        f"[dim]Opened {path.name} in {editor_cmd}.\n"
        f"Watching for saves — press Enter to finish editing.[/dim]"
    )

    # Track the last-known mtime so we reimport on each save
    last_mtime = path.stat().st_mtime
    import_count = 0

    # Set stdin to non-blocking so we can poll for Enter without blocking
    # the mtime check loop
    import select

    try:
        while True:
            # Check for Enter key (non-blocking)
            ready, _, _ = select.select([sys.stdin], [], [], 1.0)
            if ready:
                # User pressed Enter — consume the line and exit
                sys.stdin.readline()
                break

            # Check if file was modified
            try:
                current_mtime = path.stat().st_mtime
            except OSError:
                continue

            if current_mtime > last_mtime:
                last_mtime = current_mtime
                import_count += 1
                console.print(f"[dim]File saved — reimporting (#{import_count})...[/dim]")
                err = _reimport_program(client, path)
                if err:
                    console.print(err)
                else:
                    console.print("[green]Program updated[/green]")

    except KeyboardInterrupt:
        # Ctrl-C during watch — do a final reimport
        pass

    # Final reimport if there were any changes since last import
    try:
        current_mtime = path.stat().st_mtime
    except OSError:
        current_mtime = last_mtime

    if current_mtime > last_mtime:
        console.print("[dim]Final reimport...[/dim]")
        err = _reimport_program(client, path)
        if err:
            return err

    if import_count > 0:
        return f"[green]Edit complete — {import_count} save(s) reimported[/green]"
    else:
        return "[dim]Edit complete — no changes detected[/dim]"
