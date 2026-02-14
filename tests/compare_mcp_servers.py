#!/usr/bin/env python3
"""Test harness comparing Python AtticMCP responses with the Swift implementation.

This script starts both the Swift and Python MCP servers as subprocesses,
sends identical JSON-RPC requests to each, and compares the responses to
find discrepancies.

Three levels of comparison are performed:

  Level 1 — Initialize (no AtticServer needed):
    - ``initialize`` response (protocol version, server info, capabilities)

  Level 2 — Schema comparison (no AtticServer needed):
    - ``tools/list`` response (tool names, descriptions, parameter schemas)

  Level 3 — Safe tool calls (requires a running AtticServer):
    - Calls read-only tools (status, get_registers, list_breakpoints, etc.)
    - Compares the response payloads from both servers

Shared AtticServer safety:
    Both MCP servers connect to the same AtticServer instance via socket
    discovery (``/tmp/attic-*.sock``).  This is safe because:

    1. Tool calls are sent **sequentially** — Swift first, then Python —
       so there is no interleaved socket I/O.
    2. Only **read-only** tools are called (status, registers, memory read,
       disassemble, list breakpoints, list drives, list BASIC).
    3. Each MCP server maintains its own independent socket connection to
       AtticServer, so there is no shared socket state.

    Both servers are started with ``ATTIC_MCP_NO_LAUNCH=1`` to prevent
    either one from trying to auto-launch a new AtticServer.

Usage::

    # Schema-only comparison (no AtticServer needed):
    python3 tests/compare_mcp_servers.py

    # Full comparison including tool calls (AtticServer must be running):
    python3 tests/compare_mcp_servers.py --with-calls

    # Verbose output:
    python3 tests/compare_mcp_servers.py -v

    # Specify custom Swift binary path:
    python3 tests/compare_mcp_servers.py --swift-cmd "swift run --package-path /path/to/attic AtticMCP"
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Any

# ---------------------------------------------------------------------------
# Project root detection — the script lives in tests/ under the repo root
# ---------------------------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------
# ANSI colour helpers
# ---------------------------------------------------------------------------

RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"


def red(s: str) -> str:
    return f"{RED}{s}{RESET}"


def green(s: str) -> str:
    return f"{GREEN}{s}{RESET}"


def yellow(s: str) -> str:
    return f"{YELLOW}{s}{RESET}"


def cyan(s: str) -> str:
    return f"{CYAN}{s}{RESET}"


def bold(s: str) -> str:
    return f"{BOLD}{s}{RESET}"


def dim(s: str) -> str:
    return f"{DIM}{s}{RESET}"


# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------

@dataclass
class CompareResult:
    """Tracks pass/fail/warn counts and individual findings."""

    passed: int = 0
    failed: int = 0
    warned: int = 0
    messages: list[str] = field(default_factory=list)

    def ok(self, msg: str) -> None:
        self.passed += 1
        self.messages.append(f"  {green('PASS')} {msg}")

    def fail(self, msg: str) -> None:
        self.failed += 1
        self.messages.append(f"  {red('FAIL')} {msg}")

    def warn(self, msg: str) -> None:
        self.warned += 1
        self.messages.append(f"  {yellow('WARN')} {msg}")

    def print_all(self) -> None:
        for m in self.messages:
            print(m)

    def summary_line(self) -> str:
        parts = [green(f"{self.passed} passed")]
        if self.failed:
            parts.append(red(f"{self.failed} failed"))
        if self.warned:
            parts.append(yellow(f"{self.warned} warnings"))
        return ", ".join(parts)


# ---------------------------------------------------------------------------
# MCP subprocess wrapper
# ---------------------------------------------------------------------------

class MCPProcess:
    """Manages an MCP server subprocess, sending JSON-RPC messages over stdio.

    The MCP protocol runs over stdin/stdout with one JSON object per line
    (newline-delimited JSON-RPC 2.0).  This class starts the server, feeds
    it requests, and reads responses with a timeout.
    """

    def __init__(
        self,
        name: str,
        cmd: list[str],
        cwd: str | None = None,
        env_overrides: dict[str, str] | None = None,
    ) -> None:
        self.name = name
        self.cmd = cmd
        self.cwd = cwd
        self.env_overrides = env_overrides or {}
        self.proc: subprocess.Popen[bytes] | None = None
        self._request_id = 0

    def start(self) -> None:
        """Launch the MCP server subprocess.

        The environment is inherited from the parent process, with any
        ``env_overrides`` applied on top.  The harness sets
        ``ATTIC_MCP_NO_LAUNCH=1`` to prevent either server from trying
        to auto-launch its own AtticServer (which would create conflicts).
        """
        env = os.environ.copy()
        env.update(self.env_overrides)
        self.proc = subprocess.Popen(
            self.cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=self.cwd,
            env=env,
        )

    def stop(self) -> None:
        """Terminate the subprocess."""
        if self.proc is not None:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=5)
            except Exception:
                self.proc.kill()
            self.proc = None

    def send(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a JSON-RPC request and return the parsed response.

        Args:
            method: The JSON-RPC method name (e.g. "initialize", "tools/list").
            params: Optional parameters dict.

        Returns:
            The parsed JSON response dict.

        Raises:
            RuntimeError: If the process is not started or the read times out.
        """
        if self.proc is None or self.proc.stdin is None or self.proc.stdout is None:
            raise RuntimeError(f"{self.name}: process not started")

        self._request_id += 1
        request: dict[str, Any] = {
            "jsonrpc": "2.0",
            "id": self._request_id,
            "method": method,
        }
        if params is not None:
            request["params"] = params

        line = json.dumps(request) + "\n"
        self.proc.stdin.write(line.encode("utf-8"))
        self.proc.stdin.flush()

        # Read one line of response (with timeout via poll).
        return self._read_response(timeout=30.0)

    def send_notification(self, method: str, params: dict[str, Any] | None = None) -> None:
        """Send a JSON-RPC notification (no id, no response expected)."""
        if self.proc is None or self.proc.stdin is None:
            raise RuntimeError(f"{self.name}: process not started")

        msg: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params

        line = json.dumps(msg) + "\n"
        self.proc.stdin.write(line.encode("utf-8"))
        self.proc.stdin.flush()

    def _read_response(self, timeout: float) -> dict[str, Any]:
        """Read a single JSON-RPC response line from stdout.

        Skips any notification lines (messages without an ``id`` field) and
        returns the first response that has an ``id``.  Uses a polling loop
        with a deadline so we don't block forever on a broken server.
        """
        assert self.proc is not None and self.proc.stdout is not None

        import select

        deadline = time.monotonic() + timeout
        buf = b""

        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break

            # Use select to wait for data with a timeout.
            rlist, _, _ = select.select([self.proc.stdout], [], [], min(remaining, 1.0))
            if not rlist:
                continue

            chunk = self.proc.stdout.read1(4096) if hasattr(self.proc.stdout, "read1") else self.proc.stdout.read(1)
            if not chunk:
                break
            buf += chunk

            # Process complete lines.
            while b"\n" in buf:
                line_bytes, buf = buf.split(b"\n", 1)
                line_str = line_bytes.decode("utf-8", errors="replace").strip()
                if not line_str:
                    continue
                try:
                    msg = json.loads(line_str)
                except json.JSONDecodeError:
                    continue
                # Skip notifications (no id field) and error responses
                # to notifications (id is null).
                if "id" in msg and msg["id"] is not None:
                    return msg

        raise RuntimeError(f"{self.name}: timed out waiting for response after {timeout}s")


