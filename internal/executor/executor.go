package executor

import (
	"context"
	"io"
	"net/http"
	"sync"

	"github.com/user/cli-proxy/internal/types"
)

type accountRecorder struct {
	mu      sync.Mutex
	account string
}

type ctxAccountKey struct{}

// WithAccountRecorder returns a derived context that captures which upstream
// account an executor selects while handling the request, plus a getter to read
// the recorded account afterwards (for request logging). Returns "" if the
// executor never recorded one.
func WithAccountRecorder(ctx context.Context) (context.Context, func() string) {
	r := &accountRecorder{}
	ctx = context.WithValue(ctx, ctxAccountKey{}, r)
	return ctx, func() string {
		r.mu.Lock()
		defer r.mu.Unlock()
		return r.account
	}
}

// recordAccount notes the upstream account used for this request. No-op when the
// context carries no recorder.
func recordAccount(ctx context.Context, account string) {
	if r, ok := ctx.Value(ctxAccountKey{}).(*accountRecorder); ok {
		r.mu.Lock()
		r.account = account
		r.mu.Unlock()
	}
}

type Executor interface {
	Execute(ctx context.Context, req *types.ChatCompletionRequest) (*types.ChatCompletionResponse, error)
	ExecuteStream(ctx context.Context, req *types.ChatCompletionRequest, w io.Writer) (*types.Usage, error)
	Models() []string
}

type ResponsesExecutor interface {
	OpenResponsesStream(ctx context.Context, body []byte) (io.ReadCloser, error)
}

type AnthropicExecutor interface {
	ExecuteAnthropicRaw(ctx context.Context, body []byte, clientHeaders http.Header) ([]byte, int, error)
	OpenAnthropicStream(ctx context.Context, body []byte, clientHeaders http.Header) (io.ReadCloser, int, error)
}
