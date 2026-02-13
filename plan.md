# Plan: Reimplement AtticMCP in Python with FastMCP

> **Status: COMPLETED** — The Python FastMCP implementation is active in
> `Sources/AtticMCP-Python/`. The Swift version in `Sources/AtticMCP/` has been
> removed from `Package.swift` and archived. Schema and tool-call equivalence
> verified via `tests/compare_mcp_servers.py`.

## Overview

Reimplement the AtticMCP server (currently 5 Swift files, ~1500 LOC in `Sources/AtticMCP/`) as a
Python package using **FastMCP** — the high-level decorator API from the official
[MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) (`pip install mcp`).

FastMCP auto-generates JSON schemas from Python type hints, eliminating the need for manual
tool definitions, `AnyCodable` wrappers, and JSON-RPC plumbing. Each tool is a single
decorated function — description from docstring, schema from type annotations.

The Python server communicates with AtticServer over the **CLI socket protocol** (text-based,
Unix domain socket at `/tmp/attic-<pid>.sock`), identical to how the Swift version works.

## Why FastMCP?

| Concern | Low-level `Server` (original plan) | FastMCP |
|---------|-----------------------------------|---------|
| Tool registration | Manual `@server.list_tools()` + `@server.call_tool()` dispatcher | `@mcp.tool()` on each function |
| JSON Schema | Hand-crafted `tool_definitions.py` with dicts | Auto-generated from type hints |
| Input validation | Manual in `tool_handler.py` | Pydantic validates before function runs |
| Return types | Manual `CallToolResult` construction | Return `str`, `Image`, or `list` directly |
| Boilerplate | ~80 lines of wiring | `mcp.run(transport="stdio")` |
| Separate files needed | 5 (server, definitions, handler, client, init) | 3 (server+tools, client, init) |

## Architecture

```
Claude Code ←──stdin/stdout JSON-RPC──→ attic-mcp (Python, FastMCP)
                                            │
                                            │ Unix domain socket
                                            │ /tmp/attic-<pid>.sock
                                            │ Text protocol: CMD:/OK:/ERR:
                                            ▼
                                       AtticServer (Swift, unchanged)
```

FastMCP handles the entire left side (JSON-RPC 2.0, MCP lifecycle, tool dispatch, schema
generation, input validation). Our code only needs to: (1) talk to the Unix socket and
(2) define tool functions with type hints.

## File Structure

```
Sources/AtticMCP-Python/
├── pyproject.toml              # Package config, dependencies, entry point
├── attic_mcp/
│   ├── __init__.py             # Package marker
│   ├── server.py               # FastMCP instance + all @mcp.tool() functions
│   └── cli_client.py           # Unix domain socket client (CLI protocol)
```

Three files of tool logic instead of five. The `tool_definitions.py` and `tool_handler.py`
from the original plan are merged into `server.py` — FastMCP's decorators make separate
definition and handler layers unnecessary.

## Dependencies

```toml
dependencies = ["mcp[cli]>=1.8.0"]
```

- `mcp[cli]>=1.8.0` — Official MCP Python SDK with FastMCP and CLI tools
- Python 3.10+
- No other external dependencies (socket, glob, os, signal are stdlib)

## Implementation Steps

### Step 1: Project scaffolding (`pyproject.toml`, `__init__.py`)

Create `Sources/AtticMCP-Python/pyproject.toml`:

