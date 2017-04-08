package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{}

func main() {
	httpAddr := env("HTTP", "0.0.0.0:8000")
	staticPath := env("STATIC", "./static")

	wshub := NewWsHandler()

	mux := http.NewServeMux()
	mux.Handle("/static/", http.StripPrefix("/static", http.FileServer(http.Dir(staticPath))))
	mux.Handle("/ws", wshub)
	mux.Handle("/", IndexHandler(staticPath))

	if err := http.ListenAndServe(httpAddr, mux); err != nil {
		log.Fatalf("server failed: %s", err)
	}
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

func IndexHandler(basepath string) http.HandlerFunc {
	path := filepath.Join(basepath, "index.html")
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}
		http.ServeFile(w, r, path)
	}
}

type WsHandler struct {
	mu    sync.Mutex
	state string // last state message -_-
	subs  map[chan<- string]struct{}
}

func NewWsHandler() *WsHandler {
	return &WsHandler{
		subs: make(map[chan<- string]struct{}),
	}
}

func (h *WsHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("cannot upgrade to websocket: %s", err)
		return
	}
	go func() {
		defer conn.Close()
		h.handleClient(conn)
	}()
}

func (h *WsHandler) handleClient(c *websocket.Conn) {
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

func (h *WsHandler) subscribe(c chan<- string) {
	h.mu.Lock()
	h.subs[c] = struct{}{}
	select {
	case c <- h.state:
	default:
	}
	h.mu.Unlock()
}

func (h *WsHandler) unsubscribe(c chan<- string) {
	h.mu.Lock()
	delete(h.subs, c)
	h.mu.Unlock()
}

func (h *WsHandler) broadcast(exclude chan<- string, s string) {
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
