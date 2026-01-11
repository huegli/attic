# CLI/GUI Socket Protocol

## Overview

The CLI and GUI communicate over a Unix domain socket using a simple line-based text protocol. This design allows easy debugging and is compatible with tools like `socat` or `nc` for testing.

## Connection

### Socket Location

The GUI creates a socket at startup:
```
/tmp/attic-<pid>.sock
```

Where `<pid>` is the GUI process ID.

### Discovery

The CLI looks for existing sockets:
```bash
ls /tmp/attic-*.sock
```

If multiple sockets exist (unlikely), use the most recent by modification time.

### Handshake

```
CLI: CMD:ping
GUI: OK:pong
```

If no response within 1 second, retry up to 3 times before failing.

## Message Format

### Request (CLI → GUI)

```
CMD:<command> [arguments...]
```

- Single line, terminated by newline (`\n`)
- Command and arguments separated by spaces
- Arguments containing spaces must be quoted or escaped
- Maximum line length: 4096 bytes

### Response (GUI → CLI)

**Success:**
```
OK:<response-data>
```

**Error:**
```
ERR:<error-message>
```

**Multi-line Response:**

Lines are joined with record separator (`\x1E`):
```
OK:line1\x1Eline2\x1Eline3
```

The CLI splits on `\x1E` for display.

### Async Events (GUI → CLI)

Events can arrive at any time:
```
EVENT:<event-type> <data>
```

The CLI must handle these between commands.

## Commands Reference

### Emulator Control

#### ping
Test connection.
```
CMD:ping
OK:pong
```

#### pause
Pause emulator execution.
```
CMD:pause
OK:paused
```

#### resume
Resume emulator execution.
```
CMD:resume
OK:resumed
```

#### step
Execute one or more instructions.
```
CMD:step
OK:stepped A=$00 X=$00 Y=$00 S=$FF P=$34 PC=$E477

CMD:step 10
OK:stepped A=$4F X=$03 Y=$00 S=$FD P=$30 PC=$E4A2
```

#### reset
Reset the emulator.
```
CMD:reset cold
OK:reset cold

CMD:reset warm
OK:reset warm
```

#### status
Get emulator status.
```
CMD:status
OK:status running PC=$E477 D1=/path/to/disk.atr D2=(none) BP=$600A,$602F
```

Status fields:
- `running` or `paused` - emulator state
- `PC=$XXXX` - current program counter
- `D1=...` through `D8=...` - mounted disk paths or `(none)`
- `BP=...` - comma-separated breakpoint addresses or `(none)`

### Memory Operations

#### read
Read bytes from memory.
```
CMD:read $0600 16
OK:data A9,00,8D,00,D4,A9,01,8D,01,D4,60,00,00,00,00,00
```

Address can be hex ($xxxx) or decimal. Length is in bytes.

#### write
Write bytes to memory.
```
CMD:write $0600 A9,00,8D,00,D4
OK:written 5
```

Bytes are comma-separated hex values.

### CPU State

#### registers
Get or set CPU registers.
```
CMD:registers
OK:A=$00 X=$00 Y=$00 S=$FF P=$34 PC=$E477

CMD:registers A=$50 X=$10
OK:A=$50 X=$10 Y=$00 S=$FF P=$34 PC=$E477
```

Register names: A, X, Y, S (stack pointer), P (status), PC

### Breakpoints

#### breakpoint set
Set a breakpoint.
```
CMD:breakpoint set $600A
OK:breakpoint set $600A
```

#### breakpoint clear
Clear a breakpoint.
```
CMD:breakpoint clear $600A
OK:breakpoint cleared $600A
```

#### breakpoint clearall
Clear all breakpoints.
```
CMD:breakpoint clearall
OK:breakpoints cleared
```

#### breakpoint list
List all breakpoints.
```
CMD:breakpoint list
OK:breakpoints $600A,$602F,$E477
```

Empty list:
```
CMD:breakpoint list
OK:breakpoints (none)
```

### Disk Operations

#### mount
Mount a disk image.
```
CMD:mount 1 /Users/nick/disks/game.atr
OK:mounted 1 /Users/nick/disks/game.atr
```

#### unmount
Unmount a disk.
```
CMD:unmount 1
OK:unmounted 1
```

#### drives
List mounted drives.
```
CMD:drives
OK:drives 1=/Users/nick/disks/game.atr,2=/Users/nick/disks/save.atr

CMD:drives
OK:drives (none)
```

### State Management

#### state save
Save emulator state.
```
CMD:state save /Users/nick/saves/game.attic
OK:state saved /Users/nick/saves/game.attic
```

