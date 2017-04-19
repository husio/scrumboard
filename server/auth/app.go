package auth

import (
	"net/http"
	"os"

	"github.com/husio/scrumboard/server/cache"
	"github.com/husio/scrumboard/server/surf"
)

type AuthApp struct {
	cache     cache.Cache
	html      surf.Renderer
	mux       http.Handler
	log       surf.Logger
	debug     bool
	providers map[string]Provider
}

func NewApp(
	cache cache.Cache,
	html surf.Renderer,
	providers []Provider,
	debug bool,
) *AuthApp {
	rt := surf.NewRouter()

	providersmap := make(map[string]Provider)
	for _, p := range providers {
		providersmap[p.Codename] = p
	}

	app := &AuthApp{
		cache:     cache,
		html:      html,
		mux:       rt,
		log:       surf.NewLogger(os.Stdout, "app", "auth"),
		debug:     debug,
		providers: providersmap,
	}

	rt.Get(`/login`, app.login)
	rt.Get(`/login/<method>`, app.loginOAuth2)
	rt.Get(`/login/<method>/success`, app.loginOAuth2Callback)
	rt.Get(`/logout`, app.logout)

	return app
}

func (app *AuthApp) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	app.mux.ServeHTTP(w, r)
}
