"""FastMCP server for the Attic Atari 800 XL emulator.

This is the main entry point for the AtticMCP Python server.  It creates a
FastMCP instance and registers all 24 emulator tools using ``@mcp.tool()``
decorators.  FastMCP automatically:

    - Generates JSON schemas from Python type annotations
    - Validates inputs via Pydantic before calling the tool function
    - Dispatches ``tools/call`` requests to the matching function by name
    - Handles ``tools/list`` by inspecting all registered tools
    - Manages the JSON-RPC 2.0 / MCP lifecycle over stdio

Each tool function is a thin translation layer: it formats the arguments into
a CLI protocol command, sends it over the Unix socket to AtticServer, and
returns the text response (or an Image for screenshots).

Run with::

    uv run attic-mcp          # via pyproject.toml entry point
    python -m attic_mcp.server # direct execution

For development with the MCP Inspector::

    uv run mcp dev attic_mcp/server.py
"""

from __future__ import annotations

import asyncio
import logging
import os
import shutil
import subprocess
import sys
import time
from typing import Annotated

from pydantic import Field

# FastMCP is the high-level decorator API from the official MCP Python SDK.
# It lives inside the ``mcp`` package (not the standalone ``fastmcp`` package).
from mcp.server.fastmcp import FastMCP, Image

from .cli_client import (
    CLIConnectionError,
    CLIError,
    CLISocketClient,
    MULTI_LINE_SEP,
    escape_for_inject,
    parse_hex_bytes,
    translate_key,
)

# ---------------------------------------------------------------------------
# Logging — all output goes to stderr (stdout is the JSON-RPC transport)
# ---------------------------------------------------------------------------

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("attic-mcp")

# ---------------------------------------------------------------------------
# FastMCP server instance
# ---------------------------------------------------------------------------

mcp = FastMCP("AtticMCP")

# ---------------------------------------------------------------------------
# Shared CLI socket client — connected lazily on first tool call
# ---------------------------------------------------------------------------

_client = CLISocketClient()


async def _send(command: str) -> str:
    """Send a CLI command to AtticServer, connecting lazily if needed.

    This is the central bridge between async FastMCP tool handlers and the
    synchronous CLI socket client.  Socket I/O is offloaded to a thread via
    ``asyncio.to_thread()`` so it doesn't block the event loop.

    If the client is not yet connected, it discovers a running AtticServer
    (or attempts to launch one) before sending.

    Returns:
        The OK payload from the server response.

    Raises:
        RuntimeError: If no AtticServer can be found or launched.
        CLIError: If the server returns an ERR response.
    """
    if not _client.is_connected:
        await _ensure_connected()
    try:
        return await asyncio.to_thread(_client.send, command)
    except CLIConnectionError:
        # Connection may have been lost — try reconnecting once.
        _client.disconnect()
        await _ensure_connected()
        return await asyncio.to_thread(_client.send, command)


async def _ensure_connected() -> None:
    """Discover and connect to AtticServer, launching it if necessary.

    If the ``ATTIC_MCP_NO_LAUNCH`` environment variable is set, the server
    will not attempt to auto-launch AtticServer.  This is used by the test
    harness to ensure both Swift and Python MCP servers share the same
    AtticServer instance.
    """
    path = await asyncio.to_thread(_client.discover_socket)
    if path is None and not os.environ.get("ATTIC_MCP_NO_LAUNCH"):
        logger.info("No AtticServer socket found, attempting to launch...")
        await asyncio.to_thread(_try_launch_server)
        path = await asyncio.to_thread(_client.discover_socket)
    if path is None:
        raise RuntimeError(
            "AtticServer not running and could not be launched. "
            "Start it manually with: swift run AtticServer"
        )
    await asyncio.to_thread(_client.connect, path)


