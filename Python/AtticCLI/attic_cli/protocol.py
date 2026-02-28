"""Protocol constants and response parsing for the Attic CLI socket protocol.

These constants must match CLIProtocol.swift exactly. The protocol is frozen —
no changes unless accompanied by a major version bump.
"""

from dataclasses import dataclass


# --- Wire-format prefixes ---

COMMAND_PREFIX = "CMD:"
OK_PREFIX = "OK:"
ERROR_PREFIX = "ERR:"
EVENT_PREFIX = "EVENT:"

# Multi-line responses join lines with ASCII Record Separator (0x1E).
# The client splits on this character to recover individual lines.
MULTI_LINE_SEP = "\x1e"

# --- Socket path ---

SOCKET_PATH_PREFIX = "/tmp/attic-"
SOCKET_PATH_SUFFIX = ".sock"


def socket_path_for_pid(pid: int) -> str:
    """Return the expected socket path for a given AtticServer PID."""
    return f"{SOCKET_PATH_PREFIX}{pid}{SOCKET_PATH_SUFFIX}"


# --- Timeouts (seconds) ---

COMMAND_TIMEOUT = 30.0
PING_TIMEOUT = 1.0
CONNECTION_TIMEOUT = 5.0

# --- Buffer size ---

MAX_RECV = 4096

# --- Protocol version ---

PROTOCOL_VERSION = "1.0"


# --- Response parsing ---


@dataclass(frozen=True, slots=True)
class CLIResponse:
    """Parsed server response.

    Attributes:
        success: True for OK responses, False for errors.
        payload: The response data (after prefix stripping).
        is_multiline: True if payload contains MULTI_LINE_SEP characters.
    """

    success: bool
    payload: str
    is_multiline: bool

    @property
    def lines(self) -> list[str]:
        """Split a multi-line payload into individual lines."""
        if self.is_multiline:
            return self.payload.split(MULTI_LINE_SEP)
        return [self.payload] if self.payload else []


def parse_response(raw: str) -> CLIResponse:
    """Parse a raw protocol response line into a CLIResponse.

    Args:
        raw: A single response line from the server (newline already stripped).

    Returns:
        CLIResponse with success/error status and payload.

    Raises:
        ValueError: If the response doesn't match any known prefix.
    """
    if raw.startswith(OK_PREFIX):
        payload = raw[len(OK_PREFIX) :]
        return CLIResponse(
            success=True,
            payload=payload,
            is_multiline=MULTI_LINE_SEP in payload,
        )

    if raw.startswith(ERROR_PREFIX):
        return CLIResponse(
            success=False,
            payload=raw[len(ERROR_PREFIX) :],
            is_multiline=False,
        )

    raise ValueError(f"Unexpected response: {raw!r}")


@dataclass(frozen=True, slots=True)
class CLIEvent:
    """Parsed async event from the server.

    Attributes:
        kind: Event type — "breakpoint", "stopped", or "error".
        data: Raw event data string after the event type.
    """

    kind: str
    data: str


def parse_event(raw: str) -> CLIEvent:
    """Parse an EVENT: prefixed line into a CLIEvent.

    Args:
        raw: A line starting with EVENT: (prefix already verified by caller).

    Returns:
        CLIEvent with kind and data fields.
    """
    body = raw[len(EVENT_PREFIX) :]
    # Event format: "EVENT:<kind> <data>" or just "EVENT:<kind>"
    parts = body.split(" ", 1)
    kind = parts[0]
    data = parts[1] if len(parts) > 1 else ""
    return CLIEvent(kind=kind, data=data)
