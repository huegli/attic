// =============================================================================
// help_test.go - Tests for Help System (help.go)
// =============================================================================
//
// Tests for the help system, covering:
//   - Help overview output (global + mode-specific)
//   - Topic-specific help lookup (global and mode-specific dictionaries)
//   - Case-insensitive topic matching
//   - Leading dot stripping (.boot → boot)
//   - Unknown topic error messages
//   - Help dictionary completeness (all commands have help entries)
//
// GO CONCEPT: Capturing Output for Testing
// -----------------------------------------
// The help system writes to stdout (fmt.Print) and stderr (fmt.Fprintf).
// To test output, we redirect os.Stdout to a pipe and read what was written.
// This is the same technique used in repl_test.go for REPL output capture.
//
// Compare with Swift: XCTest doesn't have built-in stdout capture; you'd
// either refactor to write to a configurable Writer or use pipe redirection.
//
// Compare with Python: pytest provides `capsys` fixture for stdout capture:
//   def test_help(capsys): print_help(...); captured = capsys.readouterr()
// Or use `contextlib.redirect_stdout(io.StringIO())`.
//
// =============================================================================

package main

import (
	"bufio"
	"os"
	"strings"
	"sync"
	"testing"
)

// =============================================================================
// Helper: Capture stdout
// =============================================================================

// captureStdout runs a function and returns everything it wrote to stdout.
//
// GO CONCEPT: Higher-Order Functions for Test Utilities
// -------------------------------------------------------
// This helper takes a function (fn func()) and captures its stdout output.
// Higher-order functions (functions that take or return other functions)
// are common in Go test utilities for wrapping behavior.
//
// Compare with Swift: Swift closures serve the same purpose:
//   func captureStdout(_ fn: () -> Void) -> String { ... }
//
// Compare with Python: Python uses context managers:
//   with redirect_stdout(io.StringIO()) as f:
//       fn()
//       return f.getvalue()
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()

	oldStdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdout pipe: %v", err)
	}
	os.Stdout = w

	var wg sync.WaitGroup
	var output string

	wg.Add(1)
	go func() {
		defer wg.Done()
		var buf strings.Builder
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			buf.WriteString(scanner.Text())
			buf.WriteString("\n")
		}
		output = buf.String()
	}()

	fn()

	w.Close()
	os.Stdout = oldStdout
	wg.Wait()
	r.Close()

	return output
}

// =============================================================================
// Help Overview Tests
// =============================================================================

// TestHelpOverviewContainsGlobalCommands verifies that .help shows global
// commands regardless of mode.
func TestHelpOverviewContainsGlobalCommands(t *testing.T) {
	modes := []REPLMode{ModeMonitor, ModeBasic, ModeDOS}
	globalCommands := []string{
		".monitor", ".basic", ".dos", ".help", ".status",
		".screenshot", ".screen", ".boot", ".reset", ".warmstart",
		".state", ".quit", ".shutdown",
	}

	for _, mode := range modes {
		output := captureStdout(t, func() {
			printHelp(mode, "")
		})

		for _, cmd := range globalCommands {
			if !strings.Contains(output, cmd) {
				t.Errorf("mode %d: help overview missing %q", mode, cmd)
			}
		}
	}
}

// TestHelpOverviewMonitorMode verifies monitor-specific commands appear.
func TestHelpOverviewMonitorMode(t *testing.T) {
	output := captureStdout(t, func() {
		printHelp(ModeMonitor, "")
	})

	monitorCommands := []string{
		"g [addr]", "s [n]", "so", "p ", "r [reg=val",
		"m <addr>", "> <addr>", "f <s>", "a <addr>",
		"d [addr]", "b set", "b clear", "b list",
		"bp <addr>", "bc <addr>", "until <addr>",
	}
	for _, cmd := range monitorCommands {
		if !strings.Contains(output, cmd) {
			t.Errorf("monitor help missing %q in output:\n%s", cmd, output)
		}
	}
}

