# REPL Commands Reference

## Overview

The REPL operates in three modes: Monitor, BASIC, and DOS. Global commands are available in all modes.

## Prompt Format

Each mode has a distinctive prompt for Emacs comint recognition:

```
[monitor] $E477>      Monitor mode (shows current PC)
[basic] >             BASIC mode
[dos] D1:>            DOS mode (shows current drive)
```

Prompt regex for comint: `^\[.+\] .+> $`

## Global Commands

Available in all modes. Prefixed with `.` to distinguish from mode-specific commands.

### Mode Switching

| Command | Description |
|---------|-------------|
| `.monitor` | Switch to monitor mode |
| `.basic` | Switch to BASIC mode (Atari BASIC tokenizer) |
| `.basic turbo` | Switch to BASIC mode (Turbo BASIC XL tokenizer) |
| `.dos` | Switch to DOS mode |

### Help

| Command | Description |
|---------|-------------|
| `.help` | Show commands for current mode |
| `.help <command>` | Show detailed help for command |

### Emulator Control

| Command | Description |
|---------|-------------|
| `.status` | Show emulator status |
| `.reset` | Cold reset (power cycle) |
| `.warmstart` | Warm reset (like pressing RESET key) |

**Status Output:**
```
Emulator Status
  State: Running
  PC: $E477
  Disk D1: /path/to/disk.atr
  Disk D2: (empty)
  Breakpoints: $600A, $602F
  BASIC mode: Atari BASIC
```

### Display

| Command | Description |
|---------|-------------|
| `.screenshot` | Save screenshot to Desktop |
| `.screenshot <path>` | Save screenshot to specific path |

### State Management

| Command | Description |
|---------|-------------|
| `.state save <path>` | Save emulator state to file |
| `.state load <path>` | Load emulator state from file |

### Session

| Command | Description |
|---------|-------------|
| `.quit` | Exit CLI (leave GUI running) |
| `.shutdown` | Exit CLI and terminate GUI |

## Monitor Mode

The monitor provides low-level debugging and memory inspection.

### Execution Control

| Command | Syntax | Description |
|---------|--------|-------------|
| `g` | `g [address]` | Go (resume execution) |
| `s` | `s [count]` | Step count instructions (default 1) |
| `pause` | `pause` | Pause execution |
| `until` | `until <address>` | Run until PC reaches address |

**Examples:**
```
[monitor] $E477> g
OK - Running
[monitor] $E477> g $0600
OK - Running from $0600
[monitor] $E477> s
$E479  8D 00 D4  STA $D400
  A=$00 X=$00 Y=$00 S=$FF P=$32
[monitor] $E479> s 5
$E484  4C 77 E4  JMP $E477
  A=$01 X=$00 Y=$00 S=$FF P=$30
[monitor] $E484> until $E480
Stopped at $E480
  A=$00 X=$00 Y=$00 S=$FF P=$32
```

### Registers

| Command | Syntax | Description |
|---------|--------|-------------|
| `r` | `r` | Display all registers |
| `r` | `r <reg>=<val>` | Set register value |

**Register names:** A, X, Y, S (stack pointer), P (status), PC

**Examples:**
```
[monitor] $E477> r
  A=$00 X=$00 Y=$00 S=$FF P=$32 PC=$E477
  Flags: ..I..Z.

[monitor] $E477> r A=$50
  A=$50 X=$00 Y=$00 S=$FF P=$32 PC=$E477

[monitor] $E477> r PC=$0600 X=$10
  A=$50 X=$10 Y=$00 S=$FF P=$32 PC=$0600
```

**Flag display format:** `NV.BDIZC` where `.` means flag is clear.

### Memory

| Command | Syntax | Description |
|---------|--------|-------------|
| `m` | `m <addr> [len]` | Memory dump (default 64 bytes) |
| `>` | `> <addr> <bytes>` | Write bytes to memory |
| `f` | `f <start> <end> <byte>` | Fill memory range |

