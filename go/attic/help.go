// =============================================================================
// help.go - Help System (Global and Mode-Specific Help Text)
// =============================================================================
//
// This file implements the CLI help system. It provides:
//   - ".help"         — Full command listing for the current mode
//   - ".help <topic>" — Detailed help for a specific command
//
// Help text is organized into four dictionaries:
//   - globalHelp:   Help for dot-commands available in all modes
//   - monitorHelp:  Help for monitor mode commands (g, s, p, r, m, etc.)
//   - basicHelp:    Help for BASIC mode commands (list, del, run, etc.)
//   - dosHelp:      Help for DOS mode commands (mount, dir, copy, etc.)
//
// The text in these dictionaries is ported directly from the Swift CLI
// (AtticCLI.swift) to ensure consistent behavior between implementations.
//
// =============================================================================

package main

// GO CONCEPT: Map Literals for Lookup Tables
// -------------------------------------------
// Go uses map[string]string for string-to-string dictionaries. Maps are
// initialized with composite literals:
//
//   var myMap = map[string]string{
//       "key1": "value1",
//       "key2": "value2",
//   }
//
// Lookup syntax: value, ok := myMap[key]
//   - ok is true if the key exists, false otherwise
//   - value is the zero value ("" for strings) if key doesn't exist
//
// Compare with Swift: Swift uses [String: String] dictionaries:
//   let help: [String: String] = ["key": "value"]
//   if let text = help[key] { print(text) }
//
// Compare with Python: Python uses dict:
//   help = {"key": "value"}
//   text = help.get(key)  # Returns None if missing
//   # Or: if key in help: text = help[key]
import (
	"fmt"
	"os"
	"strings"
)

// printHelp displays help for the current mode, or detailed help for a
// specific command topic.
//
// When topic is empty, it prints the full command listing for the mode.
// When a topic is given, it looks it up in the global and mode-specific
// help dictionaries and prints the detailed text.
//
// GO CONCEPT: String Zero Value as "Not Set"
// -------------------------------------------
// Go doesn't have optionals like Swift's String?. Instead, the zero
// value for string is "" (empty string), which we use to mean "no topic
// specified". This is a common Go idiom.
//
// Compare with Swift: The Swift version uses Optional<String>:
//   func printHelp(mode: SocketREPLMode, topic: String?) { ... }
//
// Compare with Python: Python uses None for optional parameters:
//   def print_help(mode: REPLMode, topic: str | None = None) -> None:
func printHelp(mode REPLMode, topic string) {
	// If no topic, show the full listing.
	if topic == "" {
		printHelpOverview(mode)
		return
	}

	// Normalize: strip leading dot for global commands, lowercase.
	// This allows ".help .boot" to work the same as ".help boot".
	key := strings.ToLower(topic)
	if strings.HasPrefix(key, ".") {
		key = key[1:]
	}

	// Check global commands first, then mode-specific.
	//
	// GO CONCEPT: Map Lookup with Comma-Ok Pattern
	// -----------------------------------------------
	// Go map lookups return two values: (value, ok). If ok is true,
	// the key was found. If false, value is the zero value for the
	// value type.
	//
	// Compare with Swift: if let text = globalHelp[key] { ... }
	// Compare with Python: text = global_help.get(key)
	if text, ok := globalHelp[key]; ok {
		fmt.Println(text)
		return
	}

	modeHelpMap := modeHelp(mode)
	if text, ok := modeHelpMap[key]; ok {
		fmt.Println(text)
		return
	}

	fmt.Fprintf(os.Stderr, "Error: No help for '%s'. Type .help to see available commands.\n", topic)
}

// modeHelp returns the help dictionary for mode-specific commands.
//
// GO CONCEPT: Function Returning a Map
// ---------------------------------------
// Functions can return maps just like any other type. The returned map
// is a reference type — no copying occurs. This is similar to Swift's
// dictionary return and Python's dict return.
func modeHelp(mode REPLMode) map[string]string {
	switch mode {
	case ModeMonitor:
		return monitorHelp
	case ModeBasic:
		return basicHelp
	case ModeDOS:
		return dosHelp
	default:
		return nil
	}
}

