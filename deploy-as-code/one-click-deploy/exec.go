package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Runner starts external commands (kubectl, git, sops, go) with a fixed set of
// environment overrides. After the kube context is pinned, KUBECONFIG is one
// of them, so every child -- including the Go deployer and the helm it runs --
// talks to the same cluster.
type Runner struct {
	env map[string]string
}

func newRunner() *Runner { return &Runner{env: map[string]string{}} }

// Setenv adds an override for every command started after this call.
func (r *Runner) Setenv(key, value string) { r.env[key] = value }

func (r *Runner) environ() []string {
	env := make([]string, 0, len(os.Environ())+len(r.env))
	for _, kv := range os.Environ() {
		key, _, _ := strings.Cut(kv, "=")
		if _, overridden := r.env[key]; !overridden {
			env = append(env, kv)
		}
	}
	for k, v := range r.env {
		env = append(env, k+"="+v)
	}
	return env
}

func (r *Runner) command(ctx context.Context, dir, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = r.environ()
	// On cancellation ask the child to stop cleanly first (kubectl and the
	// deployer both handle SIGINT); WaitDelay escalates to SIGKILL.
	cmd.Cancel = func() error { return cmd.Process.Signal(os.Interrupt) }
	cmd.WaitDelay = 10 * time.Second
	return cmd
}

// Output runs a command and returns its stdout.
func (r *Runner) Output(ctx context.Context, name string, args ...string) ([]byte, error) {
	return r.Input(ctx, nil, name, args...)
}

// OutputIn is Output with a working directory.
func (r *Runner) OutputIn(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	return r.capture(ctx, dir, nil, name, args...)
}

// Input runs a command with stdin and returns its stdout.
func (r *Runner) Input(ctx context.Context, stdin []byte, name string, args ...string) ([]byte, error) {
	return r.capture(ctx, "", stdin, name, args...)
}

func (r *Runner) capture(ctx context.Context, dir string, stdin []byte, name string, args ...string) ([]byte, error) {
	cmd := r.command(ctx, dir, name, args...)
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, &CmdError{Args: cmd.Args, Stderr: stderr.String(), Err: err}
	}
	return stdout.Bytes(), nil
}

// Stream runs a command attached to the terminal, for long steps whose
// progress the operator should watch.
func (r *Runner) Stream(ctx context.Context, dir, name string, args ...string) error {
	cmd := r.command(ctx, dir, name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return &CmdError{Args: cmd.Args, Err: err}
	}
	return nil
}

func splitLines(b []byte) []string {
	var out []string
	for _, line := range strings.Split(string(b), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			out = append(out, line)
		}
	}
	return out
}
