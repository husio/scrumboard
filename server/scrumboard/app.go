package scrumboard

import (
	"net/http"
	"os"

	"github.com/husio/scrumboard/server/auth"
	"github.com/husio/scrumboard/server/pubsub"
	"github.com/husio/scrumboard/server/surf"
)

type ScrumBoardApp struct {
	html  surf.Renderer
	debug bool
	mux   http.Handler
	log   surf.Logger
	hub   pubsub.Hub
	auth  Authenticator
}

type Authenticator interface {
	CurrentAccount(*http.Request) (*auth.Account, error)
}

func NewApp(
	html surf.Renderer,
	auth Authenticator,
	hub pubsub.Hub,
	debug bool,
) *ScrumBoardApp {
	app := ScrumBoardApp{
		html:  html,
		log:   surf.NewLogger(os.Stdout, "app", "scrumboard"),
		auth:  auth,
		hub:   hub,
		debug: debug,
	}

	rt := surf.NewRouter()
	rt.Get(`/`, app.index)
	rt.Get(`/b/<board-id>`, app.board)
	rt.Get(`/ws/<board-id>`, app.handleClient)
	app.mux = rt

	return &app
}

func (app *ScrumBoardApp) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	app.mux.ServeHTTP(w, r)
}