// TestHelpOverviewBasicMode verifies BASIC-specific commands appear.
func TestHelpOverviewBasicMode(t *testing.T) {
	output := captureStdout(t, func() {
		printHelp(ModeBasic, "")
	})

	basicCommands := []string{
		"list", "del", "new", "run", "renum", "info",
		"vars", "var", "stop", "cont", "save", "load",
		"export", "import", "dir",
	}
	for _, cmd := range basicCommands {
		if !strings.Contains(output, cmd) {
			t.Errorf("basic help missing %q", cmd)
		}
	}
}

// TestHelpOverviewDOSMode verifies DOS-specific commands appear.
func TestHelpOverviewDOSMode(t *testing.T) {
	output := captureStdout(t, func() {
		printHelp(ModeDOS, "")
	})

	dosCommands := []string{
		"mount", "unmount", "drives", "cd", "dir", "info",
		"type", "dump", "copy", "rename", "delete",
		"lock", "unlock", "export", "import", "newdisk", "format",
	}
	for _, cmd := range dosCommands {
		if !strings.Contains(output, cmd) {
			t.Errorf("dos help missing %q", cmd)
		}
	}
}

// =============================================================================
// Topic-Specific Help Tests
// =============================================================================

// TestHelpTopicGlobal verifies topic-specific help for global dot-commands.
func TestHelpTopicGlobal(t *testing.T) {
	tests := []struct {
		topic   string
		expects string
	}{
		{"monitor", "Switch to monitor mode"},
		{"basic", "Switch to BASIC mode"},
		{"dos", "Switch to DOS mode"},
		{"help", ".help [command]"},
		{"status", "emulator status"},
		{"screenshot", "Capture the emulator display"},
		{"screen", "GRAPHICS 0"},
		{"boot", "Boot the emulator"},
		{"reset", "cold reset"},
		{"warmstart", "warm reset"},
		{"state", "save <path>"},
		{"quit", "Disconnect from the server"},
		{"shutdown", "stop the server"},
	}

	for _, tc := range tests {
		t.Run(tc.topic, func(t *testing.T) {
			output := captureStdout(t, func() {
				printHelp(ModeMonitor, tc.topic)
			})
			if !strings.Contains(output, tc.expects) {
				t.Errorf(".help %s: expected %q in output, got:\n%s",
					tc.topic, tc.expects, output)
			}
		})
	}
}

// TestHelpTopicMonitor verifies topic-specific help for monitor commands.
func TestHelpTopicMonitor(t *testing.T) {
	tests := []struct {
		topic   string
		expects string
	}{
		{"g", "Resume execution"},
		{"s", "Step the emulator"},
		{"so", "Step over"},
		{"p", "Pause emulation"},
		{"r", "Display CPU registers"},
		{"m", "Dump memory"},
		{">", "Write bytes to memory"},
		{"f", "Fill a memory range"},
		{"a", "Assemble 6502 code"},
		{"d", "Disassemble 6502 code"},
		{"b", "Manage breakpoints"},
		{"bp", "Set a breakpoint"},
		{"bc", "Clear the breakpoint"},
		{"until", "Run the emulator until"},
	}

	for _, tc := range tests {
		t.Run(tc.topic, func(t *testing.T) {
			output := captureStdout(t, func() {
				printHelp(ModeMonitor, tc.topic)
			})
			if !strings.Contains(output, tc.expects) {
				t.Errorf(".help %s (monitor): expected %q in output, got:\n%s",
					tc.topic, tc.expects, output)
			}
		})
	}
}

