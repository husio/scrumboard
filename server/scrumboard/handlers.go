package scrumboard

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/husio/scrumboard/server/auth"
	"github.com/husio/scrumboard/server/surf"
)

func (app *ScrumBoardApp) index(w http.ResponseWriter, r *http.Request) {
	ctx, done := context.WithTimeout(r.Context(), 2*time.Second)
	defer done()

	account, err := app.auth.CurrentAccount(r)
	if err != nil {
		http.Redirect(w, r, "/login", http.StatusTemporaryRedirect)
		return
	}

	boards, err := app.bs.UserBoards(ctx, strconv.Itoa(account.AccountID))
	if err != nil {
		// this is not critical
		app.log.Error(ctx, "cannot get user boards",
			"account", strconv.Itoa(account.AccountID),
			"error", err.Error())
	}

	content := struct {
		Account *auth.Account
		Boards  []*Board
		Debug   bool
	}{
		Account: account,
		Boards:  boards,
		Debug:   app.debug,
	}
	app.html.Render(w, http.StatusOK, "index.tmpl", content)
}

func (app *ScrumBoardApp) board(w http.ResponseWriter, r *http.Request) {
	ctx, done := context.WithTimeout(r.Context(), 2*time.Second)
	defer done()

	account, err := app.auth.CurrentAccount(r)
	if err != nil {
		http.Redirect(w, r, "/login", http.StatusTemporaryRedirect)
		return
	}

	boardID := surf.PathArg(r, 0)

	if err := app.bs.AddUser(ctx, boardID, strconv.Itoa(account.AccountID)); err != nil {
		// this is not critical
		app.log.Error(ctx, "cannot add user to board",
			"account", strconv.Itoa(account.AccountID),
			"board", boardID,
			"error", err.Error())
	}

	content := struct {
		Account *auth.Account
		Debug   bool
		BoardID string
	}{
		Account: account,
		Debug:   app.debug,
		BoardID: boardID,
	}
	app.html.Render(w, http.StatusOK, "board.tmpl", content)
}

func (app *ScrumBoardApp) newBoard(w http.ResponseWriter, r *http.Request) {
	ctx, done := context.WithTimeout(r.Context(), 2*time.Second)
	defer done()

	account, err := app.auth.CurrentAccount(r)
	if err != nil {
		http.Redirect(w, r, "/login", http.StatusTemporaryRedirect)
		return
	}

	name := strings.TrimSpace(r.FormValue("name"))
	if name == "" {
		name = boardnames.Random()
	}

	board, err := app.bs.CreateBoard(ctx, genBoardID(), name)
	if err != nil {
		app.log.Error(ctx, "cannot create board",
			"account", strconv.Itoa(account.AccountID),
			"name", name,
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	if err := app.bs.AddUser(ctx, board.ID, strconv.Itoa(account.AccountID)); err != nil {
		app.log.Error(ctx, "cannot add user to board",
			"account", strconv.Itoa(account.AccountID),
			"board", board.ID,
			"error", err.Error())
		app.html.RenderDefault(w, http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/b/"+board.ID, http.StatusSeeOther)
}

func genBoardID() string {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