// printHelpOverview prints the full command listing for the current mode.
//
// GO CONCEPT: Raw String Literals for Multi-Line Text
// ---------------------------------------------------
// Go's backtick strings preserve formatting exactly as written,
// including newlines, tabs, and indentation. This makes them ideal
// for help text where whitespace alignment matters.
//
// Compare with Swift: Triple-quoted strings (""") serve the same purpose.
// Compare with Python: Triple-quoted strings (""" or ''') work identically.
func printHelpOverview(mode REPLMode) {
	fmt.Print(`Global Commands:
  .monitor          Switch to monitor mode
  .basic            Switch to BASIC mode
  .dos              Switch to DOS mode
  .help [cmd]       Show help (or help for a specific command)
  .status           Show emulator status
  .screenshot [p]   Save screenshot (default: ~/Desktop/Attic-<time>.png)
  .screen           Read screen text (GRAPHICS 0 only)
  .boot <path>      Boot with file (ATR, XEX, BAS, etc.)
  .reset            Cold reset
  .warmstart        Warm reset
  .state save <p>   Save state to file
  .state load <p>   Load state from file
  .quit             Exit CLI
  .shutdown         Exit and stop server
`)

	switch mode {
	case ModeMonitor:
		fmt.Print(`
Monitor Commands:
  g [addr]          Go (resume) from current or specified address
  s [n]             Step n instructions (default: 1)
  so                Step over (treat JSR as one instruction)
  p                 Pause emulation
  r [reg=val...]    Display/set registers
  m <addr> <len>    Memory dump
  > <addr> <bytes>  Write memory
  f <s> <e> <val>   Fill memory range with value
  a <addr>          Interactive assembly (enter instructions line by line)
  a <addr> <instr>  Assemble single instruction
  d [addr] [lines]  Disassemble code
  b set <addr>      Set breakpoint
  b clear <addr>    Clear breakpoint
  b list            List breakpoints
  bp <addr>         Set breakpoint (shorthand)
  bc <addr>         Clear breakpoint (shorthand)
  until <addr>      Run until address reached
`)

	case ModeBasic:
		fmt.Print(`
BASIC Mode:
  Enter BASIC lines with line numbers (e.g. 10 PRINT "HELLO")
  list [range]      List program (via detokenizer)
  del <line|range>  Delete line or range (e.g. del 30, del 10-50)
  new               Clear program from memory
  run               Run the BASIC program
  renum [s] [step]  Renumber lines (default: start 10, step 10)
  info              Show program size (lines, bytes, variables)
  vars              List all variables with values
  var <name>        Show single variable (e.g. var X, var A$)
  stop              Send BREAK to stop running program
  cont              Continue after BREAK
  save D:FILE       Save program to ATR disk (e.g. save D:TEST)
  load D:FILE       Load program from ATR disk (e.g. load D:TEST)
  export <path>     Export listing to file
  import <path>     Import listing from file
  dir [drive]       List disk directory (default: current drive)
  Other input is typed into the emulator as keystrokes
`)

	case ModeDOS:
		fmt.Print(`
DOS Commands:
  mount <n> <path>  Mount disk image to drive n
  unmount <n>       Unmount drive n
  drives            List mounted drives
  cd <n>            Change current drive (1-8)
  dir [pattern]     List directory (e.g. dir *.COM)
  info <file>       Show file details (size, sectors, locked)
  type <file>       Display text file contents
  dump <file>       Hex dump of file contents
  copy <src> <dst>  Copy file (e.g. copy D1:FILE D2:FILE)
  rename <old> <new> Rename a file
  delete <file>     Delete a file
  lock <file>       Lock file (read-only)
  unlock <file>     Unlock file
  export <f> <path> Export disk file to host filesystem
  import <path> <f> Import host file to disk
  newdisk <p> [type] Create new ATR (type: sd, ed, dd)
  format            Format current drive (erases all data!)
`)
	}
}

