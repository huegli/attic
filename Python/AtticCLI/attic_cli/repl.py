"""Main REPL loop with mode switching, assembly sub-mode, and tab completion.

This is the interactive heart of the CLI. It reads user input via
prompt_toolkit, dispatches to mode-specific command translators, sends
protocol commands to AtticServer, and displays responses.
"""

from prompt_toolkit import PromptSession
from prompt_toolkit.completion import Completer, Completion, WordCompleter
from prompt_toolkit.document import Document
from prompt_toolkit.formatted_text import HTML
from rich.console import Console

from .cli_client import CLIError, CLISocketClient
from .commands import QUIT, SHUTDOWN, handle_dot_command
from .help import (
    BASIC_HELP,
    DOS_HELP,
    GLOBAL_HELP,
    MONITOR_HELP,
)
from .history import get_history
from .protocol import MULTI_LINE_SEP
from .translator import translate_basic, translate_dos, translate_monitor

console = Console()


def run_repl(client: CLISocketClient) -> None:
    """Run the interactive REPL loop.

    Args:
        client: A connected CLISocketClient instance.
    """
    mode = "basic"          # Default mode (matches Swift CLI)
    current_drive = 1       # Current DOS drive number
    in_assembly = False     # Interactive assembly sub-mode
    assembly_addr = 0       # Next assembly address (hex)

    history = get_history()
    session: PromptSession = PromptSession(history=history)

    try:
        while True:
            # --- Build prompt ---
            if in_assembly:
                prompt = HTML(f"<b>${assembly_addr:04X}</b>: ")
            else:
                prompt = _mode_prompt(mode, current_drive)

            # --- Read input ---
            try:
                completer = _mode_completer(mode, in_assembly)
                line = session.prompt(prompt, completer=completer)
            except EOFError:
                # Ctrl-D: exit
                if in_assembly:
                    _end_assembly(client)
                    in_assembly = False
                    continue
                console.print("\nGoodbye")
                break
            except KeyboardInterrupt:
                # Ctrl-C: cancel current line
                continue

            trimmed = line.strip()

            # --- Interactive assembly sub-mode ---
            if in_assembly:
                if not trimmed or trimmed == ".":
                    result = _end_assembly(client)
                    if result:
                        console.print(result)
                    in_assembly = False
                    continue

                # Send instruction to assembler
                try:
                    response = client.send(f"assemble input {trimmed}")
                    if response.success:
                        payload = response.payload
                        # Response format: "assembled line\x1E$XXXX"
                        if MULTI_LINE_SEP in payload:
                            parts = payload.rsplit(MULTI_LINE_SEP, 1)
                            console.print(parts[0])
                            # Extract next address
                            addr_str = parts[1].strip().lstrip("$")
                            try:
                                assembly_addr = int(addr_str, 16)
                            except ValueError:
                                pass
                        else:
                            console.print(payload)
                    else:
                        console.print(f"[red]Error:[/red] {response.payload}")
                except Exception as exc:
                    console.print(f"[red]Error:[/red] {exc}")
                continue

            # --- Empty line ---
            if not trimmed:
                continue

            # --- Dot-commands (global) ---
            if trimmed.startswith("."):
                result = _handle_dot_with_mode(
                    trimmed, client=client, mode=mode, current_drive=current_drive
                )

                if result is QUIT or result is SHUTDOWN:
                    console.print("Goodbye")
                    break

                if isinstance(result, dict):
                    # Mode change
                    if "mode" in result:
                        mode = result["mode"]
                    if "output" in result and result["output"]:
                        console.print(result["output"])
                elif isinstance(result, str):
                    console.print(result)
                # None means output was already printed (e.g., help)
                continue

            # --- Mode-specific command translation ---
            commands = _translate_for_mode(trimmed, mode)

            for cmd in commands:
                try:
                    response = client.send(cmd)
                    if response.success:
                        payload = response.payload

                        # Check for assembly mode entry
                        if payload.startswith("ASM $"):
                            in_assembly = True
                            addr_str = payload[5:].strip()
                            try:
                                assembly_addr = int(addr_str, 16)
                            except ValueError:
                                assembly_addr = 0
                            console.print(
                                f"[dim]Entering assembly mode at ${assembly_addr:04X}. "
                                f"Type '.' or empty line to exit.[/dim]"
                            )
                            continue

                        # Track drive changes from dos cd
                        if cmd.startswith("dos cd ") and payload.startswith("D"):
                            try:
                                current_drive = int(payload[1:payload.index(":")])
                            except (ValueError, IndexError):
                                pass

                        # Track unmount affecting current drive
                        if cmd.startswith("unmount "):
                            try:
                                drive_num = int(cmd.split()[1])
                                if drive_num == current_drive:
                                    current_drive = 1
                            except (ValueError, IndexError):
                                pass

                        # Display response
                        if payload:
                            if MULTI_LINE_SEP in payload:
                                for part in payload.split(MULTI_LINE_SEP):
                                    console.print(part, highlight=False)
                            else:
                                console.print(payload, highlight=False)
                    else:
                        console.print(f"[red]Error:[/red] {response.payload}")

                except Exception as exc:
                    console.print(f"[red]Error:[/red] {exc}")
                    break

            # --- Drain async events ---
            for event in client.drain_events():
                _display_event(event)

    finally:
        client.disconnect()