// TestHelpTopicBasic verifies topic-specific help for BASIC commands.
func TestHelpTopicBasic(t *testing.T) {
	tests := []struct {
		topic   string
		expects string
	}{
		{"list", "List the BASIC program"},
		{"del", "Delete a single line"},
		{"new", "Clear the current BASIC program"},
		{"run", "Run the current BASIC program"},
		{"renum", "Renumber all program lines"},
		{"info", "program statistics"},
		{"vars", "List all BASIC variables"},
		{"var", "Show a single variable"},
		{"stop", "Send BREAK"},
		{"cont", "Continue execution"},
		{"save", "Save the current BASIC program"},
		{"load", "Load a BASIC program"},
		{"export", "Export the current BASIC listing"},
		{"import", "Import a BASIC listing"},
		{"dir", "List the directory"},
	}

	for _, tc := range tests {
		t.Run(tc.topic, func(t *testing.T) {
			output := captureStdout(t, func() {
				printHelp(ModeBasic, tc.topic)
			})
			if !strings.Contains(output, tc.expects) {
				t.Errorf(".help %s (basic): expected %q in output, got:\n%s",
					tc.topic, tc.expects, output)
			}
		})
	}
}

// TestHelpTopicDOS verifies topic-specific help for DOS commands.
func TestHelpTopicDOS(t *testing.T) {
	tests := []struct {
		topic   string
		expects string
	}{
		{"mount", "Mount an ATR disk image"},
		{"unmount", "Unmount the disk image"},
		{"drives", "List all drive slots"},
		{"cd", "Change the current working drive"},
		{"dir", "List the directory"},
		{"info", "detailed information"},
		{"type", "Display the contents"},
		{"dump", "hex dump"},
		{"copy", "Copy a file"},
		{"rename", "Rename a file"},
		{"delete", "Delete a file"},
		{"lock", "Lock a file"},
		{"unlock", "Unlock a previously locked"},
		{"export", "Export a file from the ATR disk"},
		{"import", "Import a file from the host"},
		{"newdisk", "Create a new blank ATR"},
		{"format", "Format the current drive"},
	}

	for _, tc := range tests {
		t.Run(tc.topic, func(t *testing.T) {
			output := captureStdout(t, func() {
				printHelp(ModeDOS, tc.topic)
			})
			if !strings.Contains(output, tc.expects) {
				t.Errorf(".help %s (dos): expected %q in output, got:\n%s",
					tc.topic, tc.expects, output)
			}
		})
	}
}

// TestHelpTopicCaseInsensitive verifies case-insensitive topic lookup.
//
// GO CONCEPT: Case-Insensitive Map Lookup
// -----------------------------------------
// Go maps are case-sensitive by default. To support case-insensitive
// lookup, we normalize the key to lowercase before looking it up.
// This is done in printHelp() via strings.ToLower(topic).
//
// Compare with Swift: Swift String comparison is Unicode-aware.
// Compare with Python: dict keys are case-sensitive; use .lower() to normalize.
func TestHelpTopicCaseInsensitive(t *testing.T) {
	tests := []struct {
		topic string
	}{
		{"MONITOR"},
		{"Monitor"},
		{"monitor"},
		{"RESET"},
		{"Reset"},
	}

	for _, tc := range tests {
		t.Run(tc.topic, func(t *testing.T) {
			output := captureStdout(t, func() {
				printHelp(ModeMonitor, tc.topic)
			})
			// Should find the help text, not show "No help for" error.
			if strings.Contains(output, "No help for") {
				t.Errorf("case-insensitive lookup failed for %q", tc.topic)
			}
		})
	}
}

// TestHelpTopicLeadingDotStripped verifies that ".boot" is looked up as "boot".
func TestHelpTopicLeadingDotStripped(t *testing.T) {
	output := captureStdout(t, func() {
		printHelp(ModeMonitor, ".boot")
	})

	if !strings.Contains(output, "Boot the emulator") {
		t.Errorf("leading dot not stripped for .boot, got:\n%s", output)
	}
}

