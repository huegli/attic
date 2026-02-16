// =============================================================================
// translate_test.go - Tests for Command Translation (translate.go)
// =============================================================================
//
// Comprehensive tests for the three command translation functions:
//   - translateMonitorCommand: Monitor mode commands (g, s, p, r, m, etc.)
//   - translateBASICCommand:   BASIC mode commands (list, del, run, etc.)
//   - translateDOSCommand:     DOS mode commands (mount, dir, copy, etc.)
//   - translateToProtocol:     Top-level dispatcher (dot-commands + mode routing)
//
// Tests verify that user-facing REPL commands are correctly translated to
// the wire-format CLI protocol strings expected by AtticServer. Each test
// case specifies the input command and the expected protocol output.
//
// GO CONCEPT: Table-Driven Tests
// --------------------------------
// Go's testing convention heavily uses table-driven tests: define a slice
// of test cases as anonymous structs, then iterate over them with t.Run().
// This produces clear test names, shared setup, and easy extensibility.
//
// The pattern:
//   tests := []struct {
//       name     string
//       input    string
//       expected []string  // or string, int, etc.
//   }{ ... }
//   for _, tc := range tests {
//       t.Run(tc.name, func(t *testing.T) { ... })
//   }
//
// Compare with Swift: XCTest doesn't have built-in parameterized tests.
// You'd either write separate test methods or use a loop:
//   for testCase in testCases { XCTAssertEqual(...) }
//
// Compare with Python: pytest uses @pytest.mark.parametrize:
//   @pytest.mark.parametrize("input,expected", [("g", ["resume"]), ...])
//   def test_monitor(input, expected): assert translate(input) == expected
// This is the closest equivalent to Go's table-driven approach.
//
// =============================================================================

package main

import (
	"reflect"
	"testing"
)

// =============================================================================
// Monitor Command Translation Tests
// =============================================================================

// TestTranslateMonitorCommand tests all monitor mode command translations.
//
// GO CONCEPT: reflect.DeepEqual for Slice Comparison
// ---------------------------------------------------
// Go's == operator doesn't work on slices (it can only compare to nil).
// To compare two slices element by element, use reflect.DeepEqual().
// It recursively compares all elements and returns true if they match.
//
// Compare with Swift: Swift arrays support == directly:
//   XCTAssertEqual(result, ["resume"])
//
// Compare with Python: Python lists support == directly:
//   assert result == ["resume"]
func TestTranslateMonitorCommand(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		// Go (resume) command
		{"g alone", "g", []string{"resume"}},
		{"g with address", "g $0600", []string{"registers pc=$0600", "resume"}},
		{"g with hex address", "g $E000", []string{"registers pc=$E000", "resume"}},

		// Step commands
		{"s alone", "s", []string{"step"}},
		{"s with count", "s 10", []string{"step 10"}},
		{"step alias", "step", []string{"step"}},
		{"step with count", "step 5", []string{"step 5"}},

		// Step over
		{"so", "so", []string{"stepover"}},
		{"stepover alias", "stepover", []string{"stepover"}},

		// Pause
		{"p", "p", []string{"pause"}},
		{"pause alias", "pause", []string{"pause"}},

		// Registers
		{"r alone", "r", []string{"registers"}},
		{"r with assignment", "r a=42", []string{"registers a=42"}},
		{"r multiple assignments", "r pc=E000 a=00", []string{"registers pc=E000 a=00"}},
		{"registers alias", "registers", []string{"registers"}},

		// Memory read
		{"m with args", "m $0600 16", []string{"read $0600 16"}},
		{"memory alias", "memory $D000 64", []string{"read $D000 64"}},

		// Memory write
		{"write", "> $0600 A9,00,8D,00,D4", []string{"write $0600 A9,00,8D,00,D4"}},

		// Fill
		{"fill short", "f $0600 $06FF $00", []string{"fill $0600 $06FF $00"}},
		{"fill alias", "fill $4000 $7FFF $FF", []string{"fill $4000 $7FFF $FF"}},

		// Disassemble
		{"d alone", "d", []string{"disassemble"}},
		{"d with address", "d $E000", []string{"disassemble $E000"}},
		{"d with address and lines", "d $E000 32", []string{"disassemble $E000 32"}},
		{"disassemble alias", "disassemble $C000", []string{"disassemble $C000"}},

		// Assemble
		{"a with address", "a $0600", []string{"assemble $0600"}},
		{"a single instruction", "a $0600 LDA #$42", []string{"assemble $0600 LDA #$42"}},
		{"assemble alias", "assemble $0600", []string{"assemble $0600"}},

		// Breakpoints
		{"b set", "b set $0600", []string{"breakpoint set $0600"}},
		{"b clear", "b clear $0600", []string{"breakpoint clear $0600"}},
		{"b list", "b list", []string{"breakpoint list"}},
		{"breakpoint alias", "breakpoint set $1234", []string{"breakpoint set $1234"}},
		{"bp shorthand", "bp $0600", []string{"breakpoint set $0600"}},
		{"bc shorthand", "bc $0600", []string{"breakpoint clear $0600"}},

		// Until
		{"until", "until $E459", []string{"rununtil $E459"}},

		// Unknown passthrough
		{"unknown command", "xyz $1234", []string{"xyz $1234"}},

		// Case insensitivity
		{"G uppercase", "G $0600", []string{"registers pc=$0600", "resume"}},
		{"S uppercase", "S 5", []string{"step 5"}},
		{"P uppercase", "P", []string{"pause"}},
		{"R uppercase", "R", []string{"registers"}},
		{"D uppercase", "D $0600", []string{"disassemble $0600"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := translateMonitorCommand(tc.input)
			if !reflect.DeepEqual(result, tc.expected) {
				t.Errorf("translateMonitorCommand(%q) = %v, want %v",
					tc.input, result, tc.expected)
			}
		})
	}
}

