package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

const (
	cRed     = "\033[0;31m"
	cGreen   = "\033[0;32m"
	cYellow  = "\033[1;33m"
	cBlue    = "\033[0;34m"
	cCyan    = "\033[0;36m"
	cMagenta = "\033[0;35m"
	cBold    = "\033[1m"
	cReset   = "\033[0m"
)

// Logger writes progress to out and errors to errOut. Colour is used only on
// a terminal, and never when NO_COLOR is set.
type Logger struct {
	out    io.Writer
	errOut io.Writer
	color  bool
}

func newLogger() *Logger {
	return &Logger{
		out:    os.Stdout,
		errOut: os.Stderr,
		color:  isTerminal(os.Stdout) && os.Getenv("NO_COLOR") == "",
	}
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}

func (l *Logger) paint(color, s string) string {
	if !l.color {
		return s
	}
	return color + s + cReset
}

// Bold highlights a value inside a log line.
func (l *Logger) Bold(s string) string { return l.paint(cBold, s) }

func (l *Logger) Infof(format string, a ...any) {
	fmt.Fprintf(l.out, "%s %s\n", l.paint(cCyan, "[INFO]"), fmt.Sprintf(format, a...))
}

func (l *Logger) Successf(format string, a ...any) {
	fmt.Fprintf(l.out, "%s %s\n", l.paint(cGreen, "[SUCCESS]"), fmt.Sprintf(format, a...))
}

func (l *Logger) Warnf(format string, a ...any) {
	fmt.Fprintf(l.out, "%s %s\n", l.paint(cYellow, "[WARN]"), fmt.Sprintf(format, a...))
}

func (l *Logger) Errorf(format string, a ...any) {
	fmt.Fprintf(l.errOut, "%s %s\n", l.paint(cRed, "[ERROR]"), fmt.Sprintf(format, a...))
}

func (l *Logger) Step(title string) {
	fmt.Fprintf(l.out, "\n%s\n", l.paint(cBold+cBlue, "==> "+title))
}

func (l *Logger) Banner(title string) {
	line := strings.Repeat("=", 66)
	fmt.Fprintf(l.out, "\n%s\n", l.paint(cBold+cMagenta, line+"\n  "+title+"\n"+line))
}

// Cmd shows a command before it is run, so the operator can see exactly what
// a confirmation prompt is about.
func (l *Logger) Cmd(cmdline string) {
	fmt.Fprintf(l.out, "  %s\n\n", l.paint(cBold+cCyan, "$ "+cmdline))
}

// Block prints multi-line output (kubectl tables, etc.) indented.
func (l *Logger) Block(text string) {
	text = strings.TrimRight(text, "\n")
	if text == "" {
		return
	}
	fmt.Fprintln(l.out, indent(text, "    "))
}

func indent(s, prefix string) string {
	return prefix + strings.ReplaceAll(s, "\n", "\n"+prefix)
}
