package atticprotocol

import (
	"regexp"
	"strconv"
	"strings"
)

// CommandParser parses CLI protocol commands from text lines.
type CommandParser struct{}

// NewCommandParser creates a new command parser.
func NewCommandParser() *CommandParser {
	return &CommandParser{}
}

// Parse parses a command line into a Command.
// The line may optionally include the CMD: prefix.
func (p *CommandParser) Parse(line string) (Command, error) {
	// Strip CMD: prefix if present
	commandLine := strings.TrimSpace(line)
	if strings.HasPrefix(commandLine, CommandPrefix) {
		commandLine = commandLine[len(CommandPrefix):]
	}

	// Check line length
	if len(commandLine) > MaxLineLength {
		return Command{}, ErrLineTooLong
	}

	// Split into command and arguments
	parts := strings.SplitN(commandLine, " ", 2)
	if len(parts) == 0 || parts[0] == "" {
		return Command{}, newInvalidCommandError("")
	}

	command := strings.ToLower(parts[0])
	argsString := ""
	if len(parts) > 1 {
		argsString = parts[1]
	}

	// Parse based on command word
	switch command {
	// Connection commands
	case "ping":
		return NewPingCommand(), nil
	case "version":
		return NewVersionCommand(), nil
	case "quit":
		return NewQuitCommand(), nil
	case "shutdown":
		return NewShutdownCommand(), nil

	// Emulator control
	case "pause":
		return NewPauseCommand(), nil
	case "resume":
		return NewResumeCommand(), nil
	case "step":
		return p.parseStep(argsString)
	case "reset":
		return p.parseReset(argsString)
	case "status":
		return NewStatusCommand(), nil

	// Memory operations
	case "read":
		return p.parseRead(argsString)
	case "write":
		return p.parseWrite(argsString)
	case "registers":
		return p.parseRegisters(argsString)

	// Breakpoints
	case "breakpoint":
		return p.parseBreakpoint(argsString)

	// Disassembly
	case "disasm", "disassemble", "d":
		return p.parseDisassemble(argsString)

	// Assembly
	case "asm", "assemble", "a":
		return p.parseAssemble(argsString)

	// Monitor commands
	case "stepover", "so":
		return NewStepOverCommand(), nil
	case "until", "rununtil":
		return p.parseRunUntil(argsString)
	case "fill":
		return p.parseFill(argsString)

	// Disk operations
	case "mount":
		return p.parseMount(argsString)
	case "unmount":
		return p.parseUnmount(argsString)
	case "drives":
		return NewDrivesCommand(), nil

	// Boot with file
	case "boot":
		return p.parseBoot(argsString)

	// State management
	case "state":
		return p.parseState(argsString)

	// Display
	case "screenshot":
		path := strings.TrimSpace(argsString)
		return NewScreenshotCommand(path), nil

	// Injection
	case "inject":
		return p.parseInject(argsString)

	// BASIC commands
	case "basic":
		return p.parseBasic(argsString)

	default:
		return Command{}, newInvalidCommandError(command)
	}
}

func (p *CommandParser) parseStep(args string) (Command, error) {
	args = strings.TrimSpace(args)
	if args == "" {
		return NewStepCommand(1), nil
	}
	count, err := strconv.Atoi(args)
	if err != nil || count <= 0 {
		return Command{}, newInvalidStepCountError(args)
	}
	return NewStepCommand(count), nil
}

func (p *CommandParser) parseReset(args string) (Command, error) {
	switch strings.ToLower(strings.TrimSpace(args)) {
	case "cold", "":
		return NewResetCommand(true), nil
	case "warm":
		return NewResetCommand(false), nil
	default:
		return Command{}, newInvalidResetTypeError(args)
	}
}

func (p *CommandParser) parseRead(args string) (Command, error) {
	parts := strings.Fields(args)
	if len(parts) != 2 {
		return Command{}, newMissingArgumentError("read requires address and count")
	}

	address, ok := parseAddress(parts[0])
	if !ok {
		return Command{}, newInvalidAddressError(parts[0])
	}

	count, err := strconv.ParseUint(parts[1], 10, 16)
	if err != nil {
		return Command{}, newInvalidCountError(parts[1])
	}

	return NewReadCommand(address, uint16(count)), nil
}

func (p *CommandParser) parseWrite(args string) (Command, error) {
	parts := strings.SplitN(args, " ", 2)
	if len(parts) != 2 {
		return Command{}, newMissingArgumentError("write requires address and data")
	}

	address, ok := parseAddress(strings.TrimSpace(parts[0]))
	if !ok {
		return Command{}, newInvalidAddressError(parts[0])
	}

	dataStr := strings.TrimSpace(parts[1])
	var bytes []byte

	for _, byteStr := range strings.Split(dataStr, ",") {
		trimmed := strings.TrimSpace(byteStr)
		b, ok := parseHexByte(trimmed)
		if !ok {
			return Command{}, newInvalidByteError(trimmed)
		}
		bytes = append(bytes, b)
	}

	if len(bytes) == 0 {
		return Command{}, newMissingArgumentError("write requires at least one byte")
	}

	return NewWriteCommand(address, bytes), nil
}

