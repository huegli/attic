package atticprotocol

import (
	"errors"
	"fmt"
)

// Sentinel errors for the CLI protocol.
var (
	// ErrLineTooLong indicates a protocol line exceeded MaxLineLength.
	ErrLineTooLong = errors.New("line too long")

	// ErrTimeout indicates a command timed out waiting for a response.
	ErrTimeout = errors.New("command timed out")

	// ErrSocketNotFound indicates no server socket was found.
	ErrSocketNotFound = errors.New("no server socket found")

	// ErrNotConnected indicates an operation was attempted without a connection.
	ErrNotConnected = errors.New("not connected")

	// ErrAlreadyConnected indicates connect was called while already connected.
	ErrAlreadyConnected = errors.New("already connected")
)

// ParseError represents an error that occurred during command or response parsing.
type ParseError struct {
	Kind    ParseErrorKind
	Value   string // The invalid value that caused the error
	Message string // Additional context
}

// ParseErrorKind categorizes parsing errors.
type ParseErrorKind int

const (
	// ErrKindInvalidCommand indicates an unknown or malformed command.
	ErrKindInvalidCommand ParseErrorKind = iota
	// ErrKindInvalidAddress indicates an invalid memory address format.
	ErrKindInvalidAddress
	// ErrKindInvalidCount indicates an invalid count or size value.
	ErrKindInvalidCount
	// ErrKindInvalidByte indicates an invalid byte value.
	ErrKindInvalidByte
	// ErrKindInvalidStepCount indicates an invalid step count.
	ErrKindInvalidStepCount
	// ErrKindInvalidResetType indicates an invalid reset type (not cold/warm).
	ErrKindInvalidResetType
	// ErrKindInvalidRegister indicates an unknown register name.
	ErrKindInvalidRegister
	// ErrKindInvalidRegisterFormat indicates malformed register assignment.
	ErrKindInvalidRegisterFormat
	// ErrKindInvalidValue indicates an invalid numeric value.
	ErrKindInvalidValue
	// ErrKindInvalidDriveNumber indicates an invalid drive number.
	ErrKindInvalidDriveNumber
	// ErrKindMissingArgument indicates a required argument was not provided.
	ErrKindMissingArgument
	// ErrKindUnexpectedResponse indicates an unexpected response format.
	ErrKindUnexpectedResponse
)

// Error implements the error interface.
func (e *ParseError) Error() string {
	switch e.Kind {
	case ErrKindInvalidCommand:
		return fmt.Sprintf("invalid command '%s'", e.Value)
	case ErrKindInvalidAddress:
		return fmt.Sprintf("invalid address '%s'", e.Value)
	case ErrKindInvalidCount:
		return fmt.Sprintf("invalid count '%s'", e.Value)
	case ErrKindInvalidByte:
		return fmt.Sprintf("invalid byte value '%s'", e.Value)
	case ErrKindInvalidStepCount:
		return fmt.Sprintf("invalid step count '%s'", e.Value)
	case ErrKindInvalidResetType:
		return fmt.Sprintf("invalid reset type '%s'", e.Value)
	case ErrKindInvalidRegister:
		return fmt.Sprintf("invalid register '%s'", e.Value)
	case ErrKindInvalidRegisterFormat:
		return fmt.Sprintf("invalid register format '%s'", e.Value)
	case ErrKindInvalidValue:
		return fmt.Sprintf("invalid value '%s'", e.Value)
	case ErrKindInvalidDriveNumber:
		return fmt.Sprintf("invalid drive number '%s'", e.Value)
	case ErrKindMissingArgument:
		return e.Message
	case ErrKindUnexpectedResponse:
		return fmt.Sprintf("unexpected response: %s", e.Value)
	default:
		return fmt.Sprintf("parse error: %s", e.Value)
	}
}

// Helper functions to create specific parse errors.

func newInvalidCommandError(cmd string) error {
	return &ParseError{Kind: ErrKindInvalidCommand, Value: cmd}
}

func newInvalidAddressError(addr string) error {
	return &ParseError{Kind: ErrKindInvalidAddress, Value: addr}
}

func newInvalidCountError(count string) error {
	return &ParseError{Kind: ErrKindInvalidCount, Value: count}
}

func newInvalidByteError(b string) error {
	return &ParseError{Kind: ErrKindInvalidByte, Value: b}
}

func newInvalidStepCountError(count string) error {
	return &ParseError{Kind: ErrKindInvalidStepCount, Value: count}
}

func newInvalidResetTypeError(t string) error {
	return &ParseError{Kind: ErrKindInvalidResetType, Value: t}
}

func newInvalidRegisterError(reg string) error {
	return &ParseError{Kind: ErrKindInvalidRegister, Value: reg}
}

func newInvalidRegisterFormatError(fmt string) error {
	return &ParseError{Kind: ErrKindInvalidRegisterFormat, Value: fmt}
}

func newInvalidValueError(val string) error {
	return &ParseError{Kind: ErrKindInvalidValue, Value: val}
}

func newInvalidDriveNumberError(drive string) error {
	return &ParseError{Kind: ErrKindInvalidDriveNumber, Value: drive}
}

func newMissingArgumentError(msg string) error {
	return &ParseError{Kind: ErrKindMissingArgument, Message: msg}
}

func newUnexpectedResponseError(resp string) error {
	return &ParseError{Kind: ErrKindUnexpectedResponse, Value: resp}
}

// ConnectionError represents a connection-related error.
type ConnectionError struct {
	Message string
	Cause   error
}

// Error implements the error interface.
func (e *ConnectionError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("connection failed: %s: %v", e.Message, e.Cause)
	}
	return fmt.Sprintf("connection failed: %s", e.Message)
}

// Unwrap returns the underlying cause for errors.Is/As support.
func (e *ConnectionError) Unwrap() error {
	return e.Cause
}

// NewConnectionError creates a new connection error.
func NewConnectionError(message string, cause error) error {
	return &ConnectionError{Message: message, Cause: cause}
}
