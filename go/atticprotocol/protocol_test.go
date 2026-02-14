package atticprotocol

import (
	"testing"
)

// TestProtocolConstants verifies constants match the Swift implementation.
func TestProtocolConstants(t *testing.T) {
	tests := []struct {
		name     string
		got      string
		expected string
	}{
		{"CommandPrefix", CommandPrefix, "CMD:"},
		{"OKPrefix", OKPrefix, "OK:"},
		{"ErrorPrefix", ErrorPrefix, "ERR:"},
		{"EventPrefix", EventPrefix, "EVENT:"},
		{"MultiLineSeparator", MultiLineSeparator, "\x1E"},
		{"SocketPathPrefix", SocketPathPrefix, "/tmp/attic-"},
		{"SocketPathSuffix", SocketPathSuffix, ".sock"},
		{"ProtocolVersion", ProtocolVersion, "1.0"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.expected {
				t.Errorf("got %q, want %q", tt.got, tt.expected)
			}
		})
	}
}

func TestSocketPath(t *testing.T) {
	path := SocketPath(12345)
	expected := "/tmp/attic-12345.sock"
	if path != expected {
		t.Errorf("got %q, want %q", path, expected)
	}
}

// TestCommandFormatting verifies command formatting matches the protocol.
func TestCommandFormatting(t *testing.T) {
	tests := []struct {
		name     string
		cmd      Command
		expected string
	}{
		{"Ping", NewPingCommand(), "ping"},
		{"Version", NewVersionCommand(), "version"},
		{"Quit", NewQuitCommand(), "quit"},
		{"Shutdown", NewShutdownCommand(), "shutdown"},
		{"Pause", NewPauseCommand(), "pause"},
		{"Resume", NewResumeCommand(), "resume"},
		{"Step 1", NewStepCommand(1), "step"},
		{"Step 10", NewStepCommand(10), "step 10"},
		{"Reset Cold", NewResetCommand(true), "reset cold"},
		{"Reset Warm", NewResetCommand(false), "reset warm"},
		{"Status", NewStatusCommand(), "status"},
		{"Read", NewReadCommand(0x0600, 16), "read $0600 16"},
		{"Write", NewWriteCommand(0x0600, []byte{0xA9, 0x00}), "write $0600 A9,00"},
		{"Registers (read)", NewRegistersCommand(nil), "registers"},
		{"Registers (modify)", NewRegistersCommand([]RegisterModification{
			{Name: "A", Value: 0x50},
			{Name: "X", Value: 0x10},
		}), "registers A=$0050 X=$0010"},
		{"Breakpoint Set", NewBreakpointSetCommand(0x0600), "breakpoint set $0600"},
		{"Breakpoint Clear", NewBreakpointClearCommand(0x0600), "breakpoint clear $0600"},
		{"Breakpoint ClearAll", NewBreakpointClearAllCommand(), "breakpoint clearall"},
		{"Breakpoint List", NewBreakpointListCommand(), "breakpoint list"},
		{"Disassemble (default)", NewDisassembleCommand(nil, nil), "disassemble"},
		{"Disassemble (address)", func() Command {
			addr := uint16(0x0600)
			return NewDisassembleCommand(&addr, nil)
		}(), "disassemble $0600"},
		{"Disassemble (address and lines)", func() Command {
			addr := uint16(0x0600)
			lines := 8
			return NewDisassembleCommand(&addr, &lines)
		}(), "disassemble $0600 8"},
		{"Assemble", NewAssembleCommand(0x0600), "assemble $0600"},
		{"AssembleLine", NewAssembleLineCommand(0x0600, "LDA #$00"), "assemble $0600 LDA #$00"},
		{"StepOver", NewStepOverCommand(), "stepover"},
		{"RunUntil", NewRunUntilCommand(0x0700), "until $0700"},
		{"MemoryFill", NewMemoryFillCommand(0x0600, 0x06FF, 0x00), "fill $0600 $06FF $00"},
		{"Mount", NewMountCommand(1, "/path/to/disk.atr"), "mount 1 /path/to/disk.atr"},
		{"Unmount", NewUnmountCommand(1), "unmount 1"},
		{"Drives", NewDrivesCommand(), "drives"},
		{"Boot", NewBootCommand("/path/to/game.xex"), "boot /path/to/game.xex"},
		{"StateSave", NewStateSaveCommand("/path/to/state"), "state save /path/to/state"},
		{"StateLoad", NewStateLoadCommand("/path/to/state"), "state load /path/to/state"},
		{"Screenshot (no path)", NewScreenshotCommand(""), "screenshot"},
		{"Screenshot (with path)", NewScreenshotCommand("/path/to/screenshot.png"), "screenshot /path/to/screenshot.png"},
		{"InjectBasic", NewInjectBasicCommand("SGVsbG8="), "inject basic SGVsbG8="},
		{"InjectKeys", NewInjectKeysCommand("Hello\n"), "inject keys Hello\\n"},
		{"InjectKeys with space", NewInjectKeysCommand("Hello World"), "inject keys Hello\\sWorld"},
		{"BasicLine", NewBasicLineCommand("10 PRINT HELLO"), "basic 10 PRINT HELLO"},
		{"BasicNew", NewBasicNewCommand(), "basic NEW"},
		{"BasicRun", NewBasicRunCommand(), "basic RUN"},
		{"BasicList", NewBasicListCommand(false), "basic LIST"},
		{"BasicList ATASCII", NewBasicListCommand(true), "basic LIST ATASCII"},
		// Assembly session commands
		{"AssembleInput", NewAssembleInputCommand("LDA #$00"), "asm input LDA #$00"},
		{"AssembleEnd", NewAssembleEndCommand(), "asm end"},
		// Screen text command
		{"ScreenText", NewScreenTextCommand(false), "screen"},
		{"ScreenText ATASCII", NewScreenTextCommand(true), "screen atascii"},
		// BASIC editing commands
		{"BasicDelete", NewBasicDeleteCommand("10"), "basic DEL 10"},
		{"BasicDelete range", NewBasicDeleteCommand("10-50"), "basic DEL 10-50"},
		{"BasicStop", NewBasicStopCommand(), "basic STOP"},
		{"BasicCont", NewBasicContCommand(), "basic CONT"},
		{"BasicVars", NewBasicVarsCommand(), "basic VARS"},
		{"BasicVar", NewBasicVarCommand("X"), "basic VAR X"},
		{"BasicInfo", NewBasicInfoCommand(), "basic INFO"},
		{"BasicExport", NewBasicExportCommand("/path/to/file.bas"), "basic EXPORT /path/to/file.bas"},
		{"BasicImport", NewBasicImportCommand("/path/to/file.bas"), "basic IMPORT /path/to/file.bas"},
		{"BasicDir (no drive)", NewBasicDirCommand(nil), "basic DIR"},
		{"BasicDir (drive 1)", func() Command {
			d := 1
			return NewBasicDirCommand(&d)
		}(), "basic DIR 1"},
		// BasicRenumber, BasicSave, BasicLoad
		{"BasicRenumber (no args)", NewBasicRenumberCommand(nil, nil), "basic RENUM"},
		{"BasicRenumber (start only)", func() Command {
			start := 100
			return NewBasicRenumberCommand(&start, nil)
		}(), "basic RENUM 100"},
		{"BasicRenumber (start and step)", func() Command {
			start := 100
			step := 20
			return NewBasicRenumberCommand(&start, &step)
		}(), "basic RENUM 100 20"},
		{"BasicSave (no drive)", NewBasicSaveCommand(nil, "PROGRAM"), "basic SAVE D:PROGRAM"},
		{"BasicSave (with drive)", func() Command {
			d := 2
			return NewBasicSaveCommand(&d, "MYPROG")
		}(), "basic SAVE D2:MYPROG"},
		{"BasicLoad (no drive)", NewBasicLoadCommand(nil, "PROGRAM"), "basic LOAD D:PROGRAM"},
		{"BasicLoad (with drive)", func() Command {
			d := 1
			return NewBasicLoadCommand(&d, "GAME")
		}(), "basic LOAD D1:GAME"},
		// DOS mode commands
		{"DosChangeDrive", NewDosChangeDriveCommand(2), "dos cd 2"},
		{"DosDirectory (no pattern)", NewDosDirectoryCommand(nil), "dos dir"},
		{"DosDirectory (with pattern)", func() Command {
			pattern := "*.BAS"
			return NewDosDirectoryCommand(&pattern)
		}(), "dos dir *.BAS"},
		{"DosFileInfo", NewDosFileInfoCommand("PROGRAM.BAS"), "dos info PROGRAM.BAS"},
		{"DosType", NewDosTypeCommand("README.TXT"), "dos type README.TXT"},
		{"DosDump", NewDosDumpCommand("DATA.DAT"), "dos dump DATA.DAT"},
		{"DosCopy", NewDosCopyCommand("D1:FILE.BAS", "D2:FILE.BAS"), "dos copy D1:FILE.BAS D2:FILE.BAS"},
		{"DosRename", NewDosRenameCommand("OLDNAME", "NEWNAME"), "dos rename OLDNAME NEWNAME"},
		{"DosDelete", NewDosDeleteCommand("JUNK.TMP"), "dos delete JUNK.TMP"},
		{"DosLock", NewDosLockCommand("PROTECT.BAS"), "dos lock PROTECT.BAS"},
		{"DosUnlock", NewDosUnlockCommand("PROTECT.BAS"), "dos unlock PROTECT.BAS"},
		{"DosExport", NewDosExportCommand("PROGRAM.BAS", "/host/path/program.bas"), "dos export PROGRAM.BAS /host/path/program.bas"},
		{"DosImport", NewDosImportCommand("/host/path/file.bas", "FILE.BAS"), "dos import /host/path/file.bas FILE.BAS"},
		{"DosNewDisk (no type)", NewDosNewDiskCommand("/path/to/disk.atr", nil), "dos newdisk /path/to/disk.atr"},
		{"DosNewDisk (with type)", func() Command {
			diskType := "dd"
			return NewDosNewDiskCommand("/path/to/disk.atr", &diskType)
		}(), "dos newdisk /path/to/disk.atr dd"},
		{"DosFormat", NewDosFormatCommand(), "dos format"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.cmd.Format()
			if got != tt.expected {
				t.Errorf("got %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestCommandFormatWithPrefix(t *testing.T) {
	cmd := NewPingCommand()
	got := cmd.FormatWithPrefix()
	expected := "CMD:ping"
	if got != expected {
		t.Errorf("got %q, want %q", got, expected)
	}
}

func TestCommandFormatLine(t *testing.T) {
	cmd := NewPingCommand()
	got := cmd.FormatLine()
	expected := "CMD:ping\n"
	if got != expected {
		t.Errorf("got %q, want %q", got, expected)
	}
}

// TestResponseFormatting verifies response formatting matches the protocol.
func TestResponseFormatting(t *testing.T) {
	tests := []struct {
		name     string
		resp     Response
		expected string
	}{
		{"OK", NewOKResponse("pong"), "OK:pong"},
		{"OK with data", NewOKResponse("data A9,00,8D"), "OK:data A9,00,8D"},
		{"Error", NewErrorResponse("command failed"), "ERR:command failed"},
		{"MultiLine", NewMultiLineResponse([]string{"line1", "line2", "line3"}), "OK:line1\x1Eline2\x1Eline3"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.resp.Format()
			if got != tt.expected {
				t.Errorf("got %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestResponseLines(t *testing.T) {
	resp := NewMultiLineResponse([]string{"line1", "line2", "line3"})
	lines := resp.Lines()
	if len(lines) != 3 {
		t.Errorf("expected 3 lines, got %d", len(lines))
	}
	if lines[0] != "line1" || lines[1] != "line2" || lines[2] != "line3" {
		t.Errorf("lines don't match: %v", lines)
	}
}

// TestEventFormatting verifies event formatting matches the protocol.
func TestEventFormatting(t *testing.T) {
	tests := []struct {
		name     string
		event    Event
		expected string
	}{
		{"Breakpoint", NewBreakpointEvent(0x0600, 0xA9, 0x10, 0x20, 0xFF, 0x30),
			"EVENT:breakpoint $0600 A=$A9 X=$10 Y=$20 S=$FF P=$30"},
		{"Stopped", NewStoppedEvent(0x0600), "EVENT:stopped $0600"},
		{"Error", NewErrorEvent("something went wrong"), "EVENT:error something went wrong"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.event.Format()
			if got != tt.expected {
				t.Errorf("got %q, want %q", got, tt.expected)
			}
		})
	}
}

// TestCommandParsing verifies command parsing works correctly.
func TestCommandParsing(t *testing.T) {
	parser := NewCommandParser()

	tests := []struct {
		name     string
		input    string
		expected Command
	}{
		{"Ping", "ping", NewPingCommand()},
		{"Ping with prefix", "CMD:ping", NewPingCommand()},
		{"Version", "version", NewVersionCommand()},
		{"Step", "step", NewStepCommand(1)},
		{"Step 5", "step 5", NewStepCommand(5)},
		{"Read hex", "read $0600 16", NewReadCommand(0x0600, 16)},
		{"Read 0x", "read 0x0600 16", NewReadCommand(0x0600, 16)},
		{"Read decimal", "read 1536 16", NewReadCommand(1536, 16)},
		{"Write", "write $0600 A9,00,8D", NewWriteCommand(0x0600, []byte{0xA9, 0x00, 0x8D})},
		{"Breakpoint set", "breakpoint set $0600", NewBreakpointSetCommand(0x0600)},
		{"Disassemble", "d", NewDisassembleCommand(nil, nil)},
		{"Disassemble address", "disasm $0600", func() Command {
			addr := uint16(0x0600)
			return NewDisassembleCommand(&addr, nil)
		}()},
		{"Assemble", "asm $0600 LDA #$00", NewAssembleLineCommand(0x0600, "LDA #$00")},
		{"Basic NEW", "basic NEW", NewBasicNewCommand()},
		{"Basic RUN", "basic RUN", NewBasicRunCommand()},
		{"Basic line", "basic 10 PRINT HELLO", NewBasicLineCommand("10 PRINT HELLO")},
		// New commands
		{"Boot", "boot /path/to/game.xex", NewBootCommand("/path/to/game.xex")},
		{"Basic DEL", "basic DEL 10", NewBasicDeleteCommand("10")},
		{"Basic DEL range", "basic DEL 10-50", NewBasicDeleteCommand("10-50")},
		{"Basic STOP", "basic STOP", NewBasicStopCommand()},
		{"Basic CONT", "basic CONT", NewBasicContCommand()},
		{"Basic VARS", "basic VARS", NewBasicVarsCommand()},
		{"Basic VAR", "basic VAR X", NewBasicVarCommand("X")},
		{"Basic INFO", "basic INFO", NewBasicInfoCommand()},
		{"Basic EXPORT", "basic EXPORT /path/to/file.bas", NewBasicExportCommand("/path/to/file.bas")},
		{"Basic IMPORT", "basic IMPORT /path/to/file.bas", NewBasicImportCommand("/path/to/file.bas")},
		{"Basic DIR", "basic DIR", NewBasicDirCommand(nil)},
		{"Basic DIR with drive", "basic DIR 1", func() Command {
			d := 1
			return NewBasicDirCommand(&d)
		}()},
		// New assembly session commands
		{"Asm input", "asm input LDA #$00", NewAssembleInputCommand("LDA #$00")},
		{"Asm end", "asm end", NewAssembleEndCommand()},
		// Screen text command
		{"Screen", "screen", NewScreenTextCommand(false)},
		{"Screen ATASCII", "screen atascii", NewScreenTextCommand(true)},
		// Basic LIST with ATASCII
		{"Basic LIST", "basic LIST", NewBasicListCommand(false)},
		{"Basic LIST ATASCII", "basic LIST ATASCII", NewBasicListCommand(true)},
		// Basic RENUM
		{"Basic RENUM", "basic RENUM", NewBasicRenumberCommand(nil, nil)},
		{"Basic RENUM with start", "basic RENUM 100", func() Command {
			start := 100
			return NewBasicRenumberCommand(&start, nil)
		}()},
		{"Basic RENUM with start and step", "basic RENUM 100 20", func() Command {
			start := 100
			step := 20
			return NewBasicRenumberCommand(&start, &step)
		}()},
		{"Basic RENUMBER alias", "basic RENUMBER 50 10", func() Command {
			start := 50
			step := 10
			return NewBasicRenumberCommand(&start, &step)
		}()},
		// Basic SAVE/LOAD
		{"Basic SAVE no drive", "basic SAVE D:PROGRAM", NewBasicSaveCommand(nil, "PROGRAM")},
		{"Basic SAVE with drive", "basic SAVE D2:MYPROG", func() Command {
			d := 2
			return NewBasicSaveCommand(&d, "MYPROG")
		}()},
		{"Basic LOAD no drive", "basic LOAD D:PROGRAM", NewBasicLoadCommand(nil, "PROGRAM")},
		{"Basic LOAD with drive", "basic LOAD D1:GAME", func() Command {
			d := 1
			return NewBasicLoadCommand(&d, "GAME")
		}()},
		// DOS mode commands
		{"DOS cd", "dos cd 2", NewDosChangeDriveCommand(2)},
		{"DOS dir", "dos dir", NewDosDirectoryCommand(nil)},
		{"DOS dir with pattern", "dos dir *.BAS", func() Command {
			pattern := "*.BAS"
			return NewDosDirectoryCommand(&pattern)
		}()},
		{"DOS info", "dos info PROGRAM.BAS", NewDosFileInfoCommand("PROGRAM.BAS")},
		{"DOS type", "dos type README.TXT", NewDosTypeCommand("README.TXT")},
		{"DOS dump", "dos dump DATA.DAT", NewDosDumpCommand("DATA.DAT")},
		{"DOS copy", "dos copy SOURCE DEST", NewDosCopyCommand("SOURCE", "DEST")},
		{"DOS rename", "dos rename OLD NEW", NewDosRenameCommand("OLD", "NEW")},
		{"DOS delete", "dos delete FILE.TMP", NewDosDeleteCommand("FILE.TMP")},
		{"DOS del alias", "dos del FILE.TMP", NewDosDeleteCommand("FILE.TMP")},
		{"DOS lock", "dos lock FILE.BAS", NewDosLockCommand("FILE.BAS")},
		{"DOS unlock", "dos unlock FILE.BAS", NewDosUnlockCommand("FILE.BAS")},
		{"DOS export", "dos export FILE.BAS /host/file.bas", NewDosExportCommand("FILE.BAS", "/host/file.bas")},
		{"DOS import", "dos import /host/file.bas FILE.BAS", NewDosImportCommand("/host/file.bas", "FILE.BAS")},
		{"DOS newdisk", "dos newdisk /path/disk.atr", NewDosNewDiskCommand("/path/disk.atr", nil)},
		{"DOS newdisk with type", "dos newdisk /path/disk.atr dd", func() Command {
			dt := "dd"
			return NewDosNewDiskCommand("/path/disk.atr", &dt)
		}()},
		{"DOS format", "dos format", NewDosFormatCommand()},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parser.Parse(tt.input)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			// Compare formatted output as a simple way to verify parsing
			if got.Format() != tt.expected.Format() {
				t.Errorf("got %q, want %q", got.Format(), tt.expected.Format())
			}
		})
	}
}

func TestCommandParsingErrors(t *testing.T) {
	parser := NewCommandParser()

	tests := []struct {
		name  string
		input string
	}{
		{"Invalid command", "invalidcmd"},
		{"Invalid address", "read invalid 16"},
		{"Missing args", "read"},
		{"Invalid step count", "step abc"},
		{"Invalid reset type", "reset invalid"},
		{"Invalid drive", "mount 99 /path"},
		{"Empty command", ""},
		// DOS command errors
		{"DOS no subcommand", "dos"},
		{"DOS invalid subcommand", "dos invalid"},
		{"DOS cd no drive", "dos cd"},
		{"DOS cd invalid drive", "dos cd 99"},
		{"DOS info no filename", "dos info"},
		{"DOS copy no args", "dos copy"},
		{"DOS copy one arg", "dos copy source"},
		{"DOS newdisk invalid type", "dos newdisk /path/disk.atr invalid"},
		// BASIC save/load errors
		{"Basic SAVE empty", "basic SAVE"},
		{"Basic LOAD empty", "basic LOAD"},
		// Asm input error
		{"Asm input no instruction", "asm input"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parser.Parse(tt.input)
			if err == nil {
				t.Error("expected error, got nil")
			}
		})
	}
}

// TestResponseParsing verifies response parsing works correctly.
func TestResponseParsing(t *testing.T) {
	parser := NewResponseParser()

	tests := []struct {
		name      string
		input     string
		isEvent   bool
		checkResp func(Response) bool
		checkEvt  func(Event) bool
	}{
		{"OK response", "OK:pong", false,
			func(r Response) bool { return r.IsOK() && r.Data == "pong" }, nil},
		{"Error response", "ERR:command failed", false,
			func(r Response) bool { return r.IsError() && r.Data == "command failed" }, nil},
		{"Breakpoint event", "EVENT:breakpoint $0600 A=$A9 X=$10 Y=$20 S=$FF P=$30", true,
			nil, func(e Event) bool { return e.Type == EventBreakpoint && e.Address == 0x0600 }},
		{"Stopped event", "EVENT:stopped $0600", true,
			nil, func(e Event) bool { return e.Type == EventStopped && e.Address == 0x0600 }},
		{"Error event", "EVENT:error something went wrong", true,
			nil, func(e Event) bool { return e.Type == EventError && e.Message == "something went wrong" }},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed, err := parser.Parse(tt.input)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if parsed.IsEvent != tt.isEvent {
				t.Errorf("IsEvent = %v, want %v", parsed.IsEvent, tt.isEvent)
			}
			if !tt.isEvent && tt.checkResp != nil {
				if !tt.checkResp(parsed.Response) {
					t.Errorf("response check failed: %+v", parsed.Response)
				}
			}
			if tt.isEvent && tt.checkEvt != nil {
				if !tt.checkEvt(parsed.Event) {
					t.Errorf("event check failed: %+v", parsed.Event)
				}
			}
		})
	}
}

func TestResponseParsingErrors(t *testing.T) {
	parser := NewResponseParser()

	tests := []struct {
		name  string
		input string
	}{
		{"No prefix", "invalid line"},
		{"Unknown event", "EVENT:unknown data"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parser.Parse(tt.input)
			if err == nil {
				t.Error("expected error, got nil")
			}
		})
	}
}

// TestEscapeSequences verifies escape sequence handling.
func TestEscapeSequences(t *testing.T) {
	// Test that InjectKeys properly escapes special characters including space
	cmd := NewInjectKeysCommand("line1\nline2\ttab\r space here")
	formatted := cmd.Format()
	expected := "inject keys line1\\nline2\\ttab\\r\\sspace\\shere"
	if formatted != expected {
		t.Errorf("got %q, want %q", formatted, expected)
	}
}

func TestParseEscapes(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello\\nworld", "hello\nworld"},
		{"tab\\there", "tab\there"},
		{"cr\\rhere", "cr\rhere"},
		{"space\\shere", "space here"},
		{"escape\\ehere", "escape\x1Bhere"},
		{"backslash\\\\here", "backslash\\here"},
		{"no escapes", "no escapes"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := parseEscapes(tt.input)
			if got != tt.expected {
				t.Errorf("got %q, want %q", got, tt.expected)
			}
		})
	}
}
