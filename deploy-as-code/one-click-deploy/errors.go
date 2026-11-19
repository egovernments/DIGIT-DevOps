package main

import (
	"errors"
	"fmt"
	"strings"
)

// Process exit codes.
const (
	exitOK          = 0
	exitFailure     = 1
	exitUsage       = 2
	exitInterrupted = 130
)

// errAborted is returned when the operator answers "no" to a prompt.
var errAborted = errors.New("aborted by user")

// errNotYet marks a condition that may still resolve on its own, such as an
// ApplicationSet the bootstrap app has not created yet. Pollers keep waiting
// on it; everything else treats it as a normal error.
var errNotYet = errors.New("not ready yet")

// StepError records which step failed and what to check next. main prints the
// hint after the error, so every failure ends with an actionable line.
type StepError struct {
	Step string
	Hint string
	Err  error
}

func (e *StepError) Error() string { return e.Step + ": " + e.Err.Error() }
func (e *StepError) Unwrap() error { return e.Err }

func stepErr(step, hint string, err error) error {
	return &StepError{Step: step, Hint: hint, Err: err}
}

// CmdError is returned when an external command fails. It keeps the tail of
// the command's stderr, so the cause is visible without rerunning by hand.
// stdout is deliberately never included: for `sops -d` and
// `kubectl create secret --dry-run` it holds secret material.
type CmdError struct {
	Args   []string
	Stderr string
	Err    error
}

func (e *CmdError) Error() string {
	msg := fmt.Sprintf("`%s` failed: %v", strings.Join(e.Args, " "), e.Err)
	if tail := lastLines(strings.TrimSpace(e.Stderr), 15); tail != "" {
		msg += "\n" + indent(tail, "    ")
	}
	return msg
}

func (e *CmdError) Unwrap() error { return e.Err }

// isNotFound reports whether err is a kubectl "(NotFound)" error.
func isNotFound(err error) bool {
	var ce *CmdError
	return errors.As(err, &ce) && strings.Contains(ce.Stderr, "(NotFound)")
}

func lastLines(s string, n int) string {
	lines := strings.Split(s, "\n")
	if len(lines) > n {
		lines = append([]string{"..."}, lines[len(lines)-n:]...)
	}
	return strings.Join(lines, "\n")
}
