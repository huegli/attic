"""Click CLI entry point for attic-py.

Handles argument parsing, server discovery/launch, and handoff to the REPL.
"""

import sys

import click
from rich.console import Console

from . import __version__
from .cli_client import CLIConnectionError, CLISocketClient
from .server_launcher import ensure_server_running, find_server_executable

console = Console()


@click.command()
@click.option(
    "--silent",
    is_flag=True,
    default=False,
    help="Launch server without audio output.",
)
@click.option(
    "--socket",
    "socket_path",
    default=None,
    type=click.Path(),
    help="Connect to a specific server socket path.",
)
@click.option(
    "--headless",
    is_flag=True,
    default=False,
    help="Launch server in headless mode (no GUI).",
)
@click.version_option(version=__version__, prog_name="attic-py")
def cli(silent: bool, socket_path: str | None, headless: bool) -> None:
    """Python CLI for the Attic Atari 800 XL emulator.

    Connects to a running AtticServer instance, or launches one
    automatically. Provides a REPL with monitor, BASIC, and DOS modes.
    """
    client = CLISocketClient()

    if socket_path:
        # Connect to a specific socket
        _connect_to_socket(client, socket_path)
    else:
        # Discover or launch server
        _connect_or_launch(client, silent=silent)

    # Show banner
    _print_banner(client)

    # Hand off to REPL (Phase 2)
    try:
        from .repl import run_repl

        run_repl(client)
    except ImportError:
        # Phase 1: REPL not yet implemented — just show status and exit
        console.print("[dim]REPL not yet implemented. Showing server status.[/dim]")
        try:
            status = client.send_raw("status")
            console.print(f"\n{status}")
        except Exception as exc:
            console.print(f"[red]Error:[/red] {exc}")
        finally:
            client.disconnect()


def _connect_to_socket(client: CLISocketClient, path: str) -> None:
    """Connect to a specific socket path, exiting on failure."""
    try:
        client.connect(path)
    except CLIConnectionError as exc:
        console.print(f"[red]Connection failed:[/red] {exc}")
        sys.exit(1)


def _connect_or_launch(client: CLISocketClient, *, silent: bool) -> None:
    """Discover an existing server or launch a new one, then connect."""
    result = ensure_server_running(
        silent=silent,
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


def _print_banner(client: CLISocketClient) -> None:
    """Print the welcome banner with version info."""
    console.print()
    console.print("[bold]Attic[/bold] — Atari 800 XL Emulator", highlight=False)
    console.print(f"[dim]Python CLI v{__version__}[/dim]")
    console.print("[dim]Type .help for commands, .quit to exit[/dim]")
    console.print()
