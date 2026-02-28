"""Command-to-protocol translation.

Maps user input in each REPL mode to the wire-format protocol strings
that AtticServer understands. Each translate function returns a list of
protocol command strings (some user commands expand to multiple commands).
"""

from .cli_client import escape_for_inject


def translate_monitor(line: str) -> list[str]:
    """Translate a monitor mode command to protocol strings.

    Args:
        line: Raw user input (trimmed, non-empty).

    Returns:
        List of protocol command strings to send to the server.
    """
    parts = line.split(None, 1)
    cmd = parts[0].lower()
    args = parts[1] if len(parts) > 1 else ""

    match cmd:
        case "g":
            if args:
                # Go to address: set PC then resume
                return [f"registers pc={args}", "resume"]
            return ["resume"]

        case "s":
            if args:
                return [f"step {args}"]
            return ["step"]

        case "p" | "pause":
            return ["pause"]

        case "until":
            return [f"run_until {args}"] if args else ["run_until"]

        case "r":
            if args:
                return [f"registers {args}"]
            return ["registers"]

        case "m":
            if args:
                return [f"read {args}"]
            return ["read"]

        case ">":
            return [f"write {args}"] if args else ["write"]

        case "f":
            return [f"fill {args}"] if args else ["fill"]

        case "d":
            if args:
                return [f"disassemble {args}"]
            return ["disassemble"]

        case "a":
            if args:
                return [f"assemble {args}"]
            return ["assemble"]

        case "b" | "bp":
            # Breakpoint set: b $addr or bp $addr
            if args:
                return [f"breakpoint set {args}"]
            return ["breakpoint list"]

        case "bc":
            # Breakpoint clear
            if args == "*":
                return ["breakpoint clearall"]
            if args:
                return [f"breakpoint clear {args}"]
            return ["breakpoint list"]

        case "bl":
            return ["breakpoint list"]

        case _:
            # Pass through as-is for any unrecognized commands
            return [line]


def translate_basic(line: str, *, atascii: bool = True) -> list[str]:
    """Translate a BASIC mode command to protocol strings.

    Args:
        line: Raw user input (trimmed, non-empty).
        atascii: Whether to request ATASCII rendering for LIST.

    Returns:
        List of protocol command strings to send to the server.
    """
    parts = line.split(None, 1)
    cmd = parts[0].upper()
    args = parts[1] if len(parts) > 1 else ""

    match cmd:
        case "LIST":
            suffix = " atascii" if atascii else ""
            if args:
                return [f"basic list {args}{suffix}"]
            return [f"basic list{suffix}"]

        case "DEL":
            return [f"basic del {args}"] if args else ["basic del"]

        case "STOP":
            return ["basic stop"]

        case "CONT":
            return ["basic cont"]

        case "VARS":
            return ["basic vars"]

        case "VAR":
            return [f"basic var {args}"] if args else ["basic vars"]

        case "INFO":
            return ["basic info"]

        case "EXPORT":
            return [f"basic export {args}"] if args else ["basic export"]

        case "IMPORT":
            return [f"basic import {args}"] if args else ["basic import"]

        case "DIR":
            return [f"basic dir {args}"] if args else ["basic dir"]

        case "RENUM":
            return [f"basic renum {args}"] if args else ["basic renum"]

        case "SAVE":
            return [f"basic save {args}"] if args else ["basic save"]

        case "LOAD":
            return [f"basic load {args}"] if args else ["basic load"]

        case _:
            # Everything else (including numbered lines, NEW, RUN)
            # gets injected as keystrokes
            escaped = escape_for_inject(line)
            return [f"inject keys {escaped}\\n"]


def translate_dos(line: str) -> list[str]:
    """Translate a DOS mode command to protocol strings.

    Args:
        line: Raw user input (trimmed, non-empty).

    Returns:
        List of protocol command strings to send to the server.
    """
    parts = line.split(None, 1)
    cmd = parts[0].lower()
    args = parts[1] if len(parts) > 1 else ""

    match cmd:
        case "mount":
            return [f"mount {args}"] if args else ["mount"]

        case "unmount" | "umount":
            return [f"unmount {args}"] if args else ["unmount"]

        case "drives":
            return ["drives"]

        case "cd":
            return [f"dos cd {args}"] if args else ["dos cd"]

        case "dir":
            return [f"dos dir {args}"] if args else ["dos dir"]

        case "info":
            return [f"dos info {args}"] if args else ["dos info"]

        case "type":
            return [f"dos type {args}"] if args else ["dos type"]

        case "dump":
            return [f"dos dump {args}"] if args else ["dos dump"]

        case "copy" | "cp":
            return [f"dos copy {args}"] if args else ["dos copy"]

        case "rename" | "ren":
            return [f"dos rename {args}"] if args else ["dos rename"]

        case "delete" | "del":
            return [f"dos delete {args}"] if args else ["dos delete"]

        case "lock":
            return [f"dos lock {args}"] if args else ["dos lock"]

        case "unlock":
            return [f"dos unlock {args}"] if args else ["dos unlock"]

        case "export":
            return [f"dos export {args}"] if args else ["dos export"]

        case "import":
            return [f"dos import {args}"] if args else ["dos import"]

        case "newdisk":
            return [f"dos newdisk {args}"] if args else ["dos newdisk"]

        case "format":
            return ["dos format"]

        case _:
            return [line]
