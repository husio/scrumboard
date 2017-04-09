package surf

import (
	"context"
	"fmt"
	"io"
	"runtime/debug"
	"time"
)

type Logger interface {
	Info(context.Context, string, ...string)
	Error(context.Context, string, ...string)
}

func NewLogger(out io.Writer, keyvals ...string) Logger {
	if len(keyvals)%2 == 1 {
		keyvals = append(keyvals, "")
	}
	return &logger{
		out:     out,
		keyvals: keyvals,
	}
}

type logger struct {
	out     io.Writer
	keyvals []string
}

func (lg *logger) log(ctx context.Context, keyvalues ...string) {
	if len(keyvalues)%2 == 1 {
		keyvalues = append(keyvalues, "")
	}

	/*
		if rid := requestID(ctx); rid != "" {
			keyvalues = append(keyvalues, "requestId", rid)
		}
	*/

	keyvalues = append(keyvalues, lg.keyvals...)

	// can be done better
	fmt.Fprintf(lg.out, "surf: %q\n", keyvalues)
}

func (lg *logger) Info(ctx context.Context, message string, keyvalues ...string) {
	pairs := append([]string{
		"message", message,
		"level", "info",
		"time", time.Now().Format(time.RFC3339Nano),
	}, keyvalues...)
	lg.log(ctx, pairs...)
}

func (lg *logger) Error(ctx context.Context, message string, keyvalues ...string) {
	// TODO: include stack and source location
	pairs := append([]string{
		"message", message,
		"level", "error",
		"stack", string(debug.Stack()),
		"time", time.Now().Format(time.RFC3339Nano),
	}, keyvalues...)
	lg.log(ctx, pairs...)
}