// =============================================================================
// BASIC Command Translation Tests
// =============================================================================

// TestTranslateBASICCommand tests all BASIC mode command translations.
//
// GO CONCEPT: Testing with Boolean Parameters
// -----------------------------------------------
// translateBASICCommand takes an atasciiMode parameter that affects
// LIST output. We test both modes to ensure the "atascii" suffix is
// correctly appended or omitted.
func TestTranslateBASICCommand(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		atascii    bool
		expected   string
	}{
		// LIST command
		{"list bare", "list", false, "basic list"},
		{"list with atascii", "list", true, "basic list atascii"},
		{"list range", "list 10-50", false, "basic list 10-50"},
		{"list range atascii", "list 10-50", true, "basic list 10-50 atascii"},
		{"LIST uppercase", "LIST", false, "basic list"},
		{"List mixed case", "List", true, "basic list atascii"},

		// DEL command
		{"del with line", "del 30", false, "basic del 30"},
		{"del range", "del 10-50", false, "basic del 10-50"},
		{"del no args", "del", false, "basic del"},
		{"delete alias", "delete 20", false, "basic del 20"},

		// NEW command
		{"new", "new", false, "basic new"},
		{"NEW uppercase", "NEW", false, "basic new"},

		// RUN command
		{"run", "run", false, "basic run"},
		{"RUN uppercase", "RUN", false, "basic run"},

		// STOP and CONT
		{"stop", "stop", false, "basic stop"},
		{"cont", "cont", false, "basic cont"},

		// VARS and VAR
		{"vars", "vars", false, "basic vars"},
		{"var with name", "var X", false, "basic var X"},
		{"var string", "var A$", false, "basic var A$"},
		{"var no args", "var", false, "basic var"},

		// INFO
		{"info", "info", false, "basic info"},

		// RENUM
		{"renum bare", "renum", false, "basic renum"},
		{"renum with args", "renum 100 5", false, "basic renum 100 5"},
		{"renumber alias", "renumber", false, "basic renum"},

		// SAVE and LOAD
		{"save", "save D:TEST", false, "basic save D:TEST"},
		{"save no args", "save", false, "basic save"},
		{"load", "load D:TEST", false, "basic load D:TEST"},
		{"load no args", "load", false, "basic load"},

		// EXPORT and IMPORT
		{"export", "export ~/prog.bas", false, "basic export ~/prog.bas"},
		{"import", "import ~/prog.bas", false, "basic import ~/prog.bas"},

		// DIR
		{"dir bare", "dir", false, "basic dir"},
		{"dir with drive", "dir 2", false, "basic dir 2"},

		// Keystroke injection (default for unrecognized commands)
		{"basic line", `10 PRINT "HELLO"`, false, `inject keys 10\sPRINT\s"HELLO"\n`},
		{"run immediate", "PRINT 2+2", false, `inject keys PRINT\s2+2\n`},
		{"goto", "GOTO 100", false, `inject keys GOTO\s100\n`},
		{"with tabs", "10\tPRINT", false, `inject keys 10\tPRINT\n`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := translateBASICCommand(tc.input, tc.atascii)
			if result != tc.expected {
				t.Errorf("translateBASICCommand(%q, %v) = %q, want %q",
					tc.input, tc.atascii, result, tc.expected)
			}
		})
	}
}