func (p *CommandParser) parseRegisters(args string) (Command, error) {
	args = strings.TrimSpace(args)
	if args == "" {
		return NewRegistersCommand(nil), nil
	}

	var modifications []RegisterModification
	validRegs := map[string]bool{"A": true, "X": true, "Y": true, "S": true, "P": true, "PC": true}

	for _, part := range strings.Fields(args) {
		components := strings.SplitN(part, "=", 2)
		if len(components) != 2 {
			return Command{}, newInvalidRegisterFormatError(part)
		}

		regName := strings.ToUpper(components[0])
		if !validRegs[regName] {
			return Command{}, newInvalidRegisterError(regName)
		}

		value, ok := parseAddress(components[1])
		if !ok {
			return Command{}, newInvalidValueError(components[1])
		}

		modifications = append(modifications, RegisterModification{Name: regName, Value: value})
	}

	return NewRegistersCommand(modifications), nil
}

func (p *CommandParser) parseBreakpoint(args string) (Command, error) {
	parts := strings.SplitN(strings.TrimSpace(args), " ", 2)
	if len(parts) == 0 || parts[0] == "" {
		return Command{}, newMissingArgumentError("breakpoint requires subcommand (set, clear, clearall, list)")
	}

	subcommand := strings.ToLower(parts[0])
	switch subcommand {
	case "set":
		if len(parts) < 2 {
			return Command{}, newMissingArgumentError("breakpoint set requires address")
		}
		address, ok := parseAddress(strings.TrimSpace(parts[1]))
		if !ok {
			return Command{}, newInvalidAddressError(parts[1])
		}
		return NewBreakpointSetCommand(address), nil

	case "clear":
		if len(parts) < 2 {
			return Command{}, newMissingArgumentError("breakpoint clear requires address")
		}
		address, ok := parseAddress(strings.TrimSpace(parts[1]))
		if !ok {
			return Command{}, newInvalidAddressError(parts[1])
		}
		return NewBreakpointClearCommand(address), nil

	case "clearall":
		return NewBreakpointClearAllCommand(), nil

	case "list":
		return NewBreakpointListCommand(), nil

	default:
		return Command{}, newInvalidCommandError("breakpoint " + subcommand)
	}
}

func (p *CommandParser) parseDisassemble(args string) (Command, error) {
	args = strings.TrimSpace(args)
	if args == "" {
		return NewDisassembleCommand(nil, nil), nil
	}

	parts := strings.Fields(args)

	var address *uint16
	var lines *int

	if len(parts) >= 1 {
		addr, ok := parseAddress(parts[0])
		if !ok {
			return Command{}, newInvalidAddressError(parts[0])
		}
		address = &addr
	}

	if len(parts) >= 2 {
		count, err := strconv.Atoi(parts[1])
		if err != nil || count <= 0 {
			return Command{}, newInvalidCountError(parts[1])
		}
		lines = &count
	}

	return NewDisassembleCommand(address, lines), nil
}

func (p *CommandParser) parseAssemble(args string) (Command, error) {
	parts := strings.SplitN(strings.TrimSpace(args), " ", 2)
	if len(parts) == 0 || parts[0] == "" {
		return Command{}, newMissingArgumentError("assemble requires address")
	}

	address, ok := parseAddress(parts[0])
	if !ok {
		return Command{}, newInvalidAddressError(parts[0])
	}

	// If there's an instruction on the same line, it's a single-line assembly
	if len(parts) > 1 {
		instruction := strings.TrimSpace(parts[1])
		return NewAssembleLineCommand(address, instruction), nil
	}

	// Otherwise, start interactive assembly mode
	return NewAssembleCommand(address), nil
}

func (p *CommandParser) parseRunUntil(args string) (Command, error) {
	args = strings.TrimSpace(args)
	if args == "" {
		return Command{}, newMissingArgumentError("until requires address")
	}

	address, ok := parseAddress(args)
	if !ok {
		return Command{}, newInvalidAddressError(args)
	}

	return NewRunUntilCommand(address), nil
}

func (p *CommandParser) parseFill(args string) (Command, error) {
	parts := strings.Fields(args)
	if len(parts) < 3 {
		return Command{}, newMissingArgumentError("fill requires start, end, and value")
	}

	start, ok := parseAddress(parts[0])
	if !ok {
		return Command{}, newInvalidAddressError(parts[0])
	}

	end, ok := parseAddress(parts[1])
	if !ok {
		return Command{}, newInvalidAddressError(parts[1])
	}

	value, ok := parseHexByte(parts[2])
	if !ok {
		return Command{}, newInvalidByteError(parts[2])
	}

	return NewMemoryFillCommand(start, end, value), nil
}

