package scrumboard

import (
	"net/http"

	"github.com/husio/scrumboard/server/auth"
	"github.com/husio/scrumboard/server/surf"
)

func (app *ScrumBoardApp) index(w http.ResponseWriter, r *http.Request) {
	account, err := app.auth.CurrentAccount(r)
	if err != nil {
		http.Redirect(w, r, "/login", http.StatusTemporaryRedirect)
		return
	}

	content := struct {
		Account *auth.Account
		Debug   bool
	}{
		Account: account,
		Debug:   app.debug,
	}
	app.html.Render(w, http.StatusOK, "index.tmpl", content)
}

func (app *ScrumBoardApp) board(w http.ResponseWriter, r *http.Request) {
	account, err := app.auth.CurrentAccount(r)
	if err != nil {
		http.Redirect(w, r, "/login", http.StatusTemporaryRedirect)
		return
	}

	content := struct {
		Account *auth.Account
		Debug   bool
		BoardID string
	}{
		Account: account,
		Debug:   app.debug,
		BoardID: surf.PathArg(r, 0),
	}
	app.html.Render(w, http.StatusOK, "board.tmpl", content)
}
