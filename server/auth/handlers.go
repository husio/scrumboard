package auth

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/husio/scrumboard/server/cache"
	"github.com/husio/scrumboard/server/surf"

	"golang.org/x/oauth2"
)

func (app *AuthApp) logout(w http.ResponseWriter, r *http.Request) {
	// write delete cookie
	http.SetCookie(w, &http.Cookie{
		Name:    sessionCookieName,
		Value:   "",
		Path:    "/",
		MaxAge:  -1,
		Expires: time.Time{},
	})

	app.log.Info(r.Context(), "logging out")
	http.Redirect(w, r, "/", http.StatusTemporaryRedirect)
}

const sessionCookieName = "sid"

func (app *AuthApp) login(w http.ResponseWriter, r *http.Request) {
	first := func() *Provider {
		for _, p := range app.providers {
			return &p
		}
		return nil
	}

	// only one provider is supported for now
	p := first()
	if p == nil {
		app.log.Error(r.Context(), "no auth provider configured")
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}
	content := struct {
		Debug bool
	}{
		Debug: app.debug,
	}
	app.html.Render(w, http.StatusOK, "login.tmpl", content)
}

func (app *AuthApp) loginOAuth2(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	providerCodename := surf.PathArg(r, 0)

	state := genToken()

	provider, ok := app.providers[providerCodename]
	if !ok {
		app.log.Info(ctx, "provider not found",
			"provider", providerCodename)
		app.html.RenderDefault(w, http.StatusNotFound)
		return
	}

	url := provider.Config(r).AuthCodeURL(state, oauth2.AccessTypeOnline)
	http.SetCookie(w, &http.Cookie{
		Name:    stateCookie,
		Path:    "/",
		Value:   state,
		Expires: time.Now().Add(time.Minute * 10),
	})

	err := app.cache.Set(ctx, "auth:login:"+state, &authInfo{
		Provider: provider.Codename,
		State:    state,
		Next:     r.FormValue("next"),
	}, 5*time.Minute)
	if err != nil {
		app.log.Info(ctx, "data not found in cache",
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, url, http.StatusTemporaryRedirect)
}

type authInfo struct {
	Provider string
	State    string
	Next     string
}

const stateCookie = "oauthState"

func (app *AuthApp) loginOAuth2Callback(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	var state string
	if c, err := r.Cookie(stateCookie); err != nil || c.Value == "" {
		app.log.Info(ctx, "invalid oauth state",
			"expected", state,
			"got", r.FormValue("state"))
		app.html.RenderDefault(w, http.StatusBadRequest)
		return
	} else {
		state = c.Value
	}

	if r.FormValue("state") != state {
		app.log.Info(ctx, "invalid oauth state",
			"cookie", state,
			"form", r.FormValue("state"))
		app.html.RenderDefault(w, http.StatusBadRequest)
		return
	}

	var info authInfo
	switch err := app.cache.Get(ctx, "auth:login:"+state, &info); err {
	case nil:
		// all good
	case cache.ErrMiss:
		app.html.RenderDefault(w, http.StatusBadRequest)
		return
	default:
		app.log.Error(ctx, "cannot get auth data from cache",
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	if info.State != state {
		app.log.Info(ctx, "invalid oauth state",
			"cache", state,
			"form", r.FormValue("state"))
		app.html.RenderDefault(w, http.StatusBadRequest)
		return
	}

	provider, ok := app.providers[info.Provider]
	if !ok {
		app.log.Error(ctx, "provider not found",
			"provider", info.Provider)
		app.html.RenderDefault(w, http.StatusBadRequest)
		return
	}

	conf := provider.Config(r)
	token, err := conf.Exchange(ctx, r.FormValue("code"))
	if err != nil {
		app.log.Error(ctx, "oauth2 exchange failed",
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	if !token.Valid() {
		app.log.Error(ctx, "invalid token",
			"token", fmt.Sprint(token))
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	user, err := provider.fetchUser(conf.Client(ctx, token))
	switch err {
	case nil:
		// all good
	case ErrInvalidProfile:
		app.log.Error(ctx, "invalid user profile",
			"provider", provider.Codename,
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusNotAcceptable)
		return
	default:
		app.log.Error(ctx, "cannot GET user information",
			"provider", provider.Codename,
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	account := Account{
		AccountID:   user.ID,
		Email:       user.Email,
		Name:        user.Name,
		AccessToken: token.AccessToken,
	}
	sessionToken := genToken()
	if err := app.cache.Set(ctx, "auth:session:"+sessionToken, &account, time.Hour*12); err != nil {
		app.log.Error(ctx, "cannot set token",
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:  sessionCookieName,
		Value: string(sessionToken),
		Path:  "/",
	})

	next := info.Next
	if next == "" {
		next = "/"
	}
	http.Redirect(w, r, next, http.StatusTemporaryRedirect)
}

func genToken() string {
	b := make([]byte, 18)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// CurrentAccount returns account instance assigned to current session.
// ErrNoSession is returned if session does not exist or cannot be returned.
func (app *AuthApp) CurrentAccount(r *http.Request) (*Account, error) {
	cookie, err := r.Cookie(sessionCookieName)
	if err != nil {
		return nil, ErrNoSession
	}

	var account Account
	switch err := app.cache.Get(r.Context(), "auth:session:"+cookie.Value, &account); err {
	case nil:
		return &account, nil
	case cache.ErrMiss:
		return nil, ErrNoSession
	default:
		return nil, fmt.Errorf("cannot get session from cache: %s", err)
	}

}

type Account struct {
	AccountID   int    `json:"id"`
	Email       string `json:"email"`
	Name        string `json:"name"`
	AccessToken string `json:"accessToken"`
}

var ErrNoSession = errors.New("no session")