```toml
[project]
name = "attic-mcp"
version = "0.1.0"
description = "MCP server for the Attic Atari 800 XL emulator"
requires-python = ">=3.10"
dependencies = ["mcp[cli]>=1.8.0"]

[project.scripts]
attic-mcp = "attic_mcp.server:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

Create `Sources/AtticMCP-Python/attic_mcp/__init__.py`:

```python
"""AtticMCP — MCP server for the Attic Atari 800 XL emulator."""
```

### Step 2: CLI Socket Client (`cli_client.py`)

Port the Swift `CLISocketClient` to Python. This is a synchronous socket client — FastMCP
handles async at the server level; individual tool calls bridge to sync via
`asyncio.to_thread()`.

Key responsibilities:
- **Socket discovery**: Scan `/tmp/` for `attic-*.sock` files, validate PID is alive
  via `os.kill(pid, 0)`, pick the most recently modified socket
- **Connection**: `socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)` → `connect(path)`
- **Send command**: Format as `CMD:<command>\n`, write to socket
- **Receive response**: Read until `\n`, parse `OK:` or `ERR:` prefix
- **Timeout**: 30s default, 1s for ping
- **Multi-line responses**: Replace `\x1E` (Record Separator) with `\n`

Protocol constants (from Swift `CLIProtocol.swift`):
```python
COMMAND_PREFIX = "CMD:"
OK_PREFIX = "OK:"
ERROR_PREFIX = "ERR:"
EVENT_PREFIX = "EVENT:"
MULTI_LINE_SEP = "\x1e"
COMMAND_TIMEOUT = 30.0
PING_TIMEOUT = 1.0
```

Class interface:
```python
class CLISocketClient:
    """Synchronous Unix domain socket client for the AtticServer CLI protocol."""

    def discover_socket(self) -> str | None:
        """Find the most recently modified /tmp/attic-*.sock with a live PID."""
        ...

    def connect(self, path: str) -> None:
        """Connect to the given socket path and verify with ping."""
        ...

    def disconnect(self) -> None:
        """Close the socket connection."""
        ...

    def send(self, command: str, timeout: float = COMMAND_TIMEOUT) -> str:
        """Send a CLI command and return the OK payload. Raises on ERR or timeout."""
        ...

    @property
    def is_connected(self) -> bool:
        ...
```

Helper functions (also in this file):
- `parse_hex_bytes(s: str) -> list[int]` — Parse `"A9,00,8D"` or `"A9 00 8D"` or `"$A9,$00"`
- `translate_key(key: str) -> str` — `RETURN`→`\n`, `SPACE`→`" "`, `SHIFT+X`, `CTRL+X`, etc.

### Step 3: FastMCP Server + Tools (`server.py`)

This is the core file. It creates the FastMCP instance and defines all 24 tools as
decorated functions. FastMCP auto-generates JSON schemas from the type annotations
and uses docstrings as tool descriptions.

#### Server setup and lifecycle

```python
import asyncio
import logging
import sys
from typing import Annotated
from pydantic import Field
from mcp.server.fastmcp import FastMCP, Context, Image

from .cli_client import CLISocketClient, translate_key, parse_hex_bytes

# Logging to stderr (stdout is reserved for JSON-RPC)
logging.basicConfig(stream=sys.stderr, level=logging.INFO)
logger = logging.getLogger("attic-mcp")

# Create FastMCP server instance
mcp = FastMCP("AtticMCP")

# Shared client — connected lazily on first tool call
_client = CLISocketClient()

async def _send(command: str) -> str:
    """Send a CLI command, connecting to AtticServer if needed.
    Bridges sync socket I/O to async via asyncio.to_thread()."""
    if not _client.is_connected:
        path = _client.discover_socket()
        if path is None:
            _try_launch_server()
            path = _client.discover_socket()
        if path is None:
            raise RuntimeError("AtticServer not running. Start it with: swift run AtticServer")
        _client.connect(path)
    return await asyncio.to_thread(_client.send, command)
```

#### Tool functions — all 24 tools

Each tool is a decorated async function. FastMCP reads the function name as the tool name,
the docstring as the description, and the type-annotated parameters as the JSON schema.
`Annotated[type, Field(...)]` adds constraints and per-parameter descriptions.

**Emulator Control (5 tools):**

```python
@mcp.tool()
async def emulator_status() -> str:
    """Get the current emulator status including running state, program counter, mounted disks, and breakpoints."""
    return await _send("status")

@mcp.tool()
async def emulator_pause() -> str:
    """Pause emulator execution. Required before memory writes or register modifications."""
    return await _send("pause")

@mcp.tool()
async def emulator_resume() -> str:
    """Resume emulator execution after being paused."""
    return await _send("resume")

@mcp.tool()
async def emulator_reset(cold: bool = True) -> str:
    """Reset the emulator. Cold reset reinitializes all hardware; warm reset is like pressing the RESET key."""
    mode = "cold" if cold else "warm"
    return await _send(f"reset {mode}")

@mcp.tool()
async def emulator_boot_file(
    path: Annotated[str, Field(description="Path to file to boot (ATR, XEX, BAS, CAS, or ROM)")]
) -> str:
    """Load and boot a file into the emulator. Supports ATR disk images, XEX executables, BAS BASIC programs, CAS cassette images, and ROM cartridge files."""
    return await _send(f"boot {path}")