def _try_launch_server() -> None:
    """Attempt to start AtticServer as a background subprocess.

    Searches for the ``AtticServer`` executable in:
      1. The PATH
      2. Common Swift build output directories (``.build/release``, ``.build/debug``)
      3. Standard install locations (``/usr/local/bin``, ``/opt/homebrew/bin``, ``~/.local/bin``)

    After launching, polls up to 4 seconds for the socket file to appear.
    """
    exe = shutil.which("AtticServer")

    if exe is None:
        # Check common Swift build directories relative to the working directory.
        candidates = [
            ".build/release/AtticServer",
            ".build/debug/AtticServer",
            "/usr/local/bin/AtticServer",
            "/opt/homebrew/bin/AtticServer",
            os.path.expanduser("~/.local/bin/AtticServer"),
        ]
        for candidate in candidates:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                exe = candidate
                break

    if exe is None:
        logger.warning("AtticServer executable not found")
        return

    logger.info("Launching AtticServer from %s", exe)
    subprocess.Popen(
        [exe, "--silent"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Poll for the socket file to appear (up to 4 seconds, every 200ms).
    for _ in range(20):
        time.sleep(0.2)
        if _client.discover_socket() is not None:
            logger.info("AtticServer socket discovered after launch")
            return

    logger.warning("AtticServer launched but socket did not appear within 4s")


# ===========================================================================
#  TOOLS — Emulator Control
# ===========================================================================


@mcp.tool()
async def emulator_status() -> str:
    """Get the current emulator status.

    Returns information about the running state, program counter,
    mounted disks, and active breakpoints.
    """
    return await _send("status")


@mcp.tool()
async def emulator_pause() -> str:
    """Pause emulator execution.

    Must be called before writing memory or modifying CPU registers.
    """
    return await _send("pause")


@mcp.tool()
async def emulator_resume() -> str:
    """Resume emulator execution after being paused."""
    return await _send("resume")


@mcp.tool()
async def emulator_reset(
    cold: bool = True,
) -> str:
    """Reset the emulator.

    A cold reset reinitializes all hardware and clears memory.
    A warm reset is equivalent to pressing the RESET key and preserves memory.
    """
    mode = "cold" if cold else "warm"
    return await _send(f"reset {mode}")


@mcp.tool()
async def emulator_boot_file(
    path: Annotated[str, Field(description=(
        "Absolute path to the file to boot. Supports ATR disk images, "
        "XEX executables, BAS BASIC programs, CAS cassette images, "
        "and ROM cartridge files."
    ))],
) -> str:
    """Load and boot a file into the emulator."""
    return await _send(f"boot {path}")


# ===========================================================================
#  TOOLS — Memory Access
# ===========================================================================


@mcp.tool()
async def emulator_read_memory(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Starting address to read from (0-65535 or 0x0000-0xFFFF)",
    )],
    count: Annotated[int, Field(
        ge=1, le=256,
        description="Number of bytes to read (1-256). Default is 16.",
    )] = 16,
) -> str:
    """Read bytes from emulator memory.

    Returns comma-separated hex values. Emulator should be paused for
    consistent reads of multi-byte values.
    """
    return await _send(f"read ${address:04X} {count}")


@mcp.tool()
async def emulator_write_memory(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Starting address to write to (0-65535 or 0x0000-0xFFFF)",
    )],
    data: Annotated[str, Field(description=(
        "Hex string of bytes to write, e.g. 'A9,00,8D,00,D4' or "
        "'A9 00 8D 00 D4' or '$A9,$00,$8D'"
    ))],
) -> str:
    """Write bytes to emulator memory.

    Emulator must be paused first. The data parameter accepts
    comma-separated, space-separated, or dollar-prefixed hex bytes.
    """
    bytes_list = parse_hex_bytes(data)
    hex_str = ",".join(f"{b:02X}" for b in bytes_list)
    return await _send(f"write ${address:04X} {hex_str}")


# ===========================================================================
#  TOOLS — CPU State
# ===========================================================================


@mcp.tool()
async def emulator_get_registers() -> str:
    """Get the 6502 CPU registers.

    Returns the values of A (accumulator), X (index), Y (index),
    S (stack pointer), P (processor status flags), and PC (program counter).
    """
    return await _send("registers")


