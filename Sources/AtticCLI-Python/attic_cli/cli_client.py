"""Unix domain socket client for communicating with AtticServer.

Adapted from AtticMCP-Python/attic_mcp/cli_client.py with additions for
background event handling and interactive REPL use.
"""

import glob
import logging
import os
import queue
import socket
import threading

from .protocol import (
    COMMAND_PREFIX,
    COMMAND_TIMEOUT,
    CONNECTION_TIMEOUT,
    ERROR_PREFIX,
    EVENT_PREFIX,
    MAX_RECV,
    OK_PREFIX,
    PING_TIMEOUT,
    SOCKET_PATH_PREFIX,
    SOCKET_PATH_SUFFIX,
    CLIEvent,
    CLIResponse,
    parse_event,
    parse_response,
)

logger = logging.getLogger(__name__)


class CLIConnectionError(Exception):
    """Raised when the socket connection fails or is lost."""


class CLIError(Exception):
    """Raised when the server returns an error response."""


class CLISocketClient:
    """Synchronous Unix domain socket client for AtticServer.

    Usage::

        client = CLISocketClient()
        path = client.discover_socket()
        client.connect(path)
        response = client.send("status")
        client.disconnect()

    The client includes a background thread that reads async EVENT: messages
    from the server and queues them for the REPL to process.
    """

    def __init__(self) -> None:
        self._sock: socket.socket | None = None
        self._buffer: str = ""
        self._event_queue: queue.Queue[CLIEvent] = queue.Queue()
        self._event_thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        # Lock serializes send/receive so the event thread doesn't
        # interleave with command responses.
        self._io_lock = threading.Lock()
        self._connected = False

    # --- Connection lifecycle ---

    def discover_socket(self) -> str | None:
        """Scan /tmp for live AtticServer sockets.

        Returns the most recently modified socket path, or None if no
        live server is found. Stale sockets (dead PIDs) are cleaned up.
        """
        pattern = f"{SOCKET_PATH_PREFIX}*{SOCKET_PATH_SUFFIX}"
        candidates: list[tuple[float, str]] = []

        for path in glob.glob(pattern):
            basename = os.path.basename(path)
            pid_str = basename.removeprefix("attic-").removesuffix(".sock")
            try:
                pid = int(pid_str)
            except ValueError:
                continue

            if _pid_alive(pid):
                mtime = os.path.getmtime(path)
                candidates.append((mtime, path))
            else:
                # Clean up stale socket
                try:
                    os.unlink(path)
                    logger.debug("Removed stale socket: %s", path)
                except OSError:
                    pass

        if not candidates:
            return None

        # Most recently modified first
        candidates.sort(reverse=True)
        return candidates[0][1]

    def connect(self, path: str) -> None:
        """Connect to AtticServer at the given socket path.

        Performs a ping handshake to verify the server is responsive.

        Args:
            path: Filesystem path to the Unix domain socket.

        Raises:
            CLIConnectionError: If the connection or ping fails.
        """
        self.disconnect()

        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(CONNECTION_TIMEOUT)
            sock.connect(path)
            self._sock = sock
            self._buffer = ""
        except OSError as exc:
            raise CLIConnectionError(f"Cannot connect to {path}: {exc}") from exc

        # Verify with ping
        try:
            self._sock.settimeout(PING_TIMEOUT)
            self._sock.sendall(f"{COMMAND_PREFIX}ping\n".encode())
            line = self._read_line_raw(PING_TIMEOUT)
            if not line.startswith(OK_PREFIX) or line[len(OK_PREFIX) :] != "pong":
                raise CLIConnectionError(f"Unexpected ping response: {line!r}")
        except Exception:
            self.disconnect()
            raise

        self._connected = True
        self._start_event_reader()

    def disconnect(self) -> None:
        """Close the socket and stop the event reader thread."""
        self._stop_event_reader()
        self._connected = False
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
        self._buffer = ""

    @property
    def is_connected(self) -> bool:
        """True if a socket connection is active."""
        return self._connected and self._sock is not None

    # --- Command sending ---

    def send(self, command: str, timeout: float = COMMAND_TIMEOUT) -> CLIResponse:
        """Send a command and wait for the response.

        Args:
            command: The command string (without CMD: prefix or newline).
            timeout: Maximum seconds to wait for a response.

        Returns:
            CLIResponse with the parsed server response.

        Raises:
            CLIConnectionError: If the socket is closed or times out.
            CLIError: If the server returns an error.
        """
        if self._sock is None:
            raise CLIConnectionError("Not connected")

        with self._io_lock:
            wire = f"{COMMAND_PREFIX}{command}\n".encode()
            try:
                self._sock.sendall(wire)
            except OSError as exc:
                self._connected = False
                raise CLIConnectionError(f"Send failed: {exc}") from exc

            return self._read_response(timeout)

    def send_raw(self, command: str, timeout: float = COMMAND_TIMEOUT) -> str:
        """Send a command and return the raw payload string.

        Convenience wrapper that raises CLIError on error responses.
        """
        response = self.send(command, timeout)
        if not response.success:
            raise CLIError(response.payload)
        return response.payload

    # --- Event handling ---

    def drain_events(self) -> list[CLIEvent]:
        """Return all queued async events, clearing the queue."""
        events = []
        while True:
            try:
                events.append(self._event_queue.get_nowait())
            except queue.Empty:
                break
        return events

    # --- Internal I/O ---

    def _read_response(self, timeout: float) -> CLIResponse:
        """Read lines until we get a non-EVENT response.

        EVENT lines are parsed and queued; we keep reading until we get
        an OK or ERR response.
        """
        while True:
            line = self._read_line_raw(timeout)

            if line.startswith(EVENT_PREFIX):
                event = parse_event(line)
                self._event_queue.put(event)
                continue

            return parse_response(line)

    def _read_line_raw(self, timeout: float) -> str:
        """Read one newline-terminated line from the socket.

        Uses an internal buffer to handle partial reads.

        Returns:
            The line content without the trailing newline.

        Raises:
            CLIConnectionError: On timeout, EOF, or socket error.
        """
        if self._sock is None:
            raise CLIConnectionError("Not connected")

        self._sock.settimeout(timeout)

        while "\n" not in self._buffer:
            try:
                chunk = self._sock.recv(MAX_RECV)
            except socket.timeout as exc:
                raise CLIConnectionError("Timed out waiting for response") from exc
            except OSError as exc:
                self._connected = False
                raise CLIConnectionError(f"Socket error: {exc}") from exc

            if not chunk:
                self._connected = False
                raise CLIConnectionError("Server closed connection")

            self._buffer += chunk.decode("utf-8", errors="replace")

        line, self._buffer = self._buffer.split("\n", 1)
        return line

    # --- Background event reader ---

    def _start_event_reader(self) -> None:
        """Start the background thread that reads async events."""
        # The event reader is not started immediately — it will be started
        # when the REPL is ready. For now, events are handled inline in
        # _read_response(). This avoids the complexity of having two
        # threads reading from the same socket simultaneously.
        #
        # TODO(phase7): Implement background event reader with
        # prompt_toolkit's patch_stdout for clean async display.
        pass

    def _stop_event_reader(self) -> None:
        """Stop the background event reader thread."""
        self._stop_event.set()
        if self._event_thread is not None:
            self._event_thread.join(timeout=2.0)
            self._event_thread = None
        self._stop_event.clear()


