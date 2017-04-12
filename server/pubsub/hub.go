package pubsub

import "errors"

type Hub interface {
	Subscribe(board string, recv chan<- []byte) Subscription
}

type Subscription interface {
	Broadcast([]byte) error
	Send([]byte) error
	Close() error
}

var ErrSlowClient = errors.New("slow client")