**Examples:**
```
[monitor] $E477> m $0600 32
0600: A9 00 8D 00 D4 A9 01 8D  01 D4 4C 00 06 00 00 00  |...............|
0610: 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|

[monitor] $E477> > $0600 A9 00 8D 00 D4
Wrote 5 bytes at $0600

[monitor] $E477> f $0600 $06FF $00
Filled 256 bytes ($0600-$06FF) with $00
```

### Disassembly

| Command | Syntax | Description |
|---------|--------|-------------|
| `d` | `d [addr] [lines]` | Disassemble (default: from PC, 16 lines) |

**Examples:**
```
[monitor] $E477> d
$E477  A9 00     LDA #$00
$E479  8D 00 D4  STA $D400
$E47C  A9 01     LDA #$01
$E47E  8D 01 D4  STA $D401
$E481  4C 77 E4  JMP $E477
...

[monitor] $E477> d $0600 8
$0600  A9 00     LDA #$00
$0601  8D 00 D4  STA $D400
...
```

### Assembly

| Command | Syntax | Description |
|---------|--------|-------------|
| `a` | `a <addr>` | Enter assembly mode at address |

**Interactive assembly mode:**
- Enter one instruction per line
- Blank line exits assembly mode
- Invalid instructions show error and stay at same address

**Example:**
```
[monitor] $E477> a $0600
$0600: LDA #$00
$0602: STA $D400
$0605: LDA #$01
$0607: STA $D401
$060A: RTS
$060B: 
Assembly complete: 11 bytes at $0600-$060A
```

### Breakpoints

| Command | Syntax | Description |
|---------|--------|-------------|
| `bp` | `bp <addr>` | Set breakpoint |
| `bp` | `bp` | List all breakpoints |
| `bc` | `bc <addr>` | Clear breakpoint |
| `bc` | `bc *` | Clear all breakpoints |

**Examples:**
```
[monitor] $E477> bp $600A
Breakpoint set at $600A

[monitor] $E477> bp
Breakpoints:
  $600A (hits: 0)
  $602F (hits: 3)

[monitor] $E477> bc $600A
Breakpoint cleared at $600A

[monitor] $E477> bc *
All breakpoints cleared
```

**ROM Breakpoint Warning:**
```
[monitor] $E477> bp $E477
Warning: $E477 is in ROM space
  Breakpoints in ROM use PC watching (slower execution)
  Continue? (y/n) y
Breakpoint set at $E477 (ROM watch mode)
```

### Memory Watches

| Command | Syntax | Description |
|---------|--------|-------------|
| `w` | `w <addr> [len]` | Watch memory location |
| `wc` | `wc <addr>` | Clear watch |
| `wc` | `wc *` | Clear all watches |

Watches report when memory changes:
```
* Watch $D400 changed: $00 -> $55
```

## BASIC Mode

For entering and managing BASIC programs.

### Program Entry

| Command | Syntax | Description |
|---------|--------|-------------|
| (line) | `<num> <statement>` | Enter or replace line |
| `del` | `del <line>` | Delete line |
| `del` | `del <start>-<end>` | Delete range |
| `renum` | `renum [start] [step]` | Renumber program |

**Examples:**
```
[basic] > 10 PRINT "HELLO WORLD"
[basic] > 20 GOTO 10
[basic] > del 20
[basic] > 10 FOR I=1 TO 10:PRINT I:NEXT I
[basic] > renum 100 10
Renumbered: 10->100, 20->110, ...
```

### Program Control

| Command | Syntax | Description |
|---------|--------|-------------|
| `run` | `run` | Execute program |
| `stop` | `stop` | Send BREAK to emulator |
| `cont` | `cont` | Continue after BREAK |
| `new` | `new` | Clear program |

**Examples:**
```
[basic] > run
(emulator resumes with RUN command)

[basic] > stop
Stopped at line 100

[basic] > cont
(emulator continues)
```

