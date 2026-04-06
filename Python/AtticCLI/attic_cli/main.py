"""Click CLI entry point for the Attic Python CLI.

Handles argument parsing, server discovery/launch, and handoff to the REPL.
"""

import sys

import click
from rich.console import Console

from . import __version__
from .cli_client import CLIConnectionError, CLISocketClient
from .server_launcher import ensure_server_running, find_server_executable

console = Console()

# Current sound state, set at launch. Accessible by .sound command.
sound_enabled: bool = False


@click.command()
@click.option(
    "--silent",
    is_flag=True,
    default=True,
    help="Launch server without audio output (default).",
)
@click.option(
    "--sound",
    is_flag=True,
    default=False,
    help="Launch server with audio output enabled.",
)
@click.option(
    "--socket",
    "socket_path",
    default=None,
    type=click.Path(),
    help="Connect to a specific server socket path.",
)
@click.version_option(version=__version__, prog_name="attic")
def cli(silent: bool, sound: bool, socket_path: str | None) -> None:
    """Python CLI for the Attic Atari 800 XL emulator.

    Connects to a running AtticServer instance, or launches one
    automatically. Provides a REPL with monitor, BASIC, and DOS modes.

    Sound is off by default. Use --sound to enable audio output.
    """
    # --sound overrides --silent
    global sound_enabled
    effective_silent = not sound
    sound_enabled = sound

    client = CLISocketClient()

    launched = False
    if socket_path:
        # Connect to a specific socket
        _connect_to_socket(client, socket_path)
    else:
        # Discover or launch server
        launched = _connect_or_launch(client, silent=effective_silent)

    # Detect WebSocket: if we launched the server, we know it has WebSocket.
    # If we connected to an existing server, probe the WebSocket port.
    websocket_active = launched or _probe_websocket_port()

    # Auto-start web client HTTP server only when WebSocket is active
    web_url = _start_web_client() if websocket_active else None

    # Show banner
    _print_banner(client, web_url=web_url)

    # Hand off to REPL
    from .repl import run_repl

    run_repl(client)


def _connect_to_socket(client: CLISocketClient, path: str) -> None:
    """Connect to a specific socket path, exiting on failure."""
    try:
        client.connect(path)
    except CLIConnectionError as exc:
        console.print(f"[red]Connection failed:[/red] {exc}")
        sys.exit(1)


def _connect_or_launch(client: CLISocketClient, *, silent: bool) -> bool:
    """Discover an existing server or launch a new one, then connect.

    When launching a new server, AESP TCP is disabled and WebSocket is
    enabled.  The web client HTTP server is auto-started on launch.

    Returns:
        True if the server was launched by us with WebSocket enabled.
    """
    result = ensure_server_running(
        silent=silent,
        no_aesp=True,
        websocket=True,
        discover_fn=client.discover_socket,
    )

    if not result.success:
        console.print(f"[red]Error:[/red] {result.error}")
        if find_server_executable() is None:
            console.print(
                "[dim]Hint: Build AtticServer with "
                "'swift build -c release' first.[/dim]"
            )
        sys.exit(1)

    try:
        client.connect(result.socket_path)
    except CLIConnectionError as exc:
        console.print(f"[red]Connection failed:[/red] {exc}")
        sys.exit(1)

    if result.pid:
        console.print(f"[dim]Connected to AtticServer (pid {result.pid})[/dim]")

    return result.launched


def _probe_websocket_port(port: int = 47803, timeout: float = 0.3) -> bool:
    """Check if the AtticServer WebSocket port is listening.

    Performs a quick TCP connect to detect whether the server was started
    with --websocket. Returns True if the port accepts connections.
    """
    import socket

    try:
        with socket.create_connection(("localhost", port), timeout=timeout):
            return True
    except (OSError, TimeoutError):
        return False


def _start_web_client() -> str | None:
    """Auto-start the web client HTTP server.

    Returns:
        The URL string if the server started, or None if dist dir not found.
    """
    from . import web_server

    dist_dir = web_server.find_dist_dir()
    if dist_dir is None:
        return None

    try:
        web_server.start_web_server(dist_dir, port=8080)
        return "http://localhost:8080"
    except OSError:
        return None


def _print_banner(client: CLISocketClient, *, web_url: str | None = None) -> None:
    """Print the welcome banner with version info."""
    console.print()
    console.print("[bold]Attic[/bold] — Atari 800 XL Emulator", highlight=False)
    console.print(f"[dim]Python CLI v{__version__}[/dim]")
    if web_url:
        console.print(f"[dim]Web client at {web_url}[/dim]")
    console.print("[dim]Type .help for commands, .quit to exit[/dim]")
    console.print()