```

**Memory Access (2 tools):**

```python
@mcp.tool()
async def emulator_read_memory(
    address: Annotated[int, Field(ge=0, le=0xFFFF, description="Memory address (0x0000-0xFFFF)")],
    count: Annotated[int, Field(ge=1, le=256, description="Number of bytes to read")] = 16
) -> str:
    """Read bytes from emulator memory. Returns comma-separated hex values. Emulator must be paused for consistent reads."""
    return await _send(f"read ${address:04X} {count}")

@mcp.tool()
async def emulator_write_memory(
    address: Annotated[int, Field(ge=0, le=0xFFFF, description="Memory address (0x0000-0xFFFF)")],
    data: Annotated[str, Field(description="Hex bytes to write, e.g. 'A9,00,8D' or 'A9 00 8D'")]
) -> str:
    """Write bytes to emulator memory. Emulator must be paused first."""
    # Validate and normalize hex bytes
    bytes_list = parse_hex_bytes(data)
    hex_str = ",".join(f"{b:02X}" for b in bytes_list)
    return await _send(f"write ${address:04X} {hex_str}")
```

**CPU State (2 tools):**

```python
@mcp.tool()
async def emulator_get_registers() -> str:
    """Get 6502 CPU registers: A (accumulator), X, Y (index), S (stack pointer), P (processor status), PC (program counter)."""
    return await _send("registers")

@mcp.tool()
async def emulator_set_registers(
    a: Annotated[int | None, Field(ge=0, le=0xFF, description="Accumulator (0x00-0xFF)")] = None,
    x: Annotated[int | None, Field(ge=0, le=0xFF, description="X register (0x00-0xFF)")] = None,
    y: Annotated[int | None, Field(ge=0, le=0xFF, description="Y register (0x00-0xFF)")] = None,
    s: Annotated[int | None, Field(ge=0, le=0xFF, description="Stack pointer (0x00-0xFF)")] = None,
    p: Annotated[int | None, Field(ge=0, le=0xFF, description="Processor status (0x00-0xFF)")] = None,
    pc: Annotated[int | None, Field(ge=0, le=0xFFFF, description="Program counter (0x0000-0xFFFF)")] = None,
) -> str:
    """Set one or more 6502 CPU registers. Emulator must be paused first. Only specified registers are modified."""
    parts = []
    if a is not None: parts.append(f"A=${a:02X}")
    if x is not None: parts.append(f"X=${x:02X}")
    if y is not None: parts.append(f"Y=${y:02X}")
    if s is not None: parts.append(f"S=${s:02X}")
    if p is not None: parts.append(f"P=${p:02X}")
    if pc is not None: parts.append(f"PC=${pc:04X}")
    if not parts:
        return "No registers specified"
    return await _send(f"registers {' '.join(parts)}")
```

**Execution (1 tool):**

```python
@mcp.tool()
async def emulator_execute_frames(
    count: Annotated[int, Field(ge=1, le=3600, description="Number of frames to execute (1-3600, each ~1/60s)")] = 1
) -> str:
    """Run the emulator for N frames. Each frame is approximately 1/60th of a second. Useful for advancing execution in controlled steps."""
    return await _send(f"step {count}")
```

**Debugging (4 tools):**

```python
@mcp.tool()
async def emulator_disassemble(
    address: Annotated[int | None, Field(ge=0, le=0xFFFF, description="Start address (default: current PC)")] = None,
    lines: Annotated[int, Field(ge=1, le=64, description="Number of lines to disassemble")] = 16
) -> str:
    """Disassemble 6502 machine code into assembly mnemonics."""
    addr_part = f" ${address:04X}" if address is not None else ""
    result = await _send(f"disassemble{addr_part} {lines}")
    return result.replace("\x1e", "\n")  # Multi-line separator → newlines

@mcp.tool()
async def emulator_set_breakpoint(
    address: Annotated[int, Field(ge=0, le=0xFFFF, description="Address to set breakpoint at")]
) -> str:
    """Set a breakpoint at the given address. Uses 6502 BRK instruction ($00)."""
    return await _send(f"breakpoint set ${address:04X}")

@mcp.tool()
async def emulator_clear_breakpoint(
    address: Annotated[int, Field(ge=0, le=0xFFFF, description="Address to clear breakpoint from")]
) -> str:
    """Clear a previously set breakpoint."""
    return await _send(f"breakpoint clear ${address:04X}")