### Listing

| Command | Syntax | Description |
|---------|--------|-------------|
| `list` | `list` | List entire program |
| `list` | `list <line>` | List single line |
| `list` | `list <start>-<end>` | List range |

**Examples:**
```
[basic] > list
10 PRINT "HELLO WORLD"
20 FOR I=1 TO 10
30 PRINT I
40 NEXT I
50 END

[basic] > list 20-40
20 FOR I=1 TO 10
30 PRINT I
40 NEXT I
```

### Variables

| Command | Syntax | Description |
|---------|--------|-------------|
| `vars` | `vars` | Show all variables |
| `var` | `var <name>` | Show specific variable |

**Examples:**
```
[basic] > vars
  I = 10
  COUNT = 42
  NAME$ = "CLAUDE"
  A(10) = [array 10 elements]

[basic] > var I
  I = 10 (numeric)
```

### File Operations (ATR)

| Command | Syntax | Description |
|---------|--------|-------------|
| `save` | `save "<D:FILE>"` | Save to mounted disk |
| `load` | `load "<D:FILE>"` | Load from mounted disk |
| `dir` | `dir` | List BASIC files on disk |

**Examples:**
```
[basic] > save "D:MYPROG.BAS"
Saved to D1:MYPROG.BAS (347 bytes)

[basic] > load "D:DEMO.BAS"
Loaded D1:DEMO.BAS (1,024 bytes)
```

### File Operations (Host)

| Command | Syntax | Description |
|---------|--------|-------------|
| `import` | `import <path>` | Load .BAS from macOS |
| `export` | `export <path>` | Save .BAS to macOS |

**Examples:**
```
[basic] > import ~/Documents/program.bas
Imported /Users/nick/Documents/program.bas (52 lines)

[basic] > export ~/Desktop/backup.bas
Exported to /Users/nick/Desktop/backup.bas
```

### Error Messages

```
[basic] > 10 PRIMT "HELLO"
Error at line 10, column 4:
  10 PRIMT "HELLO"
     ^^^^^
Unrecognized keyword 'PRIMT'
  Suggestion: Did you mean 'PRINT'?

[basic] > 10 FOR I=1
Error at line 10:
  10 FOR I=1
FOR without TO
  Syntax: FOR var=start TO end [STEP inc]

[basic] > 10 PRINT A(
Error at line 10, column 11:
  10 PRINT A(
            ^
Unclosed parenthesis
  Suggestion: Add closing ')'
```

## DOS Mode

For managing disk images and files.

### Drive Management

| Command | Syntax | Description |
|---------|--------|-------------|
| `mount` | `mount <n> <path>` | Mount ATR at drive n (1-8) |
| `unmount` | `unmount <n>` | Unmount drive n |
| `drives` | `drives` | Show mounted drives |
| `cd` | `cd <n>` | Change current drive |

**Examples:**
```
[dos] D1:> mount 1 ~/disks/games.atr
Mounted D1: /Users/nick/disks/games.atr (SS/SD, 32 files)

[dos] D1:> drives
  D1: /Users/nick/disks/games.atr (SS/SD)
  D2: /Users/nick/disks/save.atr (SS/DD)
  D3: (empty)
  ...

[dos] D1:> cd 2
[dos] D2:>
```

### Directory

| Command | Syntax | Description |
|---------|--------|-------------|
| `dir` | `dir [pattern]` | List files (* and ? wildcards) |
| `info` | `info <file>` | Show file details |

**Examples:**
```
[dos] D1:> dir
 GAME1    COM    28
 GAME2    COM    45
 README   TXT     3
 SAVE     DAT    12
 4 files, 88 sectors used, 632 free

[dos] D1:> dir *.COM
 GAME1    COM    28
 GAME2    COM    45
 2 files

[dos] D1:> info GAME1.COM
  Filename: GAME1.COM
  Size: 28 sectors (3,500 bytes)
  Start sector: 45
  Flags: Normal
```

