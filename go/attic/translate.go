// =============================================================================
// translate.go - Command Translation (User Input → CLI Protocol)
// =============================================================================
//
// This file translates user-facing REPL commands into the wire-format strings
// expected by the CLI text protocol (documented in docs/PROTOCOL.md).
//
// Each REPL mode (Monitor, BASIC, DOS) has its own vocabulary. The user types
// natural, short-form commands, and this module expands them into protocol
// commands before they are sent to AtticServer via the socket.
//
// Examples:
//   Monitor:  "g $0600"        → ["registers pc=$0600", "resume"]
//   BASIC:    "list 10-50"     → ["basic list 10-50"]
//   DOS:      "dir *.COM"      → ["dos dir *.COM"]
//   Global:   ".reset"         → ["reset cold"]
//
// Some monitor commands (like "g $addr") expand to multiple protocol commands
// that must be sent sequentially. This is why translateToProtocol returns a
// []string (slice of strings) rather than a single string.
//
// =============================================================================

package main

// GO CONCEPT: String Manipulation for Command Parsing
// ---------------------------------------------------
// Command translation involves a lot of string splitting, trimming, and
// prefix checking. Go's "strings" package provides all the tools needed:
//
//   strings.SplitN(s, sep, n)   — split into at most n parts
//   strings.TrimSpace(s)        — remove whitespace from both ends
//   strings.HasPrefix(s, p)     — check prefix
//   strings.ToUpper(s)          — uppercase
//   strings.ToLower(s)          — lowercase
//   strings.ReplaceAll(s, o, n) — replace all occurrences
//
// Compare with Swift: Swift uses instance methods on String:
//   line.split(separator: " ", maxSplits: 1)
//   line.trimmingCharacters(in: .whitespaces)
//   line.hasPrefix(".reset")
//
// Compare with Python: Python uses instance methods on str:
//   line.split(" ", maxsplit=1)
//   line.strip()
//   line.startswith(".reset")
//   line.upper()
import (
	"fmt"
	"strconv"
	"strings"
)

// translateToProtocol translates a REPL command to one or more CLI protocol
// command strings.
//
// Most commands produce a single protocol string, but some (like "g $addr"
// in monitor mode) expand to a sequence. The caller must send all returned
// strings to the server in order.
//
// GO CONCEPT: Function Returning a Slice
// ----------------------------------------
// Functions that return variable-length results use slices. The caller
// iterates over the result with range:
//
//   for _, cmd := range translateToProtocol(line, mode, atascii) {
//       client.SendRaw(cmd)
//   }
//
// Compare with Swift: Swift returns [String] (Array<String>), which is
// essentially the same concept — a dynamically-sized ordered collection.
//
// Compare with Python: Python returns list[str]. The caller iterates:
//   for cmd in translate_to_protocol(line, mode, atascii):
//       client.send_raw(cmd)
func translateToProtocol(line string, mode REPLMode, atasciiMode bool) []string {
	trimmed := strings.TrimSpace(line)

	// Handle dot-commands that are forwarded to the server (as opposed to
	// dot-commands handled locally in the REPL loop like .quit, .monitor).
	if strings.HasPrefix(trimmed, ".") {
		lowerTrimmed := strings.ToLower(trimmed)

		// GO CONCEPT: Early Return Pattern
		// ----------------------------------
		// Go code commonly uses early returns for special cases, letting
		// the "normal" path flow naturally without nesting. Each case is
		// self-contained with its own return statement.
		//
		// Compare with Swift: Swift uses guard/return for similar patterns:
		//   guard !trimmed.hasPrefix(".") else { return ... }
		//
		// Compare with Python: Python uses early return the same way:
		//   if trimmed.startswith("."): return [...]
		switch lowerTrimmed {
		case ".status":
			return []string{"status"}
		case ".screen":
			return []string{"screen"}
		case ".reset":
			return []string{"reset cold"}
		case ".warmstart":
			return []string{"reset warm"}
		case ".screenshot":
			return []string{"screenshot"}
		}

		// Handle dot-commands with arguments (can't use switch for prefix matching).
		if strings.HasPrefix(lowerTrimmed, ".screenshot ") {
			path := strings.TrimSpace(trimmed[12:])
			return []string{"screenshot " + path}
		}
		if strings.HasPrefix(lowerTrimmed, ".state save ") {
			path := strings.TrimSpace(trimmed[12:])
			return []string{"state save " + path}
		}
		if strings.HasPrefix(lowerTrimmed, ".state load ") {
			path := strings.TrimSpace(trimmed[12:])
			return []string{"state load " + path}
		}
		if strings.HasPrefix(lowerTrimmed, ".boot ") {
			path := strings.TrimSpace(trimmed[6:])
			return []string{"boot " + path}
		}
	}

	// Mode-specific command translation.
	switch mode {
	case ModeMonitor:
		return translateMonitorCommand(trimmed)
	case ModeBasic:
		return []string{translateBASICCommand(trimmed, atasciiMode)}
	case ModeDOS:
		return []string{translateDOSCommand(trimmed)}
	default:
		return []string{trimmed}
	}
}