@mcp.tool()
async def emulator_set_registers(
    a: Annotated[int | None, Field(
        ge=0, le=0xFF,
        description="Accumulator register (0x00-0xFF)",
    )] = None,
    x: Annotated[int | None, Field(
        ge=0, le=0xFF,
        description="X index register (0x00-0xFF)",
    )] = None,
    y: Annotated[int | None, Field(
        ge=0, le=0xFF,
        description="Y index register (0x00-0xFF)",
    )] = None,
    s: Annotated[int | None, Field(
        ge=0, le=0xFF,
        description="Stack pointer register (0x00-0xFF)",
    )] = None,
    p: Annotated[int | None, Field(
        ge=0, le=0xFF,
        description="Processor status register (0x00-0xFF)",
    )] = None,
    pc: Annotated[int | None, Field(
        ge=0, le=0xFFFF,
        description="Program counter (0x0000-0xFFFF)",
    )] = None,
) -> str:
    """Set one or more 6502 CPU registers.

    Emulator must be paused first. Only the registers you specify will be
    modified; unspecified registers are left unchanged.
    """
    # Build the register modification string.  The wire format uses 4-digit
    # hex for all values (matching the Swift implementation's $%04X format).
    parts: list[str] = []
    if a is not None:
        parts.append(f"A=${a:04X}")
    if x is not None:
        parts.append(f"X=${x:04X}")
    if y is not None:
        parts.append(f"Y=${y:04X}")
    if s is not None:
        parts.append(f"S=${s:04X}")
    if p is not None:
        parts.append(f"P=${p:04X}")
    if pc is not None:
        parts.append(f"PC=${pc:04X}")

    if not parts:
        return "No register values specified. Provide at least one of: a, x, y, s, p, pc"

    return await _send(f"registers {' '.join(parts)}")


# ===========================================================================
#  TOOLS — Execution
# ===========================================================================


@mcp.tool()
async def emulator_execute_frames(
    count: Annotated[int, Field(
        ge=1, le=3600,
        description=(
            "Number of frames to execute (1-3600, which is up to 60 seconds). "
            "Default is 1."
        ),
    )] = 1,
) -> str:
    """Run the emulator for a number of frames.

    Each frame is approximately 1/60th of a second of emulated time.
    Useful for advancing execution in controlled steps.
    """
    # The Swift version sends just "step" when count is 1.
    if count == 1:
        return await _send("step")
    return await _send(f"step {count}")


# ===========================================================================
#  TOOLS — Debugging
# ===========================================================================


@mcp.tool()
async def emulator_disassemble(
    address: Annotated[int | None, Field(
        ge=0, le=0xFFFF,
        description=(
            "Starting address to disassemble from. "
            "If not specified, disassembles from the current program counter."
        ),
    )] = None,
    lines: Annotated[int, Field(
        ge=1, le=64,
        description="Number of instructions to disassemble (1-64). Default is 16.",
    )] = 16,
) -> str:
    """Disassemble 6502 machine code into assembly mnemonics.

    Returns one instruction per line with address, hex bytes, and mnemonic.
    """
    # Wire format varies depending on which arguments are provided:
    #   disassemble                    — current PC, default lines
    #   disassemble $XXXX             — from address, default lines
    #   disassemble . <lines>          — current PC, N lines
    #   disassemble $XXXX <lines>      — from address, N lines
    if address is not None and lines != 16:
        cmd = f"disassemble ${address:04X} {lines}"
    elif address is not None:
        cmd = f"disassemble ${address:04X}"
    elif lines != 16:
        cmd = f"disassemble . {lines}"
    else:
        cmd = "disassemble"

    result = await _send(cmd)
    # Replace the multi-line separator with actual newlines.
    return result.replace(MULTI_LINE_SEP, "\n")


@mcp.tool()
async def emulator_set_breakpoint(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Memory address to set the breakpoint at (0x0000-0xFFFF)",
    )],
) -> str:
    """Set a breakpoint at the given address.

    The debugger uses the 6502 BRK instruction ($00) for breakpoints.
    When the program counter reaches this address, execution will pause.
    """
    return await _send(f"breakpoint set ${address:04X}")


