"""Find and launch AtticServer subprocess.

Ported from Sources/AtticCore/ServerLauncher.swift. Searches for the
AtticServer executable in standard locations and launches it, waiting
for the socket to appear.
"""

import logging
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from .protocol import socket_path_for_pid

logger = logging.getLogger(__name__)

# How long to wait for the server socket to appear after launch.
_POLL_INTERVAL = 0.2  # seconds
_POLL_MAX_RETRIES = 20  # 20 * 0.2 = 4 seconds total


@dataclass(frozen=True, slots=True)
class LaunchResult:
    """Result of attempting to launch AtticServer.

    Attributes:
        success: True if the server is running and the socket is available.
        socket_path: Path to the Unix domain socket (if successful).
        pid: Server process ID (if launched).
        error: Error description (if failed).
    """

    success: bool
    socket_path: str = ""
    pid: int = 0
    error: str = ""


def find_server_executable() -> str | None:
    """Search for the AtticServer executable.

    Checks (in order):
    1. Same directory as the current executable (co-located builds)
    2. .build/release/ and .build/debug/ in the project root
    3. PATH via shutil.which()
    4. Common installation directories

    Returns:
        Absolute path to AtticServer, or None if not found.
    """
    name = "AtticServer"

    # 1. Same directory as the current executable
    exe_dir = Path(sys.argv[0]).resolve().parent
    candidate = exe_dir / name
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)

    # 2. Swift build directories (relative to project root)
    # Walk up from the package directory to find the project root
    pkg_dir = Path(__file__).resolve().parent.parent  # attic_cli -> AtticCLI
    project_root = pkg_dir.parent.parent  # AtticCLI -> Python -> attic
    for build_dir in ["release", "debug"]:
        candidate = project_root / ".build" / build_dir / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    # 3. PATH
    found = shutil.which(name)
    if found:
        return found

    # 4. Common installation directories
    common_dirs = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        os.path.expanduser("~/.local/bin"),
    ]
    for d in common_dirs:
        candidate = Path(d) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    return None


def launch_server(
    *,
    silent: bool = False,
    rom_path: str | None = None,
) -> LaunchResult:
    """Launch AtticServer and wait for its socket to appear.

    Args:
        silent: Pass --silent to suppress audio output.
        rom_path: Pass --rom-path to specify ROM directory.

    Returns:
        LaunchResult indicating success or failure.
    """
    exe = find_server_executable()
    if exe is None:
        return LaunchResult(
            success=False,
            error=(
                "AtticServer executable not found. "
                "Build it with 'swift build' or ensure it's on your PATH."
            ),
        )

    args = [exe]
    if silent:
        args.append("--silent")
    if rom_path:
        args.extend(["--rom-path", rom_path])

    logger.debug("Launching AtticServer: %s", " ".join(args))

    try:
        proc = subprocess.Popen(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError as exc:
        return LaunchResult(success=False, error=f"Failed to launch AtticServer: {exc}")

    pid = proc.pid
    sock_path = socket_path_for_pid(pid)

    # Poll for the socket to appear
    for _ in range(_POLL_MAX_RETRIES):
        time.sleep(_POLL_INTERVAL)
        if os.path.exists(sock_path):
            logger.debug("AtticServer socket ready: %s (pid %d)", sock_path, pid)
            return LaunchResult(success=True, socket_path=sock_path, pid=pid)

    return LaunchResult(
        success=False,
        pid=pid,
        error=f"AtticServer launched (pid {pid}) but socket did not appear within 4 seconds.",
    )


def ensure_server_running(
    *,
    silent: bool = False,
    rom_path: str | None = None,
    discover_fn=None,
) -> LaunchResult:
    """Ensure AtticServer is running, launching it if necessary.

    Args:
        silent: Pass --silent when launching a new server.
        rom_path: Pass --rom-path when launching a new server.
        discover_fn: Optional callable that returns an existing socket path.
            Defaults to CLISocketClient.discover_socket behavior.

    Returns:
        LaunchResult for the running server.
    """
    # Try to find an existing server first
    if discover_fn is not None:
        existing = discover_fn()
    else:
        from .cli_client import CLISocketClient

        existing = CLISocketClient().discover_socket()

    if existing is not None:
        # Extract PID from the socket path
        basename = os.path.basename(existing)
        pid_str = basename.removeprefix("attic-").removesuffix(".sock")
        try:
            pid = int(pid_str)
        except ValueError:
            pid = 0
        return LaunchResult(success=True, socket_path=existing, pid=pid)

    # No existing server — launch one
    return launch_server(silent=silent, rom_path=rom_path)