// TestTranslateBASICKeystrokeEscaping verifies that special characters
// are properly escaped for keystroke injection.
//
// GO CONCEPT: Focused Edge-Case Tests
// -----------------------------------------------
// In addition to table-driven tests covering all commands, it's good
// practice to have focused tests for tricky edge cases. The keystroke
// escaping logic has several special characters that need careful
// handling.
//
// Compare with Swift: Same approach — focused tests for edge cases.
// Compare with Python: Same approach — parametrize with edge case data.
func TestTranslateBASICKeystrokeEscaping(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"spaces escaped", "10 PRINT A", `inject keys 10\sPRINT\sA\n`},
		{"backslash escaped", `10 PRINT "\"`, `inject keys 10\sPRINT\s"\\"\n`},
		{"tab escaped", "10\tA=1", `inject keys 10\tA=1\n`},
		{"no special chars", "GOTO100", `inject keys GOTO100\n`},
		{"multiple spaces", "10  A  = 1", `inject keys 10\s\sA\s\s=\s1\n`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := translateBASICCommand(tc.input, false)
			if result != tc.expected {
				t.Errorf("translateBASICCommand(%q) = %q, want %q",
					tc.input, result, tc.expected)
			}
		})
	}
}

// =============================================================================
// DOS Command Translation Tests
// =============================================================================

// TestTranslateDOSCommand tests all DOS mode command translations.
func TestTranslateDOSCommand(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		// Top-level disk commands (not DOS-prefixed)
		{"mount", "mount 1 ~/disks/dos.atr", "mount 1 ~/disks/dos.atr"},
		{"unmount", "unmount 2", "unmount 2"},
		{"umount alias", "umount 1", "unmount 1"},
		{"drives", "drives", "drives"},

		// DOS-prefixed commands
		{"cd", "cd 2", "dos cd 2"},
		{"dir bare", "dir", "dos dir"},
		{"dir pattern", "dir *.COM", "dos dir *.COM"},
		{"info", "info AUTORUN.SYS", "dos info AUTORUN.SYS"},
		{"type", "type README.TXT", "dos type README.TXT"},
		{"dump", "dump GAME.COM", "dos dump GAME.COM"},
		{"copy", "copy D1:FILE D2:FILE", "dos copy D1:FILE D2:FILE"},
		{"cp alias", "cp SRC DST", "dos copy SRC DST"},
		{"rename", "rename OLD NEW", "dos rename OLD NEW"},
		{"ren alias", "ren OLD NEW", "dos rename OLD NEW"},
		{"delete", "delete FILE.DAT", "dos delete FILE.DAT"},
		{"del alias", "del FILE.DAT", "dos delete FILE.DAT"},
		{"lock", "lock FILE.DAT", "dos lock FILE.DAT"},
		{"unlock", "unlock FILE.DAT", "dos unlock FILE.DAT"},
		{"export", "export GAME.BAS ~/out.bas", "dos export GAME.BAS ~/out.bas"},
		{"import", "import ~/in.bas GAME.BAS", "dos import ~/in.bas GAME.BAS"},
		{"newdisk", "newdisk ~/blank.atr dd", "dos newdisk ~/blank.atr dd"},
		{"format", "format", "dos format"},

		// Case insensitivity
		{"MOUNT uppercase", "MOUNT 1 ~/disk.atr", "mount 1 ~/disk.atr"},
		{"DIR uppercase", "DIR *.BAS", "dos dir *.BAS"},

		// Unknown passthrough
		{"unknown", "xyz foo", "xyz foo"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := translateDOSCommand(tc.input)
			if result != tc.expected {
				t.Errorf("translateDOSCommand(%q) = %q, want %q",
					tc.input, result, tc.expected)
			}
		})
	}
}