@mcp.tool()
async def emulator_clear_breakpoint(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Memory address to clear the breakpoint from (0x0000-0xFFFF)",
    )],
) -> str:
    """Clear a previously set breakpoint at the given address."""
    return await _send(f"breakpoint clear ${address:04X}")


@mcp.tool()
async def emulator_list_breakpoints() -> str:
    """List all currently set breakpoints with their addresses."""
    return await _send("breakpoint list")


# ===========================================================================
#  TOOLS — Input
# ===========================================================================


@mcp.tool()
async def emulator_press_key(
    key: Annotated[str, Field(description=(
        "The key to press. Can be a single character (A-Z, 0-9), or a "
        "special key name: RETURN, SPACE, TAB, ESC, DELETE, BREAK. "
        "Modifiers: SHIFT+key, CTRL+key (e.g. CTRL+C, SHIFT+A)."
    ))],
) -> str:
    """Simulate pressing a key on the Atari keyboard.

    Translates the key name, injects it into the emulator, and runs one
    frame so the keypress is processed by the running program.
    """
    translated = translate_key(key)
    escaped = escape_for_inject(translated)
    return await _send(f"inject keys {escaped}")


# ===========================================================================
#  TOOLS — Display
# ===========================================================================


@mcp.tool()
async def emulator_screenshot(
    path: Annotated[str | None, Field(description=(
        "File path to save the PNG screenshot. If not specified, "
        "saves to a default location (~/Desktop/Attic-<timestamp>.png). "
        "Supports ~ for home directory."
    ))] = None,
):
    """Capture the current emulator display as a PNG screenshot.

    Returns the screenshot as an image if the file can be read,
    or the file path as text otherwise.
    """
    if path:
        result = await _send(f"screenshot {path}")
    else:
        result = await _send("screenshot")

    # The CLI response contains the path to the saved PNG file.
    png_path = result.strip()

    # Try to return the actual image data via FastMCP's Image helper.
    # This is an improvement over the Swift version, which only returns
    # the file path as text.  If the file can't be read, fall back to text.
    expanded = os.path.expanduser(png_path)
    if os.path.isfile(expanded):
        try:
            return Image(path=expanded)
        except Exception:
            pass

    return f"Screenshot saved to: {png_path}"


# ===========================================================================
#  TOOLS — BASIC
# ===========================================================================


@mcp.tool()
async def emulator_list_basic() -> str:
    """List the BASIC program currently in emulator memory.

    Returns the detokenized BASIC source code with line numbers.
    """
    result = await _send("basic LIST")
    return result.replace(MULTI_LINE_SEP, "\n")


# ===========================================================================
#  TOOLS — Disk Operations
# ===========================================================================


@mcp.tool()
async def emulator_mount_disk(
    drive: Annotated[int, Field(
        ge=1, le=8,
        description="Drive number (1-8)",
    )],
    path: Annotated[str, Field(
        description="Absolute path to the ATR disk image file",
    )],
) -> str:
    """Mount an ATR disk image to a drive slot (D1: through D8:)."""
    return await _send(f"mount {drive} {path}")


@mcp.tool()
async def emulator_unmount_disk(
    drive: Annotated[int, Field(
        ge=1, le=8,
        description="Drive number (1-8)",
    )],
) -> str:
    """Unmount the disk image from a drive slot."""
    return await _send(f"unmount {drive}")


@mcp.tool()
async def emulator_list_drives() -> str:
    """List all drive slots and their currently mounted disk images."""
    return await _send("drives")


# ===========================================================================
#  TOOLS — Advanced Debugging
# ===========================================================================


@mcp.tool()
async def emulator_step_over() -> str:
    """Execute one instruction, stepping over JSR subroutine calls.

    Unlike single-stepping, this treats JSR as an atomic operation and
    runs until the subroutine returns.
    """
    return await _send("stepover")


@mcp.tool()
async def emulator_run_until(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Target address to run until the program counter reaches (0x0000-0xFFFF)",
    )],
) -> str:
    """Run the emulator until the program counter reaches the specified address.

    Useful for running to a specific point in the code without setting
    a permanent breakpoint.
    """
    return await _send(f"until ${address:04X}")