func (p *CommandParser) parseMount(args string) (Command, error) {
	parts := strings.SplitN(strings.TrimSpace(args), " ", 2)
	if len(parts) != 2 {
		return Command{}, newMissingArgumentError("mount requires drive number and path")
	}

	drive, err := strconv.Atoi(parts[0])
	if err != nil || drive < 1 || drive > 8 {
		return Command{}, newInvalidDriveNumberError(parts[0])
	}

	return NewMountCommand(drive, parts[1]), nil
}

func (p *CommandParser) parseUnmount(args string) (Command, error) {
	args = strings.TrimSpace(args)
	drive, err := strconv.Atoi(args)
	if err != nil || drive < 1 || drive > 8 {
		return Command{}, newInvalidDriveNumberError(args)
	}
	return NewUnmountCommand(drive), nil
}

func (p *CommandParser) parseBoot(args string) (Command, error) {
	path := strings.TrimSpace(args)
	if path == "" {
		return Command{}, newMissingArgumentError("boot requires a file path")
	}
	// Note: Tilde expansion should be done by the caller if needed
	return NewBootCommand(path), nil
}

func (p *CommandParser) parseState(args string) (Command, error) {
	parts := strings.SplitN(strings.TrimSpace(args), " ", 2)
	if len(parts) == 0 || parts[0] == "" {
		return Command{}, newMissingArgumentError("state requires subcommand (save or load)")
	}

	if len(parts) < 2 {
		return Command{}, newMissingArgumentError("state " + parts[0] + " requires path")
	}

	path := strings.TrimSpace(parts[1])
	switch strings.ToLower(parts[0]) {
	case "save":
		return NewStateSaveCommand(path), nil
	case "load":
		return NewStateLoadCommand(path), nil
	default:
		return Command{}, newInvalidCommandError("state " + parts[0])
	}
}

func (p *CommandParser) parseInject(args string) (Command, error) {
	parts := strings.SplitN(strings.TrimSpace(args), " ", 2)
	if len(parts) == 0 || parts[0] == "" {
		return Command{}, newMissingArgumentError("inject requires subcommand (basic or keys)")
	}

	if len(parts) < 2 {
		return Command{}, newMissingArgumentError("inject " + parts[0] + " requires data")
	}

	data := parts[1]
	switch strings.ToLower(parts[0]) {
	case "basic":
		return NewInjectBasicCommand(data), nil
	case "keys":
		return NewInjectKeysCommand(parseEscapes(data)), nil
	default:
		return Command{}, newInvalidCommandError("inject " + parts[0])
	}
}

func (p *CommandParser) parseBasic(args string) (Command, error) {
	trimmed := strings.TrimSpace(args)

	if trimmed == "" {
		return Command{}, newMissingArgumentError("basic requires a line or command")
	}

	// Split into first word and remaining argument text
	parts := strings.SplitN(trimmed, " ", 2)
	firstWord := strings.ToUpper(parts[0])
	rest := ""
	if len(parts) > 1 {
		rest = strings.TrimSpace(parts[1])
	}

	switch firstWord {
	case "NEW":
		return NewBasicNewCommand(), nil
	case "RUN":
		return NewBasicRunCommand(), nil
	case "LIST":
		return NewBasicListCommand(), nil
	case "DEL":
		if rest == "" {
			return Command{}, newMissingArgumentError("basic del requires a line number or range (e.g., 10 or 10-50)")
		}
		return NewBasicDeleteCommand(rest), nil
	case "STOP":
		return NewBasicStopCommand(), nil
	case "CONT":
		return NewBasicContCommand(), nil
	case "VARS":
		return NewBasicVarsCommand(), nil
	case "VAR":
		if rest == "" {
			return Command{}, newMissingArgumentError("basic var requires a variable name")
		}
		return NewBasicVarCommand(rest), nil
	case "INFO":
		return NewBasicInfoCommand(), nil
	case "EXPORT":
		if rest == "" {
			return Command{}, newMissingArgumentError("basic export requires a file path")
		}
		// Note: Tilde expansion should be done by the caller if needed
		return NewBasicExportCommand(rest), nil
	case "IMPORT":
		if rest == "" {
			return Command{}, newMissingArgumentError("basic import requires a file path")
		}
		// Note: Tilde expansion should be done by the caller if needed
		return NewBasicImportCommand(rest), nil
	case "DIR":
		if rest == "" {
			return NewBasicDirCommand(nil), nil
		}
		drive, err := strconv.Atoi(rest)
		if err != nil || drive < 1 || drive > 8 {
			return Command{}, newInvalidDriveNumberError(rest)
		}
		return NewBasicDirCommand(&drive), nil
	default:
		// Anything else is a numbered BASIC line (e.g., "10 PRINT X")
		return NewBasicLineCommand(trimmed), nil
	}
}

