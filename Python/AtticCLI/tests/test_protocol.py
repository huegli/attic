"""Tests for protocol constants, response parsing, and event parsing."""

import pytest

from attic_cli.protocol import (
    COMMAND_PREFIX,
    COMMAND_TIMEOUT,
    CONNECTION_TIMEOUT,
    ERROR_PREFIX,
    EVENT_PREFIX,
    MAX_RECV,
    MULTI_LINE_SEP,
    OK_PREFIX,
    PING_TIMEOUT,
    PROTOCOL_VERSION,
    SOCKET_PATH_PREFIX,
    SOCKET_PATH_SUFFIX,
    CLIEvent,
    CLIResponse,
    parse_event,
    parse_response,
    socket_path_for_pid,
)


# --- Protocol Constants ---


class TestProtocolConstants:
    """Verify protocol constants match CLIProtocol.swift."""

    def test_command_prefix(self):
        assert COMMAND_PREFIX == "CMD:"

    def test_ok_prefix(self):
        assert OK_PREFIX == "OK:"

    def test_error_prefix(self):
        assert ERROR_PREFIX == "ERR:"

    def test_event_prefix(self):
        assert EVENT_PREFIX == "EVENT:"

    def test_multi_line_separator(self):
        assert MULTI_LINE_SEP == "\x1e"
        assert ord(MULTI_LINE_SEP) == 0x1E

    def test_socket_path_prefix(self):
        assert SOCKET_PATH_PREFIX == "/tmp/attic-"

    def test_socket_path_suffix(self):
        assert SOCKET_PATH_SUFFIX == ".sock"

    def test_timeouts(self):
        assert COMMAND_TIMEOUT == 30.0
        assert PING_TIMEOUT == 1.0
        assert CONNECTION_TIMEOUT == 5.0

    def test_max_recv(self):
        assert MAX_RECV == 4096

    def test_protocol_version(self):
        assert PROTOCOL_VERSION == "1.0"


# --- Socket Path ---


class TestSocketPath:
    def test_socket_path_for_pid(self):
        assert socket_path_for_pid(12345) == "/tmp/attic-12345.sock"

    def test_socket_path_for_pid_1(self):
        assert socket_path_for_pid(1) == "/tmp/attic-1.sock"


# --- Response Parsing ---


class TestParseResponse:
    def test_ok_simple(self):
        resp = parse_response("OK:pong")
        assert resp.success is True
        assert resp.payload == "pong"
        assert resp.is_multiline is False

    def test_ok_empty_payload(self):
        resp = parse_response("OK:")
        assert resp.success is True
        assert resp.payload == ""
        assert resp.is_multiline is False

    def test_ok_multiline(self):
        payload = f"line1{MULTI_LINE_SEP}line2{MULTI_LINE_SEP}line3"
        resp = parse_response(f"OK:{payload}")
        assert resp.success is True
        assert resp.is_multiline is True
        assert resp.lines == ["line1", "line2", "line3"]

    def test_error_response(self):
        resp = parse_response("ERR:Invalid command")
        assert resp.success is False
        assert resp.payload == "Invalid command"
        assert resp.is_multiline is False

    def test_unexpected_response_raises(self):
        with pytest.raises(ValueError, match="Unexpected response"):
            parse_response("UNKNOWN:data")

    def test_lines_single(self):
        resp = parse_response("OK:single line")
        assert resp.lines == ["single line"]

    def test_lines_empty(self):
        resp = parse_response("OK:")
        assert resp.lines == []

    def test_ok_with_colon_in_payload(self):
        resp = parse_response("OK:A=$FF X=$00 Y=$00 S=$FD P=$34 PC=$E000")
        assert resp.success is True
        assert "A=$FF" in resp.payload


# --- Event Parsing ---


class TestParseEvent:
    def test_breakpoint_event(self):
        raw = "EVENT:breakpoint $0600 A=$FF X=$00 Y=$00 S=$FD P=$34"
        event = parse_event(raw)
        assert event.kind == "breakpoint"
        assert "$0600" in event.data

    def test_stopped_event(self):
        raw = "EVENT:stopped $E000"
        event = parse_event(raw)
        assert event.kind == "stopped"
        assert event.data == "$E000"

    def test_error_event(self):
        raw = "EVENT:error Something went wrong"
        event = parse_event(raw)
        assert event.kind == "error"
        assert event.data == "Something went wrong"

    def test_event_without_data(self):
        raw = "EVENT:ping"
        event = parse_event(raw)
        assert event.kind == "ping"
        assert event.data == ""


# --- CLIResponse Dataclass ---


class TestCLIResponse:
    def test_frozen(self):
        resp = CLIResponse(success=True, payload="test", is_multiline=False)
        with pytest.raises(AttributeError):
            resp.success = False  # type: ignore

    def test_equality(self):
        a = CLIResponse(success=True, payload="test", is_multiline=False)
        b = CLIResponse(success=True, payload="test", is_multiline=False)
        assert a == b
