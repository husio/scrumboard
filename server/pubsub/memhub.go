package pubsub

import "sync"

// in memory hub register, because when running on free heroku, we use single
// process anyway
type memhub struct {
	mu            sync.Mutex
	subscriptions map[string]map[*memsub]struct{}
}

var _ Hub = (*memhub)(nil)

func NewMemoryHub() Hub {
	return &memhub{
		subscriptions: make(map[string]map[*memsub]struct{}),
	}
}

func (h *memhub) Subscribe(board string, recv chan<- []byte) Subscription {
	h.mu.Lock()
	defer h.mu.Unlock()

	sub := &memsub{
		hub:   h,
		board: board,
		recv:  recv,
	}
	if _, ok := h.subscriptions[board]; !ok {
		h.subscriptions[board] = make(map[*memsub]struct{})
	}
	h.subscriptions[board][sub] = struct{}{}
	return sub
}

type memsub struct {
	hub   *memhub
	board string
	recv  chan<- []byte
}

var _ Subscription = (*memsub)(nil)

func (s *memsub) Broadcast(data []byte) error {
	s.hub.mu.Lock()
	defer s.hub.mu.Unlock()

	for sub := range s.hub.subscriptions[s.board] {
		// do not broadcast message to myself
		if sub == s {
			continue
		}
		select {
		case sub.recv <- data:
		default:
			// ignore slow clients
		}
	}

	return nil
}

func (s *memsub) Send(data []byte) error {
	select {
	case s.recv <- data:
		return nil
	default:
		return ErrSlowClient
	}
}

func (s *memsub) Close() error {
	s.hub.mu.Lock()
	defer s.hub.mu.Unlock()

	delete(s.hub.subscriptions[s.board], s)
	// if this is the last subscription, delete the whole channel
	if len(s.hub.subscriptions[s.board]) == 0 {
		delete(s.hub.subscriptions, s.board)
	}

	return nil
}