// =============================================================================
// Top-Level translateToProtocol Tests
// =============================================================================

// TestTranslateToProtocolDotCommands tests dot-command translation at the
// top level (before mode-specific routing).
func TestTranslateToProtocolDotCommands(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		// Forwarded dot-commands
		{"status", ".status", []string{"status"}},
		{"screen", ".screen", []string{"screen"}},
		{"reset", ".reset", []string{"reset cold"}},
		{"warmstart", ".warmstart", []string{"reset warm"}},
		{"screenshot bare", ".screenshot", []string{"screenshot"}},
		{"screenshot path", ".screenshot ~/cap.png", []string{"screenshot ~/cap.png"}},
		{"state save", ".state save ~/s.state", []string{"state save ~/s.state"}},
		{"state load", ".state load ~/s.state", []string{"state load ~/s.state"}},
		{"boot", ".boot ~/game.atr", []string{"boot ~/game.atr"}},

		// Case insensitivity for dot-commands
		{"RESET uppercase", ".RESET", []string{"reset cold"}},
		{"Status mixed", ".Status", []string{"status"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Mode shouldn't matter for dot-commands.
			result := translateToProtocol(tc.input, ModeMonitor, false)
			if !reflect.DeepEqual(result, tc.expected) {
				t.Errorf("translateToProtocol(%q) = %v, want %v",
					tc.input, result, tc.expected)
			}
		})
	}
}

// TestTranslateToProtocolModeRouting verifies that mode-specific commands
// are routed to the correct translation function.
func TestTranslateToProtocolModeRouting(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		mode     REPLMode
		atascii  bool
		expected []string
	}{
		// Monitor mode routing
		{"monitor g", "g", ModeMonitor, false, []string{"resume"}},
		{"monitor d", "d $0600", ModeMonitor, false, []string{"disassemble $0600"}},

		// BASIC mode routing
		{"basic list", "list", ModeBasic, false, []string{"basic list"}},
		{"basic list atascii", "list", ModeBasic, true, []string{"basic list atascii"}},
		{"basic injection", "PRINT 42", ModeBasic, false, []string{`inject keys PRINT\s42\n`}},

		// DOS mode routing
		{"dos dir", "dir", ModeDOS, false, []string{"dos dir"}},
		{"dos mount", "mount 1 ~/d.atr", ModeDOS, false, []string{"mount 1 ~/d.atr"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := translateToProtocol(tc.input, tc.mode, tc.atascii)
			if !reflect.DeepEqual(result, tc.expected) {
				t.Errorf("translateToProtocol(%q, mode=%d, atascii=%v) = %v, want %v",
					tc.input, tc.mode, tc.atascii, result, tc.expected)
			}
		})
	}
}

// =============================================================================
// Hex Address Parsing Tests
// =============================================================================

// TestParseHexAddress verifies hex address parsing for the assembly sub-mode.
//
// GO CONCEPT: Testing Functions with Multiple Returns
// ---------------------------------------------------
// When testing functions that return (value, ok), we check both values.
// The ok boolean tells us whether parsing succeeded, and the value
// gives us the result. This is the Go equivalent of testing Swift
// optionals (nil vs non-nil) or Python (None vs value).
func TestParseHexAddress(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected uint16
		ok       bool
	}{
		{"valid $0600", "$0600", 0x0600, true},
		{"valid $E000", "$E000", 0xE000, true},
		{"valid $FFFF", "$FFFF", 0xFFFF, true},
		{"valid $0000", "$0000", 0x0000, true},
		{"lowercase hex", "$abcd", 0xABCD, true},
		{"with spaces", "  $0600  ", 0x0600, true},

		// Invalid inputs
		{"no prefix", "0600", 0, false},
		{"empty", "", 0, false},
		{"just dollar", "$", 0, false},
		{"invalid hex", "$GHIJ", 0, false},
		{"decimal", "1536", 0, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			val, ok := parseHexAddress(tc.input)
			if ok != tc.ok {
				t.Errorf("parseHexAddress(%q) ok = %v, want %v", tc.input, ok, tc.ok)
			}
			if ok && val != tc.expected {
				t.Errorf("parseHexAddress(%q) = $%04X, want $%04X", tc.input, val, tc.expected)
			}
		})
	}
}