# ---------------------------------------------------------------------------
# JSON-RPC helpers
# ---------------------------------------------------------------------------

def make_initialize_params() -> dict[str, Any]:
    """Return standard MCP initialize params."""
    return {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {
            "name": "compare-harness",
            "version": "0.1.0",
        },
    }


def make_tool_call_params(name: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
    """Return params for a tools/call request."""
    result: dict[str, Any] = {"name": name}
    if arguments is not None:
        result["arguments"] = arguments
    else:
        result["arguments"] = {}
    return result


# ---------------------------------------------------------------------------
# Comparison logic
# ---------------------------------------------------------------------------

def compare_initialize(swift_resp: dict, python_resp: dict, verbose: bool) -> CompareResult:
    """Compare the initialize responses from both servers."""
    result = CompareResult()

    sr = swift_resp.get("result", {})
    pr = python_resp.get("result", {})

    # Protocol version
    sv = sr.get("protocolVersion")
    pv = pr.get("protocolVersion")
    if sv == pv:
        result.ok(f"Protocol version matches: {sv}")
    else:
        result.fail(f"Protocol version: Swift={sv!r}, Python={pv!r}")

    # Server name
    sn = sr.get("serverInfo", {}).get("name")
    pn = pr.get("serverInfo", {}).get("name")
    if sn == pn:
        result.ok(f"Server name matches: {sn}")
    else:
        result.fail(f"Server name: Swift={sn!r}, Python={pn!r}")

    # Server version (may differ — Python uses FastMCP default)
    svv = sr.get("serverInfo", {}).get("version")
    pvv = pr.get("serverInfo", {}).get("version")
    if svv == pvv:
        result.ok(f"Server version matches: {svv}")
    else:
        result.warn(f"Server version differs: Swift={svv!r}, Python={pvv!r}")

    # Capabilities — both should declare tools
    sc = sr.get("capabilities", {})
    pc = pr.get("capabilities", {})
    if "tools" in sc and "tools" in pc:
        result.ok("Both declare 'tools' capability")
    else:
        result.fail(f"Capabilities: Swift={sc}, Python={pc}")

    if verbose:
        result.print_all()
    return result


def compare_tools_list(
    swift_resp: dict,
    python_resp: dict,
    verbose: bool,
) -> CompareResult:
    """Compare the tools/list responses, checking names, schemas, and descriptions."""
    result = CompareResult()

    swift_tools_raw = swift_resp.get("result", {}).get("tools", [])
    python_tools_raw = python_resp.get("result", {}).get("tools", [])

    # Index by name for easy cross-referencing.
    swift_tools: dict[str, dict] = {t["name"]: t for t in swift_tools_raw}
    python_tools: dict[str, dict] = {t["name"]: t for t in python_tools_raw}

    swift_names = set(swift_tools.keys())
    python_names = set(python_tools.keys())

    # -- Tool set comparison ------------------------------------------------
    only_swift = swift_names - python_names
    only_python = python_names - swift_names
    common = swift_names & python_names

    if not only_swift and not only_python:
        result.ok(f"Tool sets match: {len(common)} tools in both")
    else:
        if only_swift:
            result.fail(f"Tools only in Swift: {sorted(only_swift)}")
        if only_python:
            result.fail(f"Tools only in Python: {sorted(only_python)}")
        result.ok(f"Common tools: {len(common)}")

    # -- Per-tool comparison ------------------------------------------------
    for name in sorted(common):
        st = swift_tools[name]
        pt = python_tools[name]
        _compare_single_tool(name, st, pt, result, verbose)

    if verbose:
        result.print_all()
    return result


def _compare_single_tool(
    name: str,
    swift_tool: dict,
    python_tool: dict,
    result: CompareResult,
    verbose: bool,
) -> None:
    """Compare a single tool definition between Swift and Python."""
    prefix = f"[{name}]"

    # -- Description --------------------------------------------------------
    sd = swift_tool.get("description", "")
    pd = python_tool.get("description", "")
    if sd == pd:
        result.ok(f"{prefix} Descriptions match")
    else:
        # Descriptions always differ (different wording) — warn, don't fail.
        result.warn(f"{prefix} Descriptions differ")
        if verbose:
            result.messages.append(f"        Swift:  {dim(_trunc(sd, 100))}")
            result.messages.append(f"        Python: {dim(_trunc(pd, 100))}")

    # -- Input schema -------------------------------------------------------
    ss = swift_tool.get("inputSchema", {})
    ps = python_tool.get("inputSchema", {})

    # Compare property names.
    s_props = set(ss.get("properties", {}).keys())
    p_props = set(ps.get("properties", {}).keys())

    if s_props == p_props:
        result.ok(f"{prefix} Parameter names match: {sorted(s_props) if s_props else '(none)'}")
    else:
        only_s = s_props - p_props
        only_p = p_props - s_props
        if only_s:
            result.fail(f"{prefix} Parameters only in Swift: {sorted(only_s)}")
        if only_p:
            result.fail(f"{prefix} Parameters only in Python: {sorted(only_p)}")

    # Compare required arrays.
    s_req = set(ss.get("required", []))
    p_req = set(ps.get("required", []))
    if s_req == p_req:
        if s_req:
            result.ok(f"{prefix} Required fields match: {sorted(s_req)}")
    else:
        result.fail(f"{prefix} Required differs: Swift={sorted(s_req)}, Python={sorted(p_req)}")

    # Compare individual parameter schemas.
    common_props = s_props & p_props
    for prop in sorted(common_props):
        sp = ss["properties"][prop]
        pp = ps["properties"][prop]
        _compare_property(name, prop, sp, pp, result, verbose)


def _compare_property(
    tool_name: str,
    prop_name: str,
    swift_prop: dict,
    python_prop: dict,
    result: CompareResult,
    verbose: bool,
) -> None:
    """Compare a single property schema between Swift and Python."""
    prefix = f"[{tool_name}.{prop_name}]"

    # -- Type ---------------------------------------------------------------
    s_type = _extract_type(swift_prop)
    p_type = _extract_type(python_prop)
    if s_type == p_type:
        result.ok(f"{prefix} Type matches: {s_type}")
    else:
        # Optional params may use anyOf in Python vs bare type in Swift.
        # This is an expected FastMCP/Pydantic difference, so warn, not fail.
        if p_type == f"{s_type}|null" or p_type == f"null|{s_type}":
            result.warn(f"{prefix} Type nullable in Python: Swift={s_type}, Python={p_type}")
        else:
            result.fail(f"{prefix} Type mismatch: Swift={s_type}, Python={p_type}")

    # -- Constraints (min/max) ----------------------------------------------
    s_min = swift_prop.get("minimum")
    s_max = swift_prop.get("maximum")

    # Python might nest constraints inside anyOf items or at the top level.
    p_min, p_max = _extract_constraints(python_prop)

    if s_min == p_min and s_max == p_max:
        if s_min is not None or s_max is not None:
            result.ok(f"{prefix} Constraints match: min={s_min}, max={s_max}")
    else:
        # Be tolerant of exclusiveMinimum vs minimum differences.
        if _constraints_equivalent(s_min, s_max, p_min, p_max):
            result.ok(f"{prefix} Constraints equivalent: Swift=({s_min},{s_max}), Python=({p_min},{p_max})")
        else:
            result.fail(
                f"{prefix} Constraints differ: "
                f"Swift=(min={s_min}, max={s_max}), "
                f"Python=(min={p_min}, max={p_max})"
            )

    # -- Default value ------------------------------------------------------
    s_default = swift_prop.get("default")
    p_default = python_prop.get("default")
    if s_default == p_default:
        if s_default is not None:
            result.ok(f"{prefix} Default matches: {s_default}")
    elif s_default is None and p_default is None:
        pass  # Both have no default.
    else:
        result.warn(f"{prefix} Default differs: Swift={s_default!r}, Python={p_default!r}")

    # -- Description (parameter-level) --------------------------------------
    s_desc = swift_prop.get("description", "")
    p_desc = python_prop.get("description", "")
    if not s_desc and not p_desc:
        pass
    elif s_desc == p_desc:
        result.ok(f"{prefix} Param description matches")
    else:
        # Parameter descriptions always differ in phrasing — warn.
        result.warn(f"{prefix} Param description differs")
        if verbose:
            result.messages.append(f"          Swift:  {dim(_trunc(s_desc, 90))}")
            result.messages.append(f"          Python: {dim(_trunc(p_desc, 90))}")


def compare_tool_calls(
    swift_proc: MCPProcess,
    python_proc: MCPProcess,
    verbose: bool,
) -> CompareResult:
    """Call safe read-only tools on both servers and compare responses.

    Only calls tools that don't modify emulator state (read-only).  Requires
    a running AtticServer that both MCP servers connect to independently.

    Calls are made **sequentially** (Swift first, then Python for each tool)
    so both servers never send commands to AtticServer simultaneously.  Since
    only read-only tools are tested, the emulator state is identical for both.
    """
    result = CompareResult()

    # Safe read-only tools with their test arguments.
    safe_calls: list[tuple[str, dict[str, Any]]] = [
        ("emulator_status", {}),
        ("emulator_get_registers", {}),
        ("emulator_list_breakpoints", {}),
        ("emulator_list_drives", {}),
        ("emulator_read_memory", {"address": 0, "count": 16}),
        ("emulator_disassemble", {"address": 0xE000, "lines": 5}),
        ("emulator_list_basic", {}),
    ]

    for tool_name, args in safe_calls:
        prefix = f"[call:{tool_name}]"
        try:
            swift_resp = swift_proc.send("tools/call", make_tool_call_params(tool_name, args))
            python_resp = python_proc.send("tools/call", make_tool_call_params(tool_name, args))
        except RuntimeError as exc:
            result.fail(f"{prefix} Call failed: {exc}")
            continue

        # Extract text content from both responses.
        s_result = swift_resp.get("result", {})
        p_result = python_resp.get("result", {})

        s_content = _extract_text_content(s_result)
        p_content = _extract_text_content(p_result)

        s_error = s_result.get("isError", False)
        p_error = p_result.get("isError", False)

        if s_error != p_error:
            result.fail(f"{prefix} isError differs: Swift={s_error}, Python={p_error}")
        elif s_content == p_content:
            result.ok(f"{prefix} Responses match ({len(s_content)} chars)")
        else:
            # Responses may differ in formatting but carry the same data.
            result.warn(f"{prefix} Response text differs")
            if verbose:
                result.messages.append(f"        Swift:  {dim(_trunc(s_content, 120))}")
                result.messages.append(f"        Python: {dim(_trunc(p_content, 120))}")

    if verbose:
        result.print_all()
    return result


# ---------------------------------------------------------------------------
# Schema extraction helpers
# ---------------------------------------------------------------------------

def _extract_type(prop: dict) -> str:
    """Extract the canonical type string from a JSON Schema property.

    Handles both simple ``{"type": "integer"}`` and Pydantic-style
    ``{"anyOf": [{"type": "integer"}, {"type": "null"}]}`` schemas.
    """
    if "type" in prop:
        return str(prop["type"])

    if "anyOf" in prop:
        types = []
        for item in prop["anyOf"]:
            if "type" in item:
                types.append(str(item["type"]))
        return "|".join(sorted(types))

    if "oneOf" in prop:
        types = []
        for item in prop["oneOf"]:
            if "type" in item:
                types.append(str(item["type"]))
        return "|".join(sorted(types))

    return "unknown"


def _extract_constraints(prop: dict) -> tuple[Any, Any]:
    """Extract min/max constraints, looking inside anyOf items if needed.

    Pydantic schemas for ``int | None`` put constraints inside the
    ``anyOf`` item for the integer type, not at the top level.  This
    function normalises that.
    """
    p_min = prop.get("minimum")
    p_max = prop.get("maximum")

    # Also check exclusiveMinimum/exclusiveMaximum
    if p_min is None:
        p_min = prop.get("exclusiveMinimum")
    if p_max is None:
        p_max = prop.get("exclusiveMaximum")

    if p_min is None and p_max is None:
        # Look inside anyOf/oneOf items.
        for key in ("anyOf", "oneOf"):
            for item in prop.get(key, []):
                if item.get("type") in ("integer", "number"):
                    m = item.get("minimum", item.get("exclusiveMinimum"))
                    x = item.get("maximum", item.get("exclusiveMaximum"))
                    if m is not None or x is not None:
                        return (m, x)

    return (p_min, p_max)


def _constraints_equivalent(
    s_min: Any, s_max: Any,
    p_min: Any, p_max: Any,
) -> bool:
    """Check if constraints are semantically equivalent despite notation differences.

    For example, Pydantic may use ``ge``/``le`` which map to ``minimum``/``maximum``,
    while some schemas use ``exclusiveMinimum``/``exclusiveMaximum``.
    """
    def _coerce(v: Any) -> int | None:
        if v is None:
            return None
        return int(v)

    return _coerce(s_min) == _coerce(p_min) and _coerce(s_max) == _coerce(p_max)


def _extract_text_content(result: dict) -> str:
    """Extract the text from a ToolCallResult content array."""
    content = result.get("content", [])
    texts = []
    for item in content:
        if isinstance(item, dict):
            if item.get("type") == "text":
                texts.append(item.get("text", ""))
            elif item.get("type") == "image":
                texts.append("<image data>")
    return "\n".join(texts)


def _trunc(s: str, max_len: int) -> str:
    """Truncate a string for display, replacing newlines with spaces."""
    s = s.replace("\n", " ").replace("\r", "")
    if len(s) > max_len:
        return s[:max_len] + "..."
    return s


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def check_attic_server_running() -> bool:
    """Check if an AtticServer is reachable via a /tmp/attic-*.sock socket.

    Returns True if a live socket was found, False otherwise.  This is used
    as a pre-flight check before running Level 3 (tools/call) comparisons.
    """
    import glob as globmod
    import signal

    for path in globmod.glob("/tmp/attic-*.sock"):
        basename = os.path.basename(path)
        pid_str = basename.removeprefix("attic-").removesuffix(".sock")
        try:
            pid = int(pid_str)
            os.kill(pid, 0)  # Signal 0 = check existence.
            return True
        except (ValueError, ProcessLookupError, PermissionError):
            continue
    return False


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare Python and Swift AtticMCP server responses",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show detailed per-check output",
    )
    parser.add_argument(
        "--with-calls",
        action="store_true",
        help="Also exercise tools/call (requires a running AtticServer)",
    )
    parser.add_argument(
        "--swift-cmd",
        default=None,
        help=(
            "Command to start the Swift MCP server. Default: "
            "'swift run AtticMCP' in the repo root"
        ),
    )
    parser.add_argument(
        "--python-cmd",
        default=None,
        help=(
            "Command to start the Python MCP server. Default: "
            "'uv run --directory Sources/AtticMCP-Python attic-mcp'"
        ),
    )
    args = parser.parse_args()

    verbose: bool = args.verbose

    # Build server commands.
    if args.swift_cmd:
        swift_cmd = args.swift_cmd.split()
    else:
        swift_cmd = ["swift", "run", "--package-path", REPO_ROOT, "AtticMCP"]

    if args.python_cmd:
        python_cmd = args.python_cmd.split()
    else:
        python_dir = os.path.join(REPO_ROOT, "Sources", "AtticMCP-Python")
        python_cmd = ["uv", "run", "--directory", python_dir, "attic-mcp"]

    print(bold("=" * 70))
    print(bold("  AtticMCP Server Comparison Harness"))
    print(bold("=" * 70))
    print()
    print(f"  Swift command:  {' '.join(swift_cmd)}")
    print(f"  Python command: {' '.join(python_cmd)}")
    print()

    # -- Pre-flight check for --with-calls ----------------------------------
    if args.with_calls:
        if not check_attic_server_running():
            print(red("Error: --with-calls requires a running AtticServer"))
            print("  Start it with: swift run AtticServer")
            print("  Both MCP servers will connect to this same instance.")
            print("  (Read-only tools are called sequentially, so this is safe.)")
            sys.exit(2)
        print(f"  {green('AtticServer detected')} — Level 3 tool calls enabled")
        print()

    # -- Start both servers -------------------------------------------------
    # Set ATTIC_MCP_NO_LAUNCH=1 to prevent either server from trying to
    # auto-launch its own AtticServer.  For --with-calls, the user must
    # start AtticServer manually so both MCP servers share the same instance.
    no_launch_env = {"ATTIC_MCP_NO_LAUNCH": "1"}

    swift = MCPProcess("Swift", swift_cmd, cwd=REPO_ROOT, env_overrides=no_launch_env)
    python = MCPProcess("Python", python_cmd, cwd=REPO_ROOT, env_overrides=no_launch_env)

    try:
        print(f"{cyan('Starting servers...')}")
        swift.start()
        python.start()
        # Give them a moment to initialise.
        time.sleep(2)

        # -- Initialize handshake -------------------------------------------
        print()
        print(bold("--- Level 1: Initialize ---"))
        print()

        init_params = make_initialize_params()
        swift_init = swift.send("initialize", init_params)
        python_init = python.send("initialize", init_params)

        if verbose:
            print(f"  Swift initialize response:  {json.dumps(swift_init, indent=2)[:500]}")
            print(f"  Python initialize response: {json.dumps(python_init, indent=2)[:500]}")
            print()

        init_result = compare_initialize(swift_init, python_init, verbose)
        if not verbose:
            init_result.print_all()
        print(f"\n  Initialize: {init_result.summary_line()}")

        # Send initialized notification (required by MCP protocol).
        swift.send_notification("initialized")
        python.send_notification("initialized")

        # Small delay for servers to process the notification.
        time.sleep(0.5)

        # -- Tools list comparison ------------------------------------------
        print()
        print(bold("--- Level 2: tools/list ---"))
        print()

        swift_tools = swift.send("tools/list", {})
        python_tools = python.send("tools/list", {})

        if verbose:
            s_count = len(swift_tools.get("result", {}).get("tools", []))
            p_count = len(python_tools.get("result", {}).get("tools", []))
            print(f"  Swift tools count:  {s_count}")
            print(f"  Python tools count: {p_count}")
            print()

        tools_result = compare_tools_list(swift_tools, python_tools, verbose)
        if not verbose:
            tools_result.print_all()
        print(f"\n  tools/list: {tools_result.summary_line()}")

        # -- Tool calls (optional) ------------------------------------------
        calls_result = CompareResult()
        if args.with_calls:
            print()
            print(bold("--- Level 3: tools/call (read-only) ---"))
            print()

            calls_result = compare_tool_calls(swift, python, verbose)
            if not verbose:
                calls_result.print_all()
            print(f"\n  tools/call: {calls_result.summary_line()}")

        # -- Overall summary ------------------------------------------------
        print()
        print(bold("=" * 70))
        total_passed = init_result.passed + tools_result.passed + calls_result.passed
        total_failed = init_result.failed + tools_result.failed + calls_result.failed
        total_warned = init_result.warned + tools_result.warned + calls_result.warned
        total = total_passed + total_failed + total_warned

        parts = [green(f"{total_passed} passed")]
        if total_failed:
            parts.append(red(f"{total_failed} failed"))
        if total_warned:
            parts.append(yellow(f"{total_warned} warnings"))

        print(f"  {bold('Overall')}: {', '.join(parts)} ({total} checks)")
        print(bold("=" * 70))

        if total_failed > 0:
            sys.exit(1)

    except RuntimeError as exc:
        print(red(f"\nError: {exc}"))
        sys.exit(2)
    except KeyboardInterrupt:
        print("\nInterrupted.")
    finally:
        swift.stop()
        python.stop()


if __name__ == "__main__":
    main()
