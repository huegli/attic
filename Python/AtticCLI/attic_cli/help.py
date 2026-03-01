"""Help text system for all REPL commands.

Provides mode-specific and global help, both as overview tables and
per-command detailed help with examples.
"""

from rich.console import Console
from rich.panel import Panel
from rich.table import Table

console = Console()

# --- Global dot-commands help ---

GLOBAL_HELP: dict[str, str] = {
    "monitor": "Switch to monitor (debugger) mode.",
    "basic": (
        "Switch to BASIC mode.\n"
        "  .basic         — Standard Atari BASIC\n"
        "  .basic turbo   — Turbo BASIC XL"
    ),
    "dos": "Switch to DOS (disk management) mode.",
    "help": (
        "Show help for commands.\n"
        "  .help          — Show overview of available commands\n"
        "  .help <topic>  — Show detailed help for a specific command"
    ),
    "status": "Show emulator status (running state, PC, mounted disks, breakpoints).",
    "screen": "Read the text displayed on the Atari GRAPHICS 0 screen.",
    "reset": "Cold reset the emulator (reinitializes hardware, clears memory).",
    "warmstart": "Warm reset the emulator (like pressing RESET key, preserves memory).",
    "screenshot": (
        "Capture the emulator display as a PNG image.\n"
        "  .screenshot           — Display inline (if supported) or save to Desktop\n"
        "  .screenshot <path>    — Save to specific path"
    ),
    "boot": (
        "Load and boot a file into the emulator.\n"
        "  .boot <path>   — Supports ATR, XEX, BAS, CAS, ROM files"
    ),
    "state": (
        "Save or load emulator state.\n"
        "  .state save <path>    — Save complete emulator state\n"
        "  .state load <path>    — Restore previously saved state"
    ),
    "quit": "Disconnect from server and exit (server keeps running).",
    "shutdown": "Disconnect, stop the server, and exit.",
}

# --- Monitor mode commands ---

MONITOR_HELP: dict[str, str] = {
    "g": (
        "Resume execution (go).\n"
        "  g              — Resume from current PC\n"
        "  g $E000        — Set PC to $E000 and resume"
    ),
    "s": (
        "Step one or more instructions.\n"
        "  s              — Step one instruction\n"
        "  s 10           — Step 10 instructions"
    ),
    "p": "Pause emulator execution.",
    "pause": "Pause emulator execution.",
    "until": (
        "Run until the PC reaches a specific address.\n"
        "  until $0600    — Run until PC == $0600"
    ),
    "r": (
        "Display or set CPU registers.\n"
        "  r              — Display all registers\n"
        "  r a=$42        — Set accumulator to $42\n"
        "  r pc=$E000     — Set program counter\n"
        "  r a=$FF x=$00  — Set multiple registers"
    ),
    "m": (
        "Display memory contents (hex dump).\n"
        "  m $0600        — Dump 16 bytes at $0600\n"
        "  m $0600 32     — Dump 32 bytes at $0600"
    ),
    ">": (
        "Write bytes to memory.\n"
        "  > $0600 A9,00,8D,00,D4   — Write bytes at $0600"
    ),
    "f": (
        "Fill memory range with a value.\n"
        "  f $0600 $06FF $00   — Fill $0600-$06FF with zeros"
    ),
    "d": (
        "Disassemble instructions.\n"
        "  d              — Disassemble from current PC\n"
        "  d $E000        — Disassemble from $E000\n"
        "  d $E000 20     — Disassemble 20 lines from $E000"
    ),
    "a": (
        "Assemble instructions.\n"
        "  a $0600              — Start interactive assembly at $0600\n"
        "  a $0600 LDA #$00    — Assemble single instruction"
    ),
    "b": (
        "Set breakpoint.\n"
        "  b $0600        — Set breakpoint at $0600\n"
        "  b              — List all breakpoints"
    ),
    "bp": "Alias for 'b' (set breakpoint).",
    "bc": (
        "Clear breakpoint.\n"
        "  bc $0600       — Clear breakpoint at $0600\n"
        "  bc *           — Clear all breakpoints"
    ),
    "bl": "List all breakpoints.",
}

# --- BASIC mode commands ---

BASIC_HELP: dict[str, str] = {
    "list": (
        "List BASIC program lines.\n"
        "  list           — List entire program\n"
        "  list 10        — List line 10\n"
        "  list 10-50     — List lines 10 through 50"
    ),
    "del": (
        "Delete BASIC program lines.\n"
        "  del 30         — Delete line 30\n"
        "  del 10-50      — Delete lines 10 through 50"
    ),
    "run": "Run the current BASIC program.",
    "stop": "Stop the running BASIC program.",
    "cont": "Continue a stopped BASIC program.",
    "new": "Clear the current BASIC program from memory.",
    "vars": "Display all BASIC variables and their values.",
    "var": (
        "Display a specific BASIC variable.\n"
        "  var X          — Show value of variable X"
    ),
    "info": "Display information about the current BASIC program.",
    "renum": (
        "Renumber program lines.\n"
        "  renum          — Renumber starting from 10, step 10\n"
        "  renum 100      — Renumber starting from 100\n"
        "  renum 100 5    — Start at 100, step 5"
    ),
    "save": (
        "Save BASIC program to ATR disk.\n"
        '  save D:PROG    — Save as PROG on drive 1\n'
        '  save D2:PROG   — Save as PROG on drive 2'
    ),
    "load": (
        "Load BASIC program from ATR disk.\n"
        '  load D:PROG    — Load PROG from drive 1'
    ),
    "import": (
        "Import BASIC program from host filesystem.\n"
        "  import ~/program.bas   — Import from host file"
    ),
    "export": (
        "Export BASIC program to host filesystem.\n"
        "  export ~/program.bas   — Export to host file"
    ),
    "dir": (
        "List files on disk.\n"
        "  dir            — List current drive\n"
        "  dir 2          — List drive 2"
    ),
}