@mcp.tool()
async def emulator_list_breakpoints() -> str:
    """List all currently set breakpoints."""
    return await _send("breakpoint list")
```

**Input (1 tool):**

```python
@mcp.tool()
async def emulator_press_key(
    key: Annotated[str, Field(description="Key to press: single char, or special name like RETURN, SPACE, TAB, BREAK, ESC, SHIFT+X, CTRL+X")]
) -> str:
    """Simulate pressing a key on the Atari keyboard. After injection, runs one frame so the keypress is processed."""
    translated = translate_key(key)
    return await _send(f"inject keys {translated}")
```

**Display (1 tool):**

```python
@mcp.tool()
async def emulator_screenshot(
    path: Annotated[str | None, Field(description="File path for the PNG screenshot (default: temp file)")] = None
) -> Image:
    """Capture the current emulator display as a PNG screenshot."""
    if path:
        result = await _send(f"screenshot {path}")
    else:
        result = await _send("screenshot")
    # result contains the path to the saved PNG
    png_path = result.strip()
    return Image(path=png_path)
```

Note: `Image` is FastMCP's helper — it reads the file and returns `ImageContent` with
base64-encoded PNG data automatically.

**BASIC (1 tool):**

```python
@mcp.tool()
async def emulator_list_basic() -> str:
    """List the BASIC program currently in emulator memory (detokenized source code)."""
    result = await _send("basic LIST")
    return result.replace("\x1e", "\n")
```

**Disk Operations (3 tools):**

```python
@mcp.tool()
async def emulator_mount_disk(
    drive: Annotated[int, Field(ge=1, le=8, description="Drive number (1-8)")],
    path: Annotated[str, Field(description="Path to ATR disk image file")]
) -> str:
    """Mount an ATR disk image to a drive slot."""
    return await _send(f"mount {drive} {path}")

@mcp.tool()
async def emulator_unmount_disk(
    drive: Annotated[int, Field(ge=1, le=8, description="Drive number (1-8)")]
) -> str:
    """Unmount the disk image from a drive slot."""
    return await _send(f"unmount {drive}")

@mcp.tool()
async def emulator_list_drives() -> str:
    """List all drive slots and their mounted disk images."""
    return await _send("drives")
```

**Advanced Debugging (4 tools):**

```python
@mcp.tool()
async def emulator_step_over() -> str:
    """Execute one instruction, stepping over JSR subroutine calls."""
    return await _send("stepover")

@mcp.tool()
async def emulator_run_until(
    address: Annotated[int, Field(ge=0, le=0xFFFF, description="Address to run until PC reaches")]
) -> str:
    """Run the emulator until the program counter reaches the specified address."""
    return await _send(f"until ${address:04X}")

@mcp.tool()
async def emulator_assemble(
    address: Annotated[int, Field(ge=0, le=0xFFFF, description="Address to assemble instruction at")],
    instruction: Annotated[str, Field(description="6502 assembly instruction, e.g. 'LDA #$42' or 'JSR $E459'")]
) -> str:
    """Assemble a single 6502 instruction and write it to memory at the given address."""
    return await _send(f"assemble ${address:04X} {instruction}")

@mcp.tool()
async def emulator_fill_memory(
    start: Annotated[int, Field(ge=0, le=0xFFFF, description="Start address")],
    end: Annotated[int, Field(ge=0, le=0xFFFF, description="End address (inclusive)")],
    value: Annotated[int, Field(ge=0, le=0xFF, description="Byte value to fill with")]
) -> str:
    """Fill a memory range with a byte value. Emulator must be paused."""
    return await _send(f"fill ${start:04X} ${end:04X} ${value:02X}")
```

**State Management (2 tools):**

```python
@mcp.tool()
async def emulator_save_state(
    path: Annotated[str, Field(description="File path to save the emulator state to")]
) -> str:
    """Save the complete emulator state (CPU, memory, hardware) to a file."""
    return await _send(f"state save {path}")

@mcp.tool()
async def emulator_load_state(
    path: Annotated[str, Field(description="File path to load the emulator state from")]
) -> str:
    """Load a previously saved emulator state from a file."""
    return await _send(f"state load {path}")
```

#### Entry point

```python
def main():
    """Entry point for the attic-mcp command."""
    mcp.run(transport="stdio")

if __name__ == "__main__":
    main()