// =============================================================================
// Topic-Specific Help Text
// =============================================================================
//
// GO CONCEPT: Package-Level Variables with Map Literals
// ---------------------------------------------------
// These maps are initialized once at package load time (not inside a
// function). They are effectively constants, but Go doesn't allow const
// for maps or slices — only primitive types (bool, string, int, etc.)
// can be const. So we use "var" for map constants.
//
// The maps are unexported (lowercase names) so they're private to this
// package. No external code can modify them (though Go doesn't enforce
// immutability — it's a convention).
//
// Compare with Swift: Swift uses "static let" for dictionary constants:
//   private static let globalHelp: [String: String] = [...]
//
// Compare with Python: Python uses module-level dicts:
//   _GLOBAL_HELP: dict[str, str] = { ... }
// The underscore prefix is a convention for "private" module members.

// globalHelp contains detailed help for global dot-commands.
// Keys are command names without the leading dot (e.g. "monitor", not ".monitor").
var globalHelp = map[string]string{
	"monitor": `  .monitor
    Switch to monitor mode for 6502 debugging.
    Provides disassembly, breakpoints, memory inspection, and
    register manipulation.`,

	"basic": `  .basic
    Switch to BASIC mode for writing and running Atari BASIC programs.
    Numbered lines are tokenized and injected into emulator memory.
    Non-numbered input is typed into the emulator as keystrokes.`,

	"dos": `  .dos
    Switch to DOS mode for disk image management.
    Mount, browse, and manipulate ATR disk images and their files.`,

	"help": `  .help [command]
    Show help for all commands, or detailed help for a specific command.
    Examples:
      .help           Show full command listing for current mode
      .help mount     Show detailed help for the mount command
      .help g         Show detailed help for the go command
      .help .boot     Show detailed help for the .boot command`,

	"status": `  .status
    Show emulator status including running state, program counter,
    mounted disk drives, and active breakpoints.`,

	"screenshot": `  .screenshot [path]
    Capture the emulator display as a PNG screenshot.
    If no path is given, saves to ~/Desktop/Attic-<timestamp>.png.
    Examples:
      .screenshot
      .screenshot ~/captures/screen.png`,

	"screen": `  .screen
    Read the text currently displayed on the Atari GRAPHICS 0 screen.
    Returns the 40x24 character text screen as plain text.
    Only works when the emulator is in text mode (GRAPHICS 0).`,

	"boot": `  .boot <path>
    Boot the emulator with a file. Supported formats:
      .ATR  - Disk image (mounted to D1: and booted)
      .XEX  - Executable (loaded and run)
      .BAS  - BASIC program (loaded into BASIC)
      .CAS  - Cassette image
      .ROM  - Cartridge ROM
    Example:
      .boot ~/games/StarRaiders.atr`,

	"reset": `  .reset
    Perform a cold reset of the emulator. Reinitializes all hardware
    and clears memory. Equivalent to powering off and on.`,

	"warmstart": `  .warmstart
    Perform a warm reset. Equivalent to pressing the RESET key on
    the Atari. Preserves memory contents but resets the CPU.`,

	"state": `  .state save <path>
  .state load <path>
    Save or load the complete emulator state (CPU, memory, hardware).
    Examples:
      .state save ~/saves/game.state
      .state load ~/saves/game.state`,

	"quit": `  .quit
    Disconnect from the server and exit the CLI.
    If the server was launched by this CLI session, it keeps running.`,

	"shutdown": `  .shutdown
    Disconnect and stop the server. If this CLI session launched
    the server, sends SIGTERM to terminate it. If the server was
    already running, only disconnects (leaves the server running).`,
}

