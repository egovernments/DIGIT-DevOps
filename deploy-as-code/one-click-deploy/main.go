// Command one-click-deploy brings up a DIGIT environment managed by Argo CD
// and then exposes the platform services through Kong. See README.md.
package main

import (
	"context"
	"errors"
	"flag"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

// run is main without os.Exit, so deferred cleanup (temporary kubeconfig,
// port-forward) always happens before the process ends.
func run(args []string) int {
	log := newLogger()

	cfg, err := parseArgs(args, os.Getenv, os.Stderr)
	if errors.Is(err, flag.ErrHelp) {
		return exitOK
	}
	if err != nil {
		log.Errorf("%v", err)
		return exitUsage
	}

	// The first Ctrl+C cancels ctx: running commands are interrupted and
	// cleanup runs. stop() restores default handling, so a second Ctrl+C
	// during cleanup kills the process.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	w := newWorkflow(cfg, log)
	err = w.Run(ctx)
	// Read before stop(): stop cancels ctx as well.
	interrupted := ctx.Err() != nil
	stop()
	w.Close()

	switch {
	case err == nil:
		log.Successf("Done.")
		return exitOK
	case interrupted:
		log.Errorf("Interrupted. Every step is safe to rerun.")
		return exitInterrupted
	case errors.Is(err, errAborted):
		log.Warnf("%v. Nothing after this point was changed.", err)
		return exitFailure
	default:
		report(log, err)
		return exitFailure
	}
}

func report(log *Logger, err error) {
	log.Errorf("%v", err)
	var se *StepError
	if errors.As(err, &se) && se.Hint != "" {
		log.Errorf("Next: %s", se.Hint)
	}
}