// Helper functions

// parseAddress parses an address in $XXXX, 0xXXXX, or decimal format.
func parseAddress(s string) (uint16, bool) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "$") {
		val, err := strconv.ParseUint(s[1:], 16, 16)
		if err != nil {
			return 0, false
		}
		return uint16(val), true
	} else if strings.HasPrefix(strings.ToLower(s), "0x") {
		val, err := strconv.ParseUint(s[2:], 16, 16)
		if err != nil {
			return 0, false
		}
		return uint16(val), true
	} else {
		val, err := strconv.ParseUint(s, 10, 16)
		if err != nil {
			return 0, false
		}
		return uint16(val), true
	}
}

// parseHexByte parses a hex byte value (with or without $ prefix).
func parseHexByte(s string) (byte, bool) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "$") {
		s = s[1:]
	}
	val, err := strconv.ParseUint(s, 16, 8)
	if err != nil {
		return 0, false
	}
	return byte(val), true
}

// parseEscapes processes escape sequences in a string.
func parseEscapes(s string) string {
	var result strings.Builder
	runes := []rune(s)
	for i := 0; i < len(runes); i++ {
		if runes[i] == '\\' && i+1 < len(runes) {
			i++
			switch runes[i] {
			case 'n':
				result.WriteRune('\n')
			case 't':
				result.WriteRune('\t')
			case 'r':
				result.WriteRune('\r')
			case 's':
				result.WriteRune(' ') // Space
			case 'e':
				result.WriteRune('\x1B') // Escape character
			case '\\':
				result.WriteRune('\\')
			default:
				result.WriteRune(runes[i])
			}
		} else {
			result.WriteRune(runes[i])
		}
	}
	return result.String()
}

// ResponseParser parses responses and events from the CLI protocol.
type ResponseParser struct {
	addressRegex *regexp.Regexp
}

// NewResponseParser creates a new response parser.
func NewResponseParser() *ResponseParser {
	return &ResponseParser{
		addressRegex: regexp.MustCompile(`\$([0-9A-Fa-f]{4})`),
	}
}

// ParsedMessage represents either a Response or an Event from the server.
type ParsedMessage struct {
	IsEvent  bool
	Response Response
	Event    Event
}

// Parse parses a response or event line from the server.
func (p *ResponseParser) Parse(line string) (ParsedMessage, error) {
	trimmed := strings.TrimSpace(line)

	if strings.HasPrefix(trimmed, OKPrefix) {
		data := trimmed[len(OKPrefix):]
		return ParsedMessage{
			IsEvent:  false,
			Response: NewOKResponse(data),
		}, nil
	} else if strings.HasPrefix(trimmed, ErrorPrefix) {
		message := trimmed[len(ErrorPrefix):]
		return ParsedMessage{
			IsEvent:  false,
			Response: NewErrorResponse(message),
		}, nil
	} else if strings.HasPrefix(trimmed, EventPrefix) {
		eventData := trimmed[len(EventPrefix):]
		event, err := p.parseEvent(eventData)
		if err != nil {
			return ParsedMessage{}, err
		}
		return ParsedMessage{
			IsEvent: true,
			Event:   event,
		}, nil
	}

	return ParsedMessage{}, newUnexpectedResponseError(trimmed)
}

func (p *ResponseParser) parseEvent(data string) (Event, error) {
	parts := strings.SplitN(data, " ", 2)
	if len(parts) == 0 {
		return Event{}, newUnexpectedResponseError("empty event")
	}

	eventType := strings.ToLower(parts[0])
	switch eventType {
	case "breakpoint":
		// Format: breakpoint $XXXX A=$XX X=$XX Y=$XX S=$XX P=$XX
		match := p.addressRegex.FindStringSubmatch(data)
		var address uint16
		if len(match) >= 2 {
			if val, err := strconv.ParseUint(match[1], 16, 16); err == nil {
				address = uint16(val)
			}
		}
		// TODO: Parse register values from the event data
		return NewBreakpointEvent(address, 0, 0, 0, 0, 0), nil

	case "stopped":
		match := p.addressRegex.FindStringSubmatch(data)
		var address uint16
		if len(match) >= 2 {
			if val, err := strconv.ParseUint(match[1], 16, 16); err == nil {
				address = uint16(val)
			}
		}
		return NewStoppedEvent(address), nil

	case "error":
		message := "Unknown error"
		if len(parts) > 1 {
			message = parts[1]
		}
		return NewErrorEvent(message), nil

	default:
		return Event{}, newUnexpectedResponseError("unknown event type '" + eventType + "'")
	}
}
