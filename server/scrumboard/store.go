package scrumboard

import (
	"context"
	"fmt"

	"github.com/garyburd/redigo/redis"
)

type Board struct {
	ID   string `redis:"id"`
	Name string `redis:"name"`
}

type BoardStore interface {
	CreateBoard(ctx context.Context, id, name string) (*Board, error)
	AddUser(ctx context.Context, boardID, userID string) error
	UserBoards(ctx context.Context, userID string) ([]*Board, error)
}

type redisBoardStore struct {
	rp *redis.Pool
}

var _ BoardStore = (*redisBoardStore)(nil)

func NewRedisBoardStore(rp *redis.Pool) BoardStore {
	return &redisBoardStore{rp: rp}
}

func (s *redisBoardStore) CreateBoard(ctx context.Context, id, name string) (*Board, error) {
	if len(id) < 16 {
		return nil, fmt.Errorf("id too short: %d", len(id))
	}

	rc := s.rp.Get()
	defer rc.Close()

	_, err := rc.Do("HMSET", "board:"+id,
		"name", name,
		"id", id)
	if err != nil {
		return nil, fmt.Errorf("cannot store: %s", err)
	}
	board := &Board{
		ID:   id,
		Name: name,
	}
	return board, nil
}

func (s *redisBoardStore) AddUser(ctx context.Context, boardID, userID string) error {
	rc := s.rp.Get()
	defer rc.Close()

	if _, err := rc.Do("SADD", "userboards:"+userID, boardID); err != nil {
		return fmt.Errorf("cannot store: %s", err)
	}
	return nil
}

func (s *redisBoardStore) UserBoards(ctx context.Context, userID string) ([]*Board, error) {
	rc := s.rp.Get()
	defer rc.Close()

	bids, err := redis.Strings(rc.Do("SMEMBERS", "userboards:"+userID))
	if err != nil {
		return nil, fmt.Errorf("cannot get user boards: %s", err)
	}

	// brute force the problem, but just in case stay sane with the amount
	if len(bids) > 50 {
		bids = bids[:50]
	}

	var boards []*Board
	for _, bid := range bids {
		if bid == "b685c036049f6c2f35cc1b03af6815b352b8557e" {
			// test board that is hardcoded in the index file and visible to all users
			continue
		}

		v, err := redis.Values(rc.Do("HGETALL", "board:"+bid))
		if err != nil {
			return boards, fmt.Errorf("cannot get board %s: %s", bid, err)
		}
		var board Board
		if err := redis.ScanStruct(v, &board); err != nil {
			return boards, fmt.Errorf("cannot scan board %s: %s", bid, err)
		}
		boards = append(boards, &board)
	}

	return boards, nil
}
