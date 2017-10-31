package pubsub

import (
	"fmt"
	"log"

	"github.com/garyburd/redigo/redis"
)

type hubSnapshot struct {
	hub Hub
	rp  *redis.Pool
}

var _ Hub = (*hubSnapshot)(nil)

func Snapshot(rp *redis.Pool, hub Hub) Hub {
	return &hubSnapshot{
		hub: hub,
		rp:  rp,
	}
}

func (s *hubSnapshot) Subscribe(board string, recv chan<- []byte) Subscription {
	sub := s.hub.Subscribe(board, recv)

	subsnap := &subSnapshot{
		key: "board:snapshot:" + board,
		rp:  s.rp,
		sub: sub,
	}
	subsnap.sendSnapshot()
	return subsnap
}

type subSnapshot struct {
	key string
	sub Subscription
	rp  *redis.Pool
}

func (s *subSnapshot) sendSnapshot() error {
	rc := s.rp.Get()
	defer rc.Close()

	data, err := redis.Bytes(rc.Do("GET", s.key))
	if err != nil {
		return fmt.Errorf("cannot get from db: %s", err)
	}

	return s.Send(data)
}

func (s *subSnapshot) Send(data []byte) error {
	return s.sub.Send(data)
}

func (s *subSnapshot) Broadcast(data []byte) error {
	rc := s.rp.Get()
	defer rc.Close()

	if _, err := rc.Do("SET", s.key, data); err != nil {
		log.Printf("cannot create snapshot: %s", err)
	}

	return s.sub.Broadcast(data)
}

func (s subSnapshot) Close() error {
	return s.sub.Close()
}
