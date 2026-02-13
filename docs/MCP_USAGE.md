# AtticMCP - Claude Code Integration

This document describes how to use the AtticMCP server to interact with the Atari 800 XL emulator from Claude Code or other MCP-compatible AI assistants.

## Overview

AtticMCP is a Model Context Protocol (MCP) server that exposes the Atari 800 XL emulator's functionality as tools. It is implemented in Python using [FastMCP](https://github.com/modelcontextprotocol/python-sdk) (the official MCP Python SDK), which provides automatic JSON schema generation from type hints and Pydantic input validation. The server communicates via JSON-RPC 2.0 over stdin/stdout and connects to a running AtticServer instance via Unix domain sockets.

The source code lives in `Sources/AtticMCP-Python/`.

## Prerequisites

1. **AtticServer must be running** - The MCP server connects to AtticServer via CLI socket protocol
2. **Python 3.10+** and **uv** - Required to run the MCP server
3. **Claude Code** - Or any MCP-compatible client

### Starting AtticServer

```bash
# In one terminal, start the emulator server
swift run AtticServer

# Optionally specify ROM path
swift run AtticServer --rom-path ~/ROMs
```

The server will create a socket at `/tmp/attic-<pid>.sock`. AtticMCP automatically discovers this socket.

## Configuration

### Project-Level Configuration (Recommended)

The project already includes a `.mcp.json` in the repository root:

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

### User-Level Configuration

Add to `~/.claude/claude_desktop_config.json`:

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

Replace `/path/to/attic` with the absolute path to your Attic repository.

## Available Tools

### Emulator Control

| Tool | Description |
|------|-------------|
| `emulator_status` | Get current emulator state (running/paused, PC, mounted disks, breakpoints) |
| `emulator_pause` | Pause emulation for inspection/debugging |
| `emulator_resume` | Resume emulation after pause |
| `emulator_reset` | Reset the emulator (cold or warm reset) |

**Example - Check Status:**
```
Tool: emulator_status
Result: status running PC=$F302 D1=(none) D2=(none) BP=(none)
```

**Example - Cold Reset:**
```
Tool: emulator_reset
Arguments: { "cold": true }
Result: Emulator reset (cold)
```

### Memory Access

| Tool | Description |
|------|-------------|
| `emulator_read_memory` | Read bytes from memory (returns hex string) |
| `emulator_write_memory` | Write bytes to memory (emulator must be paused) |

**Example - Read Page Zero:**
```
Tool: emulator_read_memory
Arguments: { "address": 0, "count": 16 }
Result: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
```

**Example - Write to Memory:**
```
Tool: emulator_write_memory
Arguments: { "address": 1536, "data": "A9,00,8D,00,D4" }
Result: Wrote 5 bytes to $0600
```

### CPU State

| Tool | Description |
|------|-------------|
| `emulator_get_registers` | Get 6502 CPU registers (A, X, Y, S, P, PC) |
| `emulator_set_registers` | Modify CPU registers (emulator must be paused) |

**Example - Get Registers:**
```
Tool: emulator_get_registers
Result: A=$FF X=$80 Y=$01 S=$F5 P=$B0 PC=$F310
```

**Example - Set PC to Custom Address:**
```
Tool: emulator_set_registers
Arguments: { "pc": 1536 }
Result: Registers updated
```

### Execution Control

| Tool | Description |
|------|-------------|
| `emulator_execute_frames` | Run emulator for N frames (~1/60th second each) |

**Example - Run for 1 Second:**
```
Tool: emulator_execute_frames
Arguments: { "count": 60 }
Result: Executed 60 frames, PC=$E459
```

### Disk Operations

| Tool | Description |
|------|-------------|
| `emulator_mount_disk` | Mount an ATR disk image to a drive (1-8) |
| `emulator_unmount_disk` | Unmount a disk from a drive |
| `emulator_list_drives` | List all drives and their mounted disks |

**Example - Mount a Disk:**
```
Tool: emulator_mount_disk
Arguments: { "drive": 1, "path": "/path/to/game.atr" }
Result: Mounted /path/to/game.atr on D1:
```

**Example - List Drives:**
```
Tool: emulator_list_drives
Result: D1: game.atr  D2: (empty)  D3: (empty) ...
```