// TestHelpTopicUnknown verifies error output for unknown topics.
func TestHelpTopicUnknown(t *testing.T) {
	// Capture stderr for error message.
	oldStderr := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stderr pipe: %v", err)
	}
	os.Stderr = w
	t.Cleanup(func() { os.Stderr = oldStderr })

	var wg sync.WaitGroup
	var stderrOutput string

	wg.Add(1)
	go func() {
		defer wg.Done()
		var buf strings.Builder
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			buf.WriteString(scanner.Text())
			buf.WriteString("\n")
		}
		stderrOutput = buf.String()
	}()

	// Capture stdout too (printHelp may write to stdout for found topics).
	_ = captureStdout(t, func() {
		printHelp(ModeMonitor, "nonexistent")
	})

	w.Close()
	wg.Wait()
	r.Close()

	if !strings.Contains(stderrOutput, "No help for") {
		t.Errorf("expected 'No help for' error, got:\n%s", stderrOutput)
	}
}

// =============================================================================
// Help Dictionary Completeness Tests
// =============================================================================

// TestHelpDictionaryGlobalComplete verifies all expected global commands
// have help entries.
//
// GO CONCEPT: Testing Map Completeness
// -----------------------------------------------
// We define the expected keys and verify they all exist in the map.
// This catches regressions where a new command is added to the
// overview but its topic-specific help entry is forgotten.
func TestHelpDictionaryGlobalComplete(t *testing.T) {
	expectedKeys := []string{
		"monitor", "basic", "dos", "help", "status", "screenshot",
		"screen", "boot", "reset", "warmstart", "state", "quit", "shutdown",
	}

	for _, key := range expectedKeys {
		if _, ok := globalHelp[key]; !ok {
			t.Errorf("globalHelp missing entry for %q", key)
		}
	}
}

// TestHelpDictionaryMonitorComplete verifies all monitor commands have help.
func TestHelpDictionaryMonitorComplete(t *testing.T) {
	expectedKeys := []string{
		"g", "s", "step", "so", "stepover", "p", "pause",
		"r", "registers", "m", "memory", ">",
		"f", "fill", "a", "assemble", "d", "disassemble",
		"b", "breakpoint", "bp", "bc", "until",
	}

	for _, key := range expectedKeys {
		if _, ok := monitorHelp[key]; !ok {
			t.Errorf("monitorHelp missing entry for %q", key)
		}
	}
}

// TestHelpDictionaryBasicComplete verifies all BASIC commands have help.
func TestHelpDictionaryBasicComplete(t *testing.T) {
	expectedKeys := []string{
		"list", "del", "new", "run", "renum", "info",
		"vars", "var", "stop", "cont", "save", "load",
		"export", "import", "dir",
	}

	for _, key := range expectedKeys {
		if _, ok := basicHelp[key]; !ok {
			t.Errorf("basicHelp missing entry for %q", key)
		}
	}
}

// TestHelpDictionaryDOSComplete verifies all DOS commands have help.
func TestHelpDictionaryDOSComplete(t *testing.T) {
	expectedKeys := []string{
		"mount", "unmount", "drives", "cd", "dir", "info",
		"type", "dump", "copy", "rename", "delete",
		"lock", "unlock", "export", "import", "newdisk", "format",
	}

	for _, key := range expectedKeys {
		if _, ok := dosHelp[key]; !ok {
			t.Errorf("dosHelp missing entry for %q", key)
		}
	}
}

// TestModeHelpReturnsCorrectDictionary verifies modeHelp() returns the
// right dictionary for each mode.
func TestModeHelpReturnsCorrectDictionary(t *testing.T) {
	// Verify monitor mode.
	m := modeHelp(ModeMonitor)
	if _, ok := m["g"]; !ok {
		t.Error("modeHelp(ModeMonitor) should contain 'g'")
	}

	// Verify basic mode.
	b := modeHelp(ModeBasic)
	if _, ok := b["list"]; !ok {
		t.Error("modeHelp(ModeBasic) should contain 'list'")
	}

	// Verify DOS mode.
	d := modeHelp(ModeDOS)
	if _, ok := d["mount"]; !ok {
		t.Error("modeHelp(ModeDOS) should contain 'mount'")
	}

	// Verify unknown mode returns nil.
	u := modeHelp(REPLMode(99))
	if u != nil {
		t.Errorf("modeHelp(99) should return nil, got %v", u)
	}
}