// translateMonitorCommand translates a monitor mode command to protocol
// command(s).
//
// Most commands produce a single protocol string, but "g $addr" expands to
// two: set the program counter first, then resume execution.
//
// GO CONCEPT: strings.SplitN for Command Parsing
// ------------------------------------------------
// SplitN(s, sep, n) splits s into at most n substrings. With n=2, we get
// the command keyword and all remaining arguments as two parts. This is
// the same as Swift's split(separator:maxSplits:) and Python's
// str.split(sep, maxsplit).
//
// Compare with Swift:
//   let parts = cmd.split(separator: " ", maxSplits: 1)
//   let keyword = String(parts.first ?? "")
//   let args = parts.count > 1 ? String(parts[1]) : ""
//
// Compare with Python:
//   parts = cmd.split(" ", maxsplit=1)
//   keyword = parts[0]
//   args = parts[1] if len(parts) > 1 else ""
func translateMonitorCommand(cmd string) []string {
	parts := strings.SplitN(cmd, " ", 2)
	keyword := strings.ToLower(parts[0])
	args := ""
	if len(parts) > 1 {
		args = strings.TrimSpace(parts[1])
	}

	// GO CONCEPT: Multi-Value Switch Cases
	// --------------------------------------
	// Go allows matching multiple values in a single case, separated by
	// commas. This is equivalent to Swift's "case x, y:" and Python's
	// "case x | y:" patterns.
	switch keyword {
	case "g":
		// "g" alone means resume from current PC.
		// "g $addr" means set PC to addr, then resume.
		if args == "" {
			return []string{"resume"}
		}
		return []string{"registers pc=" + args, "resume"}

	case "s", "step":
		if args == "" {
			return []string{"step"}
		}
		return []string{"step " + args}

	case "so", "stepover":
		return []string{"stepover"}

	case "p", "pause":
		return []string{"pause"}

	case "r", "registers":
		if args == "" {
			return []string{"registers"}
		}
		return []string{"registers " + args}

	case "m", "memory":
		// "m $0600 16" → "read $0600 16"
		return []string{"read " + args}

	case ">":
		// "> $0600 A9,00" → "write $0600 A9,00"
		return []string{"write " + args}

	case "f", "fill":
		// "f $0600 $06FF $00" → "fill $0600 $06FF $00"
		return []string{"fill " + args}

	case "d", "disassemble":
		if args == "" {
			return []string{"disassemble"}
		}
		return []string{"disassemble " + args}

	case "a", "assemble":
		// "a $0600" → "assemble $0600" (enters interactive assembly mode)
		// "a $0600 LDA #$42" → "assemble $0600 LDA #$42" (single instruction)
		if args == "" {
			return []string{"assemble"}
		}
		return []string{"assemble " + args}

	case "b", "breakpoint":
		return []string{"breakpoint " + args}

	case "bp":
		// Shorthand: "bp $0600" → "breakpoint set $0600"
		return []string{"breakpoint set " + args}

	case "bc":
		// Shorthand: "bc $0600" → "breakpoint clear $0600"
		return []string{"breakpoint clear " + args}

	case "until":
		return []string{"rununtil " + args}

	default:
		// Pass through unrecognized commands unchanged.
		return []string{cmd}
	}
}