# --- Helpers ---


def _pid_alive(pid: int) -> bool:
    """Check if a process with the given PID is still running.

    Uses signal 0 (no actual signal sent) to probe process existence.
    """
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we can't signal it
        return True


def parse_hex_bytes(data: str) -> list[int]:
    """Parse a hex byte string into a list of integers.

    Accepts comma-separated, space-separated, or $-prefixed hex bytes.
    Example inputs: "A9,00,8D", "A9 00 8D", "$A9,$00,$8D"

    Raises:
        ValueError: If any byte is out of 0-255 range or input is empty.
    """
    cleaned = data.replace("$", "").replace(",", " ")
    tokens = cleaned.split()
    if not tokens:
        raise ValueError("Empty byte string")

    result = []
    for token in tokens:
        value = int(token, 16)
        if not 0 <= value <= 255:
            raise ValueError(f"Byte value out of range: {value}")
        result.append(value)
    return result


def escape_for_inject(text: str) -> str:
    """Escape text for the `inject keys` wire format.

    The protocol treats space as a command argument separator, so literal
    spaces must be escaped as \\s. This matches the Swift-side parseEscapes().
    """
    return (
        text.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
        .replace(" ", "\\s")
    )


def translate_key(key: str) -> str:
    """Translate a key name to the character expected by `inject keys`.

    Handles special key names (RETURN, SPACE, etc.) and modifiers
    (SHIFT+key, CTRL+key).
    """
    upper = key.upper()

    specials = {
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

    if upper in specials:
        return specials[upper]

    if upper.startswith("SHIFT+") and len(upper) == 7:
        return upper[6].upper()

    if upper.startswith("CTRL+") and len(upper) == 6:
        ch = upper[5].upper()
        return chr(ord(ch) - 64)

    # Single character or unrecognized — pass through
    return key