def _handle_dot_with_mode(
    line: str,
    *,
    client: CLISocketClient,
    mode: str,
    current_drive: int,
) -> dict | str | object | None:
    """Handle dot-commands, returning mode changes as dicts.

    Returns:
        - dict with "mode" and/or "output" keys for mode changes
        - str for display text
        - QUIT/SHUTDOWN sentinels
        - None for already-printed output
    """
    lower = line.strip().lower()
    parts = line.strip().split(None, 1)
    cmd = parts[0].lower() if parts else ""
    args = parts[1] if len(parts) > 1 else ""

    # Mode switches
    if lower == ".monitor":
        return {"mode": "monitor", "output": "Switched to monitor mode"}
    if lower in (".basic", ".basic atari"):
        return {"mode": "basic", "output": "Switched to BASIC mode"}
    if lower == ".basic turbo":
        return {"mode": "basic_turbo", "output": "Switched to Turbo BASIC mode"}
    if lower == ".dos":
        return {"mode": "dos", "output": "Switched to DOS mode"}

    # Delegate to commands module for everything else
    effective_mode = mode.replace("basic_turbo", "basic")
    return handle_dot_command(
        line,
        client=client,
        mode=effective_mode,
        set_mode=lambda m: None,  # mode switching handled above
    )


def _mode_prompt(mode: str, drive: int) -> HTML:
    """Generate the prompt for the current mode."""
    match mode:
        case "monitor":
            return HTML("<style fg='ansigray'>[monitor]</style> <b>&gt;</b> ")
        case "basic":
            return HTML("<style fg='ansigray'>[basic]</style> <b>&gt;</b> ")
        case "basic_turbo":
            return HTML(
                "<style fg='ansigray'>[basic:turbo]</style> <b>&gt;</b> "
            )
        case "dos":
            return HTML(
                f"<style fg='ansigray'>[dos]</style> <b>D{drive}:&gt;</b> "
            )
        case _:
            return HTML("<b>&gt;</b> ")


class _DotAwareCompleter(Completer):
    """Completer that treats '.' as part of the word being completed.

    WordCompleter splits on '.' so typing '.h<TAB>' fails to match '.help'.
    This completer matches the full text from the last whitespace boundary,
    preserving the leading dot for dot-commands.
    """

    def __init__(self, words: list[str]) -> None:
        self.words = [w.lower() for w in words]

    def get_completions(self, document: Document, complete_event):
        # Get text from the last whitespace to the cursor
        text = document.text_before_cursor
        # Find the last space to get the current "word" including dots
        space_idx = text.rfind(" ")
        if space_idx >= 0:
            current_word = text[space_idx + 1 :]
        else:
            current_word = text
        prefix = current_word.lower()

        for word in self.words:
            if word.startswith(prefix):
                yield Completion(word, start_position=-len(current_word))


def _mode_completer(mode: str, in_assembly: bool) -> _DotAwareCompleter | None:
    """Build a tab completer for the current mode."""
    if in_assembly:
        return None  # No completion in assembly mode

    # Global dot-commands
    global_cmds = [f".{cmd}" for cmd in GLOBAL_HELP]

    match mode:
        case "monitor":
            mode_cmds = list(MONITOR_HELP.keys())
        case "basic" | "basic_turbo":
            mode_cmds = list(BASIC_HELP.keys())
        case "dos":
            mode_cmds = list(DOS_HELP.keys())
        case _:
            mode_cmds = []

    return _DotAwareCompleter(global_cmds + mode_cmds)


def _translate_for_mode(line: str, mode: str) -> list[str]:
    """Translate user input to protocol commands based on current mode."""
    match mode:
        case "monitor":
            return translate_monitor(line)
        case "basic" | "basic_turbo":
            return translate_basic(line)
        case "dos":
            return translate_dos(line)
        case _:
            return [line]


def _end_assembly(client: CLISocketClient) -> str | None:
    """End interactive assembly mode."""
    try:
        response = client.send("assemble end")
        if response.success and response.payload:
            return response.payload
        if not response.success:
            return f"[red]Error:[/red] {response.payload}"
    except Exception as exc:
        return f"[red]Error:[/red] {exc}"
    return None


def _display_event(event) -> None:
    """Display an async event from the server."""
    from rich.panel import Panel

    match event.kind:
        case "breakpoint":
            console.print(Panel(
                f"Breakpoint hit: {event.data}",
                title="BREAKPOINT",
                border_style="yellow",
            ))
        case "stopped":
            console.print(f"[yellow]Program stopped at {event.data}[/yellow]")
        case "error":
            console.print(f"[red]Server error:[/red] {event.data}")
        case _:
            console.print(f"[dim]Event: {event.kind} {event.data}[/dim]")