@mcp.tool()
async def emulator_assemble(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Memory address to assemble the instruction at (0x0000-0xFFFF)",
    )],
    instruction: Annotated[str, Field(description=(
        "6502 assembly instruction to assemble, e.g. 'LDA #$00', "
        "'JMP $E459', 'NOP', 'STA $D400'"
    ))],
) -> str:
    """Assemble a single 6502 instruction and write it to memory.

    The instruction is assembled at the given address and the resulting
    bytes are written directly to emulator memory.
    """
    return await _send(f"assemble ${address:04X} {instruction}")


@mcp.tool()
async def emulator_assemble_block(
    address: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Starting memory address to assemble at (0x0000-0xFFFF)",
    )],
    instructions: Annotated[list[str], Field(
        min_length=1,
        description=(
            "List of 6502 assembly instructions to assemble sequentially, "
            "e.g. ['LDA #$00', 'STA $D400', 'RTS']. Each instruction is "
            "assembled at the next available address after the previous one."
        ),
    )],
) -> str:
    """Assemble multiple 6502 instructions as a block and write them to memory.

    Starts an interactive assembly session at the given address, feeds each
    instruction in order, then ends the session.  This is more efficient
    than calling emulator_assemble repeatedly because the address advances
    automatically.  Returns each assembled line and a summary.
    """
    # Start the interactive assembly session.
    await _send(f"assemble ${address:04X}")

    assembled_lines: list[str] = []
    try:
        for instr in instructions:
            result = await _send(f"assemble input {instr}")
            # The server returns "<formatted-line>\x1e<next-addr>".
            # We keep the formatted line (before the separator).
            line = result.split(MULTI_LINE_SEP)[0] if MULTI_LINE_SEP in result else result
            assembled_lines.append(line)
    except Exception:
        # Clean up the session on error so the server isn't left with
        # a dangling assembly session for this client.
        try:
            await _send("assemble end")
        except Exception:
            pass
        raise

    # End the session and capture the summary.
    summary = await _send("assemble end")

    return "\n".join(assembled_lines) + "\n" + summary


@mcp.tool()
async def emulator_fill_memory(
    start: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="Start address of the range to fill (0x0000-0xFFFF)",
    )],
    end: Annotated[int, Field(
        ge=0, le=0xFFFF,
        description="End address of the range to fill, inclusive (0x0000-0xFFFF)",
    )],
    value: Annotated[int, Field(
        ge=0, le=0xFF,
        description="Byte value to fill the range with (0x00-0xFF)",
    )],
) -> str:
    """Fill a memory range with a single byte value.

    Emulator must be paused first. Fills all bytes from start to end
    (inclusive) with the specified value.
    """
    if end < start:
        return f"Error: end address (${end:04X}) must be >= start address (${start:04X})"
    return await _send(f"fill ${start:04X} ${end:04X} ${value:02X}")


# ===========================================================================
#  TOOLS — State Management
# ===========================================================================


@mcp.tool()
async def emulator_save_state(
    path: Annotated[str, Field(
        description="Absolute path to save the emulator state file",
    )],
) -> str:
    """Save the complete emulator state to a file.

    Captures CPU registers, memory contents, hardware state, and all
    peripheral configurations. The state can be restored later with
    emulator_load_state.
    """
    return await _send(f"state save {path}")


@mcp.tool()
async def emulator_load_state(
    path: Annotated[str, Field(
        description="Absolute path to the emulator state file to load",
    )],
) -> str:
    """Load a previously saved emulator state from a file.

    Restores all CPU registers, memory contents, hardware state, and
    peripheral configurations to exactly the state when the file was saved.
    """
    return await _send(f"state load {path}")


# ===========================================================================
#  Entry point
# ===========================================================================


def main() -> None:
    """Entry point for the ``attic-mcp`` command.

    Starts the FastMCP server using stdio transport (JSON-RPC 2.0 over
    stdin/stdout).  This is the standard transport for local MCP servers
    used by Claude Code and similar clients.
    """
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
