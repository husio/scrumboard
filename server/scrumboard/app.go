package scrumboard

import (
	"net/http"
	"os"

	"github.com/husio/scrumboard/server/auth"
	"github.com/husio/scrumboard/server/surf"
)

type ScrumBoardApp struct {
	ps    pubSub
	html  surf.Renderer
	debug bool
	mux   http.Handler
	log   surf.Logger
	auth  Authenticator
}

type Authenticator interface {
	CurrentAccount(*http.Request) (*auth.Account, error)
}

func NewApp(
	html surf.Renderer,
	auth Authenticator,
	debug bool,
) *ScrumBoardApp {
	app := ScrumBoardApp{
		html:  html,
		log:   surf.NewLogger(os.Stdout, "app", "scrumboard"),
		auth:  auth,
		debug: debug,
		ps: pubSub{
			// initial state -_-
			state: `{"rows": 3, "cards": []}`,
			subs:  make(map[chan<- string]struct{}),
		},
	}

	rt := surf.NewRouter()
	rt.Get(`/`, app.board)
	rt.Get(`/ws`, app.ps.handleClient)
	app.mux = rt

	return &app
}

func (app *ScrumBoardApp) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	app.mux.ServeHTTP(w, r)
}