### File Operations

| Command | Syntax | Description |
|---------|--------|-------------|
| `type` | `type <file>` | Display text file |
| `dump` | `dump <file>` | Hex dump of file |
| `copy` | `copy <src> <dest>` | Copy file |
| `rename` | `rename <old> <new>` | Rename file |
| `delete` | `delete <file>` | Delete file |
| `lock` | `lock <file>` | Set read-only |
| `unlock` | `unlock <file>` | Clear read-only |

**Examples:**
```
[dos] D1:> type README.TXT
Welcome to my disk!
This disk contains games.
Have fun!

[dos] D1:> copy GAME1.COM D2:BACKUP.COM
Copied GAME1.COM to D2:BACKUP.COM (28 sectors)

[dos] D1:> rename GAME1.COM ARCADE.COM
Renamed GAME1.COM to ARCADE.COM

[dos] D1:> delete SAVE.DAT
Delete SAVE.DAT? (y/n) y
Deleted SAVE.DAT
```

### Host Transfer

| Command | Syntax | Description |
|---------|--------|-------------|
| `export` | `export <file> <path>` | Extract to macOS |
| `import` | `import <path> <file>` | Add from macOS |

**Examples:**
```
[dos] D1:> export GAME1.COM ~/Desktop/game1.com
Exported GAME1.COM to /Users/nick/Desktop/game1.com (3,500 bytes)

[dos] D1:> import ~/Desktop/newgame.com NEWGAME.COM
Imported /Users/nick/Desktop/newgame.com as NEWGAME.COM (45 sectors)
```

### Disk Management

| Command | Syntax | Description |
|---------|--------|-------------|
| `newdisk` | `newdisk <path> [type]` | Create new ATR |
| `format` | `format` | Format current disk |

**Disk types:** `ss/sd` (90K), `ss/ed` (130K), `ss/dd` (180K)

**Examples:**
```
[dos] D1:> newdisk ~/disks/new.atr ss/sd
Created new disk image: /Users/nick/disks/new.atr (SS/SD, 90K)

[dos] D1:> format
WARNING: This will erase all data on D1:
Format D1:? (y/n) y
Formatting... done.
```

### Error Messages

```
[dos] D1:> type MISSING.TXT
Error: File not found 'MISSING.TXT'
  Available files: GAME1.COM, GAME2.COM, README.TXT, SAVE.DAT
  
[dos] D1:> copy GAME1.COM D3:BACKUP.COM
Error: Drive D3: not mounted
  Suggestion: Use 'mount 3 <path>' to mount a disk image

[dos] D1:> import /nonexistent/file.com GAME.COM  
Error: Cannot open '/nonexistent/file.com': No such file or directory

[dos] D1:> delete LOCKED.COM
Error: File 'LOCKED.COM' is locked
  Suggestion: Use 'unlock LOCKED.COM' first
```

## Keyboard Shortcuts

When focused on the REPL (in compatible terminal/Emacs):

| Key | Action |
|-----|--------|
| Ctrl-C | Interrupt current operation / send BREAK |
| Ctrl-D | Exit (same as .quit) |
| Up/Down | Command history |
| Tab | Command completion |

## Output Formatting

### Hex Values

- Addresses: `$XXXX` (4 hex digits)
- Bytes: `$XX` (2 hex digits)
- Binary: `%XXXXXXXX` (8 bits)

### Memory Dumps

```
ADDR  HEX BYTES                            ASCII
0600: A9 00 8D 00 D4 A9 01 8D  01 D4 4C 00 06 00 00 00  |...............|
```

### Disassembly

```
ADDR  BYTES      INSTRUCTION
$E477  A9 00     LDA #$00
```

### Registers

```
  A=$XX X=$XX Y=$XX S=$XX P=$XX PC=$XXXX
  Flags: NV.BDIZC
```
