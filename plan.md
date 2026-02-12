# Plan: Reimplement AtticMCP in Python

## Overview

Reimplement the AtticMCP server (currently 5 Swift files in `Sources/AtticMCP/`) as a
Python package using the official [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
(`pip install mcp`). The Python server communicates with AtticServer over the **CLI socket
protocol** (text-based, Unix domain socket at `/tmp/attic-<pid>.sock`), identical to how the
Swift version works.

## Why Python?

- The official MCP Python SDK handles all JSON-RPC 2.0 and MCP lifecycle plumbing
  (initialize, tools/list, tools/call, notifications) automatically via decorators
- No need to hand-roll JSON-RPC encoding, `AnyCodable`, or manual JSON construction
- Easier to install and run — `uv run attic-mcp` vs `swift run AtticMCP`
- Python's `socket` stdlib handles Unix domain sockets directly
- The CLI text protocol (`CMD:…\n` / `OK:…\n` / `ERR:…\n`) is trivial to implement in Python

## Architecture

```
Claude Code ←──stdin/stdout JSON-RPC──→ attic-mcp (Python)
                                            │
                                            │ Unix domain socket
                                            │ /tmp/attic-<pid>.sock
                                            │ Text protocol: CMD:/OK:/ERR:
                                            ▼
                                       AtticServer (Swift, unchanged)
```

The Python MCP server is a **thin translation layer**: it receives MCP tool calls,
formats them as CLI protocol commands, sends them over the Unix socket, parses the
text response, and returns the result.

## File Structure

```
Sources/AtticMCP-Python/
├── pyproject.toml              # Package config, dependencies, entry point
├── README.md                   # (not created unless requested)
├── attic_mcp/
│   ├── __init__.py
│   ├── server.py               # MCP server setup, tool registration
│   ├── cli_socket_client.py    # Unix domain socket client (CLI protocol)
│   ├── tool_handler.py         # Tool execution logic (argument validation, command mapping)
│   └── tool_definitions.py     # All 25 tool definitions with JSON schemas
```

## Dependencies

- `mcp>=1.2.0` — Official MCP Python SDK (handles JSON-RPC, stdio transport, tool registration)
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
dependencies = ["mcp>=1.2.0"]

[project.scripts]
attic-mcp = "attic_mcp.server:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

### Step 2: CLI Socket Client (`cli_socket_client.py`)

Port the Swift `CLISocketClient` to Python. This is a synchronous socket client (the MCP
SDK handles async at the server level; individual tool calls are blocking request-response).

Key responsibilities:
- **Socket discovery**: Scan `/tmp/` for `attic-*.sock` files, validate PID is alive
  via `os.kill(pid, 0)`, pick the most recently modified socket
- **Connection**: `socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)` → `connect(path)`
- **Send command**: Format as `CMD:<command>\n`, write to socket
- **Receive response**: Read until `\n`, parse `OK:` or `ERR:` prefix
- **Timeout**: 30s default, 1s for ping
- **Multi-line responses**: Split on `\x1E` (Record Separator) for disassembly/listing output

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

Methods to implement:
```python
class CLISocketClient:
    def discover_socket() -> str | None
    def connect(path: str) -> None
    def disconnect() -> None
    def send(command: str, timeout: float = 30.0) -> str  # Returns OK data or raises
    @property
    def is_connected(self) -> bool
```

### Step 3: Tool Definitions (`tool_definitions.py`)

Define all 25 tools as a data structure that can be registered with the MCP SDK. Each tool
maps 1:1 from the Swift `MCPToolDefinitions.swift`. The MCP Python SDK uses `@server.tool()`
decorators or a `Tool` class — we define the schemas here and register them in `server.py`.

Tools to port (all 25 from Swift, preserving exact names and schemas):

**Emulator Control (5):**
1. `emulator_status` — no params
2. `emulator_pause` — no params
3. `emulator_resume` — no params
4. `emulator_reset` — `cold: bool` (default true)
5. `emulator_boot_file` — `path: str` (required)

**Memory Access (2):**
6. `emulator_read_memory` — `address: int` (required), `count: int` (default 16)
7. `emulator_write_memory` — `address: int` (required), `data: str` (required)

**CPU State (2):**
8. `emulator_get_registers` — no params
9. `emulator_set_registers` — `a, x, y, s, p, pc: int` (all optional)

**Execution (1):**
10. `emulator_execute_frames` — `count: int` (default 1)

**Debugging (4):**
11. `emulator_disassemble` — `address: int` (optional), `lines: int` (default 16)
12. `emulator_set_breakpoint` — `address: int` (required)
13. `emulator_clear_breakpoint` — `address: int` (required)
14. `emulator_list_breakpoints` — no params

**Input (1):**
15. `emulator_press_key` — `key: str` (required)

**Display (1):**
16. `emulator_screenshot` — `path: str` (optional)

**BASIC (1, read-only):**
17. `emulator_list_basic` — no params

**Disk Operations (3):**
18. `emulator_mount_disk` — `drive: int` (required), `path: str` (required)
19. `emulator_unmount_disk` — `drive: int` (required)
20. `emulator_list_drives` — no params

**Advanced Debugging (4):**
21. `emulator_step_over` — no params
22. `emulator_run_until` — `address: int` (required)
23. `emulator_assemble` — `address: int` (required), `instruction: str` (required)
24. `emulator_fill_memory` — `start: int`, `end: int`, `value: int` (all required)

**State Management (2):**
25. `emulator_save_state` — `path: str` (required)
26. `emulator_load_state` — `path: str` (required)

### Step 4: Tool Handler (`tool_handler.py`)

Port `MCPToolHandler.swift` — the core logic that translates tool calls into CLI commands.

Each tool handler method:
1. Validates arguments (range checks, required params)
2. Formats the CLI command string
3. Sends via `CLISocketClient.send()`
4. Parses the response (multi-line separator → newlines for disassembly/listing)
5. Returns text result or error

CLI command mapping (from Swift → CLI protocol):
```python
TOOL_TO_CLI = {
    "emulator_status":          "status",
    "emulator_pause":           "pause",
    "emulator_resume":          "resume",
    "emulator_reset":           "reset {cold|warm}",
    "emulator_boot_file":       "boot {path}",
    "emulator_read_memory":     "read ${address:04X} {count}",
    "emulator_write_memory":    "write ${address:04X} {hex_bytes}",
    "emulator_get_registers":   "registers",
    "emulator_set_registers":   "registers A=$XX X=$XX ...",
    "emulator_execute_frames":  "step {count}",
    "emulator_disassemble":     "disassemble [${address:04X}] {lines}",
    "emulator_set_breakpoint":  "breakpoint set ${address:04X}",
    "emulator_clear_breakpoint":"breakpoint clear ${address:04X}",
    "emulator_list_breakpoints":"breakpoint list",
    "emulator_press_key":       "inject keys {translated_key}",
    "emulator_screenshot":      "screenshot [{path}]",
    "emulator_list_basic":      "basic LIST",
    "emulator_mount_disk":      "mount {drive} {path}",
    "emulator_unmount_disk":    "unmount {drive}",
    "emulator_list_drives":     "drives",
    "emulator_step_over":       "stepover",
    "emulator_run_until":       "until ${address:04X}",
    "emulator_assemble":        "assemble ${address:04X} {instruction}",
    "emulator_fill_memory":     "fill ${start:04X} ${end:04X} ${value:02X}",
    "emulator_save_state":      "state save {path}",
    "emulator_load_state":      "state load {path}",
}
```

Helper functions to port:
- `parse_hex_bytes(s: str) -> list[int]` — Parse "A9,00,8D" or "A9 00 8D"
- `translate_key(key: str) -> str` — RETURN→\n, SPACE→" ", SHIFT+X, CTRL+X, etc.

### Step 5: MCP Server (`server.py`)

Wire everything together using the MCP Python SDK:

```python
from mcp.server import Server
from mcp.server.stdio import stdio_server

server = Server("AtticMCP")

@server.list_tools()
async def list_tools():
    return ALL_TOOLS  # From tool_definitions.py

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    return await tool_handler.execute(name, arguments)

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())
```

On initialization, the server:
1. Discovers the AtticServer socket (`/tmp/attic-*.sock`)
2. Connects via `CLISocketClient`
3. Verifies connection with a `ping` command
4. If no server found, attempts to launch AtticServer (subprocess)

Server auto-launch logic:
- Search for `AtticServer` executable: same directory, PATH, common locations
- Launch with `--silent` flag, redirect stdout/stderr to devnull
- Wait up to 4s for socket file to appear (poll every 0.2s)

### Step 6: Update `.mcp.json`

Update the project's MCP configuration to use the Python server:

```json
{
  "mcpServers": {
    "attic": {
      "command": "uv",
      "args": ["run", "--directory", "/path/to/attic/Sources/AtticMCP-Python", "attic-mcp"]
    }
  }
}
```

### Step 7: Testing

- Manual testing against running AtticServer
- Verify all 25 tools produce identical responses to the Swift version
- Test socket discovery with multiple/no servers running
- Test auto-launch when no server is running
- Test error handling (server not running, invalid arguments, timeouts)

## Key Differences from Swift Implementation

| Aspect | Swift AtticMCP | Python AtticMCP |
|--------|---------------|-----------------|
| MCP protocol handling | Manual JSON-RPC parsing | MCP SDK handles automatically |
| JSON encoding workarounds | Manual `toJSON()` to avoid 0→false | Not needed in Python |
| `AnyCodable` type | Custom type-erased wrapper | Native Python `dict`/`Any` |
| Socket I/O | Actor-based async with `select()` | Synchronous `socket.recv()` with timeout |
| Threading | Swift concurrency (actors, async/await) | asyncio (MCP SDK) + sync socket calls |
| Lines of code | ~1500 across 5 files | ~600-800 across 5 files |
| Build system | Swift Package Manager | pip/uv + pyproject.toml |

## Risks and Mitigations

1. **Socket timeout handling**: Python's `socket.settimeout()` provides blocking-with-timeout
   semantics, simpler than Swift's detached timeout tasks.

2. **Buffered reads**: Need to handle partial line reads from socket. Use a read buffer
   that accumulates data until `\n` is found, same as the Swift event reader.

3. **Server auto-launch**: The `subprocess.Popen` approach mirrors Swift's `Process` class.
   We search PATH and common locations for `AtticServer`.

4. **MCP SDK version**: Pin to `mcp>=1.2.0` for stable stdio transport support. The SDK
   is maintained by Anthropic and is the recommended approach.

5. **Async/sync bridge**: The MCP SDK is async (asyncio), but CLI socket operations are
   synchronous. Use `asyncio.to_thread()` or `loop.run_in_executor()` to avoid blocking
   the event loop during socket I/O.