#### state load
Load emulator state.
```
CMD:state load /Users/nick/saves/game.attic
OK:state loaded /Users/nick/saves/game.attic
```

### Display

#### screenshot
Capture screen to file.
```
CMD:screenshot /Users/nick/screenshots/screen.png
OK:screenshot /Users/nick/screenshots/screen.png
```

Default path if not specified:
```
CMD:screenshot
OK:screenshot /Users/nick/Desktop/Attic-<YYYYMMDD-HHMMSS>.png
```

### BASIC Injection

#### inject basic
Inject tokenized BASIC program into memory.
```
CMD:inject basic <base64-encoded-tokenized-data>
OK:injected basic 1234 bytes
```

The data is base64-encoded binary of the tokenized BASIC program including all memory structures (VNTP, VVTP, STMTAB, etc.).

### Keyboard Injection

#### inject keys
Inject keystrokes as if typed.
```
CMD:inject keys RUN\n
OK:injected keys 4
```

Escape sequences:
- `\n` - Return
- `\t` - Tab
- `\e` - Escape
- `\\` - Backslash

### Session Control

#### quit
Disconnect CLI (leave GUI running).
```
CMD:quit
OK:goodbye
[connection closed by CLI]
```

#### shutdown
Terminate GUI and disconnect.
```
CMD:shutdown
OK:shutting down
[connection closed by GUI]
```

## Async Events

Events are sent by the GUI without a corresponding command.

### breakpoint
Breakpoint was hit.
```
EVENT:breakpoint $600A A=$4F X=$00 Y=$03 S=$F7 P=$B4
```

### stopped
Emulator stopped (e.g., BRK instruction without breakpoint).
```
EVENT:stopped $600A
```

### error
Async error occurred.
```
EVENT:error Disk read error on D1:
```

## Error Responses

All errors follow the format:
```
ERR:<error-message>
```

### Common Errors

```
ERR:Invalid command 'foo'
ERR:Invalid address 'ZZZZ'
ERR:Invalid register 'Q'
ERR:File not found '/path/to/file'
ERR:Permission denied '/path/to/file'
ERR:Disk image not mounted: 1
ERR:Breakpoint already set at $600A
ERR:No breakpoint at $600A
ERR:Invalid base64 data
ERR:State file corrupt
```

## Protocol Versioning

Future versions may add a version negotiation:
```
CMD:version
OK:version 1.0

CMD:version 2.0
ERR:Unsupported version 2.0, server is 1.0
```

For now, version 1.0 is implied.

## Examples

### Complete Session

```
# CLI connects
CMD:ping
OK:pong

# Check what's mounted
CMD:drives
OK:drives (none)

# Mount a disk
CMD:mount 1 /Users/nick/disks/game.atr
OK:mounted 1 /Users/nick/disks/game.atr

# Check registers
CMD:registers
OK:A=$00 X=$00 Y=$00 S=$FF P=$34 PC=$E477

# Set a breakpoint
CMD:breakpoint set $600A
OK:breakpoint set $600A

# Resume execution
CMD:resume
OK:resumed

# ... some time passes, breakpoint hits ...
EVENT:breakpoint $600A A=$4F X=$00 Y=$03 S=$F7 P=$B4

# Read memory around PC
CMD:read $6000 32
OK:data A9,00,8D,00,D4,A9,01,8D,01,D4,4C,00,60,...

# Step a few instructions
CMD:step 5
OK:stepped A=$00 X=$00 Y=$03 S=$F7 P=$36 PC=$600F

# Take a screenshot
CMD:screenshot
OK:screenshot /Users/nick/Desktop/Attic-<YYYYMMDD-HHMMSS>.png

# Save state
CMD:state save /Users/nick/saves/checkpoint.attic
OK:state saved /Users/nick/saves/checkpoint.attic

# Disconnect
CMD:quit
OK:goodbye
```

## Implementation Notes

### Socket Permissions

The socket should be created with mode 0600 (user read/write only) for security.

### Buffer Management

- Read buffer: 8192 bytes
- Write buffer: 8192 bytes
- Line accumulator for partial reads

### Timeout Handling

- Command timeout: 30 seconds (for long operations like state save)
- Ping timeout: 1 second
- Connection timeout: 5 seconds

### Thread Safety

The GUI should handle socket I/O on a dedicated thread, queuing commands to the main thread for execution. Responses are sent back on the socket thread.

```swift
class SocketHandler {
    let socket: FileHandle
    let commandQueue: DispatchQueue
    let responseQueue: DispatchQueue
    
    func handleCommand(_ line: String) {
        commandQueue.async {
            let response = self.execute(line)
            self.responseQueue.async {
                self.send(response)
            }
        }
    }
}
```