// monitorHelp contains detailed help for monitor mode commands.
var monitorHelp = map[string]string{
	"g": `  g [addr]
    Resume execution from the current PC, or from a specified address.
    If an address is given, sets PC before resuming.
    Examples:
      g             Resume from current PC
      g $E000       Set PC to $E000 and resume`,

	"s": `  s [n]
    Step the emulator by n frames (default: 1).
    After stepping, displays the current register state.
    Examples:
      s             Step 1 frame
      s 10          Step 10 frames`,

	"step": `  step [n]
    Alias for 's'. Step the emulator by n frames (default: 1).`,

	"so": `  so
    Step over. Execute the next instruction, but if it is a JSR
    (subroutine call), run until the subroutine returns.`,

	"stepover": `  stepover
    Alias for 'so'. Step over subroutine calls.`,

	"p": `  p
    Pause emulation. The emulator must be paused before writing
    memory or modifying CPU registers.`,

	"pause": `  pause
    Alias for 'p'. Pause emulation.`,

	"r": `  r [reg=val ...]
    Display CPU registers, or set one or more register values.
    Register names: A, X, Y, S (stack pointer), P (flags), PC.
    Examples:
      r                 Show all registers
      r a=42            Set accumulator to $42
      r pc=E000 a=00    Set PC and A`,

	"registers": `  registers [reg=val ...]
    Alias for 'r'. Display or set CPU registers.`,

	"m": `  m <addr> [len]
    Dump memory starting at addr for len bytes (default: 16).
    Address must be prefixed with $.
    Examples:
      m $0600           Dump 16 bytes at $0600
      m $D000 64        Dump 64 bytes at $D000`,

	"memory": `  memory <addr> [len]
    Alias for 'm'. Dump memory contents.`,

	">": `  > <addr> <bytes>
    Write bytes to memory. Emulator must be paused first.
    Bytes are comma-separated hex values.
    Examples:
      > $0600 A9,00,8D,00,D4    Write 5 bytes at $0600`,

	"f": `  f <start> <end> <value>
    Fill a memory range with a single byte value.
    Emulator must be paused first.
    Examples:
      f $0600 $06FF $00     Fill 256 bytes with zero
      f $4000 $7FFF $FF     Fill 16KB with $FF`,

	"fill": `  fill <start> <end> <value>
    Alias for 'f'. Fill a memory range with a byte value.`,

	"a": `  a <addr> [instruction]
    Assemble 6502 code. Two modes:
      a $0600             Enter interactive assembly (line by line)
      a $0600 LDA #$42   Assemble a single instruction
    In interactive mode, enter one instruction per line.
    Enter a blank line or '.' to exit.
    Examples:
      a $0600
      a $0600 NOP
      a $0600 JMP $E459`,

	"assemble": `  assemble <addr> [instruction]
    Alias for 'a'. Assemble 6502 code.`,

	"d": `  d [addr] [lines]
    Disassemble 6502 code starting at addr.
    If no address given, disassembles from current PC.
    Examples:
      d                 Disassemble 16 lines from PC
      d $E000           Disassemble from $E000
      d $E000 32        Disassemble 32 lines from $E000`,

	"disassemble": `  disassemble [addr] [lines]
    Alias for 'd'. Disassemble 6502 code.`,

	"b": `  b <set|clear|list> [addr]
    Manage breakpoints using the 6502 BRK instruction.
    Examples:
      b set $0600       Set breakpoint at $0600
      b clear $0600     Clear breakpoint at $0600
      b list            List all active breakpoints`,

	"breakpoint": `  breakpoint <set|clear|list> [addr]
    Alias for 'b'. Manage breakpoints.`,

	"bp": `  bp <addr>
    Set a breakpoint at the given address (shorthand for 'b set').
    Example:
      bp $0600          Set breakpoint at $0600`,

	"bc": `  bc <addr>
    Clear the breakpoint at the given address (shorthand for 'b clear').
    Example:
      bc $0600          Clear breakpoint at $0600`,

	"until": `  until <addr>
    Run the emulator until the program counter reaches the specified
    address, then pause.
    Example:
      until $E459       Run until PC reaches $E459`,
}

