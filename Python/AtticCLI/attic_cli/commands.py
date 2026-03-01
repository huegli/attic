"""Global dot-commands available in all REPL modes.

Handles commands like .help, .status, .reset, .screenshot, .quit, etc.
Some commands are handled entirely on the client side (mode switching, help),
while others are forwarded to the server.
"""

from .cli_client import CLIError, CLISocketClient
from .help import print_help_overview, print_help_topic
from .protocol import MULTI_LINE_SEP
from .terminal_images import display_inline_image

# Sentinel return values for the REPL loop
QUIT = object()
SHUTDOWN = object()


def handle_dot_command(
    line: str,
    *,
    client: CLISocketClient,
    mode: str,
    set_mode: callable,
) -> str | object | None:
    """Handle a dot-command (line starting with '.').

    Args:
        line: The full input line (e.g., ".help monitor").
        client: Connected socket client.
        mode: Current mode name ("monitor", "basic", "dos").
        set_mode: Callback to change the current mode.

    Returns:
        - A string to display to the user.
        - QUIT or SHUTDOWN sentinel to signal the REPL should exit.
        - None for no output (e.g., help was printed directly).
    """
    stripped = line.strip()
    lower = stripped.lower()
    parts = stripped.split(None, 1)
    cmd = parts[0].lower() if parts else ""
    args = parts[1] if len(parts) > 1 else ""

    # --- Client-side commands (no server round-trip) ---

    if lower == ".monitor":
        set_mode("monitor")
        return "Switched to monitor mode"

    if lower in (".basic", ".basic atari"):
        set_mode("basic")
        return "Switched to BASIC mode"

    if lower == ".basic turbo":
        set_mode("basic_turbo")
        return "Switched to Turbo BASIC mode"

    if lower == ".dos":
        set_mode("dos")
        return "Switched to DOS mode"

    if lower == ".help":
        print_help_overview(mode)
        return None

    if cmd == ".help":
        print_help_topic(mode, args)
        return None

    if lower == ".quit":
        try:
            client.send_raw("quit")
        except CLIError:
            pass
        return QUIT

    if lower == ".shutdown":
        try:
            client.send_raw("shutdown")
        except CLIError:
            pass
        return SHUTDOWN

    # --- Commands forwarded to server ---

    if lower == ".status":
        return _send_and_format(client, "status")

    if lower == ".screen":
        return _send_and_format(client, "screen")

    if lower == ".reset":
        return _send_and_format(client, "reset cold")

    if lower == ".warmstart":
        return _send_and_format(client, "reset warm")

    if cmd == ".screenshot":
        return _handle_screenshot(client, args)

    if cmd == ".boot":
        if not args:
            return "[red]Usage: .boot <path>[/red]"
        return _send_and_format(client, f"boot {args}")

    if cmd == ".state":
        return _handle_state(client, args)

    return f"[red]Unknown command: {stripped}[/red]"


def _send_and_format(client: CLISocketClient, command: str) -> str:
    """Send a command and format the response for display.

    Multi-line responses (containing 0x1E separators) are split
    into individual lines.
    """
    try:
        response = client.send(command)
        if not response.success:
            return f"[red]Error:[/red] {response.payload}"
        if response.is_multiline:
            return "\n".join(response.lines)
        return response.payload
    except Exception as exc:
        return f"[red]Error:[/red] {exc}"


def _handle_screenshot(client: CLISocketClient, args: str) -> str | None:
    """Handle .screenshot command with optional inline display."""
    command = f"screenshot {args}" if args else "screenshot"
    try:
        response = client.send(command)
        if not response.success:
            return f"[red]Error:[/red] {response.payload}"

        payload = response.payload.strip()
        # Server returns "screenshot saved to /path/to/file.png"
        # Extract just the file path
        prefix = "screenshot saved to "
        if payload.lower().startswith(prefix):
            path = payload[len(prefix):]
        else:
            path = payload
        # Try to display inline; falls back to printing the path
        display_inline_image(path)
        return None
    except Exception as exc:
        return f"[red]Error:[/red] {exc}"


def _handle_state(client: CLISocketClient, args: str) -> str:
    """Handle .state save/load commands."""
    if not args:
        return "[red]Usage: .state save|load <path>[/red]"

    parts = args.split(None, 1)
    subcmd = parts[0].lower()
    path = parts[1] if len(parts) > 1 else ""

    if subcmd not in ("save", "load"):
        return f"[red]Unknown state subcommand: {subcmd}[/red]"

    if not path:
        return f"[red]Usage: .state {subcmd} <path>[/red]"

    return _send_and_format(client, f"state {subcmd} {path}")
