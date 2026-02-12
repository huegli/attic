"""CLI socket client for the AtticServer text protocol.

This module implements a synchronous Unix domain socket client that speaks the
AtticServer CLI protocol. The protocol is line-based and text-oriented:

    Request:   CMD:<command> [arguments...]\\n
    Success:   OK:<response-data>\\n
    Error:     ERR:<error-message>\\n
    Event:     EVENT:<event-type> <data>\\n

Multi-line responses (e.g., disassembly, BASIC listings) encode newlines as
the ASCII Record Separator character (0x1E) within a single protocol line.

Socket files live at /tmp/attic-<pid>.sock, where <pid> is the AtticServer
process ID. The client discovers sockets by scanning /tmp/ and verifying that
the corresponding PID is still alive.

Usage from an async context (FastMCP tools are async):

    client = CLISocketClient()
    path = client.discover_socket()
    client.connect(path)
    result = await asyncio.to_thread(client.send, "status")
"""

from __future__ import annotations

import glob
import logging
import os
import re
import socket
import sys

# ---------------------------------------------------------------------------
# Protocol constants — must match Sources/AtticCore/CLIProtocol.swift
# ---------------------------------------------------------------------------

COMMAND_PREFIX = "CMD:"
OK_PREFIX = "OK:"
ERROR_PREFIX = "ERR:"
EVENT_PREFIX = "EVENT:"

# Multi-line responses join lines with this character (ASCII Record Separator).
MULTI_LINE_SEP = "\x1e"

# Timeouts in seconds.
COMMAND_TIMEOUT = 30.0
PING_TIMEOUT = 1.0
CONNECTION_TIMEOUT = 5.0

# Socket path pattern.
SOCKET_PATH_PREFIX = "/tmp/attic-"
SOCKET_PATH_SUFFIX = ".sock"

# Maximum bytes to read in one recv() call.
MAX_RECV = 4096

logger = logging.getLogger("attic-mcp.cli")


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class CLIError(Exception):
    """Raised when the server returns an ERR: response."""


class CLIConnectionError(Exception):
    """Raised when the server is unreachable or the socket is broken."""


# ---------------------------------------------------------------------------
# Socket client
# ---------------------------------------------------------------------------

class CLISocketClient:
    """Synchronous Unix domain socket client for the AtticServer CLI protocol.

    This client is intentionally synchronous — the FastMCP server bridges to
    async via ``asyncio.to_thread()``.  Keeping socket I/O synchronous avoids
    the complexity of async socket handling for what is a simple request/response
    protocol with a single connection.

    Typical lifecycle::

        client = CLISocketClient()
        path = client.discover_socket()   # scan /tmp for attic-*.sock
        if path:
            client.connect(path)          # connect + verify with ping
            result = client.send("status")
        client.disconnect()
    """

    def __init__(self) -> None:
        self._sock: socket.socket | None = None
        self._buffer: str = ""

    # -- Socket discovery ---------------------------------------------------

    def discover_socket(self) -> str | None:
        """Find the most recently modified ``/tmp/attic-*.sock`` with a live PID.

        Stale sockets (whose PID no longer exists) are cleaned up automatically.
        Returns the path to the best socket, or ``None`` if none found.
        """
        pattern = f"{SOCKET_PATH_PREFIX}*{SOCKET_PATH_SUFFIX}"
        candidates: list[tuple[float, str]] = []

        for path in glob.glob(pattern):
            # Extract PID from the filename: /tmp/attic-<pid>.sock
            basename = os.path.basename(path)
            pid_str = basename.removeprefix("attic-").removesuffix(".sock")
            try:
                pid = int(pid_str)
            except ValueError:
                continue

            # Check if the process is still alive.
            if not _pid_alive(pid):
                # Clean up stale socket file.
                try:
                    os.unlink(path)
                    logger.debug("Removed stale socket: %s", path)
                except OSError:
                    pass
                continue

            # Use modification time for sorting (most recent first).
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                continue
            candidates.append((mtime, path))

        if not candidates:
            return None

        # Sort by modification time, most recent first.
        candidates.sort(key=lambda t: t[0], reverse=True)
        return candidates[0][1]

    # -- Connection ---------------------------------------------------------

    def connect(self, path: str) -> None:
        """Connect to the given Unix socket and verify with a ping.

        Raises ``CLIConnectionError`` if the socket cannot be reached or the
        ping handshake fails.
        """
        self.disconnect()  # Clean up any previous connection.
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(CONNECTION_TIMEOUT)
            sock.connect(path)
            self._sock = sock
            self._buffer = ""
            logger.info("Connected to %s", path)
        except OSError as exc:
            raise CLIConnectionError(f"Cannot connect to {path}: {exc}") from exc

        # Verify the connection with a ping handshake.
        try:
            response = self.send("ping", timeout=PING_TIMEOUT)
            if response != "pong":
                raise CLIConnectionError(f"Unexpected ping response: {response!r}")
        except Exception as exc:
            self.disconnect()
            raise CLIConnectionError(f"Ping handshake failed: {exc}") from exc

    def disconnect(self) -> None:
        """Close the socket connection if open."""
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
            self._buffer = ""
            logger.info("Disconnected")

    @property
    def is_connected(self) -> bool:
        """Return whether the socket is currently open."""
        return self._sock is not None

    # -- Command execution --------------------------------------------------

    def send(self, command: str, timeout: float = COMMAND_TIMEOUT) -> str:
        """Send a CLI command and return the OK payload.

        Formats the command as ``CMD:<command>\\n``, writes it to the socket,
        reads the response, and returns the data portion of an ``OK:`` reply.

        Raises:
            CLIError: If the server returns ``ERR:<message>``.
            CLIConnectionError: If the socket is not connected or the read
                times out / fails.
        """
        if self._sock is None:
            raise CLIConnectionError("Not connected to AtticServer")

        # Format and send the command.
        wire = f"{COMMAND_PREFIX}{command}\n"
        try:
            self._sock.settimeout(timeout)
            self._sock.sendall(wire.encode("utf-8"))
        except OSError as exc:
            self.disconnect()
            raise CLIConnectionError(f"Send failed: {exc}") from exc

        # Read the response (one line ending with \n).
        line = self._read_line(timeout)

        if line.startswith(OK_PREFIX):
            return line[len(OK_PREFIX):]
        elif line.startswith(ERROR_PREFIX):
            raise CLIError(line[len(ERROR_PREFIX):])
        elif line.startswith(EVENT_PREFIX):
            # Events are asynchronous notifications — skip and read again.
            # In practice, events rarely arrive during a synchronous exchange,
            # but we handle it gracefully by recursing for the actual response.
            logger.debug("Received event during command: %s", line)
            return self.send("", timeout)  # Read next line (empty CMD is harmless)
        else:
            raise CLIError(f"Unexpected response: {line!r}")

    # -- Internal helpers ---------------------------------------------------

    def _read_line(self, timeout: float) -> str:
        """Read bytes from the socket until a newline is found.

        Accumulates data in an internal buffer to handle partial reads.
        Returns the line without the trailing newline.
        """
        if self._sock is None:
            raise CLIConnectionError("Not connected")

        self._sock.settimeout(timeout)

        while "\n" not in self._buffer:
            try:
                chunk = self._sock.recv(MAX_RECV)
            except socket.timeout as exc:
                raise CLIConnectionError(
                    f"Read timed out after {timeout}s"
                ) from exc
            except OSError as exc:
                self.disconnect()
                raise CLIConnectionError(f"Read failed: {exc}") from exc

            if not chunk:
                self.disconnect()
                raise CLIConnectionError("Connection closed by server")

            self._buffer += chunk.decode("utf-8", errors="replace")

        # Split on the first newline — keep any remainder in the buffer.
        line, self._buffer = self._buffer.split("\n", 1)
        return line


