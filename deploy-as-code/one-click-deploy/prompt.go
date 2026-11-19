package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
)

// Prompter asks the operator before every step that changes the cluster.
// With assumeYes every question is answered yes without reading stdin.
type Prompter struct {
	in        *bufio.Reader
	out       io.Writer
	assumeYes bool
}

func newPrompter(in io.Reader, out io.Writer, assumeYes bool) *Prompter {
	return &Prompter{in: bufio.NewReader(in), out: out, assumeYes: assumeYes}
}

// Confirm returns nil on "y"/"yes" and errAborted on anything else.
func (p *Prompter) Confirm(ctx context.Context, question string) error {
	if p.assumeYes {
		return nil
	}
	answer, err := p.readLine(ctx, question+" [y/N]: ")
	if err != nil {
		return err
	}
	if strings.EqualFold(answer, "y") || strings.EqualFold(answer, "yes") {
		return nil
	}
	return errAborted
}

// readLine reads one answer, returning early if ctx is cancelled (Ctrl+C at
// a prompt). The reading goroutine is left blocked on stdin in that case,
// which is harmless because the process is about to exit.
func (p *Prompter) readLine(ctx context.Context, prompt string) (string, error) {
	fmt.Fprint(p.out, prompt)
	type result struct {
		line string
		err  error
	}
	ch := make(chan result, 1)
	go func() {
		line, err := p.in.ReadString('\n')
		ch <- result{line, err}
	}()
	select {
	case <-ctx.Done():
		fmt.Fprintln(p.out)
		return "", ctx.Err()
	case r := <-ch:
		if r.err != nil && !(errors.Is(r.err, io.EOF) && r.line != "") {
			return "", fmt.Errorf("reading answer from stdin: %w (set options.assumeYes: true for unattended runs)", r.err)
		}
		return strings.TrimSpace(r.line), nil
	}
}