// basicHelp contains detailed help for BASIC mode commands.
var basicHelp = map[string]string{
	"list": `  list [range]
    List the BASIC program in memory using the detokenizer.
    Optionally specify a line range.
    Examples:
      list              List entire program
      list 10-50        List lines 10 through 50`,

	"del": `  del <line|range>
    Delete a single line or a range of lines.
    Examples:
      del 30            Delete line 30
      del 10-50         Delete lines 10 through 50`,

	"new": `  new
    Clear the current BASIC program from memory.
    This removes all program lines and variables.`,

	"run": `  run
    Run the current BASIC program from the beginning.`,

	"renum": `  renum [start] [step]
    Renumber all program lines. Default start is 10, step is 10.
    Updates GOTO/GOSUB references automatically.
    Examples:
      renum             Renumber 10, 20, 30, ...
      renum 100 5       Renumber 100, 105, 110, ...`,

	"info": `  info
    Show program statistics: number of lines, total bytes used,
    and variable count.`,

	"vars": `  vars
    List all BASIC variables with their current values.
    Shows variable name, type (numeric, string, array), and value.`,

	"var": `  var <name>
    Show a single variable's value.
    Examples:
      var X             Show numeric variable X
      var A$            Show string variable A$`,

	"stop": `  stop
    Send BREAK to stop a running BASIC program.
    The program can be continued with 'cont'.`,

	"cont": `  cont
    Continue execution after a BREAK or STOP statement.`,

	"save": `  save D:FILE
    Save the current BASIC program to a mounted ATR disk.
    The file spec must include the drive prefix (D: or D1: etc).
    Examples:
      save D:TEST       Save as TEST on current drive
      save D2:GAME      Save as GAME on drive 2`,

	"load": `  load D:FILE
    Load a BASIC program from a mounted ATR disk.
    Examples:
      load D:TEST       Load TEST from current drive
      load D2:GAME      Load GAME from drive 2`,

	"export": `  export <path>
    Export the current BASIC listing to a host filesystem file.
    Example:
      export ~/programs/myprog.bas`,

	"import": `  import <path>
    Import a BASIC listing from a host filesystem file.
    Lines are tokenized and loaded into emulator memory.
    Example:
      import ~/programs/myprog.bas`,

	"dir": `  dir [drive]
    List the directory of a mounted disk. Defaults to current drive.
    Examples:
      dir               List current drive
      dir 2             List drive 2`,
}

// dosHelp contains detailed help for DOS mode commands.
var dosHelp = map[string]string{
	"mount": `  mount <n> <path>
    Mount an ATR disk image to drive n (1-8).
    Examples:
      mount 1 ~/disks/dos.atr
      mount 2 ~/disks/game.atr`,

	"unmount": `  unmount <n>
    Unmount the disk image from drive n.
    Example:
      unmount 2`,

	"drives": `  drives
    List all drive slots (D1: through D8:) and their mounted images.`,

	"cd": `  cd <n>
    Change the current working drive (1-8).
    Subsequent commands like dir, type, etc. use this drive.
    Example:
      cd 2`,

	"dir": `  dir [pattern]
    List the directory of the current drive.
    Optional glob pattern filters results.
    Examples:
      dir               List all files
      dir *.COM         List only .COM files`,

	"info": `  info <file>
    Show detailed information about a file: size in bytes,
    sector count, and whether it's locked.
    Example:
      info AUTORUN.SYS`,

	"type": `  type <file>
    Display the contents of a text file.
    Example:
      type README.TXT`,

	"dump": `  dump <file>
    Show a hex dump of a file's contents, with both hex bytes
    and ASCII representation.
    Example:
      dump GAME.COM`,

	"copy": `  copy <source> <dest>
    Copy a file. Use drive prefixes for cross-drive copies.
    Examples:
      copy D1:FILE.COM D2:FILE.COM
      copy GAME.BAS BACKUP.BAS`,

	"rename": `  rename <old> <new>
    Rename a file on the current drive.
    Example:
      rename OLDNAME.BAS NEWNAME.BAS`,

	"delete": `  delete <file>
    Delete a file from the current drive.
    Example:
      delete TEMP.DAT`,

	"lock": `  lock <file>
    Lock a file (make it read-only).
    Example:
      lock IMPORTANT.DAT`,

	"unlock": `  unlock <file>
    Unlock a previously locked file.
    Example:
      unlock IMPORTANT.DAT`,

	"export": `  export <file> <path>
    Export a file from the ATR disk to the host filesystem.
    Example:
      export GAME.BAS ~/exports/game.bas`,

	"import": `  import <path> <file>
    Import a file from the host filesystem into the ATR disk.
    Example:
      import ~/programs/game.bas GAME.BAS`,

	"newdisk": `  newdisk <path> [type]
    Create a new blank ATR disk image. Type can be:
      sd   Single density (90KB, 720 sectors)
      ed   Enhanced density (130KB, 1040 sectors)
      dd   Double density (180KB, 720 sectors)
    Default is single density.
    Example:
      newdisk ~/disks/blank.atr dd`,

	"format": `  format
    Format the current drive, erasing all data.
    This writes a fresh directory and VTOC to the disk.
    WARNING: All existing data on the disk will be lost!`,
}