# --- DOS mode commands ---

DOS_HELP: dict[str, str] = {
    "mount": (
        "Mount an ATR disk image to a drive.\n"
        "  mount 1 ~/disks/game.atr   — Mount to D1:"
    ),
    "unmount": (
        "Unmount a disk image from a drive.\n"
        "  unmount 1      — Unmount D1:"
    ),
    "drives": "List all drive slots and their mounted disk images.",
    "cd": (
        "Change the current drive.\n"
        "  cd 2           — Switch to D2:"
    ),
    "dir": (
        "List files on disk.\n"
        "  dir            — List current drive\n"
        "  dir *.BAS      — List matching files"
    ),
    "info": (
        "Show file information.\n"
        "  info PROG.BAS  — Show size, attributes, etc."
    ),
    "type": (
        "Display file contents as text.\n"
        "  type README    — Show file contents"
    ),
    "dump": (
        "Display file contents as hex dump.\n"
        "  dump PROG.BAS  — Hex dump of file"
    ),
    "copy": (
        "Copy a file.\n"
        "  copy PROG.BAS BACKUP.BAS"
    ),
    "rename": (
        "Rename a file.\n"
        "  rename OLD.BAS NEW.BAS"
    ),
    "delete": (
        "Delete a file.\n"
        "  delete TEMP.BAS"
    ),
    "lock": (
        "Lock a file (write-protect).\n"
        "  lock PROG.BAS"
    ),
    "unlock": (
        "Unlock a file.\n"
        "  unlock PROG.BAS"
    ),
    "export": (
        "Export a file from ATR disk to host filesystem.\n"
        "  export PROG.BAS ~/prog.bas"
    ),
    "import": (
        "Import a file from host filesystem to ATR disk.\n"
        "  import ~/prog.bas PROG.BAS"
    ),
    "newdisk": (
        "Create a new blank ATR disk image.\n"
        "  newdisk ~/new.atr       — Single density (default)\n"
        "  newdisk ~/new.atr ed    — Enhanced density\n"
        "  newdisk ~/new.atr dd    — Double density"
    ),
    "format": "Format the current drive's disk.",
}


def print_help_overview(mode: str) -> None:
    """Print the help overview for the current mode.

    Shows global dot-commands and mode-specific commands.

    Args:
        mode: Current mode name — "monitor", "basic", or "dos".
    """
    # Global commands table
    global_table = Table(title="Global Commands", show_header=True, title_style="bold")
    global_table.add_column("Command", style="cyan", no_wrap=True)
    global_table.add_column("Description")

    for cmd in [
        "monitor", "basic", "dos", "help", "status", "screen",
        "reset", "warmstart", "screenshot", "boot", "state", "quit", "shutdown",
    ]:
        desc = GLOBAL_HELP[cmd].split("\n")[0]  # First line only
        global_table.add_row(f".{cmd}", desc)

    console.print(global_table)
    console.print()

    # Mode-specific commands
    mode_commands = _mode_help_dict(mode)
    if mode_commands:
        mode_table = Table(
            title=f"{mode.capitalize()} Mode Commands",
            show_header=True,
            title_style="bold",
        )
        mode_table.add_column("Command", style="cyan", no_wrap=True)
        mode_table.add_column("Description")

        for cmd, text in mode_commands.items():
            desc = text.split("\n")[0]
            mode_table.add_row(cmd, desc)

        console.print(mode_table)


def print_help_topic(mode: str, topic: str) -> None:
    """Print detailed help for a specific command.

    Args:
        mode: Current mode name.
        topic: Command name to look up (with or without leading dot).
    """
    # Strip leading dot if present
    clean = topic.lstrip(".")

    # Check global commands first
    if clean in GLOBAL_HELP:
        console.print(Panel(
            GLOBAL_HELP[clean],
            title=f".{clean}",
            title_align="left",
            border_style="cyan",
        ))
        return

    # Check current mode commands first, then all other modes
    for help_dict in [_mode_help_dict(mode), MONITOR_HELP, BASIC_HELP, DOS_HELP]:
        if clean in help_dict:
            console.print(Panel(
                help_dict[clean],
                title=clean,
                title_align="left",
                border_style="cyan",
            ))
            return

    console.print(f"[red]No help available for '{topic}'[/red]")
    console.print("[dim]Type .help for a list of available commands[/dim]")


def _mode_help_dict(mode: str) -> dict[str, str]:
    """Return the help dictionary for the given mode name."""
    match mode:
        case "monitor":
            return MONITOR_HELP
        case "basic":
            return BASIC_HELP
        case "dos":
            return DOS_HELP
        case _:
            return {}
