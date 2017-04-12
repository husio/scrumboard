package scrumboard

import (
	"context"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
	"github.com/husio/scrumboard/server/surf"
)

func (app *ScrumBoardApp) handleClient(w http.ResponseWriter, r *http.Request) {
	boardID := surf.PathArg(r, 0)

	if len(boardID) != 40 {
		surf.JSONErr(w, http.StatusBadRequest, "invalid board id")
		return
	}

	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("cannot upgrade to websocket: %s", err)
		surf.JSONErr(w, http.StatusBadRequest, "cannot upgrade to websocket")
		return
	}
	defer ws.Close()

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	recv := make(chan []byte, 4)
	sub := app.hub.Subscribe(boardID, recv)
	defer sub.Close()

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				_, msg, err := ws.ReadMessage()
				if err != nil {
					log.Printf("cannot read message: %s", err)
					cancel()
					return
				}
				sub.Broadcast(msg)
			}
		}
	}()

	for msg := range recv {
		if err := ws.WriteMessage(websocket.TextMessage, msg); err != nil {
			log.Printf("cannot write to client: %s", err)
			return
		}
	}
}

var upgrader = websocket.Upgrader{}