// translateBASICCommand translates a BASIC mode command to a single protocol
// command string.
//
// Recognized BASIC commands (LIST, DEL, RUN, etc.) are prefixed with "basic "
// for the protocol. Unrecognized input is assumed to be direct BASIC code
// (like "10 PRINT \"HELLO\"") and is sent as keystroke injection.
//
// GO CONCEPT: String Escaping for Keystroke Injection
// ---------------------------------------------------
// When injecting BASIC input as keystrokes, certain characters need to be
// escaped so the protocol can transmit them unambiguously:
//   - Space → \s   (spaces are argument separators in the protocol)
//   - Tab   → \t   (tabs are whitespace)
//   - \     → \\   (backslash is the escape character)
//   - \n is appended to simulate pressing RETURN
//
// This is the same escaping scheme used by the Swift CLI.
//
// Compare with Swift:
//   let escaped = cmd
//       .replacingOccurrences(of: "\\", with: "\\\\")
//       .replacingOccurrences(of: " ", with: "\\s")
//       .replacingOccurrences(of: "\t", with: "\\t")
//
// Compare with Python:
//   escaped = cmd.replace("\\", "\\\\").replace(" ", "\\s").replace("\t", "\\t")
func translateBASICCommand(cmd string, atasciiMode bool) string {
	parts := strings.SplitN(cmd, " ", 2)
	keyword := strings.ToUpper(parts[0])
	args := ""
	if len(parts) > 1 {
		args = strings.TrimSpace(parts[1])
	}

	switch keyword {
	case "LIST":
		result := "basic list"
		if args != "" {
			result += " " + args
		}
		if atasciiMode {
			result += " atascii"
		}
		return result

	case "DEL", "DELETE":
		if args == "" {
			return "basic del" // Let server report the missing argument error
		}
		return "basic del " + args

	case "NEW":
		return "basic new"

	case "RUN":
		return "basic run"

	case "STOP":
		return "basic stop"

	case "CONT":
		return "basic cont"

	case "VARS":
		return "basic vars"

	case "VAR":
		if args == "" {
			return "basic var"
		}
		return "basic var " + args

	case "INFO":
		return "basic info"

	case "RENUM", "RENUMBER":
		if args == "" {
			return "basic renum"
		}
		return "basic renum " + args

	case "SAVE":
		if args == "" {
			return "basic save"
		}
		return "basic save " + args

	case "LOAD":
		if args == "" {
			return "basic load"
		}
		return "basic load " + args

	case "EXPORT":
		if args == "" {
			return "basic export"
		}
		return "basic export " + args

	case "IMPORT":
		if args == "" {
			return "basic import"
		}
		return "basic import " + args

	case "DIR":
		if args == "" {
			return "basic dir"
		}
		return "basic dir " + args

	default:
		// Default: inject keys to type BASIC input via keyboard.
		// Escape special characters so they survive protocol transport,
		// then append \n to simulate pressing RETURN.
		escaped := strings.ReplaceAll(cmd, `\`, `\\`)
		escaped = strings.ReplaceAll(escaped, " ", `\s`)
		escaped = strings.ReplaceAll(escaped, "\t", `\t`)
		return "inject keys " + escaped + `\n`
	}
}

// translateDOSCommand translates a DOS mode command to a single protocol
// command string.
//
// Three disk commands (mount, unmount, drives) are top-level protocol
// commands shared across modes. All other DOS commands are prefixed with
// "dos " for the protocol.
//
// GO CONCEPT: Consistent Command Translation Pattern
// ---------------------------------------------------
// All three translation functions follow the same pattern:
//   1. Split input into keyword + args
//   2. Normalize keyword (lowercase for monitor/DOS, uppercase for BASIC)
//   3. Switch on keyword to produce the protocol string
//   4. Default case passes through or rejects unknown commands
//
// This consistency makes the code predictable and easy to extend.
//
// Compare with Swift: The Swift CLI uses the identical pattern with
// switch/case, producing the same protocol output for the same input.
//
// Compare with Python: Python would use a dict of handler functions
// or match/case for the same dispatch pattern.
func translateDOSCommand(cmd string) string {
	parts := strings.SplitN(cmd, " ", 2)
	keyword := strings.ToLower(parts[0])
	args := ""
	if len(parts) > 1 {
		args = strings.TrimSpace(parts[1])
	}

	switch keyword {
	// Top-level disk commands (shared across modes, not DOS-prefixed).
	case "mount":
		return "mount " + args
	case "unmount", "umount":
		return "unmount " + args
	case "drives":
		return "drives"

	// DOS-specific commands — prefixed with "dos" for the protocol.
	case "cd":
		return "dos cd " + args
	case "dir":
		if args == "" {
			return "dos dir"
		}
		return "dos dir " + args
	case "info":
		return "dos info " + args
	case "type":
		return "dos type " + args
	case "dump":
		return "dos dump " + args
	case "copy", "cp":
		return "dos copy " + args
	case "rename", "ren":
		return "dos rename " + args
	case "delete", "del":
		return "dos delete " + args
	case "lock":
		return "dos lock " + args
	case "unlock":
		return "dos unlock " + args
	case "export":
		return "dos export " + args
	case "import":
		return "dos import " + args
	case "newdisk":
		return "dos newdisk " + args
	case "format":
		return "dos format"

	default:
		// Pass through unrecognized commands unchanged.
		return cmd
	}
}

// parseHexAddress parses a hex address string like "$0600" into a uint16.
//
// The string must have a "$" prefix. Returns the parsed address and true
// on success, or 0 and false on failure.
//
// GO CONCEPT: Multiple Return Values for Optional Results
// --------------------------------------------------------
// Go doesn't have optionals like Swift's UInt16?. Instead, we return
// (value, ok) where ok indicates whether the value is valid. This is
// the same pattern used by map lookups: val, ok := m[key].
//
// Compare with Swift:
//   static func parseHexAddress(_ str: String) -> UInt16? {
//       guard str.hasPrefix("$") else { return nil }
//       return UInt16(str.dropFirst(), radix: 16)
//   }
//
// Compare with Python:
//   def parse_hex_address(s: str) -> int | None:
//       if not s.startswith("$"): return None
//       try: return int(s[1:], 16)
//       except ValueError: return None
func parseHexAddress(s string) (uint16, bool) {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "$") {
		return 0, false
	}
	// Parse the hex digits after the $ prefix.
	// strconv.ParseUint returns (value, error).
	val, err := parseUint16Hex(s[1:])
	if err != nil {
		return 0, false
	}
	return val, true
}

// parseUint16Hex parses a hex string (without $ prefix) into a uint16.
//
// GO CONCEPT: strconv Package for Number Parsing
// ------------------------------------------------
// strconv.ParseUint(s, base, bitSize) parses unsigned integers.
//   - base 16 means hexadecimal
//   - bitSize 16 means the result must fit in a uint16
//
// Compare with Swift: UInt16("0600", radix: 16) returns an optional.
// Compare with Python: int("0600", 16) returns an int or raises ValueError.
func parseUint16Hex(s string) (uint16, error) {
	val, err := strconv.ParseUint(s, 16, 16)
	if err != nil {
		return 0, fmt.Errorf("invalid hex string: %s", s)
	}
	return uint16(val), nil
}