**Example - Unmount:**
```
Tool: emulator_unmount_disk
Arguments: { "drive": 1 }
Result: Unmounted D1:
```

### Debugging

| Tool | Description |
|------|-------------|
| `emulator_disassemble` | Disassemble 6502 code at an address |
| `emulator_set_breakpoint` | Set a breakpoint at an address |
| `emulator_clear_breakpoint` | Clear a breakpoint |
| `emulator_list_breakpoints` | List all breakpoints |
| `emulator_step_over` | Step over JSR subroutines |
| `emulator_run_until` | Run until PC reaches a specific address |
| `emulator_assemble` | Assemble a single 6502 instruction to memory |
| `emulator_assemble_block` | Assemble multiple instructions as a block |
| `emulator_fill_memory` | Fill a memory range with a byte value |

**Example - Disassemble at PC:**
```
Tool: emulator_disassemble
Arguments: { "lines": 8 }
Result:
$E459  A5 12     LDA $12
$E45B  29 03     AND #$03
$E45D  D0 F7     BNE $E456
...
```

**Example - Set Breakpoint:**
```
Tool: emulator_set_breakpoint
Arguments: { "address": 1536 }
Result: Breakpoint set at $0600
```

**Example - Step Over:**
```
Tool: emulator_step_over
Result: A=$00 X=$FF Y=$00 S=$F5 P=$32 PC=$E45B
```

**Example - Run Until Address:**
```
Tool: emulator_run_until
Arguments: { "address": 58457 }
Result: Reached $E459
```

**Example - Assemble Single Instruction:**
```
Tool: emulator_assemble
Arguments: { "address": 1536, "instruction": "LDA #$00" }
Result: Assembled 2 bytes at $0600
```

**Example - Assemble a Block of Instructions:**
```
Tool: emulator_assemble_block
Arguments: { "address": 1536, "instructions": ["LDA #$00", "STA $D400", "RTS"] }
Result:
$0600: A9 00     LDA #$00
$0602: 8D 00 D4  STA $D400
$0605: 60        RTS
Assembly complete: 6 bytes at $0600-$0605
```

**Example - Fill Memory:**
```
Tool: emulator_fill_memory
Arguments: { "start": 1536, "end": 1791, "value": 0 }
Result: Filled $0600-$06FF with $00
```

### Keyboard Input

| Tool | Description |
|------|-------------|
| `emulator_press_key` | Simulate a key press |

**Key Values:**
- Letters: `A`-`Z`
- Numbers: `0`-`9`
- Special: `RETURN`, `SPACE`, `BREAK`, `ESC`, `TAB`, `DELETE`
- Modifiers: `SHIFT+A`, `CTRL+C`

**Example - Press Return:**
```
Tool: emulator_press_key
Arguments: { "key": "RETURN" }
Result: Key pressed: RETURN
```

### Display

| Tool | Description |
|------|-------------|
| `emulator_screenshot` | Capture screenshot of the Atari display as PNG |

**Example - Take Screenshot:**
```
Tool: emulator_screenshot
Result: screenshot saved to /Users/name/Desktop/Attic-2026-02-04-223421.png
```

**Example - Save to Custom Path:**
```
Tool: emulator_screenshot
Arguments: { "path": "~/screenshots/atari-game.png" }
Result: screenshot saved to /Users/name/screenshots/atari-game.png
```

### BASIC Programming

| Tool | Description |
|------|-------------|
| `emulator_list_basic` | List the current BASIC program in memory |

**Note:** Direct BASIC memory injection tools (`emulator_enter_basic_line`, `emulator_run_basic`, `emulator_new_basic`) are disabled for safety. Use `emulator_press_key` to type BASIC commands interactively instead.

**Example - List BASIC Program:**
```
Tool: emulator_list_basic
Result:
10 PRINT "HELLO WORLD"
20 GOTO 10
```

**Example - Type BASIC Commands:**
```
# Type a BASIC line using key presses
Tool: emulator_press_key
Arguments: { "key": "1" }

Tool: emulator_press_key
Arguments: { "key": "0" }

# ... continue typing ...

Tool: emulator_press_key
Arguments: { "key": "RETURN" }
```

### State Management

| Tool | Description |
|------|-------------|
| `emulator_save_state` | Save complete emulator state to a file |
| `emulator_load_state` | Load emulator state from a file |