```

That's it. No `list_tools()`, no `call_tool()` dispatcher, no `tool_definitions.py`,
no `tool_handler.py`. FastMCP does all the wiring.

### Step 4: Server auto-launch logic

If no AtticServer socket is found, attempt to launch one:

```python
def _try_launch_server() -> None:
    """Attempt to start AtticServer as a subprocess."""
    import subprocess, shutil, time

    # Search for AtticServer executable
    exe = shutil.which("AtticServer")
    if exe is None:
        # Try common build locations
        for candidate in [
            ".build/release/AtticServer",
            ".build/debug/AtticServer",
        ]:
            if os.path.isfile(candidate):
                exe = candidate
                break
    if exe is None:
        return  # Caller will raise RuntimeError

    subprocess.Popen(
        [exe, "--silent"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # Wait for socket to appear (poll every 200ms, up to 4s)
    for _ in range(20):
        time.sleep(0.2)
        if _client.discover_socket():
            return
```

### Step 5: Update `.mcp.json`

Update the project's MCP configuration to use the Python server:

```json
{
  "mcpServers": {
    "attic": {
      "command": "uv",
      "args": ["run", "--directory", "Sources/AtticMCP-Python", "attic-mcp"]
    }
  }
}
```

### Step 6: Testing

- `uv run mcp dev Sources/AtticMCP-Python/attic_mcp/server.py` — MCP Inspector UI for
  interactive tool testing
- Manual testing against running AtticServer
- Verify all 24 tools produce identical responses to the Swift version
- Test socket discovery with multiple/no servers running
- Test auto-launch when no server is running
- Test Pydantic validation (out-of-range addresses, missing required params)
- Test error handling (server not running, invalid arguments, timeouts)

## What FastMCP Eliminates

Compared to the original plan's low-level `Server` approach:

| Eliminated | Why |
|------------|-----|
| `tool_definitions.py` (entire file) | Schemas auto-generated from type hints |
| `tool_handler.py` (entire file) | Handler logic lives in each `@mcp.tool()` function |
| `@server.list_tools()` handler | FastMCP registers tools automatically |
| `@server.call_tool()` dispatcher | FastMCP dispatches by function name |
| Manual `CallToolResult` construction | Return `str` or `Image` directly |
| `stdio_server()` context manager | `mcp.run(transport="stdio")` |
| Input validation code | Pydantic validates from `Field(ge=..., le=...)` |
| JSON Schema dicts | Generated from `Annotated[int, Field(...)]` |

## Comparison: Swift vs Python (FastMCP)

| Aspect | Swift AtticMCP | Python AtticMCP (FastMCP) |
|--------|---------------|--------------------------|
| MCP protocol | Manual JSON-RPC parsing | FastMCP handles all of it |
| Tool definitions | 541-line `MCPToolDefinitions.swift` | Type hints on each function |
| Tool dispatch | 835-line `MCPToolHandler.swift` | Inline in each `@mcp.tool()` function |
| JSON workarounds | `AnyCodable`, manual `toJSON()` | Not needed |
| Input validation | Manual range checks | Pydantic `Field(ge=..., le=...)` |
| Image returns | Manual base64 + JSON | `return Image(path=...)` |
| Lines of code | ~1500 across 5 files | ~400-500 across 3 files |
| Build system | Swift Package Manager | pip/uv + pyproject.toml |

## Risks and Mitigations

1. **Async/sync bridge**: FastMCP tool functions are `async def`, but socket I/O is
   synchronous. We use `asyncio.to_thread()` to offload blocking `send()` calls
   without stalling the event loop.

2. **Socket buffering**: Python's `socket.recv()` may return partial data. The
   `CLISocketClient` uses a read buffer that accumulates bytes until `\n` is found.

3. **Pydantic validation errors**: FastMCP returns JSON-RPC errors automatically when
   Pydantic rejects inputs. We rely on this rather than writing our own validation —
   the `Field(ge=0, le=0xFFFF)` constraints match the Swift version's range checks.

4. **Image return for screenshots**: FastMCP's `Image(path=...)` reads the file and
   base64-encodes it. If the screenshot file is missing (AtticServer error), we get
   a clear Python exception that FastMCP converts to an error response.

5. **Server auto-launch**: Uses `subprocess.Popen` with polling, same approach as Swift.
   If the server can't be found, we raise a clear error message rather than hanging.