# ---------------------------------------------------------------------------
# Helper functions for tool argument processing
# ---------------------------------------------------------------------------

def parse_hex_bytes(data: str) -> list[int]:
    """Parse a hex byte string into a list of integers.

    Accepts several common formats:
        - Comma-separated: ``"A9,00,8D,00,D4"``
        - Space-separated: ``"A9 00 8D 00 D4"``
        - Dollar-prefixed:  ``"$A9,$00,$8D"``
        - Mixed:            ``"$A9 00, 8D"``

    Returns:
        List of integers in 0–255 range.

    Raises:
        ValueError: If any byte cannot be parsed.
    """
    # Normalize: strip dollar signs, replace commas with spaces, split.
    normalized = data.replace("$", "").replace(",", " ")
    parts = normalized.split()

    result: list[int] = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        value = int(part, 16)
        if not 0 <= value <= 255:
            raise ValueError(f"Byte value out of range: 0x{value:02X}")
        result.append(value)

    if not result:
        raise ValueError("No hex bytes found in input")
    return result


def translate_key(key: str) -> str:
    """Translate a human-readable key name to the character(s) to inject.

    Handles special key names (RETURN, SPACE, ESC, etc.) and modifier
    prefixes (SHIFT+, CTRL+).  Single characters are passed through as-is.

    This mirrors the Swift ``MCPToolHandler.translateKey()`` function.

    Returns:
        The character string to inject via the ``inject keys`` command.
    """
    upper = key.upper().strip()

    # Special keys — maps to the character code the Atari expects.
    special: dict[str, str] = {
        "RETURN": "\n",
        "ENTER": "\n",
        "SPACE": " ",
        "TAB": "\t",
        "ESC": "\x1b",
        "ESCAPE": "\x1b",
        "DELETE": "\x7f",
        "BACKSPACE": "\x7f",
        "BREAK": "\x03",
    }

    if upper in special:
        return special[upper]

    # Modifier keys: SHIFT+<char> or CTRL+<char>.
    if "+" in upper:
        modifier, _, char = upper.partition("+")
        char = char.strip()
        if len(char) == 1:
            if modifier == "SHIFT":
                return char.upper()
            elif modifier == "CTRL":
                # Ctrl+A = 0x01, Ctrl+Z = 0x1A, etc.
                code = ord(char.upper()) - 64
                if 1 <= code <= 26:
                    return chr(code)
        # Fall through for unrecognized modifiers.

    # Single character or unrecognized — return as-is.
    return key


def escape_for_inject(text: str) -> str:
    """Escape a string for the ``inject keys`` wire format.

    The CLI protocol requires certain characters to be escaped before
    transmission in the ``CMD:inject keys <text>`` command:

        \\  →  \\\\
        \\n →  \\\\n
        \\t →  \\\\t
        \\r →  \\\\r
        (space) → \\\\s

    This mirrors ``CLISocketClient.formatCommand()`` for ``.injectKeys``.
    """
    result = text.replace("\\", "\\\\")
    result = result.replace("\n", "\\n")
    result = result.replace("\t", "\\t")
    result = result.replace("\r", "\\r")
    result = result.replace(" ", "\\s")
    return result


# ---------------------------------------------------------------------------
# Internal utilities
# ---------------------------------------------------------------------------

def _pid_alive(pid: int) -> bool:
    """Check if a process with the given PID is running.

    Uses ``os.kill(pid, 0)`` which sends no signal but checks for existence.
    Returns ``True`` if the process exists, ``False`` otherwise.
    """
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we can't signal it — still alive.
        return True