**Example - Save State:**
```
Tool: emulator_save_state
Arguments: { "path": "/tmp/checkpoint.a8s" }
Result: State saved to /tmp/checkpoint.a8s
```

**Example - Load State:**
```
Tool: emulator_load_state
Arguments: { "path": "/tmp/checkpoint.a8s" }
Result: State loaded from /tmp/checkpoint.a8s
```

## Example Workflows

### Workflow 1: Debugging a 6502 Program

```
1. Pause the emulator
   Tool: emulator_pause

2. Check current state
   Tool: emulator_status
   Tool: emulator_get_registers

3. Disassemble at current PC
   Tool: emulator_disassemble
   Arguments: { "lines": 16 }

4. Set a breakpoint
   Tool: emulator_set_breakpoint
   Arguments: { "address": 58457 }

5. Resume and wait for breakpoint
   Tool: emulator_resume

6. When hit, examine memory
   Tool: emulator_read_memory
   Arguments: { "address": 128, "count": 32 }
```

### Workflow 2: Capturing Screenshots

```
1. Take a screenshot of current display
   Tool: emulator_screenshot
   Result: screenshot saved to ~/Desktop/Attic-2026-02-04-120000.png

2. Or save to a specific location
   Tool: emulator_screenshot
   Arguments: { "path": "~/projects/atari/screens/demo.png" }

3. Run program and capture result
   Tool: emulator_execute_frames
   Arguments: { "count": 60 }

   Tool: emulator_screenshot
   Arguments: { "path": "~/output/result.png" }
```

### Workflow 3: Interacting with BASIC

```
1. Check what program is in memory
   Tool: emulator_list_basic

2. Type BASIC commands using key injection
   # Type "10 PRINT "HI""
   Tool: emulator_press_key
   Arguments: { "key": "1" }
   Tool: emulator_press_key
   Arguments: { "key": "0" }
   Tool: emulator_press_key
   Arguments: { "key": "SPACE" }
   # ... continue with P, R, I, N, T, etc.
   Tool: emulator_press_key
   Arguments: { "key": "RETURN" }

3. Let the emulator process input
   Tool: emulator_execute_frames
   Arguments: { "count": 10 }

4. Verify the program was entered
   Tool: emulator_list_basic
```

### Workflow 4: Examining Atari Memory Map

```
# Check BASIC pointers (LOMEM, VNTP, etc.)
Tool: emulator_read_memory
Arguments: { "address": 128, "count": 16 }

# Read screen memory (default at $9C00)
Tool: emulator_read_memory
Arguments: { "address": 39936, "count": 40 }

# Check hardware registers
Tool: emulator_read_memory
Arguments: { "address": 53248, "count": 32 }
```

## Troubleshooting

### "Not connected to AtticServer"

The MCP server couldn't find or connect to AtticServer.

**Solutions:**
1. Ensure AtticServer is running: `swift run AtticServer`
2. Check for socket file: `ls /tmp/attic-*.sock`
3. Restart AtticServer if socket is stale

### "No AtticServer socket found"

No `/tmp/attic-*.sock` file exists.

**Solution:** Start AtticServer first, then use MCP tools.

### Timeout Errors

Commands are timing out waiting for response.

**Possible causes:**
- AtticServer is busy or hung
- Emulator is in a tight loop

**Solutions:**
1. Try `emulator_pause` to stop execution
2. Reset with `emulator_reset`
3. Restart AtticServer

### Memory Write Fails

"Emulator must be paused" error when writing memory.

**Solution:** Always pause before writing:
```
Tool: emulator_pause
Tool: emulator_write_memory
Arguments: { "address": 1536, "data": "A9,00" }
Tool: emulator_resume
```

## Protocol Details

AtticMCP implements the Model Context Protocol (MCP) specification:
- Protocol version: 2024-11-05
- Transport: stdin/stdout
- Message format: JSON-RPC 2.0

The server connects to AtticServer via Unix domain socket using the CLI text protocol defined in `docs/PROTOCOL.md`.

## See Also

- [PROTOCOL.md](PROTOCOL.md) - CLI socket protocol specification
- [6502_REFERENCE.md](6502_REFERENCE.md) - 6502 instruction set reference
- [REPL_COMMANDS.md](REPL_COMMANDS.md) - Full REPL command documentation
