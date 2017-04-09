package scrumboard

import (
	"context"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

type pubSub struct {
	mu    sync.Mutex
	state string // last state message -_-
	subs  map[chan<- string]struct{}
}

var upgrader = websocket.Upgrader{}

func (h *pubSub) handleClient(w http.ResponseWriter, r *http.Request) {
	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("cannot upgrade to websocket: %s", err)
		return
	}
	defer c.Close()

	log.Printf("opening connection: %p", c)
	defer log.Printf("closing connection: %p", c)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sub := make(chan string, 4)
	h.subscribe(sub)
	defer h.unsubscribe(sub)

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				_, msg, err := c.ReadMessage()
				if err != nil {
					log.Printf("cannot read message: %s", err)
					cancel()
					return
				}
				h.broadcast(sub, string(msg))
			}
		}
	}()

	for msg := range sub {
		if err := c.WriteMessage(websocket.TextMessage, []byte(msg)); err != nil {
			log.Printf("cannot write to client: %s", err)
			return
		}
	}
}

func (h *pubSub) subscribe(c chan<- string) {
	h.mu.Lock()
	h.subs[c] = struct{}{}
	select {
	case c <- h.state:
	default:
	}
	h.mu.Unlock()
}

func (h *pubSub) unsubscribe(c chan<- string) {
	h.mu.Lock()
	delete(h.subs, c)
	h.mu.Unlock()
}

func (h *pubSub) broadcast(exclude chan<- string, s string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.state = s

	for c := range h.subs {
		if c == exclude {
			continue
		}
		select {
		case c <- s:
		default:
			log.Printf("slow subscriber: %p", c)
			// ignore slow clients
		}
	}
}
