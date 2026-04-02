"""Simple HTTP server for hosting the Attic web client.

Serves static files from the web-client/dist/ directory on a background
daemon thread. Auto-started on attic-py launch so the web client is
always available in the browser.
"""

import logging
import os
import sys
import threading
from functools import partial
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

logger = logging.getLogger(__name__)

# Module-level reference to the running server (prevents double-start).
_running_server: HTTPServer | None = None
_server_port: int = 0


def find_dist_dir() -> str | None:
    """Locate the web-client/dist/ directory.

    Searches in order:
    1. PyInstaller frozen bundle (sys._MEIPASS)
    2. Relative to project root (development layout)

    Returns:
        Absolute path to the dist directory, or None if not found.
    """
    # 1. Frozen bundle
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidate = Path(meipass) / "web-client" / "dist"
        if candidate.is_dir():
            return str(candidate)

    # 2. Development layout: walk up from this file to the project root.
    #    __file__ is Python/AtticCLI/attic_cli/web_server.py
    #    Project root is four levels up.
    pkg_dir = Path(__file__).resolve().parent.parent  # attic_cli -> AtticCLI
    project_root = pkg_dir.parent.parent  # AtticCLI -> Python -> attic
    candidate = project_root / "web-client" / "dist"
    if candidate.is_dir():
        return str(candidate)

    # 3. Environment variable override
    env_dir = os.environ.get("ATTIC_WEB_DIR")
    if env_dir:
        candidate = Path(env_dir)
        if candidate.is_dir():
            return str(candidate)

    return None


class _QuietHandler(SimpleHTTPRequestHandler):
    """HTTP handler that suppresses request logging."""

    def log_message(self, format, *args):
        # Silence per-request output; errors still go to logger.
        pass


def start_web_server(dist_dir: str, port: int = 8080) -> HTTPServer:
    """Start an HTTP server serving static files from *dist_dir*.

    The server runs in a daemon thread and will be cleaned up
    automatically when the main process exits.

    Args:
        dist_dir: Absolute path to the directory to serve.
        port: TCP port to listen on.

    Returns:
        The running HTTPServer instance.

    Raises:
        OSError: If the port is already in use.
    """
    global _running_server, _server_port

    handler = partial(_QuietHandler, directory=dist_dir)
    httpd = HTTPServer(("", port), handler)

    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()

    _running_server = httpd
    _server_port = port
    logger.debug("Web server started on port %d serving %s", port, dist_dir)
    return httpd


def stop_web_server() -> bool:
    """Shut down the running web server, if any.

    Returns:
        True if a server was stopped, False if none was running.
    """
    global _running_server, _server_port

    if _running_server is None:
        return False

    _running_server.shutdown()
    _running_server = None
    _server_port = 0
    return True


def is_running() -> bool:
    """Return True if the web server is currently running."""
    return _running_server is not None


def get_port() -> int:
    """Return the port the web server is listening on, or 0 if not running."""
    return _server_port
