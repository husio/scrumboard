package scrumboard

import (
	"net/http"

	"github.com/husio/scrumboard/server/auth"
)

func (app *ScrumBoardApp) board(w http.ResponseWriter, r *http.Request) {
	account, err := app.auth.CurrentAccount(r)
	if err != nil {
		http.Redirect(w, r, "/login", http.StatusTemporaryRedirect)
		return
	}

	content := struct {
		Account *auth.Account
	}{
		Account: account,
	}
	app.html.Render(w, http.StatusOK, "board.tmpl", content)
}
